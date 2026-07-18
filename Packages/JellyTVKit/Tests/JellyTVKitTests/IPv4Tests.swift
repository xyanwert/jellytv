import XCTest
@testable import JellyTVKit

/// Tests for the IP helpers behind the setup screen's octet reel and the LAN
/// discovery sweep.
final class IPv4Tests: XCTestCase {

    func testOctetsFromValidAddress() {
        XCTAssertEqual(IPv4.octets(from: "192.168.1.100"), [192, 168, 1, 100])
        XCTAssertEqual(IPv4.octets(from: "0.0.0.0"), [0, 0, 0, 0])
        XCTAssertEqual(IPv4.octets(from: "255.255.255.255"), [255, 255, 255, 255])
    }

    func testOctetsRejectsInvalid() {
        XCTAssertNil(IPv4.octets(from: "192.168.1"))      // too few
        XCTAssertNil(IPv4.octets(from: "192.168.1.1.1"))  // too many
        XCTAssertNil(IPv4.octets(from: "192.168.1.256"))  // out of range
        XCTAssertNil(IPv4.octets(from: "192.168.-1.1"))   // negative
        XCTAssertNil(IPv4.octets(from: "192.168.1."))     // trailing empty
        XCTAssertNil(IPv4.octets(from: "192.168.a.1"))    // non-numeric
        XCTAssertNil(IPv4.octets(from: "jellyfin.local")) // hostname
        XCTAssertNil(IPv4.octets(from: ""))               // empty
    }

    func testStringRoundTrip() {
        XCTAssertEqual(IPv4.string(from: [192, 168, 1, 100]), "192.168.1.100")
        // out-of-range octets are clamped when formatting
        XCTAssertEqual(IPv4.string(from: [999, -5, 168, 1]), "255.0.168.1")
        // valid address round-trips through octets() and back
        let addr = "10.0.42.7"
        XCTAssertEqual(IPv4.string(from: IPv4.octets(from: addr)!), addr)
    }

    func testClamp() {
        XCTAssertEqual(IPv4.clamp(-1), 0)
        XCTAssertEqual(IPv4.clamp(0), 0)
        XCTAssertEqual(IPv4.clamp(128), 128)
        XCTAssertEqual(IPv4.clamp(255), 255)
        XCTAssertEqual(IPv4.clamp(256), 255)
        XCTAssertEqual(IPv4.clamp(9000), 255)
    }

    func testSubnetBase() {
        XCTAssertEqual(IPv4.subnetBase(of: "192.168.1.150"), "192.168.1")
        XCTAssertEqual(IPv4.subnetBase(of: "10.0.42.7"), "10.0.42")
    }

    func testSubnetBaseRejectsLoopbackLinkLocalAndGarbage() {
        XCTAssertNil(IPv4.subnetBase(of: "127.0.0.1"))   // loopback
        XCTAssertNil(IPv4.subnetBase(of: "169.254.5.9")) // link-local
        XCTAssertNil(IPv4.subnetBase(of: "not-an-ip"))   // garbage
        XCTAssertNil(IPv4.subnetBase(of: "1.2.3"))       // malformed
    }
}
