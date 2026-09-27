import XCTest
@testable import JellyTVKit

final class LanguageTests: XCTestCase {
    private func audio(_ index: Int, _ lang: String?, isDefault: Bool = false, title: String? = nil) -> JellyfinAPI.MediaStream {
        JellyfinAPI.MediaStream(type: "Audio", codec: "ac3", index: index, language: lang, title: title, isDefault: isDefault)
    }
    private func sub(_ index: Int, _ lang: String?, forced: Bool = false, text: Bool = true) -> JellyfinAPI.MediaStream {
        JellyfinAPI.MediaStream(type: "Subtitle", codec: text ? "subrip" : "PGSSUB", index: index, language: lang,
                                isForced: forced, isTextSubtitleStream: text)
    }

    func testCanonicalCodes() {
        XCTAssertEqual(LanguageTable.canonical("es"), "spa")
        XCTAssertEqual(LanguageTable.canonical("SPA"), "spa")
        XCTAssertEqual(LanguageTable.canonical("es-MX"), "spa")
        XCTAssertEqual(LanguageTable.canonical("deu"), "ger")
        XCTAssertEqual(LanguageTable.canonical("zho"), "chi")
        XCTAssertNil(LanguageTable.canonical("und"))
        XCTAssertNil(LanguageTable.canonical(nil))
        XCTAssertEqual(LanguageTable.canonical("xyz"), "xyz")
    }

    func testEndonyms() {
        XCTAssertEqual(LanguageTable.endonym(for: "spa"), "Español")
        XCTAssertEqual(LanguageTable.endonym(for: "ja"), "日本語")
        XCTAssertEqual(LanguageTable.endonym(for: "ara"), "العربية")
        XCTAssertEqual(LanguageTable.endonym(for: "xyz"), "XYZ")
        XCTAssertEqual(LanguageTable.all.count, 10)
    }

    func testPrefersFirstAvailableAudioLanguage() {
        let streams = [audio(1, "eng", isDefault: true), audio(2, "spa"), audio(3, "jpn")]
        let pref = LibraryLanguagePreference(audio: ["fre", "spa", "eng"])
        XCTAssertEqual(TrackPicker.choose(streams: streams, preference: pref).audioIndex, 2)
    }

    func testFallsBackToDefaultAudio() {
        let streams = [audio(1, "eng"), audio(2, "jpn", isDefault: true)]
        let pref = LibraryLanguagePreference(audio: ["spa"])
        XCTAssertEqual(TrackPicker.choose(streams: streams, preference: pref).audioIndex, 2)
    }

    func testSkipsCommentaryWhenAnotherTrackMatches() {
        let streams = [audio(1, "eng", title: "Director's commentary"), audio(2, "eng")]
        let pref = LibraryLanguagePreference(audio: ["eng"])
        XCTAssertEqual(TrackPicker.choose(streams: streams, preference: pref).audioIndex, 2)
    }

    func testSubtitlesOnPicksPreferredFullTextTrack() {
        let streams = [audio(1, "eng"), sub(2, "spa", forced: true), sub(3, "spa"), sub(4, "eng")]
        let pref = LibraryLanguagePreference(audio: ["eng"], subtitles: ["spa"], subtitleMode: .on)
        let choice = TrackPicker.choose(streams: streams, preference: pref)
        XCTAssertEqual(choice.subtitleIndex, 3)
        XCTAssertFalse(choice.subtitleIsBurnIn)
        XCTAssertFalse(choice.subtitleIsAutomatic)
    }

    func testSubtitlesOnPrefersTextOverBitmap() {
        let streams = [audio(1, "eng"), sub(2, "spa", text: false), sub(3, "spa")]
        let pref = LibraryLanguagePreference(subtitles: ["spa"], subtitleMode: .on)
        XCTAssertEqual(TrackPicker.choose(streams: streams, preference: pref).subtitleIndex, 3)
    }

    func testBitmapOnlyIsBurnIn() {
        let streams = [audio(1, "eng"), sub(2, "spa", text: false)]
        let pref = LibraryLanguagePreference(subtitles: ["spa"], subtitleMode: .on)
        let choice = TrackPicker.choose(streams: streams, preference: pref)
        XCTAssertEqual(choice.subtitleIndex, 2)
        XCTAssertTrue(choice.subtitleIsBurnIn)
    }

    func testSubtitlesOffKeepsForcedInAudioLanguage() {
        let streams = [audio(1, "eng"), sub(2, "eng", forced: true), sub(3, "spa")]
        let pref = LibraryLanguagePreference(audio: ["eng"], subtitles: ["spa"], subtitleMode: .off)
        let choice = TrackPicker.choose(streams: streams, preference: pref)
        XCTAssertEqual(choice.subtitleIndex, 2)
        XCTAssertTrue(choice.subtitleIsAutomatic)
    }

    func testSubtitlesOffWithoutForcedIsOff() {
        let streams = [audio(1, "eng"), sub(3, "spa")]
        let pref = LibraryLanguagePreference(audio: ["eng"], subtitles: ["spa"], subtitleMode: .off)
        XCTAssertNil(TrackPicker.choose(streams: streams, preference: pref).subtitleIndex)
    }

    func testSmartTurnsSubtitlesOnForForeignAudio() {
        let streams = [audio(1, "jpn", isDefault: true), sub(2, "eng"), sub(3, "spa")]
        let pref = LibraryLanguagePreference(audio: ["spa", "eng"], subtitles: ["spa", "eng"], subtitleMode: .smart)
        let choice = TrackPicker.choose(streams: streams, preference: pref)
        XCTAssertEqual(choice.audioIndex, 1)
        XCTAssertEqual(choice.subtitleIndex, 3)
        XCTAssertTrue(choice.subtitleIsAutomatic)
    }

    func testSmartStaysOffWhenAudioIsPreferred() {
        let streams = [audio(1, "jpn"), audio(2, "spa"), sub(3, "spa")]
        let pref = LibraryLanguagePreference(audio: ["spa"], subtitles: ["spa"], subtitleMode: .smart)
        let choice = TrackPicker.choose(streams: streams, preference: pref)
        XCTAssertEqual(choice.audioIndex, 2)
        XCTAssertNil(choice.subtitleIndex)
    }

    func testNoPreferenceUsesDefaults() {
        let streams = [audio(1, "eng"), audio(2, "spa", isDefault: true), sub(3, "eng")]
        let choice = TrackPicker.choose(streams: streams, preference: nil)
        XCTAssertEqual(choice.audioIndex, 2)
        XCTAssertNil(choice.subtitleIndex)
    }

    func testPreferenceCapsAtThree() {
        let pref = LibraryLanguagePreference(audio: ["a", "b", "c", "d"])
        XCTAssertEqual(pref.audio.count, 3)
    }
}
