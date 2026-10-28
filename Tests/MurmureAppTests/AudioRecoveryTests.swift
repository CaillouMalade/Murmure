import XCTest
@preconcurrency import AVFoundation
@testable import Murmure

final class AudioRecoveryTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Murmure-audio-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func tone(at url: URL) throws {
        let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1])
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8_000))
        buffer.frameLength = 8_000
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for i in 0..<8_000 { samples[i] = Float(sin(Double(i) * 2 * .pi * 440 / 16_000) * 0.2) }
        try file.write(from: buffer)
    }
    func testBadSystemTrackRecoversMicrophoneAndPreservesOriginal() async throws {
        let root = try directory(), microphone = root.appendingPathComponent("microphone.m4a")
        try tone(at: microphone)
        let result = try await AudioFinalizer.finish(directory: root, tracks: [(microphone, 10), (root.appendingPathComponent("missing-system.m4a"), 10)], warning: nil)
        XCTAssertTrue(result.warning?.contains("microphone only") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: microphone.path))
        XCTAssertEqual(try Data(contentsOf: result.audio), try Data(contentsOf: microphone))
        let duration = try await AVURLAsset(url: result.audio).load(.duration)
        XCTAssertGreaterThan(duration.seconds, 0.4)
    }
    func testTwoSyntheticTracksExportAlignedAudio() async throws {
        let root = try directory(), microphone = root.appendingPathComponent("microphone.m4a"), system = root.appendingPathComponent("system.m4a")
        try tone(at: microphone); try tone(at: system)
        let result = try await AudioFinalizer.finish(directory: root, tracks: [(microphone, 10), (system, 10.25)], warning: nil)
        XCTAssertNil(result.warning)
        let duration = try await AVURLAsset(url: result.audio).load(.duration)
        XCTAssertGreaterThan(duration.seconds, 0.7)
        XCTAssertTrue(FileManager.default.fileExists(atPath: microphone.path)); XCTAssertTrue(FileManager.default.fileExists(atPath: system.path))
    }
    func testUnreadableCaptureCannotBecomeFinalizedAudio() async throws {
        let root = try directory(), source = root.appendingPathComponent("microphone.m4a")
        try Data("not audio".utf8).write(to: source)
        do { _ = try await AudioFinalizer.single(source, directory: root); XCTFail("Expected unreadable capture rejection") }
        catch { XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("audio.m4a").path)) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testSelectionReplacementUsesUTF16AndRejectsInvalidRanges() async {
        await MainActor.run {
            XCTAssertEqual(TextInsertionTarget.replacing("a😀café", selection: CFRange(location: 1, length: 2), with: "é"), "aécafé")
            XCTAssertNil(TextInsertionTarget.replacing("abc", selection: CFRange(location: 4, length: 0), with: "x"))
            XCTAssertNil(TextInsertionTarget.replacing("abc", selection: CFRange(location: 1, length: Int.max), with: "x"))
        }
    }
}
