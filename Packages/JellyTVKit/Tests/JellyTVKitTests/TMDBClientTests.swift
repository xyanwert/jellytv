import XCTest
@testable import JellyTVKit

final class TMDBClientTests: XCTestCase {

    // MARK: - TMDBTVResult.primaryNetwork

    func testPrimaryNetworkFromFirstEntry() {
        let result = TMDBTVResult(networks: [
            TMDBNetwork(name: "Adult Swim", logoPath: "/abc123.png"),
            TMDBNetwork(name: "Cartoon Network", logoPath: "/xyz789.png"),
        ])
        XCTAssertEqual(result.primaryNetwork?.name, "Adult Swim")
        XCTAssertEqual(result.primaryNetwork?.logoURL, "https://image.tmdb.org/t/p/w300/abc123.png")
    }

    func testPrimaryNetworkNilWhenNoLogoPath() {
        let result = TMDBTVResult(networks: [TMDBNetwork(name: "Public Access")])
        XCTAssertEqual(result.primaryNetwork?.name, "Public Access")
        XCTAssertNil(result.primaryNetwork?.logoURL)
    }

    func testPrimaryNetworkNilWhenNetworksEmpty() {
        XCTAssertNil(TMDBTVResult(networks: []).primaryNetwork)
    }

    func testPrimaryNetworkNilWhenNetworksMissing() {
        XCTAssertNil(TMDBTVResult(networks: nil).primaryNetwork)
    }

    // MARK: - JSON decoding

    func testTVResultDecodesFromJSON() throws {
        let json = """
        {"networks":[{"name":"HBO","logo_path":"/hbo.png"}]}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(TMDBTVResult.self, from: json)
        XCTAssertEqual(result.primaryNetwork?.name, "HBO")
        XCTAssertEqual(result.primaryNetwork?.logoURL, "https://image.tmdb.org/t/p/w300/hbo.png")
    }

    func testFindResultDecodesFromJSON() throws {
        let json = """
        {"movie_results":[],"tv_results":[{"id":1396}],"person_results":[]}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(TMDBFindResult.self, from: json)
        XCTAssertEqual(result.tvResults?.first?.id, 1396)
    }

    func testFindResultNilWhenNoTVMatch() throws {
        let json = """
        {"movie_results":[],"tv_results":[],"person_results":[]}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(TMDBFindResult.self, from: json)
        XCTAssertNil(result.tvResults?.first)
    }
}
