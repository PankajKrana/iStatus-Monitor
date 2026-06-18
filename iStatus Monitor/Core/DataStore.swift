import Foundation
import OSLog

actor DataStore {
    private let encoder = JSONEncoder()
    private let fileURL: URL

    /// Cap on the live metrics log. At ~1 sample/sec the file would otherwise grow
    /// unbounded on a continuously-running menu-bar utility (B10). When exceeded
    /// the log is rotated to a single `.1` backup, bounding disk use to ~2× this.
    private let maxLogBytes: UInt64

    init(filename: String = "metrics-log.jsonl", maxLogBytes: UInt64 = 10_000_000) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        fileURL = base.appendingPathComponent("iStatusMonitor").appendingPathComponent(filename)
        self.maxLogBytes = maxLogBytes
    }

    func persist(_ snapshot: SystemSnapshot) async {
        do {
            try ensureDirectoryExists()
            let data = try encoder.encode(snapshot)
            try appendLine(data)
        } catch {
            // Best-effort: the app continues operating even if metrics aren't
            // persisted to disk (they're still available in-memory).
            Logger.persistence.error("Metrics log write failed: \(error.localizedDescription, privacy: .public)")
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

        rotateIfNeeded()

        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        handle.write(data)
        handle.write(Data([0x0A]))
    }

    /// Rotate the log to a single `.1` backup once it exceeds the size cap.
    private func rotateIfNeeded() {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
        guard size >= maxLogBytes else { return }

        let backup = fileURL.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: fileURL, to: backup)
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
    }
}
