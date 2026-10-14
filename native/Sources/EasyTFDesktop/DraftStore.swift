import Foundation
import Darwin

enum DraftStore {
    static var file: URL {
        let folder = ProcessInfo.processInfo.environment["EASYTF_DESKTOP_STATE_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/EasyTF")
        return folder.appendingPathComponent("desktop-draft.json")
    }
    static func save(_ value: JSONValue, to file: URL = DraftStore.file) throws {
        let folder = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temporary = folder.appendingPathComponent(".draft-" + UUID().uuidString)
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw EngineError(message: "Could not save the local workspace draft.") }
        defer { close(descriptor); try? FileManager.default.removeItem(at: temporary) }
        let data = try JSONEncoder().encode(value)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let amount = write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                guard amount > 0 else { throw EngineError(message: "Could not write the local workspace draft.") }
                offset += amount
            }
        }
        guard fsync(descriptor) == 0, rename(temporary.path, file.path) == 0 else { throw EngineError(message: "Could not save the local workspace draft.") }
    }
    static func load(from file: URL = DraftStore.file) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file)) }
}
