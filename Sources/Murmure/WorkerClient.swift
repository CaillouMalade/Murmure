import Foundation
import MurmureCore

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
        if let audio { size = (try FileManager.default.attributesOfItem(atPath: audio.path)[.size] as? NSNumber)?.uint64Value }
        var options = job?.options
        if endpoint == nil { options?.device = "cpu" }
        let request = WorkerRequest(op: op, root: endpoint?.root ?? localRoot.path, id: job?.id, bytes: size, options: options)
        var header = try JSONEncoder().encode(request); header.append(10)
        let data = try await ProcessRunner.run(executable: executable, arguments: arguments, header: header, file: audio, timeout: op == "transcribe" ? 180 : (audio == nil ? 45 : 1800))
        let result: WorkerResponse
        do { result = try JSONDecoder().decode(WorkerResponse.self, from: data) }
        catch { throw MurmureError.message("The worker returned an invalid response. Check that the app and worker versions match.") }
        if result.state == "error" { throw MurmureError.message(result.error ?? "The worker rejected the request.") }
        if let protocolVersion = result.protocolVersion, protocolVersion != 1 {
            throw MurmureError.message("The worker uses an incompatible protocol. Update the app and worker together.")
        }
        return result
    }
}
