import Foundation

public enum DictationBackend: String, Codable, CaseIterable, Sendable {
    case ssh, onDevice
    public var title: String { self == .ssh ? "SSH worker" : "On this Mac (Apple speech)" }
}
public enum DictationGesture: String, Codable, CaseIterable, Sendable {
    case hold, toggle
    public var title: String { self == .hold ? "Hold to speak, release to insert" : "Press to start / press to finish" }
}
public struct DictationSettings: Codable, Equatable, Sendable {
    public var enabled = true
    public var backend = DictationBackend.ssh
    public var gesture = DictationGesture.hold
    public var copyToClipboard = false
    public var shortcut = KeyboardShortcut()
    public init() {}
}
public struct KeyboardShortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt32 = 49 // Space
    public var control = true
    public var option = true
    public var command = false
    public var shift = false
    public var keyLabel = "Space"
    public init() {}
    public var display: String { (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + keyLabel }
    public var hasModifier: Bool { control || option || command }
}
public enum SummaryProvider: String, Codable, CaseIterable, Sendable {
    case codex, claude
    public var title: String { self == .codex ? "Codex CLI" : "Claude Code" }
}
public struct SummarySettings: Codable, Equatable, Sendable {
    public var automatic = false
    public var provider = SummaryProvider.codex
    public var codexPath = ""
    public var claudePath = ""
    public var template = """
    Summarize this transcript in Markdown. Keep the original language.
    Use these sections, omitting an empty section:
    # Summary
    ## Key points
    ## Decisions
    ## Action items
    Attribute speakers only when the transcript supports it. Don't invent facts, owners or deadlines.
    """
    public init() {}
    public var executablePath: String { provider == .codex ? codexPath : claudePath }
}
public enum SummaryState: String, Codable, Sendable { case running, completed, failed, interrupted }
public struct SummaryRecord: Codable, Sendable {
    public var state: SummaryState
    public var provider: SummaryProvider
    public var path: String?
    public var exportedPath: String?
    public var error: String?
    public var viewedAt: Date?
    public init(state: SummaryState, provider: SummaryProvider) { self.state = state; self.provider = provider }
}
public enum DictationCommand: String, Sendable {
    case start, stop, toggle, cancel
    public static func parse(_ url: URL) -> DictationCommand? {
        guard url.scheme?.lowercased() == "murmure", url.host?.lowercased() == "dictation",
              url.query == nil, url.fragment == nil, url.user == nil, url.password == nil else { return nil }
        let value = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return value.isEmpty ? .toggle : DictationCommand(rawValue: value)
    }
}
