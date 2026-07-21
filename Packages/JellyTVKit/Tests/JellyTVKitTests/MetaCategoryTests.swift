import XCTest
@testable import JellyTVKit

final class MetaCategoryTests: XCTestCase {

    func testIsNSFW() {
        XCTAssertFalse(MetaCategory.movies.isNSFW)
        XCTAssertTrue(MetaCategory.moviesxxx.isNSFW)
        XCTAssertFalse(MetaCategory.animefilm.isNSFW)
        XCTAssertFalse(MetaCategory.shows.isNSFW)
        XCTAssertFalse(MetaCategory.anime.isNSFW)
        XCTAssertTrue(MetaCategory.hentai.isNSFW)
        XCTAssertFalse(MetaCategory.videos.isNSFW)
        XCTAssertTrue(MetaCategory.porn.isNSFW)
    }

    func testIsAnime() {
        XCTAssertFalse(MetaCategory.movies.isAnime)
        XCTAssertFalse(MetaCategory.moviesxxx.isAnime)
        XCTAssertTrue(MetaCategory.animefilm.isAnime)
        XCTAssertFalse(MetaCategory.shows.isAnime)
        XCTAssertTrue(MetaCategory.anime.isAnime)
        XCTAssertTrue(MetaCategory.hentai.isAnime)
        XCTAssertFalse(MetaCategory.videos.isAnime)
        XCTAssertFalse(MetaCategory.porn.isAnime)
    }

    func testCollectionType() {
        XCTAssertEqual(MetaCategory.movies.collectionType, "movies")
        XCTAssertEqual(MetaCategory.moviesxxx.collectionType, "movies")
        XCTAssertEqual(MetaCategory.animefilm.collectionType, "movies")
        XCTAssertEqual(MetaCategory.shows.collectionType, "tvshows")
        XCTAssertEqual(MetaCategory.anime.collectionType, "tvshows")
        XCTAssertEqual(MetaCategory.hentai.collectionType, "tvshows")
        XCTAssertEqual(MetaCategory.videos.collectionType, "homevideos")
        XCTAssertEqual(MetaCategory.porn.collectionType, "homevideos")
    }

    func testSupportsNSFW() {
        XCTAssertTrue(MetaCategory.supportsNSFW(collectionType: "movies"))
        XCTAssertTrue(MetaCategory.supportsNSFW(collectionType: "tvshows"))
        XCTAssertTrue(MetaCategory.supportsNSFW(collectionType: "homevideos"))
        XCTAssertFalse(MetaCategory.supportsNSFW(collectionType: "music"))
    }

    func testSupportsAnime() {
        XCTAssertTrue(MetaCategory.supportsAnime(collectionType: "movies"))
        XCTAssertTrue(MetaCategory.supportsAnime(collectionType: "tvshows"))
        XCTAssertFalse(MetaCategory.supportsAnime(collectionType: "homevideos"))
        XCTAssertFalse(MetaCategory.supportsAnime(collectionType: "music"))
    }

    func testResolveMovies() {
        XCTAssertEqual(MetaCategory.resolve(collectionType: "movies", isNSFW: false, isAnime: false), .movies)
        XCTAssertEqual(MetaCategory.resolve(collectionType: "movies", isNSFW: true, isAnime: false), .moviesxxx)
        XCTAssertEqual(MetaCategory.resolve(collectionType: "movies", isNSFW: false, isAnime: true), .animefilm)
        // No combined NSFW+anime category for movies — NSFW takes priority
        // (Settings keeps the two toggles mutually exclusive for this kind).
        XCTAssertEqual(MetaCategory.resolve(collectionType: "movies", isNSFW: true, isAnime: true), .moviesxxx)
    }

    func testResolveTVShows() {
        XCTAssertEqual(MetaCategory.resolve(collectionType: "tvshows", isNSFW: false, isAnime: false), .shows)
        XCTAssertEqual(MetaCategory.resolve(collectionType: "tvshows", isNSFW: false, isAnime: true), .anime)
        XCTAssertEqual(MetaCategory.resolve(collectionType: "tvshows", isNSFW: true, isAnime: false), .hentai)
        XCTAssertEqual(MetaCategory.resolve(collectionType: "tvshows", isNSFW: true, isAnime: true), .hentai)
    }

    func testResolveHomeVideos() {
        XCTAssertEqual(MetaCategory.resolve(collectionType: "homevideos", isNSFW: false, isAnime: false), .videos)
        XCTAssertEqual(MetaCategory.resolve(collectionType: "homevideos", isNSFW: true, isAnime: false), .porn)
        // Anime has nowhere to go for home videos — ignored.
        XCTAssertEqual(MetaCategory.resolve(collectionType: "homevideos", isNSFW: false, isAnime: true), .videos)
    }

    func testResolveReturnsNilForUnknownCollectionType() {
        XCTAssertNil(MetaCategory.resolve(collectionType: "music", isNSFW: false, isAnime: false))
    }

    func testLibraryClassificationOverrideCodableRoundTrip() throws {
        let override = LibraryClassificationOverride(isNSFW: true, isAnime: false)
        let data = try JSONEncoder().encode(override)
        let decoded = try JSONDecoder().decode(LibraryClassificationOverride.self, from: data)
        XCTAssertEqual(decoded, override)
    }
}

final class LibraryClassifierTests: XCTestCase {

    func testClassifyMovies() {
        XCTAssertEqual(LibraryClassifier.classify(collectionType: "movies", name: "Movies"), .movies)
    }

    func testClassifyMoviesXXX() {
        XCTAssertEqual(LibraryClassifier.classify(collectionType: "movies", name: "Movies XXX"), .moviesxxx)
        XCTAssertEqual(LibraryClassifier.classify(collectionType: "movies", name: "NSFW Films"), .moviesxxx)
        XCTAssertEqual(LibraryClassifier.classify(collectionType: "movies", name: "Adult Movies"), .moviesxxx)
    }

    func testClassifyAnimeFilm() {
        XCTAssertEqual(LibraryClassifier.classify(collectionType: "movies", name: "Anime Films"), .animefilm)
        XCTAssertEqual(LibraryClassifier.classify(collectionType: "movies", name: "アニメ Movies"), .animefilm)
    }

    func testClassifyShows() {
        XCTAssertEqual(LibraryClassifier.classify(collectionType: "tvshows", name: "TV Shows"), .shows)
    }

    func testClassifyAnime() {
        XCTAssertEqual(LibraryClassifier.classify(collectionType: "tvshows", name: "Anime"), .anime)
        XCTAssertEqual(LibraryClassifier.classify(collectionType: "tvshows", name: "アニメ"), .anime)
    }

    func testClassifyHentai() {
        XCTAssertEqual(LibraryClassifier.classify(collectionType: "tvshows", name: "Hentai"), .hentai)
    }

    func testClassifyVideos() {
        XCTAssertEqual(LibraryClassifier.classify(collectionType: "homevideos", name: "Videos"), .videos)
    }

    func testClassifyPorn() {
        XCTAssertEqual(LibraryClassifier.classify(collectionType: "homevideos", name: "Porn"), .porn)
        XCTAssertEqual(LibraryClassifier.classify(collectionType: "homevideos", name: "XXX Videos"), .porn)
        XCTAssertEqual(LibraryClassifier.classify(collectionType: "homevideos", name: "JAV Collection"), .porn)
    }

    func testClassifyReturnsNilForMusic() {
        XCTAssertNil(LibraryClassifier.classify(collectionType: "music", name: "Music"))
    }

    func testClassifyReturnsNilForBooks() {
        XCTAssertNil(LibraryClassifier.classify(collectionType: "books", name: "Books"))
    }

    func testClassifyReturnsNilForNilCollectionType() {
        XCTAssertNil(LibraryClassifier.classify(collectionType: nil, name: "Unknown"))
    }

    func testClassifyCaseInsensitive() {
        XCTAssertEqual(LibraryClassifier.classify(collectionType: "movies", name: "ANIME films"), .animefilm)
        XCTAssertEqual(LibraryClassifier.classify(collectionType: "movies", name: "XXX Movies"), .moviesxxx)
        XCTAssertEqual(LibraryClassifier.classify(collectionType: "tvshows", name: "PORN Shows"), .hentai)
    }
}
