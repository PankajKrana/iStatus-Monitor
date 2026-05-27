import Darwin
import Foundation
import Network

actor NetworkMonitor {
    private struct InterfaceCounter: Sendable {
        let name: String
        let bytesIn: UInt64
        let bytesOut: UInt64
        let flags: UInt32
        let ipv4: String?
        let ipv6: String?
    }

    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "NetworkMonitor.PathQueue")
    private var pathStatus: NWPath.Status = .requiresConnection
    private var pathPrimaryType: NWInterface.InterfaceType?

    private var previousCounters: [String: InterfaceCounter] = [:]
    private var history60s: [ThroughputPoint] = []
    private var totalDownloadSinceLaunch: UInt64 = 0
    private var totalUploadSinceLaunch: UInt64 = 0

    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task {
                await self?.updatePath(path)
            }
        }
        pathMonitor.start(queue: pathQueue)
    }

    deinit {
        pathMonitor.cancel()
    }

    func snapshots(every interval: Duration = .seconds(1)) -> AsyncStream<NetworkSnapshot> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    if let snapshot = latestSnapshot() {
                        continuation.yield(snapshot)
                    }

                    do {
                        try await Task.sleep(for: interval)
                    } catch {
                        break
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func latestSnapshot() -> NetworkSnapshot? {
        let now = Date()
        let current = collectInterfaceCounters()

        var interfaceStats: [InterfaceStats] = []
        interfaceStats.reserveCapacity(current.count)

        var tickDownload: UInt64 = 0
        var tickUpload: UInt64 = 0

        let primaryFromPath = primaryInterfaceTypeFromPath()

        for (name, currentCounter) in current {
            let previous = previousCounters[name]

            let downloadDelta: UInt64
            let uploadDelta: UInt64

            if let previous {
                downloadDelta = currentCounter.bytesIn >= previous.bytesIn ? currentCounter.bytesIn - previous.bytesIn : 0
                uploadDelta = currentCounter.bytesOut >= previous.bytesOut ? currentCounter.bytesOut - previous.bytesOut : 0
            } else {
                downloadDelta = 0
                uploadDelta = 0
            }

            tickDownload += downloadDelta
            tickUpload += uploadDelta

            let type = interfaceType(for: name)
            let isPrimary = (primaryFromPath != nil && type == primaryFromPath) || isLikelyPrimary(name: name)

            interfaceStats.append(
                InterfaceStats(
                    name: name,
                    displayName: displayName(for: name),
                    type: type,
                    downloadBytesPerSecond: downloadDelta,
                    uploadBytesPerSecond: uploadDelta,
                    totalBytesReceived: currentCounter.bytesIn,
                    totalBytesSent: currentCounter.bytesOut,
                    ipv4Address: currentCounter.ipv4,
                    ipv6Address: currentCounter.ipv6,
                    isConnected: isConnected(flags: currentCounter.flags),
                    isPrimary: isPrimary
                )
            )
        }

        previousCounters = current

        totalDownloadSinceLaunch += tickDownload
        totalUploadSinceLaunch += tickUpload

        history60s.append(
            ThroughputPoint(
                timestamp: now,
                downloadBytesPerSecond: tickDownload,
                uploadBytesPerSecond: tickUpload
            )
        )
        if history60s.count > 60 {
            history60s.removeFirst(history60s.count - 60)
        }

        interfaceStats.sort { lhs, rhs in
            if lhs.isPrimary != rhs.isPrimary {
                return lhs.isPrimary && !rhs.isPrimary
            }
            return lhs.name < rhs.name
        }

        return NetworkSnapshot(
            timestamp: now,
            interfaces: interfaceStats,
            connectivitySatisfied: pathStatus == .satisfied,
            totalDownloadSinceLaunch: totalDownloadSinceLaunch,
            totalUploadSinceLaunch: totalUploadSinceLaunch,
            history60s: history60s
        )
    }

    func read() async -> NetworkMetrics {
        guard let snapshot = latestSnapshot() else { return .empty }

        let primary = snapshot.interfaces.first(where: { $0.isPrimary }) ?? snapshot.interfaces.first
        let inbound = snapshot.interfaces.reduce(UInt64(0)) { $0 + $1.downloadBytesPerSecond }
        let outbound = snapshot.interfaces.reduce(UInt64(0)) { $0 + $1.uploadBytesPerSecond }

        return NetworkMetrics(
            bytesInPerSecond: inbound,
            bytesOutPerSecond: outbound,
            primaryInterface: primary?.name ?? ""
        )
    }

    private func updatePath(_ path: NWPath) {
        pathStatus = path.status
        if path.usesInterfaceType(.wifi) {
            pathPrimaryType = .wifi
        } else if path.usesInterfaceType(.wiredEthernet) {
            pathPrimaryType = .wiredEthernet
        } else if path.usesInterfaceType(.cellular) {
            pathPrimaryType = .cellular
        } else if path.usesInterfaceType(.other) {
            pathPrimaryType = .other
        } else {
            pathPrimaryType = nil
        }
    }

    private func primaryInterfaceTypeFromPath() -> NetworkInterfaceType? {
        guard let type = pathPrimaryType else { return nil }
        switch type {
        case .wifi: return .wifi
        case .wiredEthernet: return .ethernet
        case .cellular: return .cellular
        case .other: return .other
        default: return .other
        }
    }

    private func collectInterfaceCounters() -> [String: InterfaceCounter] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let head = pointer else { return [:] }
        defer { freeifaddrs(head) }

        var counters: [String: InterfaceCounter] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = head

        while let entry = cursor?.pointee {
            defer { cursor = entry.ifa_next }

            guard let cName = entry.ifa_name else { continue }
            let name = String(cString: cName)

            let flags = UInt32(entry.ifa_flags)
            guard isActiveNonLoopback(flags: flags, name: name) else { continue }

            guard let ifaAddr = entry.ifa_addr else { continue }
            let family = ifaAddr.pointee.sa_family
            if family == UInt8(AF_LINK) {
                guard let dataPtr = entry.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
                let bytesIn = UInt64(dataPtr.pointee.ifi_ibytes)
                let bytesOut = UInt64(dataPtr.pointee.ifi_obytes)
                let existing = counters[name]
                counters[name] = InterfaceCounter(
                    name: name,
                    bytesIn: bytesIn,
                    bytesOut: bytesOut,
                    flags: flags,
                    ipv4: existing?.ipv4,
                    ipv6: existing?.ipv6
                )
            } else if family == UInt8(AF_INET) || family == UInt8(AF_INET6) {
                let ipAddress = ipString(from: entry.ifa_addr)
                let existing = counters[name]
                counters[name] = InterfaceCounter(
                    name: name,
                    bytesIn: existing?.bytesIn ?? 0,
                    bytesOut: existing?.bytesOut ?? 0,
                    flags: flags,
                    ipv4: family == UInt8(AF_INET) ? ipAddress : existing?.ipv4,
                    ipv6: family == UInt8(AF_INET6) ? ipAddress : existing?.ipv6
                )
            }
        }

        return counters
    }

    private func ipString(from sockaddr: UnsafeMutablePointer<sockaddr>?) -> String? {
        guard let sockaddr else { return nil }

        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let len = socklen_t(sockaddr.pointee.sa_len)

        let result = getnameinfo(sockaddr, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
        guard result == 0 else { return nil }
        return String(cString: host)
    }

    private func isActiveNonLoopback(flags: UInt32, name: String) -> Bool {
        let isUp = (flags & UInt32(IFF_UP)) != 0
        let isRunning = (flags & UInt32(IFF_RUNNING)) != 0
        let isLoopback = (flags & UInt32(IFF_LOOPBACK)) != 0 || name == "lo0"
        return isUp && isRunning && !isLoopback
    }

    private func isConnected(flags: UInt32) -> Bool {
        (flags & UInt32(IFF_UP)) != 0 && (flags & UInt32(IFF_RUNNING)) != 0
    }

    private func displayName(for interface: String) -> String {
        if interface.hasPrefix("en") {
            if interface == "en0" { return "Wi-Fi" }
            return "Ethernet"
        }
        if interface.hasPrefix("utun") { return "VPN" }
        if interface.hasPrefix("bridge") { return "Bridge" }
        if interface.hasPrefix("awdl") { return "AWDL" }
        return interface
    }

    private func interfaceType(for interface: String) -> NetworkInterfaceType {
        if interface.hasPrefix("utun") { return .vpn }
        if interface.hasPrefix("en") {
            return interface == "en0" ? .wifi : .ethernet
        }
        return .other
    }

    private func isLikelyPrimary(name: String) -> Bool {
        name == "en0" || name == "en1" || name.hasPrefix("utun")
    }
}
