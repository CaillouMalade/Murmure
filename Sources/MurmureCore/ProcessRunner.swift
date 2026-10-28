import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private final class ProcessOutput: @unchecked Sendable {
    var data = Data()
    var error: Error?
}
private final class ProcessControl: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var timeout = false
    var wasCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    var didTimeOut: Bool { lock.lock(); defer { lock.unlock() }; return timeout }
    func attach(_ process: Process) {
        lock.lock(); self.process = process; let stop = cancelled || timeout; lock.unlock()
        if stop { terminate(process) }
    }
    func stop(timedOut: Bool = false) {
        lock.lock()
        if timedOut { timeout = true } else { cancelled = true }
        let running = process; lock.unlock()
        if let running { terminate(running) }
    }
    private func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
            if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
        }
    }
}

public enum ProcessRunner {
    /// No shell, bounded pipes, cancellable lifetime, fixed-size disk-to-stdin chunks.
    public static func run(executable: URL, arguments: [String], header: Data = Data(), file: URL? = nil,
                           timeout: TimeInterval, directory: URL? = nil, environment: [String: String]? = nil) async throws -> Data {
        let control = ProcessControl()
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    if control.wasCancelled { continuation.resume(throwing: CancellationError()); return }
                    let process = Process()
                    process.executableURL = executable; process.arguments = arguments
                    process.currentDirectoryURL = directory
                    if let environment { process.environment = environment }
                    let input = Pipe(), output = Pipe(), errors = Pipe()
                    process.standardInput = input; process.standardOutput = output; process.standardError = errors
                    do { try process.run() } catch { continuation.resume(throwing: error); return }
                    control.attach(process)
                    let deadline = DispatchWorkItem { if process.isRunning { control.stop(timedOut: true) } }
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: deadline)
                    let group = DispatchGroup()
                    let stdout = ProcessOutput(), stderr = ProcessOutput()
                    for (pipe, result, limit) in [(output, stdout, 16 * 1024 * 1024), (errors, stderr, 256 * 1024)] {
                        group.enter()
                        DispatchQueue.global(qos: .utility).async {
                            do {
                                while let block = try pipe.fileHandleForReading.read(upToCount: 65_536), !block.isEmpty {
                                    if result.data.count + block.count > limit {
                                        result.error = MurmureError.message("The command response exceeded its output limit.")
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
                        if control.wasCancelled { throw CancellationError() }
                        try input.fileHandleForWriting.write(contentsOf: header)
                        if let file {
                            let handle = try FileHandle(forReadingFrom: file)
                            defer { try? handle.close() }
                            while let block = try handle.read(upToCount: 65_536), !block.isEmpty {
                                if control.wasCancelled { throw CancellationError() }
                                try input.fileHandleForWriting.write(contentsOf: block)
                            }
                        }
                    } catch { inputError = error }
                    try? input.fileHandleForWriting.close()
                    process.waitUntilExit(); deadline.cancel(); group.wait()
                    if control.wasCancelled { continuation.resume(throwing: CancellationError()) }
                    else if control.didTimeOut { continuation.resume(throwing: MurmureError.message("The command timed out. The original audio/transcript has been kept.")) }
                    else if process.terminationStatus != 0 {
                        let detail = String(data: stderr.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        continuation.resume(throwing: MurmureError.message(detail.isEmpty ? "The command failed (exit \(process.terminationStatus)). Check the executable, login and setup." : String(detail.prefix(1600))))
                    } else if let error = stdout.error ?? stderr.error ?? inputError { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: stdout.data) }
                }
            }
        }, onCancel: { control.stop() })
    }
}
