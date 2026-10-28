import Foundation

public enum SummaryService {
    public static func executable(settings: SummarySettings) throws -> URL {
        let path = settings.executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) else {
            throw MurmureError.message("Choose the full path to \(settings.provider.title) in Settings and sign in to it in Terminal first.")
        }
        return URL(fileURLWithPath: path)
    }
    public static func run(settings: SummarySettings, transcript: String, title: String) async throws -> String {
        let executable = try executable(settings: settings)
        let prompt = try MarkdownWorkflow.summaryPrompt(template: settings.template, transcript: transcript, title: title)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Murmure-summary-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try await ProcessRunner.run(executable: executable, arguments: AgentInvocation.arguments(provider: settings.provider),
                                               header: Data(prompt.utf8), timeout: 300, directory: directory, environment: environment(for: executable))
        try Task.checkCancellation()
        return try AgentInvocation.output(data, provider: settings.provider)
    }
    public static func version(settings: SummarySettings) async throws -> String {
        let executable = try executable(settings: settings)
        let data = try await ProcessRunner.run(executable: executable, arguments: ["--version"], timeout: 15, environment: environment(for: executable))
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    private static func environment(for executable: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = [executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin", environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"].joined(separator: ":")
        return environment
    }
}
