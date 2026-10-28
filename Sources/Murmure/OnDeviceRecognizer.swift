@preconcurrency import Speech
import MurmureCore

@MainActor
final class OnDeviceRecognizer {
    private var recognition: SFSpeechRecognitionTask?
    private var continuation: CheckedContinuation<Transcript, Error>?
    private var deadline: Task<Void, Never>?

    static func authorize() async throws -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            let status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            guard status == .authorized else { throw MurmureError.message("Allow Speech Recognition for on-device dictation in System Settings.") }
            return true
        }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { throw MurmureError.message("Allow Speech Recognition for on-device dictation in System Settings.") }
        return false
    }
    func transcribe(_ audio: URL, language: String) async throws -> Transcript {
        let locale = language.isEmpty ? Locale.current : Locale(identifier: language)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            throw MurmureError.message("On-device speech recognition is unavailable for this language on this Mac. Install the language in macOS or choose SSH in Dictation settings.")
        }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let request = SFSpeechURLRecognitionRequest(url: audio)
                request.requiresOnDeviceRecognition = true
                request.shouldReportPartialResults = false
                request.addsPunctuation = true
                recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    Task { @MainActor in
                        guard let self else { return }
                        if let result, result.isFinal {
                            let segments = result.bestTranscription.segments.map { Segment(start: $0.timestamp, end: $0.timestamp + $0.duration, text: $0.substring) }
                            // Apple supplies punctuation in formattedString; keep it intact.
                            let text = result.bestTranscription.formattedString
                            let end = segments.last?.end ?? 0
                            self.finish(.success(Transcript(language: locale.identifier, segments: [Segment(start: 0, end: end, text: text)])))
                        } else if let error { self.finish(.failure(error)) }
                    }
                }
                deadline = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 120_000_000_000) } catch { return }
                    self?.finish(.failure(MurmureError.message("On-device dictation timed out. The recording has been kept.")))
                }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) } }
    }
    private func finish(_ result: Result<Transcript, Error>) {
        guard let continuation else { return }
        self.continuation = nil; deadline?.cancel(); deadline = nil
        recognition?.cancel(); recognition = nil
        continuation.resume(with: result)
    }
}
