import Foundation
import Darwin

struct EngineError: LocalizedError { let message: String; var errorDescription: String? { message } }
final class EngineCancellation {
    private let lock = NSLock(); private var flag = false
    func cancel() { lock.lock(); flag = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}
enum Engine {
    static var executable: URL {
        if let path = ProcessInfo.processInfo.environment["EASYTF_DESKTOP_ENGINE"] { return URL(fileURLWithPath: path) }
        return Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/easytf-desktop")
    }
    static func call(_ request: JSONValue, cancellation: EngineCancellation) throws -> JSONValue {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw EngineError(message: "The Rust engine is missing. Build the EasyTF app using scripts/build-macos.sh.") }
        let process = Process(); process.executableURL = executable
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = (environment["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = environment
        let input = Pipe(), output = Pipe()
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        let descriptor = output.fileHandleForReading.fileDescriptor
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        defer { try? input.fileHandleForWriting.close(); try? output.fileHandleForReading.close() }
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: JSONEncoder().encode(request)); try input.fileHandleForWriting.close()
        var result = Data()
        func drain() {
            var buffer = [UInt8](repeating: 0, count: 16384)
            for _ in 0..<64 {
                let size = read(descriptor, &buffer, buffer.count)
                guard size > 0 else { break }
                if result.count < 128 * 1024 * 1024 { result.append(contentsOf: buffer.prefix(size)) }
            }
        }
        let deadline = Date().addingTimeInterval(120)
        var stop: String?
        while process.isRunning {
            drain()
            if cancellation.cancelled { stop = "Operation cancelled."; break }
            if Date() > deadline { stop = "The engine timed out. Check AWS connectivity if using a resource picker."; break }
            Thread.sleep(forTimeInterval: 0.03)
        }
        if stop != nil {
            process.terminate()
            let grace = Date().addingTimeInterval(0.5)
            while process.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit(); drain()
        if let stop = stop { throw EngineError(message: stop) }
        let envelope = try JSONDecoder().decode(JSONValue.self, from: result)
        guard envelope["ok"].bool else { throw EngineError(message: envelope["error"].text) }
        return envelope["data"]
    }
}
