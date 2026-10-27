import Foundation
import MurmureCore

private final class ProcessOutput: @unchecked Sendable {
    var data = Data()
    var error: Error?
}

enum ProcessRunner {
    /// Stream disk -> pipe in fixed-size blocks. Drain both output pipes concurrently.
    static func run(executable: URL, arguments: [String], header: Data, file: URL?, timeout: TimeInterval) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = executable; process.arguments = arguments
                let input = Pipe(), output = Pipe(), errors = Pipe()
                process.standardInput = input; process.standardOutput = output; process.standardError = errors
                do { try process.run() } catch { continuation.resume(throwing: error); return }
                let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: deadline)
                let group = DispatchGroup()
                let stdout = ProcessOutput(), stderr = ProcessOutput()
                for (pipe, result, limit) in [(output, stdout, 16 * 1024 * 1024), (errors, stderr, 64 * 1024)] {
                    group.enter()
                    DispatchQueue.global(qos: .utility).async {
                        do {
                            while let block = try pipe.fileHandleForReading.read(upToCount: 65_536), !block.isEmpty {
                                if result.data.count + block.count > limit {
                                    result.error = MurmureError.message("The worker response was too large.")
                                    if process.isRunning { process.terminate() }
                                    break
                                }
                                result.data.append(block)
                            }
                        } catch { result.error = error }
                        group.leave()
                    }
                }
                var inputError: Error?
                do {
                    try input.fileHandleForWriting.write(contentsOf: header)
                    if let file {
                        let handle = try FileHandle(forReadingFrom: file)
                        defer { try? handle.close() }
                        while let block = try handle.read(upToCount: 65_536), !block.isEmpty {
                            try input.fileHandleForWriting.write(contentsOf: block)
                        }
                    }
                } catch { inputError = error }
                try? input.fileHandleForWriting.close()
                process.waitUntilExit(); deadline.cancel(); group.wait()
                if process.terminationStatus != 0 {
                    let detail = String(data: stderr.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(throwing: MurmureError.message(detail.isEmpty ? "The worker stopped responding. Check the SSH connection and worker setup." : String(detail.prefix(1600))))
                } else if let error = stdout.error ?? stderr.error ?? inputError {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: stdout.data)
                }
            }
        }
    }
}

struct WorkerClient {
    var endpoint: WorkerEndpoint?
    var localPython: String
    var localRoot: URL

    func request(op: String, job: RecordingJob? = nil, audio: URL? = nil) async throws -> WorkerResponse {
        let executable: URL
        let arguments: [String]
        if let endpoint {
            executable = URL(fileURLWithPath: "/usr/bin/ssh")
            arguments = try SSHCommand.arguments(for: endpoint)
        } else {
            guard localPython.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: localPython) else {
                throw MurmureError.message("Choose the full path to your local worker's Python in Settings, for example /Users/you/Murmure/.venv/bin/python.")
            }
            executable = URL(fileURLWithPath: localPython)
            guard let script = Bundle.main.url(forResource: "murmure_worker", withExtension: "py") else {
                throw MurmureError.message("The bundled worker is missing. Build the .app with scripts/build-app.sh.")
            }
            arguments = ["-u", script.path, "rpc"]
        }
        var size: UInt64?
        if let audio { size = try FileManager.default.attributesOfItem(atPath: audio.path)[.size] as? UInt64 }
        var options = job?.options
        if endpoint == nil { options?.device = "cpu" }
        let request = WorkerRequest(op: op, root: endpoint?.root ?? localRoot.path, id: job?.id, bytes: size, options: options)
        var header = try JSONEncoder().encode(request); header.append(10)
        let data = try await ProcessRunner.run(executable: executable, arguments: arguments, header: header, file: audio, timeout: audio == nil ? 45 : 1800)
        let result: WorkerResponse
        do { result = try JSONDecoder().decode(WorkerResponse.self, from: data) }
        catch { throw MurmureError.message("The worker returned an invalid response. Check that the app and worker versions match.") }
        if result.state == "error" { throw MurmureError.message(result.error ?? "The worker rejected the request.") }
        return result
    }
}
