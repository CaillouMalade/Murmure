import AppKit
import MurmureCore

private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class SettingsWindow: NSWindowController, NSWindowDelegate {
    private var settings: AppSettings
    private let localRoot: URL
    private let onSave: (AppSettings) throws -> Void
    private let onShortcutCapture: (Bool) -> Void
    private let host = NSTextField(), python = NSTextField(), script = NSTextField(), root = NSTextField()
    private let localPython = NSTextField(), folder = NSTextField(), model = NSTextField(), language = NSTextField()
    private let source = NSPopUpButton(), device = NSPopUpButton(), backend = NSPopUpButton(), gesture = NSPopUpButton(), provider = NSPopUpButton()
    private let codex = NSTextField(), claude = NSTextField(), template = NSTextView()
    private let shortcut = ShortcutRecorder()
    private let enabled = NSButton(checkboxWithTitle: "Enable dictation shortcut", target: nil, action: nil)
    private let copy = NSButton(checkboxWithTitle: "Also copy finished dictation to the clipboard", target: nil, action: nil)
    private let automatic = NSButton(checkboxWithTitle: "Automatically summarize new recordings", target: nil, action: nil)
    private let timestamps = NSButton(checkboxWithTitle: "Add timestamps", target: nil, action: nil)
    private let speakers = NSButton(checkboxWithTitle: "Label speakers (requires diarization on the worker)", target: nil, action: nil)
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private var testButton: NSButton!

    init(settings: AppSettings, localRoot: URL, onShortcutCapture: @escaping (Bool) -> Void = { _ in }, onSave: @escaping (AppSettings) throws -> Void) {
        self.settings = settings; self.localRoot = localRoot; self.onSave = onSave; self.onShortcutCapture = onShortcutCapture
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 680), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Murmure Settings"; window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 700, height: 640)
        super.init(window: window); window.delegate = self
        source.addItems(withTitles: AudioSource.allCases.map(\.title)); source.selectItem(at: AudioSource.allCases.firstIndex(of: settings.source) ?? 0)
        device.addItems(withTitles: ["auto", "cpu", "cuda"]); device.selectItem(withTitle: settings.options.device)
        backend.addItems(withTitles: DictationBackend.allCases.map(\.title)); backend.selectItem(at: DictationBackend.allCases.firstIndex(of: settings.dictation.backend) ?? 0)
        gesture.addItems(withTitles: DictationGesture.allCases.map(\.title)); gesture.selectItem(at: DictationGesture.allCases.firstIndex(of: settings.dictation.gesture) ?? 0)
        provider.addItems(withTitles: SummaryProvider.allCases.map(\.title)); provider.selectItem(at: SummaryProvider.allCases.firstIndex(of: settings.summary.provider) ?? 0)
        host.stringValue = settings.remote.host; host.placeholderString = "e.g. g14 (from ~/.ssh/config)"
        python.stringValue = settings.remote.python; script.stringValue = settings.remote.script; root.stringValue = settings.remote.root
        python.placeholderString = "e.g. C:/Murmure/.venv/Scripts/python.exe"; script.placeholderString = "e.g. C:/Murmure/worker/murmure_worker.py"
        localPython.stringValue = settings.localPython; localPython.placeholderString = "/Users/you/Murmure/.venv/bin/python"
        folder.stringValue = settings.outputFolder; folder.placeholderString = "Default: ~/Documents/Murmure"
        model.stringValue = settings.options.model; language.stringValue = settings.options.language; language.placeholderString = "Automatic, or en / fr / de…"
        codex.stringValue = settings.summary.codexPath; codex.placeholderString = "/opt/homebrew/bin/codex"
        claude.stringValue = settings.summary.claudePath; claude.placeholderString = "/Users/you/.local/bin/claude"
        timestamps.state = settings.options.timestamps ? .on : .off; speakers.state = settings.options.diarization ? .on : .off
        enabled.state = settings.dictation.enabled ? .on : .off; copy.state = settings.dictation.copyToClipboard ? .on : .off
        automatic.state = settings.summary.automatic ? .on : .off
        shortcut.value = settings.dictation.shortcut; shortcut.captureChanged = onShortcutCapture
        template.string = settings.summary.template; template.font = .systemFont(ofSize: 13); template.isRichText = false
        template.isAutomaticQuoteSubstitutionEnabled = false; template.isAutomaticDashSubstitutionEnabled = false
        template.isVerticallyResizable = true; template.autoresizingMask = [.width]; template.textContainer?.widthTracksTextView = true

        let tabs = NSTabView()
        let output = pathRow(folder, title: "Choose…", action: #selector(chooseFolder))
        let recordingGrid = grid([("Audio source", source), ("SSH alias", host), ("Remote Python", python), ("Remote worker", script), ("Remote data folder", root), ("Local Python (fallback)", localPython), ("Whisper model", model), ("Language", language), ("Remote processor", device), ("Markdown folder", output)])
        testButton = NSButton(title: "Test SSH connection", target: self, action: #selector(testConnection))
        addTab("Recordings", to: tabs, views: [label("Click the icon to record; click again to save and transcribe. Right-click for recordings and actions."), recordingGrid, timestamps, speakers, label("Transcripts are .md files in your chosen folder. SSH uses your existing keys and verified hosts; the worker runs on the selected computer.", secondary: true), testButton])
        addTab("Dictation", to: tabs, views: [label("Speak with a keyboard shortcut. The small menu-bar capsule animates while recording and processing, then inserts the finished text at the original cursor."), enabled, grid([("Speech engine", backend), ("Shortcut behavior", gesture), ("Shortcut", shortcut)]), copy, label("SSH is the default and uses the recording connection above. On-device recognition uses Apple's local speech engine when available for your language. The engine starts only for a dictation request.", secondary: true), label("Typing into another app needs Accessibility permission. Password fields are excluded. If the cursor or field changes, the result is kept for manual copying instead of being inserted elsewhere.", secondary: true), label("Commands: open -g 'murmure://dictation/toggle'\nAlso available: /start, /stop and /cancel.", secondary: true)])
        let templateScroll = NSScrollView(); templateScroll.hasVerticalScroller = true; templateScroll.borderType = .bezelBorder; templateScroll.documentView = template
        templateScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 210).isActive = true
        let testCLI = NSButton(title: "Check CLI version", target: self, action: #selector(testAgent))
        addTab("Summaries", to: tabs, views: [label("Save the original Markdown transcript, then optionally ask a CLI agent to summarize it using your instructions. The summary is a separate .summary.md file beside it."), grid([("Agent", provider), ("Codex CLI", pathRow(codex, title: "Choose…", action: #selector(chooseCodex))), ("Claude Code CLI", pathRow(claude, title: "Choose…", action: #selector(chooseClaude)))]), automatic, label("Uses your signed-in CLI account and its normal usage limits. Automatic handoff applies only to new saved recordings with this option enabled; quick dictation is a typing action.", secondary: true), NSTextField(labelWithString: "Summary instructions / Markdown template"), templateScroll, testCLI])
        let saveButton = NSButton(title: "Save", target: self, action: #selector(save)); saveButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [feedback, NSView(), saveButton]); buttons.orientation = .horizontal
        feedback.textColor = .secondaryLabelColor; feedback.font = .systemFont(ofSize: 11)
        tabs.translatesAutoresizingMaskIntoConstraints = false; buttons.translatesAutoresizingMaskIntoConstraints = false
        if let content = window.contentView {
            content.addSubview(tabs); content.addSubview(buttons)
            NSLayoutConstraint.activate([tabs.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16), tabs.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16), tabs.topAnchor.constraint(equalTo: content.topAnchor, constant: 16), tabs.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -12), buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24), buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24), buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16), feedback.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, constant: -160)])
        }
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func windowWillClose(_ notification: Notification) { onShortcutCapture(false) }
    private func label(_ text: String, secondary: Bool = false) -> NSTextField {
        let view = NSTextField(wrappingLabelWithString: text)
        if secondary { view.font = .systemFont(ofSize: 11); view.textColor = .secondaryLabelColor }
        return view
    }
    private func grid(_ rows: [(String, NSView)]) -> NSGridView {
        let view = NSGridView(views: rows.map { [NSTextField(labelWithString: $0.0), $0.1] })
        view.rowSpacing = 10; view.columnSpacing = 16; view.column(at: 0).xPlacement = .trailing; view.column(at: 1).xPlacement = .fill
        view.column(at: 0).width = 160
        return view
    }
    private func pathRow(_ field: NSTextField, title: String, action: Selector) -> NSStackView {
        let view = NSStackView(views: [field, NSButton(title: title, target: self, action: action)]); view.orientation = .horizontal; return view
    }
    private func addTab(_ title: String, to tabs: NSTabView, views: [NSView]) {
        let item = NSTabViewItem(identifier: title); item.label = title
        let content = SettingsDocumentView(), stack = NSStackView(views: views)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14; stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20), stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)])
        for view in views { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        content.translatesAutoresizingMaskIntoConstraints = false; scroll.documentView = content
        content.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        item.view = scroll; tabs.addTabViewItem(item)
    }
    private func draft() -> AppSettings {
        var value = settings
        value.source = AudioSource.allCases[max(0, source.indexOfSelectedItem)]
        value.options.timestamps = timestamps.state == .on; value.options.diarization = speakers.state == .on
        value.options.model = model.stringValue.trimmingCharacters(in: .whitespacesAndNewlines); value.options.language = language.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        value.options.device = device.titleOfSelectedItem ?? "auto"
        value.remote = WorkerEndpoint(host: host.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), python: python.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), script: script.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), root: root.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        value.localPython = localPython.stringValue.trimmingCharacters(in: .whitespacesAndNewlines); value.outputFolder = folder.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        value.dictation.enabled = enabled.state == .on; value.dictation.copyToClipboard = copy.state == .on
        value.dictation.backend = DictationBackend.allCases[max(0, backend.indexOfSelectedItem)]; value.dictation.gesture = DictationGesture.allCases[max(0, gesture.indexOfSelectedItem)]
        value.dictation.shortcut = shortcut.value
        value.summary.provider = SummaryProvider.allCases[max(0, provider.indexOfSelectedItem)]; value.summary.automatic = automatic.state == .on
        value.summary.codexPath = codex.stringValue.trimmingCharacters(in: .whitespacesAndNewlines); value.summary.claudePath = claude.stringValue.trimmingCharacters(in: .whitespacesAndNewlines); value.summary.template = template.string
        return value
    }
    @objc private func save() {
        let value = draft()
        do {
            if !value.remote.host.isEmpty { _ = try SSHCommand.arguments(for: value.remote) }
            guard !value.options.model.isEmpty, !value.remote.root.isEmpty else { throw MurmureError.message("Enter a model and a worker data folder.") }
            guard !value.dictation.enabled || value.dictation.shortcut.hasModifier else { throw MurmureError.message("Use Control, Option or Command in the dictation shortcut.") }
            if value.summary.automatic {
                _ = try SummaryService.executable(settings: value.summary)
                guard !value.summary.template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MurmureError.message("Write a summary template first.") }
            }
            try onSave(value); close()
        } catch { feedback.stringValue = error.localizedDescription }
    }
    @objc private func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { folder.stringValue = url.path }
    }
    private func chooseExecutable(into field: NSTextField) {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let url = panel.url { field.stringValue = url.path }
    }
    @objc private func chooseCodex() { chooseExecutable(into: codex) }
    @objc private func chooseClaude() { chooseExecutable(into: claude) }
    @objc private func testAgent() {
        let value = draft(); feedback.stringValue = "Checking CLI…"
        Task {
            do { feedback.stringValue = "\(try await SummaryService.version(settings: value.summary)). Version check only; sign in through Terminal." }
            catch { feedback.stringValue = error.localizedDescription }
        }
    }
    @objc private func testConnection() {
        let value = draft(); testButton.isEnabled = false; feedback.stringValue = "Connecting…"
        Task {
            defer { testButton.isEnabled = true }
            do {
                let result = try await WorkerClient(endpoint: value.remote, localPython: value.localPython, localRoot: localRoot).request(op: "probe")
                if result.transcriptionInstalled == false { feedback.stringValue = "Connected, but worker/requirements.txt is not installed in that Python." }
                else if value.options.diarization && result.diarizationInstalled == false { feedback.stringValue = "Connected; speaker labels need diarization dependencies and model access." }
                else { feedback.stringValue = "Connected to worker \(result.version ?? "unknown"). Model weights are checked on use." }
            } catch { feedback.stringValue = error.localizedDescription }
        }
    }
}
