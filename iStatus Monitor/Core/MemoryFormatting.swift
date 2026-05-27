import Foundation

extension Int {
    func toMemoryString() -> String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .memory)
    }

    func toNetworkSpeedString() -> String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .binary) + "/s"
    }
}
