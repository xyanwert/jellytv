import Foundation
import JellyTVKit
#if canImport(Darwin)
import Darwin
#endif

/// A Jellyfin server found on the local network.
struct DiscoveredServer: Identifiable, Equatable {
    let host: String     // dotted-quad IP
    let port: Int
    let name: String
    var id: String { "\(host):\(port)" }
    var address: String { "\(host):\(port)" }
}

/// Discovers Jellyfin servers on the local `/24` subnet.
///
/// Jellyfin's own UDP-broadcast auto-discovery would need Apple's multicast
/// entitlement on tvOS (special approval), so instead we do an entitlement-free
/// **unicast sweep**: read the Apple TV's own IPv4 via `getifaddrs`, then probe
/// every host `x.y.z.1…254` on port 8096 with the same unauthenticated
/// `/System/Info/Public` check the connect flow uses. Any reachable Jellyfin
/// answers regardless of whether it supports broadcast. Only the standard Local
/// Network permission is required.
@MainActor
final class LanScanner: ObservableObject {
    enum Phase: Equatable { case idle, scanning, done }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var servers: [DiscoveredServer] = []
    /// e.g. "192.168.1.x" — the subnet being swept, for the UI readout.
    @Published private(set) var subnetLabel: String?

    private let port = 8096
    private let maxConcurrent = 24
    private let probeTimeout: TimeInterval = 1.2
    private var task: Task<Void, Never>?

    /// Kick off (or restart) a sweep.
    func start() {
        if applyDemoHook() { return }
        task?.cancel()
        servers = []
        phase = .scanning
        let port = self.port
        let maxConcurrent = self.maxConcurrent
        let timeout = self.probeTimeout
        task = Task { [weak self] in
            await self?.scan(port: port, maxConcurrent: maxConcurrent, timeout: timeout)
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        if phase == .scanning { phase = .done }
    }

    private func scan(port: Int, maxConcurrent: Int, timeout: TimeInterval) async {
        guard let net = Self.localSubnet() else {
            subnetLabel = nil
            phase = .done
            return
        }
        subnetLabel = "\(net.base).x"

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = false
        config.allowsCellularAccess = false
        let session = URLSession(configuration: config)

        await withTaskGroup(of: DiscoveredServer?.self) { group in
            var next = 1
            func enqueueNext() {
                while next <= 254 {
                    let host = "\(net.base).\(next)"
                    next += 1
                    if host == net.selfIP { continue }
                    group.addTask { await Self.probe(host: host, port: port, session: session) }
                    return
                }
            }
            for _ in 0..<maxConcurrent { enqueueNext() }

            for await found in group {
                if Task.isCancelled { break }
                if let found {
                    servers.append(found)
                    servers.sort { $0.host.localizedStandardCompare($1.host) == .orderedAscending }
                }
                enqueueNext()
            }
        }

        if !Task.isCancelled { phase = .done }
    }

    /// Probe one host's `/System/Info/Public`; return a server if it looks like
    /// Jellyfin. Runs off the main actor.
    nonisolated private static func probe(host: String, port: Int, session: URLSession) async -> DiscoveredServer? {
        guard let url = URL(string: "http://\(host):\(port)/System/Info/Public") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let info = try JSONDecoder().decode(JellyfinAPI.PublicSystemInfo.self, from: data)
            // Only accept responses that actually look like Jellyfin.
            guard info.looksLikeJellyfin else { return nil }
            return DiscoveredServer(host: host, port: port, name: info.serverName ?? host)
        } catch {
            return nil
        }
    }

    /// The device's own IPv4 network: the first three octets ("192.168.1") plus
    /// its full address, from the Wi-Fi/Ethernet interface. Simulator inherits
    /// the host Mac's network, so this works there too.
    nonisolated private static func localSubnet() -> (base: String, selfIP: String)? {
        #if canImport(Darwin)
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var candidate: (String, String)?
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            guard let sa = p.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(p.pointee.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP, (flags & IFF_LOOPBACK) == 0 else { continue }

            var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len),
                              &hostBuf, socklen_t(hostBuf.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: hostBuf)
            // subnetBase rejects loopback / link-local / malformed addresses.
            guard let base = IPv4.subnetBase(of: ip) else { continue }
            let name = String(cString: p.pointee.ifa_name)
            // Prefer the primary Wi-Fi/Ethernet interface, but keep any valid
            // private address as a fallback.
            if name == "en0" { return (base, ip) }
            if candidate == nil { candidate = (base, ip) }
        }
        return candidate
        #else
        return nil
        #endif
    }

    /// Screenshot/testing hook: `JT_SCAN_DEMO` forces a discovery state so the
    /// scanning / found / empty UI can be captured without a live server.
    private func applyDemoHook() -> Bool {
        guard let demo = ProcessInfo.processInfo.environment["JT_SCAN_DEMO"] else { return false }
        subnetLabel = "192.168.1.x"
        switch demo {
        case "found":
            servers = [
                DiscoveredServer(host: "192.168.1.150", port: 8096, name: "Living Room"),
                DiscoveredServer(host: "192.168.1.42", port: 8096, name: "Basement NAS"),
            ]
            phase = .done
        case "scanning":
            servers = []
            phase = .scanning
        case "empty":
            servers = []
            phase = .done
        default:
            return false
        }
        return true
    }
}
