import Foundation

actor DataStore {
    private let encoder = JSONEncoder()
    private let fileURL: URL

    init(filename: String = "metrics-log.jsonl") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        fileURL = base.appendingPathComponent("iStatusMonitor").appendingPathComponent(filename)
    }

    func persist(_ snapshot: SystemSnapshot) async {
        do {
            try ensureDirectoryExists()
            let data = try encoder.encode(snapshot)
            try appendLine(data)
        } catch {
            // Best-effort persistence for diagnostics and trend history.
        }
    }

    private func ensureDirectoryExists() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func appendLine(_ data: Data) throws {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        handle.write(data)
        handle.write(Data([0x0A]))
    }
}
