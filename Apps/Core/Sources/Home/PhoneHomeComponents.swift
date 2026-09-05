import SwiftUI
import JellyTVKit

#if os(iOS)
/// Phone Home's compact header — "Home" + the profile avatar, replacing the
/// iPad/tvOS `TopBar`'s "HOME // FEATURED" eyebrow + decorative clock + hero
/// rotation dots. None of those read as useful on a phone: there's no
/// full-bleed hero backdrop behind this row any more (see `HomeView`'s phone
/// branch) so the eyebrow has nothing to caption, the decorative clock sits a
/// few points under the *real* status-bar clock, and the carousel dots belong
/// on the carousel itself, not the page header — see `Browse.dc.html`/
/// `Home.dc.html`'s plain "Home" + avatar row.
struct PhoneHomeHeader: View {
    let initial: String
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Home")
                .font(Typography.font(30, .black))
                .tracking(-0.9)
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: 0)
            Button(action: onOpenSettings) {
                Avatar(initial: initial, size: 34)
                    .overlay(Circle().stroke(Color(hex: "#FFF3F3"), lineWidth: 2))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }
}

/// One capsule in `PhoneLibraryPillsRow` — a plain pill, or (for the active
/// "For You" pill) accent-filled with a soft glow, matching `Home.dc.html`'s
/// open state for whichever destination is current.
private struct PhoneLibraryPill: View {
    let label: String
    var systemImage: String? = nil
    let isActive: Bool
    let action: () -> Void

    @EnvironmentObject private var theme: Theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 13, weight: .bold))
                }
                Text(label)
                    .font(Typography.font(14, .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(isActive ? .white : Palette.text(0.82))
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background {
                if isActive {
                    Capsule().fill(theme.accent)
                        .shadow(color: theme.accent.opacity(0.42), radius: 12, y: 4)
                } else {
                    Capsule().fill(Palette.text(0.08))
                        .overlay(Capsule().stroke(Palette.text(0.1), lineWidth: 1))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// **Every library one tap from Home, instead of buried behind "More".**
/// iPad/tvOS put the whole library list in a rail flyout because the rail is
/// always on screen to open it from; on phone `NavRail` is gone entirely (see
/// that file's phone branch) and the tab bar only has room for Home/Search/
/// Movies/Shows/More (`PhoneTabBar`) — so a library that isn't one of those
/// five (Anime, Late Night, a Home Videos library, …) would otherwise cost a
/// second tap into the "More" sheet every single time. This row surfaces them
/// right under the header instead, exactly like the genre's own apps do.
///
/// "For You" is Home itself (always the active pill, no-op when tapped —
/// there's nowhere to navigate *to*); Movies/Shows route through the same
/// `onSelectRail` the tab bar uses; everything else routes through
/// `AppState.pendingLibraryNavigation`, the same mechanism `LibraryRow`
/// (the "More" sheet's own list) already uses.
struct PhoneLibraryPillsRow: View {
    let libraries: [Library]
    let onSelectRail: (RailTarget) -> Void

    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                PhoneLibraryPill(label: "For You", systemImage: "star.fill", isActive: true, action: {})
                PhoneLibraryPill(label: "Movies", systemImage: "rectangle.stack", isActive: false) {
                    onSelectRail(.movies)
                }
                PhoneLibraryPill(label: "Shows", systemImage: "tv", isActive: false) {
                    onSelectRail(.tv)
                }
                ForEach(libraries) { library in
                    PhoneLibraryPill(label: library.name, isActive: false) {
                        appState.pendingLibraryNavigation = library.category
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

/// **The featured card carousel** — phone's replacement for the full-bleed,
/// auto-rotating hero backdrop (`HomeView.heroBackdropLayer`/`HeroView`).
/// Contained art (302×384, `Home.dc.html`) with neighbouring cards peeking at
/// the edges, built on `ScrollView` + `.scrollTargetBehavior(.viewAligned)` —
/// the standard iOS 17 "paged carousel" recipe — rather than adapting the
/// existing crumble/departure transition system, which exists specifically to
/// animate a full-bleed backdrop that phone doesn't have any more.
///
/// **Deliberately does not auto-rotate.** The iPad/tvOS hero is ambient,
/// glanced-at-from-a-couch set dressing, so timed rotation reads as intended
/// motion. A phone carousel is something a thumb actively swipes — Netflix's
/// and Disney+'s own mobile "featured" rails don't auto-advance either, and
/// timed rotation stealing the card out from under a mid-swipe thumb (or
/// resetting scroll position while you're reading the synopsis) is worse than
/// no motion at all. See `HomeView`'s phone branch, which skips
/// `startHeroRotation()` entirely rather than pointing it at this carousel.
struct PhoneFeaturedCarousel: View {
    let heroes: [HeroFeature]
    let onSelect: (HeroFeature) -> Void

    static let cardSize = CGSize(width: 302, height: 384)

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(heroes) { hero in
                    PhoneFeaturedCard(hero: hero, onSelect: { onSelect(hero) })
                }
            }
            .scrollTargetLayout()
        }
        .safeAreaPadding(.horizontal, 44)
        .scrollTargetBehavior(.viewAligned)
        .frame(height: Self.cardSize.height)
    }
}

/// One page of `PhoneFeaturedCarousel`: contained artwork, a bottom scrim, and
/// a centered text block (eyebrow pill / title / episode line / rating
/// chips) — the same real `HeroFeature` fields `HeroView` shows on iPad/tvOS,
/// just recomposed for a vertical card instead of a side-by-side split.
struct PhoneFeaturedCard: View {
    let hero: HeroFeature
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottom) {
                artwork
                scrim
                textBlock
            }
            .frame(width: PhoneFeaturedCarousel.cardSize.width,
                   height: PhoneFeaturedCarousel.cardSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
        }
        .buttonStyle(FocusScaleStyle(scale: 1.02, cornerRadius: 18))
    }

    @ViewBuilder private var artwork: some View {
        if hero.image.hasPrefix("http") {
            CachedHeroImage(urlString: hero.image, fallback: hero.artwork.gradient)
        } else if !hero.image.isEmpty {
            Image(hero.image).resizable().scaledToFill()
        } else {
            hero.artwork.gradient
        }
    }

    private var scrim: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.34),
                .init(color: .black.opacity(0.72), location: 0.68),
                .init(color: Color(hex: "#03060B"), location: 1.0),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var textBlock: some View {
        VStack(spacing: 10) {
            if !hero.eyebrow.isEmpty {
                Text(hero.eyebrow.uppercased())
                    .font(Mono.font(10, .heavy))
                    .tracking(1.6)
                    .foregroundStyle(Color(hex: "#0B0D13"))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Color(hex: "#F4F5F7"), in: Capsule())
            }
            // No `.tracking()` here on purpose — `HeroView.textBlock`'s own
            // comment documents that negative tracking on a `Text` breaks
            // multi-line layout in this SwiftUI version (it stopped a
            // manual "\n" from wrapping at all there); this card hit the
            // same landmine as a title that simply refused to wrap and
            // painted straight across both neighbours instead of clipping
            // inside its own card. `minimumScaleFactor` is the safety net
            // for a title still too wide at two lines.
            Text(hero.title)
                .font(Typography.font(27, .black))
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .frame(width: PhoneFeaturedCarousel.cardSize.width - 36)
                .shadow(color: .black.opacity(0.6), radius: 18)
            // The real-data equivalent of the mockup's "Season 3 · 8 new
            // episodes" — that new-episode count isn't data this app has, so
            // this shows the same episode line `HeroView` renders on iPad/
            // tvOS instead of inventing a number. Genre already appears in
            // the chip row below, so it isn't repeated here as a fallback.
            if !hero.episode.isEmpty {
                Text(hero.episode)
                    .font(Typography.font(13, .semibold))
                    .foregroundStyle(Palette.text(0.72))
            }
            HStack(spacing: 8) {
                if !hero.certification.isEmpty {
                    Text(hero.certification)
                        .font(Mono.font(9, .bold))
                        .foregroundStyle(Palette.text(0.8))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Palette.text(0.28), lineWidth: 1))
                }
                let tail = [hero.year, hero.genre].filter { !$0.isEmpty }.joined(separator: " · ")
                if !tail.isEmpty {
                    Text(tail)
                        .font(Typography.font(12, .semibold))
                        .foregroundStyle(Palette.text(0.55))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 22)
    }
}
#endif
