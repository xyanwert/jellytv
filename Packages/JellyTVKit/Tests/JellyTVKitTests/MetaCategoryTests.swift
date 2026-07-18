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
