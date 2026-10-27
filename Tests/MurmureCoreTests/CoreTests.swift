import XCTest
@testable import MurmureCore

final class CoreTests: XCTestCase {
    func testTranscriptIncludesSpeakersWithoutTimestamps() {
        let transcript = Transcript(language: "en", segments: [Segment(start: 3661.9, end: 3663, text: " Hello. ", speaker: "SPEAKER_00")])
        XCTAssertEqual(transcript.formatted(timestamps: false), "SPEAKER_00: Hello.\n")
        XCTAssertEqual(transcript.formatted(timestamps: true), "[01:01:01] SPEAKER_00: Hello.\n")
    }
    func testSSHRejectsShellInjectionAndOptions() throws {
        for bad in ["-oProxyCommand=bad", "host;touch", "user@host", "host\ncommand"] {
            XCTAssertThrowsError(try SSHCommand.arguments(for: WorkerEndpoint(host: bad)))
        }
        XCTAssertThrowsError(try SSHCommand.arguments(for: WorkerEndpoint(host: "g14", python: "python;whoami")))
        let args = try SSHCommand.arguments(for: WorkerEndpoint(host: "g14", python: "C:/Murmure/venv/Scripts/python.exe", script: "C:/Murmure/worker/murmure_worker.py"))
        XCTAssertEqual(args.suffix(2).first, "g14")
        XCTAssertTrue(args.contains("StrictHostKeyChecking=yes"))
    }
    func testAtomicPersistenceAndCrashRecovery() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try JobRepository(root: root)
        var job = RecordingJob(source: .both, options: TranscriptionOptions())
        try repository.save(job)
        let loaded = try XCTUnwrap(repository.load().first)
        XCTAssertEqual(loaded.id, job.id)
        XCTAssertEqual(JobRepository.recovered(loaded).state, .interrupted)
        job.state = .uploading
        XCTAssertEqual(JobRepository.recovered(job).state, .remote)
        job.state = .completed
        XCTAssertEqual(JobRepository.recovered(job).state, .completed)
        XCTAssertThrowsError(try repository.directory(for: "../escape"))
    }
    func testPythonProtocolResponse() throws {
        let response = try JSONDecoder().decode(WorkerResponse.self, from: Data(#"{"state":"completed","id":"example","transcript":{"language":"fr","segments":[{"start":0.1,"end":1.5,"text":"Bonjour","speaker":null}]}}"#.utf8))
        XCTAssertEqual(response.transcript?.formatted(timestamps: false), "Bonjour\n")
    }
}
