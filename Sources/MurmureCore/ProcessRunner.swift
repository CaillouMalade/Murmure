import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private final class ProcessOutput: @unchecked Sendable {
    var data = Data()
    var error: Error?
}
private final class ProcessControl: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var timeout = false
    private var aborted = false
    var wasCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    var didTimeOut: Bool { lock.lock(); defer { lock.unlock() }; return timeout }
    var shouldStopIO: Bool { lock.lock(); defer { lock.unlock() }; return cancelled || timeout || aborted }
    func attach(_ process: Process) {
        lock.lock(); self.process = process; let stop = cancelled || timeout || aborted; lock.unlock()
        if stop { terminate(process) }
    }
    func stop(timedOut: Bool = false, abort: Bool = false) {
        lock.lock()
        if timedOut { timeout = true } else if abort { aborted = true } else { cancelled = true }
        let running = process; lock.unlock()
        if let running { terminate(running) }
    }
    private func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
            if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
        }
    }
}

public enum ProcessRunner {
    private static func nonblocking(_ handle: FileHandle, writing: Bool = false) {
        let descriptor = handle.fileDescriptor
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        #if os(macOS)
        if writing { _ = fcntl(descriptor, F_SETNOSIGPIPE, 1) }
        #endif
    }
    private static func write(_ data: Data, to handle: FileHandle, process: Process, control: ProcessControl) throws {
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                if control.shouldStopIO { throw MurmureError.message("The command stopped before input was complete.") }
                guard process.isRunning else { throw MurmureError.message("The command closed before accepting its input.") }
                var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLOUT), revents: 0)
                guard poll(&descriptor, 1, 100) > 0 else { continue }
                #if canImport(Darwin)
                let count = Darwin.write(handle.fileDescriptor, base.advanced(by: offset), buffer.count - offset)
                #else
                let count = Glibc.write(handle.fileDescriptor, base.advanced(by: offset), buffer.count - offset)
                #endif
                if count > 0 { offset += count }
                else if errno != EAGAIN && errno != EINTR { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            }
        }
    }
    /// No shell, bounded pipes, cancellable lifetime, fixed-size disk-to-stdin chunks.
    public static func run(executable: URL, arguments: [String], header: Data = Data(), file: URL? = nil,
                           timeout: TimeInterval, directory: URL? = nil, environment: [String: String]? = nil) async throws -> Data {
        let control = ProcessControl()
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    if control.wasCancelled { continuation.resume(throwing: CancellationError()); return }
                    let process = Process()
                    process.executableURL = executable; process.arguments = arguments
                    process.currentDirectoryURL = directory
                    if let environment { process.environment = environment }
                    let input = Pipe(), output = Pipe(), errors = Pipe()
                    process.standardInput = input; process.standardOutput = output; process.standardError = errors
                    do { try process.run() } catch { continuation.resume(throwing: error); return }
                    nonblocking(input.fileHandleForWriting, writing: true)
                    nonblocking(output.fileHandleForReading); nonblocking(errors.fileHandleForReading)
                    control.attach(process)
                    let deadline = DispatchWorkItem { if process.isRunning { control.stop(timedOut: true) } }
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: deadline)
                    let group = DispatchGroup()
                    let stdout = ProcessOutput(), stderr = ProcessOutput()
                    for (pipe, result, limit) in [(output, stdout, 16 * 1024 * 1024), (errors, stderr, 256 * 1024)] {
                        group.enter()
                        DispatchQueue.global(qos: .utility).async {
                            defer { try? pipe.fileHandleForReading.close(); group.leave() }
                            var buffer = [UInt8](repeating: 0, count: 65_536)
                            while !control.shouldStopIO {
                                var descriptor = pollfd(fd: pipe.fileHandleForReading.fileDescriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
                                let ready = poll(&descriptor, 1, 100)
                                if ready == 0 { if !process.isRunning { break }; continue }
                                if ready < 0 { if errno == EINTR { continue }; break }
                                #if canImport(Darwin)
                                let count = Darwin.read(descriptor.fd, &buffer, 65_536)
                                #else
                                let count = Glibc.read(descriptor.fd, &buffer, 65_536)
                                #endif
                                if count == 0 { break }
                                if count < 0 {
                                    if errno == EAGAIN || errno == EINTR { continue }
                                    result.error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO); break
                                }
                                if result.data.count + count > limit {
                                    result.error = MurmureError.message("The command response exceeded its output limit.")
                                    control.stop(abort: true); break
                                }
                                result.data.append(contentsOf: buffer.prefix(count))
                            }
                        }
                    }
                    var inputError: Error?
                    do {
                        if control.wasCancelled { throw CancellationError() }
                        try write(header, to: input.fileHandleForWriting, process: process, control: control)
                        if let file {
                            let handle = try FileHandle(forReadingFrom: file)
                            defer { try? handle.close() }
                            while let block = try handle.read(upToCount: 65_536), !block.isEmpty {
                                if control.wasCancelled { throw CancellationError() }
                                try write(block, to: input.fileHandleForWriting, process: process, control: control)
                            }
                        }
                    } catch { inputError = error }
                    try? input.fileHandleForWriting.close()
                    process.waitUntilExit(); deadline.cancel(); group.wait()
                    if control.wasCancelled { continuation.resume(throwing: CancellationError()) }
                    else if control.didTimeOut { continuation.resume(throwing: MurmureError.message("The command timed out. The original audio/transcript has been kept.")) }
                    else if let error = stdout.error ?? stderr.error { continuation.resume(throwing: error) }
                    else if process.terminationStatus != 0 {
                        let detail = String(data: stderr.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        continuation.resume(throwing: MurmureError.message(detail.isEmpty ? "The command failed (exit \(process.terminationStatus)). Check the executable, login and setup." : String(detail.prefix(1600))))
                    } else if let error = stdout.error ?? stderr.error ?? inputError { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: stdout.data) }
                }
            }
        }, onCancel: { control.stop() })
    }
}
