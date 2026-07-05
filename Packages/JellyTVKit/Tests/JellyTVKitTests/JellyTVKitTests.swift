import XCTest
@testable import JellyTVKit

final class JellyTVKitTests: XCTestCase {
    func testVersionMatchesMarketingVersion() {
        XCTAssertEqual(JellyTVKit.version, "0.1.0")
    }

    func testDisplayName() {
        XCTAssertEqual(JellyTVKit.displayName, "JellyTV")
    }
}
