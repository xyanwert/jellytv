import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Process-lifetime decoded-image cache for hero backdrops, keyed by URL
/// string.
///
/// The hero rotation reuses the *same* `heroImage` call site for a slide in
/// two different roles over its lifetime: first as the opaque "base" (while
/// it's the current slide, ~15s), then later as the "outgoing" snapshot that
/// crumbles away. Those are two structurally distinct views (no `.id()`
/// between them, deliberately, to avoid forcing a reload/remount on every
/// rotation), so if each one used a plain `AsyncImage` it would carry its
/// *own* independent loading state — the outgoing view's `AsyncImage` has
/// never fetched this URL from its own perspective, so the instant it
/// appears at full opacity it briefly shows whatever it last had loaded
/// (the slide from *two* cycles ago) until its own fetch catches up. That's
/// the "previous image flashes" bug.
///
/// Routing every hero image load through this shared cache instead means the
/// image is already decoded and ready by the time the same slide comes back
/// around as the outgoing snapshot, so it renders correctly on the very
/// first frame — no per-view loading state, no flash.
@MainActor
enum HeroImageCache {
    private static var images: [String: Image] = [:]
    private static var inFlight: Set<String> = []

    static func cached(_ urlString: String) -> Image? {
        images[urlString]
    }

    static func load(_ urlString: String) async {
        guard images[urlString] == nil, !inFlight.contains(urlString),
              let url = URL(string: urlString) else { return }
        inFlight.insert(urlString)
        #if canImport(UIKit)
        if let (data, _) = try? await URLSession.shared.data(from: url),
           let uiImage = UIImage(data: data) {
            images[urlString] = Image(uiImage: uiImage)
        }
        #endif
        inFlight.remove(urlString)
    }
}

/// A hero backdrop image backed by `HeroImageCache` — shows the cached image
/// immediately if one's already decoded, otherwise the fallback gradient
/// while it loads in the background.
///
/// `resolvedImage` reads the cache directly in `body`, synchronously, rather
/// than only through the `.task` below into `@State`. That matters because
/// this view's identity is reused across hero rotations (no `.id()`), so its
/// `@State` persists from the *previous* time it was shown — if the cache
/// lookup only happened inside `.task`, there'd be one render where `body`
/// runs with the OLD `@State` value (this cycle's `.task` hasn't started yet)
/// even though the cache already has the right image ready, which
/// reintroduces the exact "previous image flashes" bug this file exists to
/// fix. Reading the cache straight from `body` means a cache hit is visible
/// on the very first frame, no matter when the task gets scheduled.
struct CachedHeroImage: View {
    let urlString: String
    let fallback: LinearGradient

    @State private var loadedImage: Image?

    private var resolvedImage: Image? {
        HeroImageCache.cached(urlString) ?? loadedImage
    }

    var body: some View {
        Group {
            if let resolvedImage {
                resolvedImage.resizable().aspectRatio(contentMode: .fill)
            } else {
                fallback
            }
        }
        .task(id: urlString) {
            guard HeroImageCache.cached(urlString) == nil else { return }
            await HeroImageCache.load(urlString)
            loadedImage = HeroImageCache.cached(urlString)
        }
    }
}
