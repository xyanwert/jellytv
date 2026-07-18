import Foundation

/// Pure helpers for IPv4 addresses — parsing, formatting, clamping, and subnet
/// math shared by the setup screen's octet reel and the LAN discovery sweep.
/// Deliberately free of networking so it stays unit-testable.
public enum IPv4 {
    public static let octetRange = 0...255

    /// Parse `"192.168.1.100"` into four octets, or `nil` if it isn't a valid
    /// dotted quad with every octet in `0...255`.
    public static func octets(from address: String) -> [Int]? {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var result: [Int] = []
        result.reserveCapacity(4)
        for part in parts {
            guard let value = Int(part), octetRange.contains(value) else { return nil }
            result.append(value)
        }
        return result
    }

    /// Format four octets back into a dotted quad, clamping each to `0...255`.
    public static func string(from octets: [Int]) -> String {
        octets.map { String(clamp($0)) }.joined(separator: ".")
    }

    /// Clamp a single octet into `0...255`.
    public static func clamp(_ octet: Int) -> Int {
        min(255, max(0, octet))
    }

    /// The `/24` base (`"192.168.1"`) of an address, or `nil` if it isn't a valid
    /// dotted quad or is an address that isn't useful to sweep — loopback
    /// (`127.x`) or link-local (`169.254.x`).
    public static func subnetBase(of address: String) -> String? {
        guard let o = octets(from: address) else { return nil }
        if o[0] == 127 { return nil }
        if o[0] == 169 && o[1] == 254 { return nil }
        return "\(o[0]).\(o[1]).\(o[2])"
    }
}
