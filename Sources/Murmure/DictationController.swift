import AppKit
@preconcurrency import AVFoundation
import MurmureCore
import MurmureUI

@MainActor
final class DictationController {
    private let repository: JobRepository
    private let recorder = AudioRecorder()
    private let onDevice = OnDeviceRecognizer()
    private var job: RecordingJob?
    private var configuration: AppSettings?
    private var target: TextInsertionTarget?
    private var copyReason: String?
    private var session = UUID()
    private var operation: Task<Void, Never>?
    private var meter: Timer?
    private var stopRequested = false
    private var cancelling = false
    private(set) var phase = DictationIndicator.Phase.idle { didSet { phaseChanged?(phase) } }
    var isActive: Bool { phase != .idle }
    var phaseChanged: ((DictationIndicator.Phase) -> Void)?
    var levelChanged: ((Float) -> Void)?
    var saved: ((RecordingJob) throws -> Void)?
    var failed: ((Error) -> Void)?
    var resultNeedsCopy: ((String) -> Void)?

    init(repository: JobRepository) {
        self.repository = repository
        recorder.interrupted = { [weak self] error in self?.cancel(reason: error.localizedDescription) }
    }
    func start(settings: AppSettings) {
        guard !isActive else { return }
        guard settings.dictation.enabled else { failed?(MurmureError.message("Enable dictation in Settings first.")); return }
        session = UUID(); let token = session
        configuration = settings; stopRequested = false; cancelling = false; phase = .preparing
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                if settings.dictation.backend == .ssh { _ = try SSHCommand.arguments(for: settings.remote) }
                var prompted = false
                if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                    let granted = await AVCaptureDevice.requestAccess(for: .audio)
                    guard granted else { throw MurmureError.message("Allow Microphone access for Murmure in System Settings.") }
                    prompted = true
                }
                if settings.dictation.insertAtCursor {
                    guard TextInsertionTarget.requestPermission() else { throw MurmureError.message("Allow Murmure in System Settings → Privacy & Security → Accessibility, then return to your text field and try again. You can also turn off cursor insertion in Dictation settings to use a Copy window without this permission.") }
                }
                if settings.dictation.backend == .onDevice {
                    let speechPrompt = try await OnDeviceRecognizer.authorize(); prompted = prompted || speechPrompt
                }
                try Task.checkCancellation()
                guard !prompted else { throw MurmureError.message("Dictation permissions are ready. Return to your text field and press the shortcut again.") }
                target = nil; copyReason = nil
                if settings.dictation.insertAtCursor {
                    do { target = try TextInsertionTarget.capture() }
                    catch TextTargetError.unsupported { copyReason = "This editor does not expose a verifiable text cursor. Nothing was inserted; use Copy to place your dictation." }
                } else { copyReason = "Cursor insertion is off. Use Copy to place your dictation." }
                var options = settings.options; options.diarization = false; options.timestamps = false
                var recording = RecordingJob(source: .microphone, options: options)
                recording.kind = .dictation; recording.endpoint = settings.dictation.backend == .ssh ? settings.remote : nil
                try await recorder.start(source: .microphone, directory: repository.directory(for: recording.id))
                recording.createdAt = Date(); job = recording
                try saved?(recording)
                try Task.checkCancellation()
                guard token == session else { _ = try? await recorder.stop(); return }
                phase = .listening
                let timer = Timer(timeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
                    Task { @MainActor in guard let self else { return }; self.levelChanged?(self.recorder.microphoneLevel) }
                }
                meter = timer; RunLoop.main.add(timer, forMode: .common)
                if stopRequested { stop() }
            } catch {
                if job != nil { _ = try? await recorder.stop() }
                finishFailure(error, token: token)
            }
        }
    }
    func stop() {
        if phase == .preparing { stopRequested = true; return }
        guard phase == .listening, !cancelling, let settings = configuration, var recording = job else { return }
        meter?.invalidate(); meter = nil; phase = .processing
        let token = session
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                let capture = try await recorder.stop()
                let audio = capture.audio
                recording.captureWarning = capture.warning
                recording.duration = max(0, Date().timeIntervalSince(recording.createdAt))
                recording.state = .preparing; job = recording; try saved?(recording)
                let transcript: Transcript
                if settings.dictation.backend == .ssh {
                    let client = WorkerClient(endpoint: settings.remote, localPython: "", localRoot: repository.separateLocalWorkerRoot)
                    let response = try await client.request(op: "transcribe", job: recording, audio: audio, timeout: TimeInterval(settings.dictation.timeoutSeconds))
                    guard response.state == "completed", let result = response.transcript else {
                        throw MurmureError.message(response.error ?? "Dictation did not finish. Update the remote worker to v0.4.0 and prepare the selected model in Setup.")
                    }
                    transcript = result
                } else { transcript = try await onDevice.transcribe(audio, language: settings.options.language) }
                try Task.checkCancellation(); guard token == session else { return }
                let text = transcript.segments.map(\.text).joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
                guard !text.isEmpty else { throw MurmureError.message("No speech was detected. The recording has been kept.") }
                let directory = try repository.directory(for: recording.id)
                let file = directory.appendingPathComponent("transcript.md")
                try MarkdownWorkflow.transcript(transcript, job: recording).write(to: file, atomically: true, encoding: .utf8)
                try JSONEncoder().encode(transcript).write(to: directory.appendingPathComponent("transcript.json"), options: .atomic)
                recording.state = .completed; recording.transcriptPath = file.path
                job = recording; try saved?(recording)
                var needsCopy = true
                if let target {
                    do {
                        let confirmed = try target.insert(text)
                        if confirmed { recording.transcriptViewedAt = Date(); needsCopy = false }
                        else { recording.message = "The editor did not confirm text insertion. Check the original field before using Copy to avoid inserting it twice." }
                    } catch { recording.message = error.localizedDescription }
                } else { recording.message = copyReason ?? "Nothing was inserted. Your dictation is ready to copy." }
                if settings.dictation.copyToClipboard { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
                job = recording; try saved?(recording)
                reset(token: token)
                // A changed focus never triggers insertion in a different field.
                if needsCopy { resultNeedsCopy?(recording.id) }
            } catch { finishFailure(error, token: token) }
        }
    }
    func cancel(reason: String = "Dictation cancelled. Saved audio is kept.") {
        guard isActive, !cancelling else { return }
        cancelling = true; meter?.invalidate(); meter = nil
        operation?.cancel(); let token = session
        // Preparing and processing tasks own cleanup; keep their session active
        // until cancellation has actually reached the recorder/SSH process.
        guard phase == .listening else { return }
        operation = Task { [weak self] in
            guard let self else { return }
            if phase == .listening { _ = try? await recorder.stop() }
            if var recording = job, recording.state != .completed {
                recording.state = .interrupted; recording.message = reason; try? saved?(recording)
            }
            reset(token: token)
        }
    }
    private func finishFailure(_ error: Error, token: UUID) {
        guard token == session else { return }
        if var recording = job, recording.state != .completed {
            recording.state = error is CancellationError ? .interrupted : .failed
            recording.message = error.localizedDescription; try? saved?(recording)
        }
        reset(token: token)
        if !(error is CancellationError) { failed?(error) }
    }
    private func reset(token: UUID) {
        guard token == session else { return }
        session = UUID(); meter?.invalidate(); meter = nil
        job = nil; target = nil; copyReason = nil; configuration = nil; operation = nil; cancelling = false; phase = .idle
    }
}
