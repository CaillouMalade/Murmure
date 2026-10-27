import AppKit
import MurmureCore

@MainActor
final class SettingsWindow: NSWindowController {
    private var settings: AppSettings
    private let localRoot: URL
    private let onSave: (AppSettings) -> Void
    private let host = NSTextField(), python = NSTextField(), script = NSTextField(), root = NSTextField()
    private let localPython = NSTextField(), folder = NSTextField(), model = NSTextField(), language = NSTextField()
    private let source = NSPopUpButton(), device = NSPopUpButton()
    private let timestamps = NSButton(checkboxWithTitle: "Add timestamps", target: nil, action: nil)
    private let speakers = NSButton(checkboxWithTitle: "Label speakers (requires diarization on the worker)", target: nil, action: nil)
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private var testButton: NSButton!

    init(settings: AppSettings, localRoot: URL, onSave: @escaping (AppSettings) -> Void) {
        self.settings = settings; self.localRoot = localRoot; self.onSave = onSave
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 660), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Murmure Settings"; window.isReleasedWhenClosed = false
        super.init(window: window)
        source.addItems(withTitles: AudioSource.allCases.map(\.title)); source.selectItem(at: AudioSource.allCases.firstIndex(of: settings.source) ?? 0)
        device.addItems(withTitles: ["auto", "cpu", "cuda"]); device.selectItem(withTitle: settings.options.device)
        host.stringValue = settings.remote.host; host.placeholderString = "e.g. g14 (from ~/.ssh/config)"
        python.stringValue = settings.remote.python; script.stringValue = settings.remote.script; root.stringValue = settings.remote.root
        localPython.stringValue = settings.localPython; localPython.placeholderString = "/Users/you/Murmure/.venv/bin/python"
        folder.stringValue = settings.outputFolder; folder.placeholderString = "Default: ~/Documents/Murmure"
        model.stringValue = settings.options.model; language.stringValue = settings.options.language; language.placeholderString = "Automatic, or en / fr / de…"
        timestamps.state = settings.options.timestamps ? .on : .off; speakers.state = settings.options.diarization ? .on : .off
        let lead = NSTextField(wrappingLabelWithString: "Click the menu-bar icon to start or stop. Right-click for audio sources, options and transcripts. Recordings stay on disk; there’s no audio player.")
        let choose = NSButton(title: "Choose…", target: self, action: #selector(chooseFolder))
        let output = NSStackView(views: [folder, choose]); output.orientation = .horizontal
        let rows: [(String, NSView)] = [("Audio source", source), ("SSH alias", host), ("Remote Python", python), ("Remote worker", script), ("Remote data folder", root), ("Local Python (fallback)", localPython), ("Whisper model", model), ("Language", language), ("Remote processor", device), ("Save transcripts to", output)]
        let grid = NSGridView(views: rows.map { [NSTextField(labelWithString: $0.0), $0.1] })
        grid.rowSpacing = 10; grid.columnSpacing = 16; grid.column(at: 0).xPlacement = .trailing; grid.column(at: 1).xPlacement = .fill
        grid.widthAnchor.constraint(equalToConstant: 610).isActive = true
        let note = NSTextField(wrappingLabelWithString: "SSH uses your existing keys and known hosts. Connect once in Terminal before using Murmure. Models are installed on the worker, outside the app. Remote jobs continue independently; results are checked when you open the menu, choose Check results, launch the app or wake the Mac.")
        note.textColor = .secondaryLabelColor; note.font = .systemFont(ofSize: 11)
        testButton = NSButton(title: "Test SSH connection", target: self, action: #selector(testConnection))
        let saveButton = NSButton(title: "Save", target: self, action: #selector(save)); saveButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [testButton, NSView(), saveButton]); buttons.orientation = .horizontal
        feedback.textColor = .secondaryLabelColor; feedback.font = .systemFont(ofSize: 11)
        let stack = NSStackView(views: [lead, grid, timestamps, speakers, note, feedback, buttons])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        if let content = window.contentView {
            NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24), stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24), lead.widthAnchor.constraint(equalTo: stack.widthAnchor), note.widthAnchor.constraint(equalTo: stack.widthAnchor), feedback.widthAnchor.constraint(equalTo: stack.widthAnchor), buttons.widthAnchor.constraint(equalTo: stack.widthAnchor)])
        }
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    private func draft() -> AppSettings {
        var value = settings
        value.source = AudioSource.allCases[max(0, source.indexOfSelectedItem)]
        value.options.timestamps = timestamps.state == .on; value.options.diarization = speakers.state == .on
        value.options.model = model.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        value.options.language = language.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        value.options.device = device.titleOfSelectedItem ?? "auto"
        value.remote = WorkerEndpoint(host: host.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), python: python.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), script: script.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), root: root.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        value.localPython = localPython.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        value.outputFolder = folder.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value
    }
    @objc private func save() {
        let value = draft()
        do {
            if !value.remote.host.isEmpty { _ = try SSHCommand.arguments(for: value.remote) }
            guard !value.options.model.isEmpty, !value.remote.root.isEmpty else { throw MurmureError.message("Enter a model and a worker data folder.") }
            onSave(value); close()
        } catch { feedback.stringValue = error.localizedDescription }
    }
    @objc private func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { folder.stringValue = url.path }
    }
    @objc private func testConnection() {
        let value = draft(); testButton.isEnabled = false; feedback.stringValue = "Connecting…"
        Task {
            defer { testButton.isEnabled = true }
            do {
                let result = try await WorkerClient(endpoint: value.remote, localPython: value.localPython, localRoot: localRoot).request(op: "probe")
                feedback.stringValue = "Connected to worker \(result.version ?? "unknown version"). Models load only when a job runs."
            } catch { feedback.stringValue = error.localizedDescription }
        }
    }
}
