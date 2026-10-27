import AppKit
import MurmureCore

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var repository: JobRepository!
    private var settings = AppSettings()
    private var jobs: [RecordingJob] = []
    private let recorder = AudioRecorder()
    private var recordingID: String?
    private var transitioning = false
    private var checking = false
    private var submissions: Set<String> = []
    private var settingsWindow: SettingsWindow?
    private var transcriptWindow: TranscriptWindow?
    private var activeMenu: NSMenu?
    private var deferredTranscriptID: String?
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
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        updateIndicator()
        if settings.remote.host.isEmpty && jobs.isEmpty { showSettings(nil) }
        Task { await refreshPending() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if recordingID != nil || transitioning {
            showError(MurmureError.message("Stop the recording before quitting so its audio can be finalized."))
            return .terminateCancel
        }
        if !submissions.isEmpty {
            showError(MurmureError.message("Audio is still being sent. Wait for the transfer to finish before quitting."))
            return .terminateCancel
        }
        return .terminateNow
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { openMenu(); return }
        toggleRecording(nil)
    }
    @objc private func didWake() { Task { await refreshPending() } }

    private func updateIndicator() {
        guard let button = statusItem?.button else { return }
        let recording = recordingID != nil && !transitioning
        let readyCount = jobs.filter(\.hasUnreadTranscript).count
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
        record.isEnabled = !transitioning; menu.addItem(record)
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
        for job in jobs.prefix(12) {
            let row = menuItem(jobTitle(job), action: nil, represented: job.id)
            row.submenu = jobActions(job); menu.addItem(row)
        }
        if jobs.count > 12 { menu.addItem(menuItem("Show all recording files…", action: #selector(showAllRecordings))) }
        menu.addItem(.separator())
        menu.addItem(menuItem("Settings…", action: #selector(showSettings)))
        menu.addItem(menuItem("Quit Murmure", action: #selector(quit)))
        activeMenu = menu
        Task { await refreshPending() }
        if let button = statusItem.button { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button) }
        activeMenu = nil
        if let id = deferredTranscriptID { deferredTranscriptID = nil; presentTranscript(id: id) }
    }

    private func jobTitle(_ job: RecordingJob) -> String {
        let time = DateFormatter.localizedString(from: job.createdAt, dateStyle: .short, timeStyle: .short)
        let duration = job.duration.map { " · \(Transcript.timestamp($0))" } ?? ""
        return "\(job.hasUnreadTranscript ? "New · " : "")\(time) · \(job.source.title)\(duration) · \(job.state.title)"
    }
    private func jobActions(_ job: RecordingJob) -> NSMenu {
        let actions = NSMenu()
        if job.state == .completed { actions.addItem(menuItem("Open transcript…", action: #selector(openTranscript), represented: job.id)) }
        if let message = job.message, !message.isEmpty {
            let detail = menuItem(String(message.prefix(120)), action: nil); detail.isEnabled = false; actions.addItem(detail)
            actions.addItem(menuItem("Show details…", action: #selector(showJobDetails), represented: job.id))
        }
        if [.queued, .failed].contains(job.state) { actions.addItem(menuItem("Send / retry over SSH", action: #selector(retryRemote), represented: job.id)) }
        if [.queued, .failed, .remote].contains(job.state) { actions.addItem(menuItem("Process on this Mac…", action: #selector(runLocal), represented: job.id)) }
        actions.addItem(menuItem("Show recording folder", action: #selector(showRecordingFolder), represented: job.id))
        return actions
    }
    private func refreshVisibleMenu() {
        guard let menu = activeMenu else { return }
        menu.item(withTag: 1001)?.title = checking ? "Checking results…" : "Check results"
        menu.item(withTag: 1001)?.isEnabled = !checking
        menu.item(withTag: 1002)?.title = lastCheckMessage
        for item in menu.items {
            if let id = item.representedObject as? String, let job = jobs.first(where: { $0.id == id }) {
                item.title = jobTitle(job); item.submenu = jobActions(job)
            }
        }
    }

    @objc private func toggleRecording(_ sender: Any?) {
        guard !transitioning else { return }
        Task { if recordingID == nil { await startRecording() } else { await stopRecording() } }
    }
    private func startRecording() async {
        transitioning = true; updateIndicator()
        var job = RecordingJob(source: settings.source, options: settings.options)
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
            _ = try await recorder.stop()
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
        if userInitiated, recordingID == nil, !transitioning {
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
            let text = transcript.formatted(timestamps: job.options.timestamps)
            let file = directory.appendingPathComponent("transcript.txt")
            try text.write(to: file, atomically: true, encoding: .utf8)
            try JSONEncoder().encode(transcript).write(to: directory.appendingPathComponent("transcript.json"), options: .atomic)
            updated.transcriptPath = file.path; updated.state = .completed; updated.message = nil
            if job.state != .completed { updated.transcriptViewedAt = nil }
            do {
                let folder = settings.outputFolder.isEmpty ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Murmure") : URL(fileURLWithPath: settings.outputFolder)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let date = DateFormatter(); date.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let name = "\(date.string(from: job.createdAt))_\(job.id.prefix(6)).txt"
                try text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
            } catch { updated.message = "Transcript saved inside Murmure. Export to the chosen folder failed: \(error.localizedDescription)" }
        case "failed": updated.state = .failed; updated.message = response.error ?? "Transcription failed. The recording has been kept."
        case "missing": updated.state = .queued; updated.message = "The worker has no copy of this recording. Choose Send / retry over SSH, or process locally."
        case "queued", "running", "receiving": updated.message = nil
        default: throw MurmureError.message("Unknown worker state: \(response.state)")
        }
        try persist(updated)
        return job.state != .completed && updated.state == .completed
    }

    @objc private func showSettings(_ sender: Any?) {
        settingsWindow?.close()
        settingsWindow = SettingsWindow(settings: settings, localRoot: repository.separateLocalWorkerRoot) { [weak self] updated in
            self?.settings = updated; self?.saveSettings()
        }
        settingsWindow?.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func openTranscript(_ item: NSMenuItem) {
        if let id = item.representedObject as? String { presentTranscript(id: id) }
    }
    private func offerTranscript(id: String) {
        guard recordingID == nil, !transitioning else { return }
        if activeMenu != nil { deferredTranscriptID = id }
        else { presentTranscript(id: id) }
    }
    private func presentTranscript(id: String) {
        guard var job = jobs.first(where: { $0.id == id }), let path = job.transcriptPath else { return }
        do {
            let text = try String(contentsOfFile: path, encoding: .utf8)
            transcriptWindow?.close()
            transcriptWindow = TranscriptWindow(text: text, file: URL(fileURLWithPath: path))
            transcriptWindow?.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
            job.transcriptViewedAt = Date(); try persist(job)
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
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = "Murmure"; alert.informativeText = message
        alert.addButton(withTitle: "OK"); alert.runModal()
    }
    private func showError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = "Murmure needs attention"; alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK"); alert.runModal()
    }
}
