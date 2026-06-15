import Foundation

/// Shared, pure formatting for menu-bar / popover metric strings.
///
/// These helpers were previously duplicated verbatim across `SystemWidgets`,
/// `ModuleMenuBar`, and several metric views. Consolidating them here gives the
/// app one source of truth for how percentages, byte counts, and throughput are
/// rendered, so the formats stay consistent everywhere.
enum MetricFormat {

    /// Whole-percent string, e.g. `15` → `"15%"`.
    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    /// Memory-style byte count, e.g. `"8 GB"` (1024-based).
    static func bytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    /// Human-readable throughput, e.g. `"1.2 MB/s"` — KB/s below 1 MB/s, MB/s above.
    static func speed(_ bytesPerSecond: UInt64) -> String {
        let kilobytes = Double(bytesPerSecond) / 1024
        if kilobytes < 1024 {
            return String(format: "%.1f KB/s", kilobytes)
        }
        return String(format: "%.1f MB/s", kilobytes / 1024)
    }
}
