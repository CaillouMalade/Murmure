@preconcurrency import AVFoundation
import AppKit
import CoreMedia
import ScreenCaptureKit
import MurmureCore

private final class SystemAudioSink: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "Murmure.audio.write", qos: .userInitiated)
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var started = false
    private var writeError: Error?
    private(set) var firstTime: Double = 0
    var interrupted: ((Error) -> Void)?
    init(url: URL) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000
        ])
        input.expectsMediaDataInRealTime = true
        super.init()
        guard writer.canAdd(input) else { throw MurmureError.message("Cannot initialize Mac audio recording.") }
        writer.add(input)
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer), writeError == nil else { return }
        if !started {
            guard writer.startWriting() else { writeError = writer.error ?? MurmureError.message("Mac audio writing could not start."); return }
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            firstTime = time.seconds
            writer.startSession(atSourceTime: time); started = true
        }
        guard input.isReadyForMoreMediaData else {
            writeError = MurmureError.message("The disk could not keep up with audio capture. Original capture files have been kept.")
            return
        }
        if !input.append(sampleBuffer) { writeError = writer.error ?? MurmureError.message("Mac audio could not be saved.") }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { interrupted?(error) }
    func finish() async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                if let writeError { writer.cancelWriting(); continuation.resume(throwing: writeError); return }
                guard started else { writer.cancelWriting(); continuation.resume(throwing: MurmureError.message("No Mac audio was captured. Check Screen & System Audio Recording permission.")); return }
                input.markAsFinished()
                writer.finishWriting { [self] in
                    if writer.status == .completed { continuation.resume(returning: firstTime) }
                    else { continuation.resume(throwing: writer.error ?? MurmureError.message("Could not finish saving Mac audio.")) }
                }
            }
        }
    }
}

@MainActor
final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    private var microphone: AVAudioRecorder?
    private var stream: SCStream?
    private var sink: SystemAudioSink?
    private var directory: URL?
    private var microphoneStart: Double = 0
    private var activity: NSObjectProtocol?
    var interrupted: ((Error) -> Void)?

    func start(source: AudioSource, directory: URL) async throws {
        self.directory = directory
        if source.includesMicrophone {
            let permitted = await AVCaptureDevice.requestAccess(for: .audio)
            guard permitted else { throw MurmureError.message("Allow Microphone access for Murmure in System Settings → Privacy & Security.") }
        }
        do {
            if source.includesSystem {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                guard let display = content.displays.first else { throw MurmureError.message("No display is available for Mac audio capture.") }
                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                let configuration = SCStreamConfiguration()
                configuration.capturesAudio = true; configuration.excludesCurrentProcessAudio = true
                configuration.sampleRate = 48_000; configuration.channelCount = 2
                // Audio outputs only. Minimize the unused screen surface and cadence.
                configuration.width = 2; configuration.height = 2; configuration.queueDepth = 3
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                configuration.showsCursor = false
                let sink = try SystemAudioSink(url: directory.appendingPathComponent("system.m4a"))
                sink.interrupted = { [weak self] error in Task { @MainActor in self?.interrupted?(error) } }
                let stream = SCStream(filter: filter, configuration: configuration, delegate: sink)
                try stream.addStreamOutput(sink, type: .audio, sampleHandlerQueue: sink.queue)
                self.sink = sink; self.stream = stream
                try await stream.startCapture()
            }
            if source.includesMicrophone {
                let microphone = try AVAudioRecorder(url: directory.appendingPathComponent("microphone.m4a"), settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000
                ])
                microphone.delegate = self
                microphone.isMeteringEnabled = true
                guard microphone.prepareToRecord() else { throw MurmureError.message("The microphone could not be prepared.") }
                microphoneStart = CMClockGetTime(CMClockGetHostTimeClock()).seconds
                guard microphone.record() else { throw MurmureError.message("The microphone could not start recording.") }
                self.microphone = microphone
            }
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Recording audio")
        } catch {
            microphone?.stop(); microphone = nil
            try? await stream?.stopCapture(); stream = nil
            if let sink { _ = try? await sink.finish() }; sink = nil
            throw error
        }
    }

    var microphoneLevel: Float {
        guard let microphone else { return 0 }
        microphone.updateMeters()
        // Quiet speech still has a visible floor; no synthetic random waveform.
        return max(0, min(1, (microphone.averagePower(forChannel: 0) + 55) / 55))
    }

    func stop() async throws -> URL {
        defer {
            if let activity { ProcessInfo.processInfo.endActivity(activity) }
            activity = nil; self.directory = nil
        }
        guard let directory else { throw MurmureError.message("There is no recording to stop.") }
        var tracks: [(URL, Double)] = []
        if let microphone {
            microphone.stop(); self.microphone = nil
            tracks.append((directory.appendingPathComponent("microphone.m4a"), microphoneStart))
        }
        if let stream {
            let sink = self.sink
            self.stream = nil; self.sink = nil
            var stopError: Error?
            do { try await stream.stopCapture() } catch { stopError = error }
            if let sink {
                let start = try await sink.finish()
                tracks.append((directory.appendingPathComponent("system.m4a"), start))
            }
            if let stopError { throw stopError }
        }
        let output = directory.appendingPathComponent("audio.m4a")
        if tracks.count == 1 { try FileManager.default.moveItem(at: tracks[0].0, to: output); return output }
        guard tracks.count == 2, let base = tracks.map({ $0.1 }).min() else { throw MurmureError.message("No audio was recorded.") }
        let composition = AVMutableComposition()
        let mix = AVMutableAudioMix()
        var parameters: [AVMutableAudioMixInputParameters] = []
        for (url, start) in tracks {
            let asset = AVURLAsset(url: url)
            guard let original = try await asset.loadTracks(withMediaType: .audio).first,
                  let destination = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw MurmureError.message("Could not combine microphone and Mac audio. The separate recordings have been kept.")
            }
            let duration = try await asset.load(.duration)
            try destination.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: original,
                                            at: CMTime(seconds: max(0, start - base), preferredTimescale: 48_000))
            let parameter = AVMutableAudioMixInputParameters(track: destination)
            parameter.setVolume(0.7, at: .zero); parameters.append(parameter)
        }
        mix.inputParameters = parameters
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw MurmureError.message("Could not prepare the combined recording.")
        }
        exporter.audioMix = mix
        try await exporter.export(to: output, as: .m4a)
        return output
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor [weak self] in self?.interrupted?(error ?? MurmureError.message("Microphone recording was interrupted.")) }
    }
}
