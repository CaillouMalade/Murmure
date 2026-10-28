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
    private let localPython = NSTextField(), folder = NSTextField(), language = NSTextField()
    private let model = NSComboBox()
    private let timeout = NSPopUpButton()
    private let insert = NSButton(checkboxWithTitle: "Insert finished dictation at the original cursor", target: nil, action: nil)
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
    private var prepareRemote: NSButton!, prepareLocal: NSButton!, saveButton: NSButton!, cancelSetup: NSButton!
    private var setupTask: Task<Void, Never>?
    private let timeoutChoices = [60, 180, 300, 600, 1800]

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
        model.addItems(withObjectValues: ["tiny", "base", "small", "medium", "large-v3", "turbo"])
        model.isEditable = true; model.completes = true; model.stringValue = settings.options.model
        language.stringValue = settings.options.language; language.placeholderString = "Automatic, or en / fr / de…"
        timeout.addItems(withTitles: timeoutChoices.map { "\($0 / 60) minute\($0 == 60 ? "" : "s")" })
        timeout.selectItem(at: timeoutChoices.firstIndex(where: { $0 >= settings.dictation.timeoutSeconds }) ?? 1)
        codex.stringValue = settings.summary.codexPath; codex.placeholderString = "/opt/homebrew/bin/codex"
        claude.stringValue = settings.summary.claudePath; claude.placeholderString = "/Users/you/.local/bin/claude"
        timestamps.state = settings.options.timestamps ? .on : .off; speakers.state = settings.options.diarization ? .on : .off
        enabled.state = settings.dictation.enabled ? .on : .off; copy.state = settings.dictation.copyToClipboard ? .on : .off
        insert.state = settings.dictation.insertAtCursor ? .on : .off
        automatic.state = settings.summary.automatic ? .on : .off
        shortcut.value = settings.dictation.shortcut; shortcut.captureChanged = onShortcutCapture
        template.string = settings.summary.template; template.font = .systemFont(ofSize: 13); template.isRichText = false
        template.isAutomaticQuoteSubstitutionEnabled = false; template.isAutomaticDashSubstitutionEnabled = false
        template.isVerticallyResizable = true; template.autoresizingMask = [.width]; template.textContainer?.widthTracksTextView = true

        let tabs = NSTabView()
        let output = pathRow(folder, title: "Choose…", action: #selector(chooseFolder))
        let setupGrid = grid([("SSH alias", host), ("Remote Python", python), ("Remote worker", script), ("Remote data folder", root), ("Whisper model", model), ("Language", language), ("Remote processor", device)])
        testButton = NSButton(title: "Test SSH connection", target: self, action: #selector(testConnection))
        prepareRemote = NSButton(title: "Download & check SSH model…", target: self, action: #selector(prepareSSHModel))
        prepareLocal = NSButton(title: "Download & check local model…", target: self, action: #selector(prepareLocalModel))
        cancelSetup = NSButton(title: "Cancel check", target: self, action: #selector(cancelCheck)); cancelSetup.isHidden = true
        let checks = NSStackView(views: [testButton, prepareRemote, cancelSetup]); checks.orientation = .horizontal
        let setupHelp = NSStackView(views: [NSButton(title: "First-run guide", target: self, action: #selector(openGuide)), NSButton(title: "Copy Windows setup", target: self, action: #selector(copyWindowsSetup)), NSButton(title: "Copy Mac/Linux setup", target: self, action: #selector(copyUnixSetup))]); setupHelp.orientation = .horizontal
        addTab("Setup", to: tabs, views: [label("1. Install the worker on the computer that will transcribe audio. For SSH, that is your server: no Whisper or Python is needed on this Mac."), label("Use the matching worker ZIP, or a repository checkout. The commands below are for its folder and create a separate Python environment; they do not install or change SSH.", secondary: true), setupHelp, label("2. Configure key-based SSH and verify the server fingerprint in Terminal, then enter its alias and worker paths below."), setupGrid, label("3. Choose a model and prepare it before your first dictation. This downloads public weights on the selected computer and checks actual audio decoding. Nothing stays loaded afterwards."), label("small is a balanced multilingual starting point. tiny/base favor speed; medium/large-v3 use more resources. You can also enter a CTranslate2 model directory on the server. Select fr or en for short dictations if automatic language detection is unreliable. CPU works without CUDA; Auto uses a detected GPU and reports missing runtime libraries.", secondary: true), checks, label("Speaker labels need the optional diarization environment, FFmpeg and Community-1 model access on that computer. Turn Label speakers on under Recordings before preparing if you want its model checked too.", secondary: true), label("Optional: local Whisper for long recordings"), grid([("Local Python", localPython)]), prepareLocal, label("Local Whisper uses the same selected model and CPU. Local quick dictation instead uses Apple's on-device speech recognition and needs no Python or Whisper install. Finish by choosing Save.", secondary: true)])
        addTab("Recordings", to: tabs, views: [label("Click the icon to record; click again to save and transcribe. Right-click for recordings and actions."), grid([("Audio source", source), ("Markdown folder", output)]), timestamps, speakers, label("Transcripts are .md files in your chosen folder. Recordings and dictation have separate histories, and older recordings remain accessible. Capture problems preserve usable audio and show a warning in the transcript.", secondary: true)])
        addTab("Dictation", to: tabs, views: [label("Speak with a keyboard shortcut. The small menu-bar capsule animates while recording and processing, then inserts the finished text at the original cursor."), enabled, grid([("Speech engine", backend), ("Shortcut behavior", gesture), ("Shortcut", shortcut), ("Processing timeout", timeout)]), insert, copy, label("Turn cursor insertion off to use a Copy window without Accessibility permission. Unsupported editors also get a Copy window; unconfirmed delivery asks you to check the field before copying twice.", secondary: true), label("SSH uses the connection and prepared model under Setup. The timeout covers upload and processing after you stop speaking, not recording length. You can cancel from the menu. New installs use Control + Shift + Space; existing shortcuts are preserved. Control + Option + Space can conflict with macOS input-language switching.", secondary: true), label("Cursor insertion needs Accessibility permission. Password fields are excluded. If the cursor or field changes, the result is kept for Copy. On this Mac uses Apple's local speech engine when available for your language, with no cloud fallback.", secondary: true), label("Commands: open -g 'murmure://dictation/toggle'\nAlso available: /start, /stop and /cancel.", secondary: true)])
        let templateScroll = NSScrollView(); templateScroll.hasVerticalScroller = true; templateScroll.borderType = .bezelBorder; templateScroll.documentView = template
        templateScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 210).isActive = true
        let testCLI = NSButton(title: "Check CLI version", target: self, action: #selector(testAgent))
        addTab("Summaries", to: tabs, views: [label("Save the original Markdown transcript, then optionally ask a CLI agent to summarize it using your instructions. The summary is a separate .summary.md file beside it."), grid([("Agent", provider), ("Codex CLI", pathRow(codex, title: "Choose…", action: #selector(chooseCodex))), ("Claude Code CLI", pathRow(claude, title: "Choose…", action: #selector(chooseClaude)))]), automatic, label("Uses your signed-in CLI account and its normal usage limits. Automatic handoff applies only to new saved recordings with this option enabled; quick dictation is a typing action.", secondary: true), NSTextField(labelWithString: "Summary instructions / Markdown template"), templateScroll, testCLI])
        saveButton = NSButton(title: "Save", target: self, action: #selector(save)); saveButton.keyEquivalent = "\r"
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
    func windowWillClose(_ notification: Notification) { setupTask?.cancel(); onShortcutCapture(false) }
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
        value.options.model = model.stringValue.trimmingCharacters(in: .whitespacesAndNewlines); value.options.language = language.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        value.options.device = device.titleOfSelectedItem ?? "auto"
        value.remote = WorkerEndpoint(host: host.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), python: python.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), script: script.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), root: root.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        value.localPython = (localPython.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        value.outputFolder = (folder.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        value.dictation.enabled = enabled.state == .on; value.dictation.copyToClipboard = copy.state == .on
        value.dictation.insertAtCursor = insert.state == .on; value.dictation.timeoutSeconds = timeoutChoices[max(0, timeout.indexOfSelectedItem)]
        value.dictation.backend = DictationBackend.allCases[max(0, backend.indexOfSelectedItem)]; value.dictation.gesture = DictationGesture.allCases[max(0, gesture.indexOfSelectedItem)]
        value.dictation.shortcut = shortcut.value
        value.summary.provider = SummaryProvider.allCases[max(0, provider.indexOfSelectedItem)]; value.summary.automatic = automatic.state == .on
        value.summary.codexPath = codex.stringValue.trimmingCharacters(in: .whitespacesAndNewlines); value.summary.claudePath = claude.stringValue.trimmingCharacters(in: .whitespacesAndNewlines); value.summary.template = template.string
        return value
    }
    @objc private func save() {
        let value = draft()
        do {
            try value.options.validate()
            if !value.remote.host.isEmpty { _ = try SSHCommand.arguments(for: value.remote) }
            guard !value.options.model.isEmpty, !value.remote.root.isEmpty else { throw MurmureError.message("Enter a model and a worker data folder.") }
            guard value.outputFolder.isEmpty || value.outputFolder.hasPrefix("/") else { throw MurmureError.message("Choose a full Markdown folder path, or leave it empty for ~/Documents/Murmure.") }
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
        let value = draft(); setChecking(true); feedback.stringValue = "Connecting…"
        setupTask = Task {
            defer { setChecking(false); setupTask = nil }
            do {
                let result = try await WorkerClient(endpoint: value.remote, localPython: value.localPython, localRoot: localRoot).request(op: "probe")
                if result.transcriptionInstalled == false { feedback.stringValue = "Connected, but worker/requirements.txt is not installed in that Python." }
                else if value.options.diarization && result.diarizationInstalled == false { feedback.stringValue = "Connected; speaker labels need diarization dependencies and model access." }
                else if result.supportsModelPreparation != true { feedback.stringValue = "Connected to worker \(result.version ?? "unknown"). Update it to v0.4.0 for model preparation, then Download & check model." }
                else { feedback.stringValue = "Connected to worker \(result.version ?? "unknown"). Next, Download & check your selected model, then Save." }
            } catch { feedback.stringValue = error.localizedDescription }
        }
    }
    private func setChecking(_ value: Bool) {
        testButton.isEnabled = !value; prepareRemote.isEnabled = !value; prepareLocal.isEnabled = !value
        saveButton.isEnabled = !value; cancelSetup.isHidden = !value
    }
    @objc private func openGuide() {
        guard let url = Bundle.main.url(forResource: "START_HERE", withExtension: "txt") else {
            feedback.stringValue = "The first-run guide is in START_HERE.txt beside the downloaded app and in the repository."; return
        }
        NSWorkspace.shared.open(url)
    }
    @objc private func cancelCheck() { setupTask?.cancel() }
    @objc private func prepareSSHModel() { prepareModel(locally: false) }
    @objc private func prepareLocalModel() { prepareModel(locally: true) }
    private func prepareModel(locally: Bool) {
        let value = draft(), destination = locally ? "this Mac" : "SSH server \(value.remote.host)"
        do {
            try value.options.validate()
            if !locally { _ = try SSHCommand.arguments(for: value.remote) }
        } catch { feedback.stringValue = error.localizedDescription; return }
        let alert = NSAlert(); alert.messageText = "Prepare \(value.options.model) on \(destination)?"
        alert.informativeText = "Missing model files will be downloaded there from Hugging Face. This uses network, disk space and temporarily its processor/memory. A short silence checks audio decoding.\(value.options.diarization ? " The speaker-label model will also be loaded using that computer's existing Hugging Face access." : "") No recording or transcript is sent. Large models can take several minutes."
        alert.addButton(withTitle: "Download & check"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        setChecking(true); feedback.stringValue = "Preparing \(value.options.model) on \(destination)… Cancel is available; this can take several minutes."
        setupTask = Task {
            defer { setChecking(false); setupTask = nil }
            do {
                let client = WorkerClient(endpoint: locally ? nil : value.remote, localPython: value.localPython, localRoot: localRoot)
                let result = try await client.request(op: "prepare", options: value.options)
                guard result.state == "ready" else { throw MurmureError.message("The worker did not confirm model readiness.") }
                feedback.stringValue = "\(result.model ?? value.options.model) passed its audio check on \(destination) (\(result.device ?? "processor")). Save to use these settings."
            } catch is CancellationError { feedback.stringValue = "Check cancelled. Any downloaded cache files stay on the processing computer." }
            catch { feedback.stringValue = error.localizedDescription }
        }
    }
    @objc private func copyWindowsSetup() {
        copySetup("""
        # On the Windows processing computer, open PowerShell in the extracted
        # Murmure worker folder (or repository). Install Python 3.12 first.
        powershell -NoProfile -File scripts/setup-worker.ps1
        # Example paths when extracted to C:/Murmure:
        # Python: C:/Murmure/.venv/Scripts/python.exe
        # Worker: C:/Murmure/worker/murmure_worker.py
        # Then verify SSH from the Mac and prepare the model in Murmure Setup.
        """)
    }
    @objc private func copyUnixSetup() {
        copySetup("""
        # On the Mac/Linux processing computer, open Terminal in the extracted
        # Murmure worker folder (or repository). Python 3.11/3.12 is recommended.
        bash scripts/setup-worker.sh
        # Python: /full/path/to/Murmure/.venv/bin/python
        # Worker: /full/path/to/Murmure/worker/murmure_worker.py
        # For local Whisper, use the Python path under Setup > Local Python.
        """)
    }
    private func copySetup(_ text: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        feedback.stringValue = "Setup commands copied. Run them in the worker folder on the processing computer; nothing was installed by copying."
    }
}
