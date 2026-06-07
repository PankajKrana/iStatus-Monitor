import Darwin
import Foundation

// MARK: - Network Insights Monitor
//
// Active connections, top processes by connection count, and a cached public IP.
// Like the other monitors it owns no loop — `SystemMonitorService` calls `latest()`
// on the existing 1 s tick. Expensive work is gated against the tick clock:
//
//   - connection enumeration: at most every `connectionsInterval` (~3 s)
//   - public IP fetch:        at most every `publicIPInterval` (~15 min), performed
//                             off the tick in a one-shot Task so it never blocks
//                             monitoring; on other ticks the cached value is returned.
//
// No new timers, no polling loops. Requires the app to run **unsandboxed**:
// `proc_pidinfo`/`proc_pidfdinfo` socket enumeration returns EPERM under the App
// Sandbox (verified empirically).
actor NetworkInsightsMonitor {
    private let connectionsInterval: TimeInterval = 3
    private let publicIPInterval: TimeInterval = 15 * 60
    private let maxConnections = 50
    private let topCount = 5

    private var lastConnectionsAt: Date?
    private var cachedConnections: [NetworkConnection] = []
    private var cachedTopProcesses: [NetworkProcess] = []

    private var lastPublicIPAt: Date?
    private var cachedPublicIP: String?
    private var publicIPInFlight = false

    func latest(now: Date = Date()) -> NetworkInsights {
        if lastConnectionsAt == nil || now.timeIntervalSince(lastConnectionsAt!) >= connectionsInterval {
            let (connections, processes) = enumerateConnections()
            cachedConnections = connections
            cachedTopProcesses = processes
            lastConnectionsAt = now
        }

        if !publicIPInFlight,
           lastPublicIPAt == nil || now.timeIntervalSince(lastPublicIPAt!) >= publicIPInterval {
            publicIPInFlight = true
            lastPublicIPAt = now   // set immediately so we don't re-trigger while in flight
            Task { [weak self] in
                let ip = await NetworkInsightsMonitor.fetchPublicIP()
                await self?.storePublicIP(ip)
            }
        }

        return NetworkInsights(
            timestamp: now,
            publicIP: cachedPublicIP,
            connections: cachedConnections,
            topProcesses: cachedTopProcesses
        )
    }

    private func storePublicIP(_ ip: String?) {
        if let ip { cachedPublicIP = ip }
        publicIPInFlight = false
    }

    // MARK: Public IP (off-tick, cached)

    private static func fetchPublicIP() async -> String? {
        var request = URLRequest(url: URL(string: "https://api.ipify.org")!)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let ip = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return ip.isEmpty ? nil : ip
        } catch {
            return nil
        }
    }

    // MARK: Connection enumeration (libproc socket fdinfo)

    private func enumerateConnections() -> ([NetworkConnection], [NetworkProcess]) {
        var connections: [NetworkConnection] = []
        var perProcess: [pid_t: (name: String, count: Int)] = [:]

        for pid in listPIDs() {
            let sizeProbe = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
            guard sizeProbe > 0 else { continue }

            let capacity = Int(sizeProbe) / MemoryLayout<proc_fdinfo>.stride
            var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: capacity)
            let written = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, sizeProbe)
            guard written > 0 else { continue }
            let fdCount = Int(written) / MemoryLayout<proc_fdinfo>.stride

            var processName: String?

            for index in 0 ..< fdCount where fds[index].proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
                var socketInfo = socket_fdinfo()
                let size = Int32(MemoryLayout<socket_fdinfo>.size)
                let result = proc_pidfdinfo(pid, fds[index].proc_fd, PROC_PIDFDSOCKETINFO, &socketInfo, size)
                guard result == size else { continue }

                guard let connection = makeConnection(pid: pid, info: socketInfo.psi, name: { () -> String in
                    if let processName { return processName }
                    let resolved = self.name(for: pid)
                    processName = resolved
                    return resolved
                }) else { continue }

                if connections.count < maxConnections {
                    connections.append(connection)
                }
                var entry = perProcess[pid] ?? (name: connection.processName, count: 0)
                entry.count += 1
                perProcess[pid] = entry
            }
        }

        let topProcesses = Array(
            perProcess
                .map { NetworkProcess(pid: $0.key, name: $0.value.name, connectionCount: $0.value.count) }
                .sorted { $0.connectionCount > $1.connectionCount }
                .prefix(topCount)
        )
        return (connections, topProcesses)
    }

    /// Build a `NetworkConnection` from a socket's `socket_info`, for inet TCP/UDP
    /// sockets only. Returns nil for unix/kernel/other sockets.
    private func makeConnection(pid: pid_t, info: socket_info, name: () -> String) -> NetworkConnection? {
        switch Int(info.soi_kind) {
        case Int(SOCKINFO_TCP):
            let tcp = info.soi_proto.pri_tcp
            let endpoints = endpoints(from: tcp.tcpsi_ini)
            return NetworkConnection(
                pid: pid, processName: name(), proto: "TCP",
                localAddress: endpoints.localAddress, localPort: endpoints.localPort,
                remoteAddress: endpoints.remoteAddress, remotePort: endpoints.remotePort,
                state: tcpStateName(tcp.tcpsi_state)
            )
        case Int(SOCKINFO_IN):
            let endpoints = endpoints(from: info.soi_proto.pri_in)
            return NetworkConnection(
                pid: pid, processName: name(), proto: "UDP",
                localAddress: endpoints.localAddress, localPort: endpoints.localPort,
                remoteAddress: endpoints.remoteAddress, remotePort: endpoints.remotePort,
                state: ""
            )
        default:
            return nil
        }
    }

    private func endpoints(from sockinfo: in_sockinfo) -> (localAddress: String, localPort: Int, remoteAddress: String, remotePort: Int) {
        let isIPv6 = (Int32(sockinfo.insi_vflag) & INI_IPV6) != 0
        let localPort = Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: sockinfo.insi_lport)))
        let remotePort = Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: sockinfo.insi_fport)))

        var local = sockinfo.insi_laddr
        var foreign = sockinfo.insi_faddr
        let localAddress: String
        let remoteAddress: String
        if isIPv6 {
            localAddress = ipv6String(&local.ina_6)
            remoteAddress = ipv6String(&foreign.ina_6)
        } else {
            localAddress = ipv4String(&local.ina_46.i46a_addr4)
            remoteAddress = ipv4String(&foreign.ina_46.i46a_addr4)
        }
        return (localAddress, localPort, remoteAddress, remotePort)
    }

    private func ipv4String(_ addr: inout in_addr) -> String {
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN))
        return String(cString: buffer)
    }

    private func ipv6String(_ addr: inout in6_addr) -> String {
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        inet_ntop(AF_INET6, &addr, &buffer, socklen_t(INET6_ADDRSTRLEN))
        return String(cString: buffer)
    }

    private func tcpStateName(_ state: Int32) -> String {
        switch Int(state) {
        case 0: return "CLOSED"
        case 1: return "LISTEN"
        case 2: return "SYN_SENT"
        case 3: return "SYN_RECV"
        case 4: return "ESTABLISHED"
        case 5: return "CLOSE_WAIT"
        case 6: return "FIN_WAIT_1"
        case 7: return "CLOSING"
        case 8: return "LAST_ACK"
        case 9: return "FIN_WAIT_2"
        case 10: return "TIME_WAIT"
        default: return "UNKNOWN"
        }
    }

    // MARK: Shared libproc helpers

    private func listPIDs() -> [pid_t] {
        let sizeProbe = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard sizeProbe > 0 else { return [] }
        let capacity = Int(sizeProbe) / MemoryLayout<pid_t>.stride
        var pids = [pid_t](repeating: 0, count: capacity)
        let written = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, sizeProbe)
        guard written > 0 else { return [] }
        let count = Int(written) / MemoryLayout<pid_t>.stride
        return pids.prefix(count).filter { $0 > 0 }
    }

    private func name(for pid: pid_t) -> String {
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        if proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 {
            let last = (String(cString: pathBuffer) as NSString).lastPathComponent
            if !last.isEmpty { return last }
        }
        return "pid \(pid)"
    }
}
