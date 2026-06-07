import Foundation

// MARK: - Process & Network Insight Models
//
// Phase 2A insight data. Deliberately `Sendable, Equatable` but **not** `Codable`:
// these never enter `SystemSnapshot` / persistence (they are volatile, popover-only),
// and `Equatable` lets SwiftUI re-render the menu bar popovers only when values change.

/// A single process's resource usage. `cpuPercent` is relative to one core
/// (Activity Monitor semantics — the sum across processes can exceed 100%).
struct ProcessUsage: Identifiable, Sendable, Equatable {
    let pid: Int32
    let name: String
    let cpuPercent: Double
    let memoryBytes: UInt64

    var id: Int32 { pid }
}

/// Top processes by CPU and by memory, captured on one monitoring tick.
struct ProcessSnapshot: Sendable, Equatable {
    let timestamp: Date
    let topByCPU: [ProcessUsage]
    let topByMemory: [ProcessUsage]

    static let empty = ProcessSnapshot(timestamp: .distantPast, topByCPU: [], topByMemory: [])
}

/// One active network socket (TCP/UDP), attributed to its owning process.
struct NetworkConnection: Identifiable, Sendable, Equatable {
    let pid: Int32
    let processName: String
    let proto: String          // "TCP" / "UDP"
    let localAddress: String
    let localPort: Int
    let remoteAddress: String
    let remotePort: Int
    let state: String          // TCP state, or "" for UDP

    var id: String {
        "\(pid)-\(proto)-\(localAddress):\(localPort)-\(remoteAddress):\(remotePort)"
    }
}

/// A process ranked by how many active connections it owns. Stands in for true
/// per-process bandwidth, which requires the private NetworkStatistics framework.
struct NetworkProcess: Identifiable, Sendable, Equatable {
    let pid: Int32
    let name: String
    let connectionCount: Int

    var id: Int32 { pid }
}

/// Network insights: cached public IP, active connections, and the processes
/// with the most open connections.
struct NetworkInsights: Sendable, Equatable {
    let timestamp: Date
    let publicIP: String?
    let connections: [NetworkConnection]
    let topProcesses: [NetworkProcess]

    static let empty = NetworkInsights(timestamp: .distantPast, publicIP: nil, connections: [], topProcesses: [])
}
