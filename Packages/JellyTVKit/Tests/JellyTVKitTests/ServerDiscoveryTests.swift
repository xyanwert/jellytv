import XCTest
@testable import JellyTVKit

final class ServerDiscoveryTests: XCTestCase {

    func testCollapsePreferringYsojKeepsYsojWhenBothAnswerSameHost() {
        let jellyfin = DiscoveredServer(host: "192.168.1.150", port: 8096, name: "xyan-media", kind: .jellyfin)
        let ysoj = DiscoveredServer(host: "192.168.1.150", port: 8097, name: "xyan-media (YSOJ)", kind: .ysoj)
        // Order-independent: YSOJ wins whichever one is discovered second.
        let arrivingJellyfinFirst = ServerDiscovery.collapsePreferringYsoj([jellyfin, ysoj])
        XCTAssertEqual(arrivingJellyfinFirst, [ysoj])
        let arrivingYsojFirst = ServerDiscovery.collapsePreferringYsoj([ysoj, jellyfin])
        XCTAssertEqual(arrivingYsojFirst, [ysoj])
    }

    func testCollapsePreferringYsojKeepsPlainJellyfinWhenNoYsojOnThatHost() {
        let jellyfin = DiscoveredServer(host: "192.168.1.42", port: 8096, name: "Basement NAS", kind: .jellyfin)
        XCTAssertEqual(ServerDiscovery.collapsePreferringYsoj([jellyfin]), [jellyfin])
    }

    func testCollapsePreferringYsojKeepsDistinctHostsSeparate() {
        let ysojHost = DiscoveredServer(host: "192.168.1.150", port: 8097, name: "xyan-media (YSOJ)", kind: .ysoj)
        let plainHost = DiscoveredServer(host: "192.168.1.42", port: 8096, name: "Basement NAS", kind: .jellyfin)
        let collapsed = Set(ServerDiscovery.collapsePreferringYsoj([ysojHost, plainHost]).map(\.id))
        XCTAssertEqual(collapsed, [ysojHost.id, plainHost.id])
    }

    func testDiscoveredServerIdAndAddressCombineHostAndPort() {
        let server = DiscoveredServer(host: "192.168.1.150", port: 8097, name: "xyan-media (YSOJ)", kind: .ysoj)
        XCTAssertEqual(server.id, "192.168.1.150:8097")
        XCTAssertEqual(server.address, "192.168.1.150:8097")
    }
}
