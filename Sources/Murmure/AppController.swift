import AppKit
import MurmureCore
import MurmureUI

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var repository: JobRepository!
    private var settings = AppSettings()
    private var jobs: [RecordingJob] = []
    private let recorder = AudioRecorder()
    private var dictation: DictationController!
    private let indicator = DictationIndicator(frame: NSRect(origin: .zero, size: DictationIndicator.preferredSize))
    private let shortcut = GlobalShortcut()
    private var shortcutDown = false
    private var recordingID: String?
    private var transitioning = false
    private var checking = false
    private var submissions: Set<String> = []
    private var summaryTasks: [String: Task<Void, Never>] = [:]
    private var summaryQueue: [(id: String, configuration: SummarySettings, userInitiated: Bool)] = []
    private var settingsWindow: SettingsWindow?
    private var transcriptWindow: TranscriptWindow?
    private var activeMenu: NSMenu?
    private var deferredTranscriptID: String?
    private var deferredTranscriptShouldActivate = true
    private var lastCheckMessage = "Results are checked on demand; there is no background polling."

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            repository = try JobRepository(root: support.appendingPathComponent("Murmure/Recordings", isDirectory: true))
            if let data = UserDefaults.standard.data(forKey: "settings"), let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) { settings = decoded }
            jobs = try repository.load().map(JobRepository.recovered)
            for job in jobs { try repository.save(job) }
        } catch { showError(error); NSApp.terminate(nil); return }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self; button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Murmure recording and transcription")
        }
        recorder.interrupted = { [weak self] error in
            guard let self, self.recordingID != nil, !self.transitioning else { return }
            Task { await self.stopRecording(interruption: error) }
        }
        dictation = DictationController(repository: repository)
        dictation.phaseChanged = { [weak self] phase in self?.indicator.setPhase(phase); self?.updateIndicator() }
        dictation.levelChanged = { [weak self] level in self?.indicator.setLevel(level) }
        dictation.saved = { [weak self] job in try self?.persist(job) }
        dictation.failed = { [weak self] error in self?.showError(error) }
        dictation.resultNeedsCopy = { [weak self] id in
            self?.lastCheckMessage = "Dictation is ready to copy. Check its recovery window."
            self?.offerTranscript(id: id, activate: false)
        }
        shortcut.changed = { [weak self] pressed in self?.shortcutChanged(pressed) }
        var shortcutNeedsSetup = false
        do { try shortcut.register(settings.dictation.shortcut, enabled: settings.dictation.enabled) }
        catch { lastCheckMessage = error.localizedDescription; shortcutNeedsSetup = true }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        updateIndicator()
        if (settings.remote.host.isEmpty && jobs.isEmpty) || shortcutNeedsSetup { showSettings(nil) }
        Task { await refreshPending() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if dictation?.isActive == true {
            showError(MurmureError.message("Finish or cancel dictation from the menu before quitting.")); return .terminateCancel
        }
        if recordingID != nil || transitioning {
            showError(MurmureError.message("Stop the recording before quitting so its audio can be finalized."))
            return .terminateCancel
        }
        if !submissions.isEmpty {
            showError(MurmureError.message("Audio is still being sent. Wait for the transfer to finish before quitting."))
            return .terminateCancel
        }
        for task in summaryTasks.values { task.cancel() }
        summaryQueue.removeAll()
        for var job in jobs where job.summary?.state == .running || job.summary?.state == .queued {
            job.summary?.state = .interrupted; job.summary?.error = "Summarization stopped when Murmure quit. Retry manually."
            try? persist(job)
        }
        return .terminateNow
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { openMenu(); return }
        if dictation?.isActive == true { dictation.stop(); return }
        toggleRecording(nil)
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let command = DictationCommand.parse(url) else { continue }
            switch command {
            case .start: startDictation()
            case .stop: dictation?.stop()
            case .cancel: dictation?.cancel()
            case .toggle: toggleDictation()
            }
        }
    }
    private func shortcutChanged(_ pressed: Bool) {
        if pressed {
            guard !shortcutDown else { return }; shortcutDown = true
            if settings.dictation.gesture == .toggle { toggleDictation() } else { startDictation() }
        } else {
            guard shortcutDown else { return }; shortcutDown = false
            if settings.dictation.gesture == .hold { dictation.stop() }
        }
    }
    private func startDictation() {
        guard recordingID == nil, !transitioning, dictation != nil else { return }
        dictation.start(settings: settings)
    }
    @objc private func toggleDictation() {
        if dictation?.isActive == true { dictation.stop() } else { startDictation() }
    }
    @objc private func cancelDictation() { dictation.cancel() }
    @objc private func didWake() { Task { await refreshPending() } }

    private func updateIndicator() {
        guard let button = statusItem?.button else { return }
        if dictation?.isActive == true {
            statusItem.length = DictationIndicator.preferredSize.width + 2; button.image = nil
            if indicator.superview == nil { button.addSubview(indicator) }
            indicator.frame = NSRect(origin: NSPoint(x: 1, y: (button.bounds.height - DictationIndicator.preferredSize.height) / 2), size: DictationIndicator.preferredSize)
            indicator.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            button.toolTip = dictation.phase == .listening ? "Dictating. Release the shortcut or click to finish. Right-click to cancel." : "Processing dictation. Right-click to cancel."
            button.setAccessibilityLabel(dictation.phase == .listening ? "Murmure is listening" : "Murmure is processing dictation")
            return
        }
        indicator.setPhase(.idle); indicator.removeFromSuperview(); statusItem.length = NSStatusItem.squareLength
        button.setAccessibilityLabel("Murmure recording and transcription")
        let recording = recordingID != nil && !transitioning
        let readyCount = jobs.filter { $0.hasUnreadTranscript || $0.hasUnreadSummary }.count
        let symbol = recording ? "record.circle.fill" : (transitioning ? "ellipsis.circle" : (readyCount > 0 ? "text.bubble.fill" : "waveform.circle"))
        var image = NSImage(systemSymbolName: symbol, accessibilityDescription: recording ? "Stop recording" : "Start recording")
        if recording { image = image?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemRed])) }
        image?.isTemplate = !recording; button.image = image
        button.contentTintColor = nil
        button.toolTip = recording ? "Recording. Click to stop. Right-click for options." : (readyCount > 0 ? "\(readyCount) unread transcript(s). Right-click to open. Click to record." : "Click to record. Right-click for sources, transcripts and Settings.")
    }

    private func menuItem(_ title: String, action: Selector?, represented: Any? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; item.representedObject = represented
        return item
    }

    private func openMenu() {
        let menu = NSMenu(); menu.autoenablesItems = false
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development"
        let heading = menuItem("Murmure \(version)", action: nil); heading.isEnabled = false; menu.addItem(heading)
        let record = menuItem(recordingID == nil ? "Start recording" : "Stop recording", action: #selector(toggleRecording))
        record.isEnabled = !transitioning && !dictation.isActive; menu.addItem(record)
        let dictate = menuItem(dictation.isActive ? "Finish dictation" : "Start dictation (\(settings.dictation.shortcut.display))", action: #selector(toggleDictation))
        dictate.isEnabled = settings.dictation.enabled && recordingID == nil && !transitioning && dictation.phase != .processing
        menu.addItem(dictate)
        if dictation.isActive { menu.addItem(menuItem("Cancel dictation", action: #selector(cancelDictation))) }
        let source = menuItem("Audio source: \(settings.source.title)", action: nil)
        let sources = NSMenu()
        for value in AudioSource.allCases {
            let item = menuItem(value.title, action: #selector(selectSource), represented: value.rawValue)
            item.state = settings.source == value ? .on : .off
            item.isEnabled = recordingID == nil && !transitioning; sources.addItem(item)
        }
        source.submenu = sources; menu.addItem(source)
        let timestamps = menuItem("Add timestamps", action: #selector(toggleTimestamps))
        timestamps.state = settings.options.timestamps ? .on : .off; timestamps.isEnabled = recordingID == nil && !transitioning; menu.addItem(timestamps)
        let speakers = menuItem("Label speakers", action: #selector(toggleDiarization))
        speakers.state = settings.options.diarization ? .on : .off; speakers.isEnabled = recordingID == nil && !transitioning; menu.addItem(speakers)
        menu.addItem(.separator())
        let check = menuItem(checking ? "Checking results…" : "Check results", action: #selector(checkResults))
        check.tag = 1001; check.isEnabled = !checking; menu.addItem(check)
        let feedback = menuItem(lastCheckMessage, action: nil); feedback.tag = 1002; feedback.isEnabled = false; menu.addItem(feedback)
        let recordings = jobs.filter { $0.effectiveKind == .recording }
        for job in recordings.prefix(12) {
            let row = menuItem(jobTitle(job), action: nil, represented: job.id)
            row.tag = 2001
            row.submenu = jobActions(job); menu.addItem(row)
        }
        if recordings.count > 12 {
            let older = menuItem("Older recordings (\(recordings.count - 12))", action: nil)
            older.submenu = historyMenu(Array(recordings.dropFirst(12))); menu.addItem(older)
        }
        let dictations = jobs.filter { $0.effectiveKind == .dictation }
        if !dictations.isEmpty {
            let history = menuItem("Dictation history (\(dictations.count))", action: nil)
            history.submenu = historyMenu(dictations); menu.addItem(history)
        }
        if !jobs.isEmpty { menu.addItem(menuItem("Show all recording files…", action: #selector(showAllRecordings))) }
        menu.addItem(.separator())
        let preferences = menuItem("Settings…", action: #selector(showSettings)); preferences.isEnabled = !dictation.isActive; menu.addItem(preferences)
        menu.addItem(menuItem("Quit Murmure", action: #selector(quit)))
        activeMenu = menu
        Task { await refreshPending() }
        if let button = statusItem.button { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button) }
        activeMenu = nil
        if let id = deferredTranscriptID { deferredTranscriptID = nil; presentTranscript(id: id, activate: deferredTranscriptShouldActivate) }
    }

    private func historyMenu(_ history: [RecordingJob]) -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        for job in history {
            let row = menuItem(jobTitle(job), action: nil, represented: job.id); row.tag = 2001
            row.submenu = jobActions(job); menu.addItem(row)
        }
        return menu
    }

    private func jobTitle(_ job: RecordingJob) -> String {
        let time = DateFormatter.localizedString(from: job.createdAt, dateStyle: .short, timeStyle: .short)
        let duration = job.duration.map { " · \(Transcript.timestamp($0))" } ?? ""
        let status = job.summary?.state == .queued ? "Summary queued" : (job.summary?.state == .running ? "Summarizing…" : (job.hasUnreadSummary ? "Summary ready" : job.state.title))
        return "\(job.hasUnreadTranscript || job.hasUnreadSummary ? "New · " : "")\(time) · \(job.effectiveKind == .dictation ? "Dictation" : job.source.title)\(duration) · \(status)"
    }
    private func jobActions(_ job: RecordingJob) -> NSMenu {
        let actions = NSMenu()
        if job.state == .completed {
            actions.addItem(menuItem("Open transcript…", action: #selector(openTranscript), represented: job.id))
            actions.addItem(menuItem("Export Markdown…", action: #selector(exportMarkdown), represented: job.id))
            if job.effectiveKind == .recording {
                let summarize = menuItem("Summarize with \(settings.summary.provider.title)…", action: #selector(summarizeFromMenu), represented: job.id)
                summarize.isEnabled = summaryTasks[job.id] == nil && !summaryQueue.contains(where: { $0.id == job.id }); actions.addItem(summarize)
                if job.summary?.state == .queued || job.summary?.state == .running { actions.addItem(menuItem("Cancel summary", action: #selector(cancelSummary), represented: job.id)) }
            }
            if job.summary?.state == .completed { actions.addItem(menuItem("Open summary…", action: #selector(openSummary), represented: job.id)) }
            if let error = job.summary?.error {
                let detail = menuItem("Summary: \(String(error.prefix(100)))", action: #selector(showSummaryError), represented: job.id); actions.addItem(detail)
            }
        }
        if let message = job.message, !message.isEmpty {
            let detail = menuItem(String(message.prefix(120)), action: nil); detail.isEnabled = false; actions.addItem(detail)
            actions.addItem(menuItem("Show details…", action: #selector(showJobDetails), represented: job.id))
        }
        if job.captureWarning != nil { actions.addItem(menuItem("Capture warning…", action: #selector(showCaptureWarning), represented: job.id)) }
        if [.queued, .failed, .interrupted].contains(job.state) { actions.addItem(menuItem("Send / retry over SSH", action: #selector(retryRemote), represented: job.id)) }
        if [.queued, .failed, .interrupted, .remote].contains(job.state) { actions.addItem(menuItem("Process on this Mac…", action: #selector(runLocal), represented: job.id)) }
        if [.failed, .interrupted].contains(job.state), let directory = try? repository.directory(for: job.id),
           !FileManager.default.fileExists(atPath: directory.appendingPathComponent("audio.m4a").path) {
            for filename in ["microphone.m4a", "system.m4a"] where FileManager.default.fileExists(atPath: directory.appendingPathComponent(filename).path) {
                let recovery = menuItem(filename == "microphone.m4a" ? "Recover microphone audio…" : "Recover Mac audio…", action: #selector(recoverCapture), represented: [job.id, filename])
                actions.addItem(recovery)
            }
        }
        actions.addItem(menuItem("Show recording folder", action: #selector(showRecordingFolder), represented: job.id))
        return actions
    }
    private func refreshVisibleMenu() {
        guard let menu = activeMenu else { return }
        menu.item(withTag: 1001)?.title = checking ? "Checking results…" : "Check results"
        menu.item(withTag: 1001)?.isEnabled = !checking
        menu.item(withTag: 1002)?.title = lastCheckMessage
        func refresh(_ menu: NSMenu) {
            for item in menu.items {
                if item.tag == 2001, let id = item.representedObject as? String, let job = jobs.first(where: { $0.id == id }) {
                    item.title = jobTitle(job); item.submenu = jobActions(job)
                } else if let submenu = item.submenu { refresh(submenu) }
            }
        }
        refresh(menu)
    }

    @objc private func toggleRecording(_ sender: Any?) {
        guard !transitioning, dictation?.isActive != true else { return }
        Task { if recordingID == nil { await startRecording() } else { await stopRecording() } }
    }
    private func startRecording() async {
        transitioning = true; updateIndicator()
        var job = RecordingJob(source: settings.source, options: settings.options)
        if settings.summary.automatic { job.automaticSummary = settings.summary }
        var started = false
        do {
            try await recorder.start(source: job.source, directory: repository.directory(for: job.id))
            started = true; job.createdAt = Date()
            try persist(job)
            recordingID = job.id
        } catch {
            if started { _ = try? await recorder.stop() }
            let directory = try? repository.directory(for: job.id)
            let hasCapture = directory.map { directory in
                ["microphone.m4a", "system.m4a", "audio.m4a"].contains { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
            } ?? false
            if started || hasCapture { job.state = .failed; job.message = error.localizedDescription; try? persist(job) }
            showError(error)
        }
        transitioning = false; updateIndicator()
    }
    private func stopRecording(interruption: Error? = nil) async {
        guard let id = recordingID, var job = jobs.first(where: { $0.id == id }) else { return }
        transitioning = true; job.state = .preparing; job.duration = max(0, Date().timeIntervalSince(job.createdAt)); try? persist(job); updateIndicator()
        do {
            let capture = try await recorder.stop(); job.captureWarning = capture.warning
            job.state = .queued; job.message = interruption.map { "Capture was interrupted: \($0.localizedDescription). Saved audio is available." }
            try persist(job)
        } catch {
            job.state = .failed; job.message = error.localizedDescription; try? persist(job); showError(error)
        }
        recordingID = nil; transitioning = false; updateIndicator()
        if job.state == .queued, interruption == nil { await submit(id: id, locally: false) }
    }

    private func persist(_ job: RecordingJob) throws {
        try repository.save(job)
        if let index = jobs.firstIndex(where: { $0.id == job.id }) { jobs[index] = job }
        else { jobs.insert(job, at: 0) }
        updateIndicator(); refreshVisibleMenu()
    }
    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "settings") }
    }
    @objc private func selectSource(_ item: NSMenuItem) {
        if let raw = item.representedObject as? String, let value = AudioSource(rawValue: raw) { settings.source = value; saveSettings() }
    }
    @objc private func toggleTimestamps() { settings.options.timestamps.toggle(); saveSettings() }
    @objc private func toggleDiarization() { settings.options.diarization.toggle(); saveSettings() }
    @objc private func checkResults() { Task { await refreshPending(userInitiated: true) } }
    @objc private func retryRemote(_ item: NSMenuItem) {
        if let id = item.representedObject as? String { Task { await submit(id: id, locally: false) } }
    }
    @objc private func runLocal(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        let alert = NSAlert(); alert.messageText = "Process on this Mac?"
        alert.informativeText = "This uses this Mac’s processor and battery. Any remote job already submitted may still finish. The local worker must be configured in Settings."
        alert.addButton(withTitle: "Process locally"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { Task { await submit(id: id, locally: true) } }
    }

    @objc private func recoverCapture(_ item: NSMenuItem) {
        guard let values = item.representedObject as? [String], values.count == 2,
              let job = jobs.first(where: { $0.id == values[0] }) else { return }
        let alert = NSAlert(); alert.messageText = "Recover this audio track?"
        alert.informativeText = "Only the selected track will be used. Recovery preserves the original files and does not send audio or insert text. An unfinished capture may not be readable."
        alert.addButton(withTitle: "Recover"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            do {
                let directory = try repository.directory(for: job.id)
                let result = try await AudioFinalizer.single(directory.appendingPathComponent(values[1]), directory: directory,
                    warning: "Recovered only \(values[1] == "microphone.m4a" ? "microphone" : "Mac") audio from an incomplete recording. Original files are kept.")
                var recovered = job; recovered.captureWarning = result.warning; recovered.state = .queued
                recovered.message = "Audio recovered. Choose Send / retry over SSH or Process on this Mac to transcribe it."
                try persist(recovered); showInformation(recovered.message!)
            } catch { showError(error) }
        }
    }
    @objc private func showCaptureWarning(_ item: NSMenuItem) {
        if let id = item.representedObject as? String, let warning = jobs.first(where: { $0.id == id })?.captureWarning { showInformation(warning) }
    }

    private func submit(id: String, locally: Bool) async {
        guard !submissions.contains(id), var job = jobs.first(where: { $0.id == id }) else { return }
        guard let audio = try? repository.audio(for: id), FileManager.default.fileExists(atPath: audio.path) else {
            showError(MurmureError.message("No finalized audio is available. Original capture files, if any, are in the recording folder.")); return
        }
        if !locally && settings.remote.host.isEmpty {
            job.state = .queued; job.message = "Recording saved. Set up the SSH connection in Settings, then choose Send / retry over SSH."
            try? persist(job); return
        }
        submissions.insert(id); defer { submissions.remove(id) }
        job.endpoint = locally ? nil : settings.remote; job.state = .uploading; job.message = nil
        job.localWorkerRoot = locally ? repository.separateLocalWorkerRoot.path : nil
        do {
            try persist(job)
            let client = WorkerClient(endpoint: job.endpoint, localPython: settings.localPython, localRoot: repository.localWorkerRoot(for: job))
            let response = try await client.request(op: "submit", job: job, audio: audio)
            job.state = locally ? .local : .remote
            try persist(job)
            if try accept(response, job: job) { offerTranscript(id: job.id) }
        } catch {
            job.state = .failed; job.message = error.localizedDescription; try? persist(job); showError(error)
        }
    }

    private func refreshPending(userInitiated: Bool = false) async {
        guard !checking else { return }
        checking = true; refreshVisibleMenu()
        defer { checking = false; updateIndicator(); refreshVisibleMenu() }
        var unavailable: Set<WorkerEndpoint> = []
        var localUnavailable = false
        var newlyCompleted: [String] = []
        for job in jobs where [.remote, .local].contains(job.state) {
            if let endpoint = job.endpoint, unavailable.contains(endpoint) { continue }
            if job.endpoint == nil && localUnavailable { continue }
            do {
                let client = WorkerClient(endpoint: job.endpoint, localPython: settings.localPython, localRoot: repository.localWorkerRoot(for: job))
                let response = try await client.request(op: "status", job: job)
                guard let current = jobs.first(where: { $0.id == job.id }), current.endpoint == job.endpoint,
                      [.remote, .local].contains(current.state) else { continue }
                if try accept(response, job: current) { newlyCompleted.append(current.id) }
            } catch {
                if let endpoint = job.endpoint { unavailable.insert(endpoint) } else { localUnavailable = true }
                if var current = jobs.first(where: { $0.id == job.id }), current.endpoint == job.endpoint,
                   [.remote, .local].contains(current.state) {
                    current.message = "Could not check results: \(error.localizedDescription)"; try? persist(current)
                }
            }
        }
        let pendingCount = jobs.filter { [.remote, .local].contains($0.state) }.count
        if !unavailable.isEmpty || localUnavailable { lastCheckMessage = "A worker is unreachable. Saved audio is safe; see job details." }
        else if pendingCount > 0 { lastCheckMessage = "\(pendingCount) job(s) still processing. Check again when convenient." }
        else { lastCheckMessage = "No jobs waiting for results." }
        if userInitiated, recordingID == nil, !transitioning, !dictation.isActive {
            if let id = newlyCompleted.first ?? jobs.first(where: \.hasUnreadTranscript)?.id { offerTranscript(id: id) }
            else { showInformation(lastCheckMessage) }
        }
    }

    @discardableResult
    private func accept(_ response: WorkerResponse, job: RecordingJob) throws -> Bool {
        var updated = job
        switch response.state {
        case "completed":
            guard let transcript = response.transcript else { throw MurmureError.message("The worker reported completion without a transcript.") }
            let directory = try repository.directory(for: job.id)
            let text = MarkdownWorkflow.transcript(transcript, job: job)
            let file = directory.appendingPathComponent("transcript.md")
            try text.write(to: file, atomically: true, encoding: .utf8)
            try JSONEncoder().encode(transcript).write(to: directory.appendingPathComponent("transcript.json"), options: .atomic)
            updated.transcriptPath = file.path; updated.state = .completed; updated.message = nil
            if job.state != .completed { updated.transcriptViewedAt = nil }
            if job.effectiveKind == .recording {
                do { updated.exportedTranscriptPath = try MarkdownWorkflow.writeUnique(text, to: outputFolder.appendingPathComponent(MarkdownWorkflow.filename(for: job))).path }
                catch { updated.message = "Transcript saved inside Murmure. Export to the chosen folder failed: \(error.localizedDescription)" }
            }
        case "failed": updated.state = .failed; updated.message = response.error ?? "Transcription failed. The recording has been kept."
        case "missing": updated.state = .queued; updated.message = "The worker has no copy of this recording. Choose Send / retry over SSH, or process locally."
        case "queued", "running", "receiving": updated.message = nil
        default: throw MurmureError.message("Unknown worker state: \(response.state)")
        }
        try persist(updated)
        let newlyCompleted = job.state != .completed && updated.state == .completed
        if newlyCompleted, updated.effectiveKind == .recording, settings.summary.automatic, let configuration = job.automaticSummary {
            startSummary(id: job.id, configuration: configuration, userInitiated: false)
        }
        return newlyCompleted
    }

    private var outputFolder: URL {
        settings.outputFolder.isEmpty ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Murmure") : URL(fileURLWithPath: settings.outputFolder)
    }
    @objc private func exportMarkdown(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String, var job = jobs.first(where: { $0.id == id }), let path = job.transcriptPath else { return }
        do {
            var text = try String(contentsOfFile: path, encoding: .utf8)
            if URL(fileURLWithPath: path).pathExtension.lowercased() != "md" { text = "# Transcript\n\n" + text }
            let exported = try MarkdownWorkflow.writeUnique(text, to: outputFolder.appendingPathComponent(MarkdownWorkflow.filename(for: job)))
            job.exportedTranscriptPath = exported.path; try persist(job)
            NSWorkspace.shared.activateFileViewerSelecting([exported])
        } catch { showError(error) }
    }
    @objc private func summarizeFromMenu(_ item: NSMenuItem) {
        if let id = item.representedObject as? String { startSummary(id: id, configuration: settings.summary, userInitiated: true) }
    }
    private func startSummary(id: String, configuration: SummarySettings, userInitiated: Bool) {
        guard summaryTasks[id] == nil, !summaryQueue.contains(where: { $0.id == id }) else { return }
        if !summaryTasks.isEmpty {
            summaryQueue.append((id, configuration, userInitiated))
            if var job = jobs.first(where: { $0.id == id }) {
                job.summary = SummaryRecord(state: .queued, provider: configuration.provider); try? persist(job)
            }
            return
        }
        summaryTasks[id] = Task { [weak self] in
            guard let self else { return }
            defer {
                summaryTasks.removeValue(forKey: id); refreshVisibleMenu()
                if !summaryQueue.isEmpty {
                    let next = summaryQueue.removeFirst()
                    startSummary(id: next.id, configuration: next.configuration, userInitiated: next.userInitiated)
                }
            }
            guard var job = jobs.first(where: { $0.id == id }), job.state == .completed, let original = job.exportedTranscriptPath ?? job.transcriptPath else { return }
            do {
                let source = try String(contentsOfFile: original, encoding: .utf8)
                job.summary = SummaryRecord(state: .running, provider: configuration.provider); try persist(job)
                let text = try await SummaryService.run(settings: configuration, transcript: source, title: URL(fileURLWithPath: original).lastPathComponent)
                try Task.checkCancellation()
                guard var current = jobs.first(where: { $0.id == id }) else { return }
                let internalFile = try MarkdownWorkflow.writeUnique(text, to: repository.directory(for: id).appendingPathComponent("summary.md"))
                var result = SummaryRecord(state: .completed, provider: configuration.provider); result.path = internalFile.path
                if let exported = current.exportedTranscriptPath {
                    do { result.exportedPath = try MarkdownWorkflow.writeUnique(text, to: URL(fileURLWithPath: exported).deletingPathExtension().appendingPathExtension("summary.md")).path }
                    catch { result.error = "Summary saved inside Murmure; export failed: \(error.localizedDescription)" }
                }
                current.summary = result; try persist(current)
                if userInitiated, !dictation.isActive { presentSummary(id: id) }
            } catch {
                if var current = jobs.first(where: { $0.id == id }) {
                    current.summary = SummaryRecord(state: error is CancellationError ? .interrupted : .failed, provider: configuration.provider)
                    current.summary?.error = error is CancellationError ? "Summarization cancelled. The original transcript is kept." : error.localizedDescription
                    try? persist(current)
                }
                if userInitiated, !(error is CancellationError) { showError(error) }
            }
        }
    }
    @objc private func cancelSummary(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        summaryQueue.removeAll { $0.id == id }; summaryTasks[id]?.cancel()
        if var job = jobs.first(where: { $0.id == id }), job.summary?.state == .queued {
            job.summary?.state = .interrupted; job.summary?.error = "Summary cancelled. The original transcript is kept."; try? persist(job)
        }
    }
    @objc private func openSummary(_ item: NSMenuItem) {
        if let id = item.representedObject as? String { presentSummary(id: id) }
    }
    private func presentSummary(id: String) {
        guard var job = jobs.first(where: { $0.id == id }), let path = job.summary?.path else { return }
        do {
            transcriptWindow?.close()
            transcriptWindow = TranscriptWindow(text: try String(contentsOfFile: path, encoding: .utf8), file: URL(fileURLWithPath: path))
            transcriptWindow?.window?.title = "Murmure Summary"
            transcriptWindow?.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
            job.summary?.viewedAt = Date(); try persist(job)
        } catch { showError(error) }
    }
    @objc private func showSummaryError(_ item: NSMenuItem) {
        if let id = item.representedObject as? String, let error = jobs.first(where: { $0.id == id })?.summary?.error { showInformation(error) }
    }

    @objc private func showSettings(_ sender: Any?) {
        settingsWindow?.close()
        settingsWindow = SettingsWindow(settings: settings, localRoot: repository.separateLocalWorkerRoot, onShortcutCapture: { [weak self] capturing in
            guard let self else { return }
            if capturing { self.shortcut.unregister(); self.shortcutDown = false }
            else { try? self.shortcut.register(self.settings.dictation.shortcut, enabled: self.settings.dictation.enabled) }
        }) { [weak self] updated in
            guard let self else { return }
            do { try shortcut.register(updated.dictation.shortcut, enabled: updated.dictation.enabled) }
            catch { try? shortcut.register(settings.dictation.shortcut, enabled: settings.dictation.enabled); throw error }
            settings = updated; saveSettings()
            if !updated.summary.automatic {
                let cancelled = summaryQueue.filter { !$0.userInitiated }
                summaryQueue.removeAll { !$0.userInitiated }
                for request in cancelled {
                    if var job = jobs.first(where: { $0.id == request.id }) {
                        job.summary?.state = .interrupted; job.summary?.error = "Automatic summarization was turned off before this job started."; try? persist(job)
                    }
                }
            }
        }
        settingsWindow?.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func openTranscript(_ item: NSMenuItem) {
        if let id = item.representedObject as? String { presentTranscript(id: id) }
    }
    private func offerTranscript(id: String, activate: Bool = true) {
        guard recordingID == nil, !transitioning, !dictation.isActive else { return }
        if activeMenu != nil { deferredTranscriptID = id; deferredTranscriptShouldActivate = activate }
        else { presentTranscript(id: id, activate: activate) }
    }
    private func presentTranscript(id: String, activate: Bool = true) {
        guard var job = jobs.first(where: { $0.id == id }), let path = job.transcriptPath else { return }
        do {
            var text = try String(contentsOfFile: path, encoding: .utf8)
            if job.effectiveKind == .dictation,
               let data = try? Data(contentsOf: repository.directory(for: id).appendingPathComponent("transcript.json")),
               let transcript = try? JSONDecoder().decode(Transcript.self, from: data) {
                text = transcript.segments.map(\.text).joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
            }
            transcriptWindow?.close()
            transcriptWindow = TranscriptWindow(text: text, file: URL(fileURLWithPath: path), notice: [job.captureWarning, job.message].compactMap { $0 }.joined(separator: "\n"), onCopy: { [weak self] in
                guard let self, var current = self.jobs.first(where: { $0.id == id }) else { return }
                current.transcriptViewedAt = Date(); try? self.persist(current)
            })
            if activate {
                transcriptWindow?.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
                job.transcriptViewedAt = Date(); try persist(job)
            } else {
                // A recovery result is visible without stealing focus while an
                // editor may still be handling posted Unicode events.
                transcriptWindow?.window?.orderFrontRegardless()
            }
        } catch { showError(error) }
    }
    @objc private func showJobDetails(_ item: NSMenuItem) {
        if let id = item.representedObject as? String, let message = jobs.first(where: { $0.id == id })?.message { showInformation(message) }
    }
    @objc private func showRecordingFolder(_ item: NSMenuItem) {
        if let id = item.representedObject as? String, let directory = try? repository.directory(for: id) { NSWorkspace.shared.open(directory) }
    }
    @objc private func showAllRecordings() { NSWorkspace.shared.open(repository.root) }
    @objc private func quit() { NSApp.terminate(nil) }
    private func showInformation(_ message: String) {
        if dictation?.isActive == true { lastCheckMessage = message; return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = "Murmure"; alert.informativeText = message
        alert.addButton(withTitle: "OK"); alert.runModal()
    }
    private func showError(_ error: Error) {
        if dictation?.isActive == true { lastCheckMessage = error.localizedDescription; return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = "Murmure needs attention"; alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK"); alert.runModal()
    }
}
