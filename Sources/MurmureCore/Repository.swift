import Foundation

public final class JobRepository {
    public let root: URL
    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    public func directory(for id: String) throws -> URL {
        guard UUID(uuidString: id) != nil, !id.contains("/") else { throw MurmureError.message("Invalid recording identifier.") }
        let url = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return url
    }
    public func audio(for id: String) throws -> URL { try directory(for: id).appendingPathComponent("audio.m4a") }
    public func save(_ job: RecordingJob) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(job).write(to: directory(for: job.id).appendingPathComponent("job.json"), options: .atomic)
    }
    public func load() throws -> [RecordingJob] {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { UUID(uuidString: $0.lastPathComponent) != nil }
            .compactMap { directory in
                guard let data = try? Data(contentsOf: directory.appendingPathComponent("job.json")) else { return nil }
                return try? decoder.decode(RecordingJob.self, from: data)
            }.sorted { $0.createdAt > $1.createdAt }
    }
    public static func recovered(_ job: RecordingJob) -> RecordingJob {
        var recovered = job
        switch job.state {
        case .recording, .preparing:
            recovered.state = .interrupted; recovered.message = "Recording stopped before audio was finalized. Original capture files are kept in its folder."
        case .uploading:
            recovered.state = .remote; recovered.message = "Transfer was interrupted. Check the remote job before retrying."
        default: break
        }
        return recovered
    }
}
