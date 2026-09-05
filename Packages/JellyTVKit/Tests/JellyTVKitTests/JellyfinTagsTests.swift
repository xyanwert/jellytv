import XCTest
@testable import JellyTVKit

final class JellyfinTagsTests: XCTestCase {

    // MARK: - Normalisation

    func testNormalizedTrimsAndRejectsEmpty() {
        XCTAssertEqual(JellyfinTags.normalized("  gaby  "), "gaby")
        XCTAssertNil(JellyfinTags.normalized("   "))
        XCTAssertNil(JellyfinTags.normalized(""))
        XCTAssertNil(JellyfinTags.normalized("\n\t"))
    }

    func testNormalizedCapsLength() {
        let long = String(repeating: "a", count: 200)
        XCTAssertEqual(JellyfinTags.normalized(long)?.count, JellyfinTags.maxLength)
    }

    // MARK: - Canonical spelling

    /// The whole point: typing a tag that already exists in another casing
    /// must reuse the existing spelling, or the server ends up holding two
    /// tags that read identically on screen.
    func testCanonicalReusesExistingSpelling() {
        let vocabulary = ["Casero", "Gaby", "OF"]
        XCTAssertEqual(JellyfinTags.canonical("gaby", in: vocabulary), "Gaby")
        XCTAssertEqual(JellyfinTags.canonical("CASERO", in: vocabulary), "Casero")
        XCTAssertEqual(JellyfinTags.canonical("  of ", in: vocabulary), "OF")
    }

    func testCanonicalKeepsTypedSpellingWhenNew() {
        XCTAssertEqual(JellyfinTags.canonical("Lesbi", in: ["Casero"]), "Lesbi")
        XCTAssertNil(JellyfinTags.canonical("   ", in: ["Casero"]))
    }

    // MARK: - Toggling

    func testTogglingAddsAndRemovesCaseInsensitively() {
        XCTAssertEqual(JellyfinTags.toggling("Gaby", in: ["Casero"]), ["Casero", "Gaby"])
        XCTAssertEqual(JellyfinTags.toggling("gaby", in: ["Casero", "Gaby"]), ["Casero"])
    }

    func testTogglingPreservesOrder() {
        let tags = ["Casero", "Gaby", "OF"]
        XCTAssertEqual(JellyfinTags.toggling("Gaby", in: tags), ["Casero", "OF"])
        XCTAssertEqual(JellyfinTags.toggling("Nuevo", in: tags), ["Casero", "Gaby", "OF", "Nuevo"])
    }

    func testContains() {
        XCTAssertTrue(JellyfinTags.contains("gaby", in: ["Gaby"]))
        XCTAssertFalse(JellyfinTags.contains("gaby", in: ["Gabby"]))
    }

    // MARK: - The DTO edit

    /// `POST /Items/{id}` nulls whatever the body omits, so the one thing
    /// this edit must never do is drop a key it doesn't understand.
    func testItemDTOPreservesEveryOtherField() {
        let dto: [String: Any] = [
            "Id": "abc",
            "Name": "Some clip",
            "Overview": "A description worth not destroying.",
            "ProviderIds": ["Tmdb": "12345"],
            "SomethingThisAppHasNeverHeardOf": 42,
            "Tags": ["old"],
        ]
        let updated = JellyfinTags.itemDTO(dto, settingTags: ["new", "tags"])

        XCTAssertEqual(updated["Tags"] as? [String], ["new", "tags"])
        XCTAssertEqual(updated["Name"] as? String, "Some clip")
        XCTAssertEqual(updated["Overview"] as? String, "A description worth not destroying.")
        XCTAssertEqual(updated["ProviderIds"] as? [String: String], ["Tmdb": "12345"])
        XCTAssertEqual(updated["SomethingThisAppHasNeverHeardOf"] as? Int, 42)
        XCTAssertEqual(updated.keys.count, dto.keys.count + 1) // + LockedFields
    }

    func testItemDTOLocksTagsAgainstTheNextMetadataRefresh() {
        let updated = JellyfinTags.itemDTO(["Id": "abc"], settingTags: ["casero"])
        XCTAssertEqual(updated["LockedFields"] as? [String], ["Tags"])
    }

    func testItemDTOKeepsExistingLocksAndDoesNotDuplicate() {
        let dto: [String: Any] = ["LockedFields": ["Name", "Tags"]]
        let updated = JellyfinTags.itemDTO(dto, settingTags: [])
        XCTAssertEqual(updated["LockedFields"] as? [String], ["Name", "Tags"])
    }

    func testItemDTOAppendsToExistingLocks() {
        let dto: [String: Any] = ["LockedFields": ["Name"]]
        let updated = JellyfinTags.itemDTO(dto, settingTags: ["x"])
        XCTAssertEqual(updated["LockedFields"] as? [String], ["Name", "Tags"])
    }

    /// Clearing every tag is a deliberate act too — the field stays locked so
    /// a refresh can't repopulate it.
    func testItemDTOWithNoTagsStillLocks() {
        let updated = JellyfinTags.itemDTO(["Id": "abc"], settingTags: [])
        XCTAssertEqual(updated["Tags"] as? [String], [])
        XCTAssertEqual(updated["LockedFields"] as? [String], ["Tags"])
    }
}

extension JellyfinTagsTests {

    /// The server hands back a `Trickplay` blob it cannot itself parse, and
    /// posting it straight back is a 500 on every item that has trickplay
    /// data. See `JellyfinTags.unparseableKeys`.
    func testItemDTODropsTheKeyTheServerCannotParse() {
        let dto: [String: Any] = [
            "Id": "abc",
            "Name": "Some clip",
            "Trickplay": ["source": ["320": ["Width": 320]]],
        ]
        let updated = JellyfinTags.itemDTO(dto, settingTags: ["x"])
        XCTAssertNil(updated["Trickplay"])
        XCTAssertEqual(updated["Name"] as? String, "Some clip")
    }
}
