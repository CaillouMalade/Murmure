import Foundation

public enum AudioSource: String, Codable, CaseIterable, Sendable {
    case microphone, system, both
    public var title: String {
        switch self {
        case .microphone: return "Microphone"
        case .system: return "Mac audio"
        case .both: return "Microphone + Mac audio"
        }
    }
    public var includesMicrophone: Bool { self != .system }
    public var includesSystem: Bool { self != .microphone }
}

public struct TranscriptionOptions: Codable, Equatable, Sendable {
    public var diarization = false
    public var timestamps = true
    public var model = "small"
    public var language = ""
    public var device = "auto"
    public init() {}
}

public struct WorkerEndpoint: Codable, Hashable, Sendable {
    public var host: String
    public var python: String
    public var script: String
    public var root: String
    public init(host: String = "", python: String = "", script: String = "", root: String = "~/.murmure") {
        self.host = host; self.python = python; self.script = script; self.root = root
    }
}

public struct AppSettings: Codable, Sendable {
    public var source = AudioSource.microphone
    public var options = TranscriptionOptions()
    public var remote = WorkerEndpoint()
    public var localPython = ""
    public var outputFolder = ""
    public var dictation = DictationSettings()
    public var summary = SummarySettings()
    public init() {}
    private enum CodingKeys: String, CodingKey { case source, options, remote, localPython, outputFolder, dictation, summary }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        source = try values.decodeIfPresent(AudioSource.self, forKey: .source) ?? .microphone
        options = try values.decodeIfPresent(TranscriptionOptions.self, forKey: .options) ?? TranscriptionOptions()
        remote = try values.decodeIfPresent(WorkerEndpoint.self, forKey: .remote) ?? WorkerEndpoint()
        localPython = try values.decodeIfPresent(String.self, forKey: .localPython) ?? ""
        outputFolder = try values.decodeIfPresent(String.self, forKey: .outputFolder) ?? ""
        dictation = try values.decodeIfPresent(DictationSettings.self, forKey: .dictation) ?? DictationSettings()
        summary = try values.decodeIfPresent(SummarySettings.self, forKey: .summary) ?? SummarySettings()
    }
}

public enum JobState: String, Codable, Sendable {
    case recording, preparing, queued, uploading, remote, local, completed, failed, interrupted
    public var title: String {
        switch self {
        case .recording: return "Recording"
        case .preparing: return "Saving audio"
        case .queued: return "Ready to send"
        case .uploading: return "Sending audio"
        case .remote: return "On remote computer"
        case .local: return "Processing on this Mac"
        case .completed: return "Transcript ready"
        case .failed: return "Needs attention"
        case .interrupted: return "Recording interrupted"
        }
    }
}

public struct RecordingJob: Codable, Identifiable, Sendable {
    public var id: String
    public var createdAt: Date
    public var source: AudioSource
    public var options: TranscriptionOptions
    public var state: JobState
    public var endpoint: WorkerEndpoint?
    public var message: String?
    public var transcriptPath: String?
    public var localWorkerRoot: String?
    public var transcriptViewedAt: Date?
    public var duration: Double?
    public var kind: JobKind?
    public var exportedTranscriptPath: String?
    public var automaticSummary: SummarySettings?
    public var summary: SummaryRecord?
    public var effectiveKind: JobKind { kind ?? .recording }
    public var hasUnreadTranscript: Bool { state == .completed && transcriptViewedAt == nil }
    public var hasUnreadSummary: Bool { summary?.state == .completed && summary?.viewedAt == nil }
    public init(source: AudioSource, options: TranscriptionOptions) {
        id = UUID().uuidString.lowercased(); createdAt = Date()
        self.source = source; self.options = options; state = .recording
    }
}

public enum JobKind: String, Codable, Sendable { case recording, dictation }

public struct Segment: Codable, Equatable, Sendable {
    public var start: Double
    public var end: Double
    public var text: String
    public var speaker: String?
    public init(start: Double, end: Double, text: String, speaker: String? = nil) {
        self.start = start; self.end = end; self.text = text; self.speaker = speaker
    }
}

public struct Transcript: Codable, Sendable {
    public var language: String
    public var segments: [Segment]
    public init(language: String, segments: [Segment]) { self.language = language; self.segments = segments }
    public func formatted(timestamps: Bool) -> String {
        segments.map { segment in
            var prefix = timestamps ? "[\(Self.timestamp(segment.start))] " : ""
            if let speaker = segment.speaker { prefix += "\(speaker): " }
            return prefix + segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }.joined(separator: "\n") + "\n"
    }
    public static func timestamp(_ seconds: Double) -> String {
        let total = seconds.isFinite ? max(0, Int(min(seconds, 359_999))) : 0
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}

public struct WorkerRequest: Encodable, Sendable {
    public var op: String
    public var root: String
    public var id: String?
    public var bytes: UInt64?
    public var options: TranscriptionOptions?
    public init(op: String, root: String, id: String? = nil, bytes: UInt64? = nil, options: TranscriptionOptions? = nil) {
        self.op = op; self.root = root; self.id = id; self.bytes = bytes; self.options = options
    }
}

public struct WorkerResponse: Decodable, Sendable {
    public var state: String
    public var id: String?
    public var error: String?
    public var transcript: Transcript?
    public var version: String?
    public var protocolVersion: Int?
    public var transcriptionInstalled: Bool?
    public var diarizationInstalled: Bool?
}

public enum MurmureError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
