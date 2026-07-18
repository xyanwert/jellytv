import XCTest
@testable import JellyTVKit

/// Decoding tests for the Jellyfin REST models. These exist because a shipped
/// bug — camelCase properties with no `CodingKeys` against Jellyfin's PascalCase
/// JSON — made every login decode as a failure. Each test feeds real-shaped
/// PascalCase payloads and asserts the fields land.
final class JellyfinAPITests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - PublicSystemInfo (/System/Info/Public)

    func testPublicSystemInfoDecodesPascalCase() throws {
        let json = """
        {
            "LocalAddress": "http://192.168.1.150:8096",
            "ServerName": "xyan-media",
            "Version": "10.9.2",
            "ProductName": "Jellyfin Server",
            "Id": "9d8c7b6a5f4e",
            "StartupWizardCompleted": true
        }
        """
        let info = try decode(JellyfinAPI.PublicSystemInfo.self, json)
        XCTAssertEqual(info.serverName, "xyan-media")
        XCTAssertEqual(info.version, "10.9.2")
        XCTAssertEqual(info.id, "9d8c7b6a5f4e")
        XCTAssertEqual(info.productName, "Jellyfin Server")
        XCTAssertTrue(info.looksLikeJellyfin)
    }

    func testPublicSystemInfoToleratesMissingOptionalFields() throws {
        let info = try decode(JellyfinAPI.PublicSystemInfo.self, #"{ "ServerName": "reef" }"#)
        XCTAssertEqual(info.serverName, "reef")
        XCTAssertNil(info.version)
        XCTAssertNil(info.id)
        XCTAssertTrue(info.looksLikeJellyfin)   // name alone is enough
    }

    func testPublicSystemInfoNonJellyfinPayloadIsRejected() throws {
        // A 200 from some other service (no Id / ServerName) must not count as a
        // discovered Jellyfin server.
        let info = try decode(JellyfinAPI.PublicSystemInfo.self, #"{ "foo": "bar" }"#)
        XCTAssertFalse(info.looksLikeJellyfin)
    }

    // MARK: - AuthenticationResult (/Users/AuthenticateByName)

    func testAuthenticationResultDecodesPascalCase() throws {
        let json = """
        {
            "User": { "Name": "alex", "Id": "user-42", "HasPassword": true },
            "SessionInfo": { "Id": "sess-1" },
            "AccessToken": "tok_abcdef",
            "ServerId": "srv-1"
        }
        """
        let auth = try decode(JellyfinAPI.AuthenticationResult.self, json)
        XCTAssertEqual(auth.accessToken, "tok_abcdef")
        XCTAssertEqual(auth.userId, "user-42")
        XCTAssertEqual(auth.user.name, "alex")
    }

    func testAuthenticationResultRequiresAccessToken() {
        // A response missing AccessToken must throw rather than silently yield a
        // broken session — the opposite of the original bug's behaviour.
        let json = #"{ "User": { "Name": "alex", "Id": "u1" } }"#
        XCTAssertThrowsError(try decode(JellyfinAPI.AuthenticationResult.self, json))
    }

    // MARK: - Users list (/Users)

    func testUsersListDecodesPascalCase() throws {
        let json = """
        [
            { "Name": "alex", "Id": "u1", "HasPassword": true },
            { "Name": "Marina", "Id": "u2" }
        ]
        """
        let users = try decode([JellyfinAPI.User].self, json)
        XCTAssertEqual(users.map(\.id), ["u1", "u2"])
        XCTAssertEqual(users.map(\.name), ["alex", "Marina"])
        // case-insensitive name match, mirroring ServerConnection.resolveUser
        XCTAssertEqual(users.first { $0.name.lowercased() == "ALEX".lowercased() }?.id, "u1")
    }

    // MARK: - Authorization header

    func testAuthorizationHeaderFormat() {
        let header = JellyfinAPI.authorizationHeader(
            token: "tok", client: "JellyTV", device: "JellyTV",
            deviceId: "dev-1", version: "1.0.0")
        XCTAssertEqual(header,
            #"MediaBrowser Token="tok", Client="JellyTV", Device="JellyTV", DeviceId="dev-1", Version="1.0.0""#)
    }

    func testAuthorizationHeaderEmptyTokenForInitialAuth() {
        let header = JellyfinAPI.authorizationHeader(
            token: "", client: "JellyTV", device: "JellyTV",
            deviceId: "dev-1", version: "1.0.0")
        XCTAssertTrue(header.contains(#"Token="""#))
    }

    // MARK: - JellyfinItem decoding

    func testJellyfinItemDecodesPascalCase() throws {
        let json = """
        {
            "Id": "item-1",
            "Name": "The Deep Signal",
            "Type": "Movie",
            "Overview": "A deep-sea research crew uncovers a signal.",
            "Genres": ["Sci-Fi", "Drama"],
            "ProductionYear": 2026,
            "OfficialRating": "TV-MA",
            "CommunityRating": 8.9,
            "RunTimeTicks": 54000000000,
            "ImageTags": { "Primary": "abc123" },
            "BackdropImageTags": ["backdrop-tag"],
            "UserData": {
                "PlaybackPositionTicks": 33480000000,
                "PlayCount": 1,
                "Played": false,
                "IsFavorite": true,
                "LastPlayedDate": "2026-07-10T12:00:00Z"
            }
        }
        """
        let item = try decode(JellyfinAPI.JellyfinItem.self, json)
        XCTAssertEqual(item.id, "item-1")
        XCTAssertEqual(item.name, "The Deep Signal")
        XCTAssertEqual(item.type, "Movie")
        XCTAssertEqual(item.overview, "A deep-sea research crew uncovers a signal.")
        XCTAssertEqual(item.genres, ["Sci-Fi", "Drama"])
        XCTAssertEqual(item.productionYear, 2026)
        XCTAssertEqual(item.officialRating, "TV-MA")
        XCTAssertEqual(item.communityRating, 8.9)
        XCTAssertEqual(item.runTimeTicks, 54_000_000_000)
        XCTAssertEqual(item.imageTags, ["Primary": "abc123"])
        XCTAssertEqual(item.backdropImageTags, ["backdrop-tag"])
        XCTAssertEqual(item.userData?.playbackPositionTicks, 33_480_000_000)
        XCTAssertEqual(item.userData?.playCount, 1)
        XCTAssertEqual(item.userData?.played, false)
        XCTAssertEqual(item.userData?.isFavorite, true)
    }

    func testJellyfinItemHandlesMissingOptionalFields() throws {
        let json = #"{ "Id": "item-1", "Name": "Minimal Item" }"#
        let item = try decode(JellyfinAPI.JellyfinItem.self, json)
        XCTAssertEqual(item.id, "item-1")
        XCTAssertEqual(item.name, "Minimal Item")
        XCTAssertNil(item.type)
        XCTAssertNil(item.genres)
        XCTAssertNil(item.userData)
    }

    // MARK: - JellyfinUserView decoding

    func testJellyfinUserViewDecodesPascalCase() throws {
        let json = """
        {
            "Id": "lib-1",
            "Name": "Movies",
            "CollectionType": "movies",
            "ImageTags": { "Primary": "tag123" }
        }
        """
        let view = try decode(JellyfinAPI.JellyfinUserView.self, json)
        XCTAssertEqual(view.id, "lib-1")
        XCTAssertEqual(view.name, "Movies")
        XCTAssertEqual(view.collectionType, "movies")
        XCTAssertEqual(view.imageTags, ["Primary": "tag123"])
    }

    // MARK: - ItemsResponse decoding

    func testItemsResponseDecodesPascalCase() throws {
        let json = """
        {
            "Items": [
                { "Id": "item-1", "Name": "Item 1" },
                { "Id": "item-2", "Name": "Item 2" }
            ],
            "TotalRecordCount": 2,
            "StartIndex": 0
        }
        """
        let response = try decode(JellyfinAPI.ItemsResponse<JellyfinAPI.JellyfinItem>.self, json)
        XCTAssertEqual(response.items.count, 2)
        XCTAssertEqual(response.items[0].id, "item-1")
        XCTAssertEqual(response.items[1].name, "Item 2")
        XCTAssertEqual(response.totalRecordCount, 2)
        XCTAssertEqual(response.startIndex, 0)
    }
}
