import Foundation

/// A Jellyfin (or YSOJ-server) instance found on the local network — the
/// result shape `LanScanner`'s unicast sweep builds. Kept here, rather than
/// alongside the scanner itself, so the "one row per host, prefer YSOJ"
/// collapse rule below is testable without a simulator.
public struct DiscoveredServer: Identifiable, Equatable, Sendable {
    public let host: String     // dotted-quad IP
    public let port: Int
    public let name: String
    public let kind: JellyfinAPI.ServerKind

    public init(host: String, port: Int, name: String, kind: JellyfinAPI.ServerKind) {
        self.host = host
        self.port = port
        self.name = name
        self.kind = kind
    }

    public var id: String { "\(host):\(port)" }
    public var address: String { "\(host):\(port)" }
}

public enum ServerDiscovery {
    /// One box running both a YSOJ-server and the Jellyfin it proxies must
    /// appear as a single row — the YSOJ one — not two rows the user has to
    /// choose between. Keeps the plain-Jellyfin entry only for hosts where
    /// no YSOJ-server answered. Order-independent: whichever of the two
    /// arrives second for a given host, the result still prefers YSOJ.
    public static func collapsePreferringYsoj(_ found: [DiscoveredServer]) -> [DiscoveredServer] {
        var byHost: [String: DiscoveredServer] = [:]
        for server in found {
            if let existing = byHost[server.host], existing.kind == .ysoj { continue }
            byHost[server.host] = server
        }
        return Array(byHost.values)
    }
}
