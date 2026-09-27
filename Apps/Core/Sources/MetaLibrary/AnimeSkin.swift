import SwiftUI
import JellyTVKit
#if canImport(UIKit)
import UIKit
#endif

// The Anime library's own skin in Poster Mode (design canvas "Anime Library
// Skin"): the Zenless Zone Zero key-visual look — a hot coral ground with a
// halftone, a lime slash, an ink shelf, a die-cut アニメ / ANIME lockup, the
// focused title's key art pinned up as a tilted card, and characters cut out
// with a thick white border standing over it all.
//
// Three states, one screen: the library (the default), the title focus (the
// remote has rested on a title that has a clean cut-out of its own — its
// colour takes the ground and its character the stage), and the empty shelf.
//
// Static by construction: the ground is one flattened `Canvas`, the stickers
// are baked images (`StickerCut`), and only the stage swaps — a crossfade of
// a card-sized area, never a full-screen animation (CLAUDE.md, "Movie Night").

/// Anime metadata from AniDB/Shoko arrives with markup in it — `<br>`,
/// `<i>`, entity escapes — which a `Text` prints literally (verified: a
/// synopsis read `"…cry!"<br><br>One day…`).
enum AnimeText {
    static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "<br\\s*/?>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum AnimePalette {
    static let coral = Color(hex: "#E8554E")
    static let lime = Color(hex: "#C8F04A")
    static let yellow = Color(hex: "#F2E14C")
}

/// Which anime screen wears the skin. **Late Night** (the adult anime
/// libraries, `MetaCategory.hentai`) is the same key visual after dark: a
/// night-violet ground, a hot-pink slash with a lime rule, 深夜アニメ over
/// LATE NIGHT with an 18+ sticker — so the two screens can never be mistaken
/// for each other at a glance, which is the point of telling them apart.
enum AnimeSkinVariant {
    case anime, lateNight

    var ground: Color { self == .anime ? AnimePalette.coral : Color(hex: "#1B0C26") }
    var halftone: Color { self == .anime ? Palette.posterInk.opacity(0.16) : Color(hex: "#FF3D8B").opacity(0.2) }
    var slash: Color { self == .anime ? AnimePalette.lime : Color(hex: "#FF3D8B") }
    var rule: Color { self == .anime ? Palette.posterInk : AnimePalette.lime }
    /// Type set straight on the ground.
    var ink: Color { self == .anime ? Palette.posterInk : .white }
    var kana: String { self == .anime ? "アニメ" : "深夜アニメ" }
    var word: String { self == .anime ? "ANIME" : "LATE NIGHT" }
    var crumb: String { self == .anime ? "ANIME" : "LATE NIGHT" }
    /// The title focus's grounds, picked per title.
    var focusGrounds: [Color] {
        self == .anime
            ? [Palette.posterBlush, Palette.posterTeal, AnimePalette.yellow, AnimePalette.lime]
            : [Color(hex: "#3A0F3E"), Color(hex: "#12203F"), Color(hex: "#3F0F1E"), Color(hex: "#24123F")]
    }
    var isAdult: Bool { self == .lateNight }
}

/// Sizes off the design: TV at 1920×1080, iPad at 1194×834, iPhone 402 wide.
enum AnimeSize {
    static func pick(tv: CGFloat, pad: CGFloat, phone: CGFloat) -> CGFloat {
        switch DeviceClass.current {
        case .tv: return tv
        case .phone: return phone
        default: return pad
        }
    }
}

/// Coral with a halftone, the lime slash with its ink rule, and the hatched
/// ink shelf from `shelfTop` down. One `Canvas`.
struct AnimeGround: View {
    var variant: AnimeSkinVariant = .anime
    /// Overrides the variant's ground (the title focus).
    var color: Color? = nil
    /// Where the shelf starts, as a fraction of the height.
    var shelfTop: CGFloat

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color ?? variant.ground))
            // Halftone.
            let step: CGFloat = AnimeSize.pick(tv: 22, pad: 16, phone: 12)
            let r: CGFloat = step * 0.1
            var dots = Path()
            var y = step / 2
            let shelfY = size.height * shelfTop
            while y < shelfY {
                var x = step / 2
                while x < size.width {
                    dots.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    x += step
                }
                y += step
            }
            ctx.fill(dots, with: .color(variant.halftone))
            // The lime slash and its rule, rising to the right just above the shelf.
            let slope = size.width * tan(6 * .pi / 180)
            let base = shelfY - size.height * 0.02
            let band = size.height * 0.1
            var lime = Path()
            lime.move(to: CGPoint(x: 0, y: base))
            lime.addLine(to: CGPoint(x: size.width, y: base - slope))
            lime.addLine(to: CGPoint(x: size.width, y: base - slope - band))
            lime.addLine(to: CGPoint(x: 0, y: base - band))
            ctx.fill(lime, with: .color(variant.slash))
            var rule = Path()
            rule.move(to: CGPoint(x: 0, y: base - band * 0.55))
            rule.addLine(to: CGPoint(x: size.width, y: base - slope - band * 0.55))
            ctx.stroke(rule, with: .color(variant.rule), lineWidth: max(4, band * 0.1))
            // The shelf, hatched.
            let shelf = CGRect(x: 0, y: shelfY, width: size.width, height: size.height - shelfY)
            ctx.fill(Path(shelf), with: .color(Color(hex: "#121317")))
            var hatch = Path()
            var hx = -shelf.height
            while hx < size.width + shelf.height {
                hatch.move(to: CGPoint(x: hx, y: size.height))
                hatch.addLine(to: CGPoint(x: hx + shelf.height, y: shelfY))
                hx += 17
            }
            ctx.clip(to: Path(shelf))
            ctx.stroke(hatch, with: .color(Color(hex: "#1B1C22")), lineWidth: 7)
        }
        .drawingGroup()
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Type with a die-cut border: the text drawn in `stroke` at sixteen offsets
/// under itself, flattened into one layer. For a few words at display size.
struct DieCutText: View {
    let text: String
    var font: Font
    var fill: Color
    var stroke: Color
    var width: CGFloat
    var shadow: CGFloat = 0

    var body: some View {
        ZStack {
            ForEach(0..<16, id: \.self) { i in
                let a = Double(i) / 16 * 2 * .pi
                Text(text).font(font).foregroundStyle(stroke)
                    .offset(x: cos(a) * width, y: sin(a) * width)
            }
            Text(text).font(font).foregroundStyle(fill)
        }
        .fixedSize()
        .drawingGroup()
        .shadow(color: Palette.posterInk, radius: 0, x: shadow, y: shadow)
    }
}

/// アニメ over ANIME and the count sticker, tilted — the screen's title.
struct AnimeLogoLockup: View {
    var variant: AnimeSkinVariant = .anime
    let count: Int
    var scale: CGFloat = 1

    private var kanaSize: CGFloat { variant == .anime ? 150 : 104 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            HStack(alignment: .top, spacing: 14 * scale) {
                DieCutText(text: variant.kana, font: .system(size: kanaSize * scale, weight: .black),
                           fill: Palette.posterInk, stroke: .white, width: 11 * scale, shadow: 10 * scale)
                if variant.isAdult {
                    Text("18+")
                        .font(Display.font(44 * scale))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12 * scale)
                        .background(Color(hex: "#FF3D8B"), in: Circle().inset(by: -10 * scale))
                        .rotationEffect(.degrees(12))
                        .padding(.top, 10 * scale)
                }
            }
            HStack(spacing: 16 * scale) {
                DieCutText(text: variant.word, font: Display.font(84 * scale),
                           fill: .white, stroke: Palette.posterInk, width: 7 * scale)
                PosterStickerTag(name: "\(count) SERIES", sub: variant.isAdult ? "AFTER DARK" : "ON THIS TV",
                                 nameColor: Palette.posterInk,
                                 paper: variant.slash, size: 34 * scale, tilt: .zero)
            }
            .padding(.leading, 26 * scale)
        }
        .rotationEffect(.degrees(-4))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(variant.word.capitalized), \(count) series\(variant.isAdult ? ", adults only" : "")")
    }
}

/// The library stage: the logo, the focused title's key art pinned up tilted
/// with its name sticker, its facts and a few lines of synopsis. No buttons —
/// the shelf below is what the remote works; Select on a poster opens it.
struct AnimeLibraryStage: View {
    var variant: AnimeSkinVariant = .anime
    let item: MediaItem?
    let count: Int

    private var s: CGFloat { AnimeSize.pick(tv: 1, pad: 0.62, phone: 0.5) }

    var body: some View {
        if DeviceClass.current == .phone { phoneBody } else { wideBody }
    }

    /// The phone stacks what the wide layout sets side by side: the logo,
    /// then the key art card under it — a 600pt card beside a logo is wider
    /// than the phone.
    private var phoneBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            AnimeLogoLockup(variant: variant, count: count, scale: 0.46)
            if let item {
                keyArtPhone(item)
                    .id(item.id)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: item?.id)
    }

    private func keyArtPhone(_ item: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: -8) {
            art(item)
                .frame(width: 230, height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white, lineWidth: 5))
                .compositingGroup()
                .shadow(color: Palette.posterInk, radius: 0, x: 6, y: 6)
                .rotationEffect(.degrees(-3))
            PosterStickerTag(name: item.title, sub: stickerLine(item), nameColor: Palette.posterInk,
                             paper: AnimePalette.yellow, size: 20, tilt: .degrees(2))
                .frame(maxWidth: 240, alignment: .leading)
        }
    }

    private var wideBody: some View {
        ZStack(alignment: .topLeading) {
            AnimeLogoLockup(variant: variant, count: count, scale: s)
            if let item {
                keyArt(item)
                    .padding(.leading, 700 * s)
                    .padding(.top, 10 * s)
                    .id(item.id)
                    .transition(.opacity)
                facts(item)
                    .frame(width: 600 * s, alignment: .leading)
                    .padding(.top, 330 * s)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: item?.id)
    }

    private func keyArt(_ item: MediaItem) -> some View {
        let w = 600 * s, h = 338 * s
        return VStack(alignment: .leading, spacing: -14 * s) {
            art(item)
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: 16 * s, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16 * s, style: .continuous)
                    .strokeBorder(.white, lineWidth: 10 * s))
                .compositingGroup()
                .shadow(color: Palette.posterInk, radius: 0, x: 14 * s, y: 14 * s)
                .rotationEffect(.degrees(3))
            PosterStickerTag(name: item.title, sub: stickerLine(item), nameColor: Palette.posterInk,
                             paper: AnimePalette.yellow, size: 52 * s, tilt: .degrees(-3))
                .frame(maxWidth: w, alignment: .leading)
                .offset(x: -20 * s)
        }
    }

    @ViewBuilder
    private func art(_ item: MediaItem) -> some View {
        let source = item.backdropImage ?? item.image
        if let source, source.hasPrefix("http"), let url = URL(string: source) {
            JellyfinAsyncImage(url: url, fallback: item.artwork.gradient)
        } else {
            item.artwork.gradient
        }
    }

    private func stickerLine(_ item: MediaItem) -> String? {
        let parts = [item.certification, item.year].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func facts(_ item: MediaItem) -> some View {
        // On its own white card: the lime slash and the halftone run behind
        // this column, and bare type over them was unreadable (verified).
        if let synopsis = item.synopsis.map(AnimeText.plain), !synopsis.isEmpty {
            Text(synopsis)
                .font(Typography.font(22 * s, .bold))
                .foregroundStyle(Palette.posterInk)
                .lineSpacing(3 * s)
                .lineLimit(3)
                .padding(.horizontal, 18 * s)
                .padding(.vertical, 12 * s)
                .background(.white, in: RoundedRectangle(cornerRadius: 12 * s, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12 * s, style: .continuous)
                    .strokeBorder(Palette.posterInk, lineWidth: 3 * s))
                .compositingGroup()
                .shadow(color: Palette.posterInk, radius: 0, x: 6 * s, y: 6 * s)
                .rotationEffect(.degrees(-1.5))
        }
    }
}

/// The title focus: the remote has rested on a title whose own character
/// cuts out cleanly, so the ground takes the art's colour, the title is set
/// huge with a die-cut border, and the character stands on the right.
struct AnimeTitleFocusStage: View {
    var variant: AnimeSkinVariant = .anime
    let item: MediaItem
    let cutout: UIImage
    let count: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    DieCutText(text: variant.kana, font: .system(size: 34, weight: .black),
                               fill: Palette.posterInk, stroke: .white, width: 4)
                    Text("\(variant.crumb) · \(count) SERIES")
                        .font(Mono.font(20, .bold)).tracking(3)
                        .foregroundStyle(variant.ink)
                }
                DieCutText(text: item.title.uppercased(), font: Display.font(titleSize),
                           fill: .white, stroke: Palette.posterInk, width: 12, shadow: 10)
                    .frame(maxWidth: 1000, alignment: .leading)
                HStack(spacing: 12) {
                    ForEach(chips, id: \.self) { chip in
                        Text(chip.uppercased())
                            .font(Display.font(28))
                            .foregroundStyle(Palette.posterInk)
                            .padding(.horizontal, 14).padding(.vertical, 4)
                            .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                if let synopsis = item.synopsis.map(AnimeText.plain), !synopsis.isEmpty {
                    // Carded, like the library stage's: the slash runs behind.
                    Text(synopsis)
                        .font(Typography.font(22, .bold))
                        .foregroundStyle(Palette.posterInk)
                        .lineLimit(2)
                        .frame(width: 780, alignment: .leading)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Palette.posterInk, lineWidth: 3))
                        .compositingGroup()
                        .shadow(color: Palette.posterInk, radius: 0, x: 6, y: 6)
                        .rotationEffect(.degrees(-1.5))
                }
            }
            DieCutSticker(image: cutout, height: 560, tilt: -3, shadow: 16)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 40)
                .offset(y: -40)
        }
    }

    /// A long title steps down rather than wrapping past the stage.
    private var titleSize: CGFloat {
        let n = item.title.count
        return n <= 12 ? 150 : (n <= 22 ? 110 : 80)
    }

    private var chips: [String] {
        // `meta` reads "Series · Comedy"; the genre is its tail.
        let genre = item.meta.components(separatedBy: " · ").dropFirst().first
        return [item.certification, item.year, genre].compactMap { $0 }.filter { !$0.isEmpty }
    }
}

/// The empty shelf: said plainly, with the one thing that usually fixes it.
struct AnimeEmptyShelf: View {
    var variant: AnimeSkinVariant = .anime
    let mascot: UIImage?
    let onScan: () async -> Bool
    let onBack: () -> Void

    @State private var scanning = false
    @State private var message: String?

    private var s: CGFloat { AnimeSize.pick(tv: 1, pad: 0.62, phone: 0.45) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 24 * s) {
                Text("からっぽ…")
                    .font(.system(size: 60 * s, weight: .black))
                    .foregroundStyle(variant.ink)
                DieCutText(text: "THE SHELF\nIS EMPTY", font: Display.font(150 * s),
                           fill: .white, stroke: Palette.posterInk, width: 14 * s, shadow: 10 * s)
                    .rotationEffect(.degrees(-3), anchor: .leading)
                Text(message ?? "The server has this library, but nothing in it yet. If a plugin manages the folder, it may still be building it — scanning again usually brings the shows in.")
                    .font(Typography.font(26 * s, .bold))
                    .foregroundStyle(variant.ink)
                    .frame(maxWidth: 760 * s, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16 * s) {
                    Button {
                        guard !scanning else { return }
                        scanning = true
                        Task {
                            let ok = await onScan()
                            message = ok
                                ? "Scanning now. Shows appear here as the server finds them — this can take a few minutes."
                                : "The server didn't take the scan. It needs an administrator account — try it from the Jellyfin dashboard."
                            scanning = false
                        }
                    } label: {
                        PosterArrowPill(title: scanning ? "Scanning…" : "Scan library",
                                        systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(StickerButtonStyle(cornerRadius: 42, lift: 8))
                    Button(action: onBack) { PosterOutlinePill(title: "Back to home", ink: variant == .anime) }
                        .buttonStyle(StickerButtonStyle(cornerRadius: 42, lift: 0))
                }
            }
            .padding(.top, 40 * s)
            if let mascot {
                DieCutSticker(image: mascot, height: 620 * s, tilt: -4, shadow: 16 * s)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(y: 60 * s)
            }
        }
    }
}

// MARK: - Shared by both screens

enum AnimeSkinLayout {
    /// Where the ink shelf starts: just under the stage on TV, lower down the
    /// iPad's page; the phone's stage scrolls, so its shelf sits mid-screen.
    static var shelfTop: CGFloat { AnimeSize.pick(tv: 0.6, pad: 0.56, phone: 0.52) }
    static var stageHeight: CGFloat { AnimeSize.pick(tv: 450, pad: 330, phone: 340) }

    /// The title focus's ground, picked by the title so it is the same colour
    /// every visit.
    static func focusGround(_ variant: AnimeSkinVariant, itemId: String?) -> Color? {
        guard let itemId else { return nil }
        let options = variant.focusGrounds
        let seed = itemId.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return options[seed % options.count]
    }
}

/// The stage above the shelf: the title focus when one is up, else the
/// library stage. Fixed height, top-aligned, so the shelf never moves.
struct AnimeSkinStage: View {
    let variant: AnimeSkinVariant
    let item: MediaItem?
    let count: Int
    let focusItem: MediaItem?
    let focusCutout: UIImage?
    /// Touch only: the stage scrolls with the shelf there, so the mascots
    /// ride on it rather than being pinned to the screen (`AnimeMascotLayer`
    /// is the TV's).
    var mascots: [UIImage] = []

    var body: some View {
        Group {
            if let focusItem, let focusCutout {
                AnimeTitleFocusStage(variant: variant, item: focusItem, cutout: focusCutout, count: count)
            } else {
                AnimeLibraryStage(variant: variant, item: item, count: count)
            }
        }
        .overlay(alignment: DeviceClass.current == .phone ? .topLeading : .bottomTrailing) {
            // Touch: the character stands right of the key art card, partly
            // off the edge. On the phone the stage is only as wide as its
            // content (a vertical ScrollView proposes no width), so
            // "trailing" meant the middle of the screen, right over the card
            // (verified) — there it is placed just past the card's edge.
            if DeviceClass.current != .tv, focusItem == nil, let first = mascots.first {
                let phone = DeviceClass.current == .phone
                DieCutSticker(image: first, height: AnimeSkinLayout.stageHeight * (phone ? 0.7 : 0.82), tilt: 4,
                              shadow: phone ? 6 : 9)
                    .offset(x: phone ? 226 : 90, y: phone ? 96 : 0)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: AnimeSkinLayout.stageHeight, alignment: .top)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: focusItem?.id)
    }
}

/// The characters dressing the screen — **never over anything the remote
/// or a finger can reach** (the first cut stood across the search field
/// and the last posters; verified). The first stands in the stage band on
/// the right, between the header and the shelf, stepping aside while a
/// title's own character has the stage; the second sits on the shelf's top
/// edge like the ZZZ crew on their car. Nothing here is focusable.
struct AnimeMascotLayer: View {
    let mascots: [UIImage]
    /// A title's own character has the stage: the mascots step aside.
    let leadAside: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let shelfY = h * AnimeSkinLayout.shelfTop
            let headerY = h * AnimeSize.pick(tv: 0.13, pad: 0.14, phone: 0.12)
            ZStack(alignment: .topLeading) {
                if !leadAside, let first = mascots.first {
                    DieCutSticker(image: first, height: shelfY - headerY,
                                  tilt: 3, shadow: AnimeSize.pick(tv: 14, pad: 10, phone: 7))
                        .frame(width: w * AnimeSize.pick(tv: 0.22, pad: 0.26, phone: 0.4), height: shelfY - headerY)
                        .clipped()
                        .position(x: w - w * AnimeSize.pick(tv: 0.11, pad: 0.13, phone: 0.2), y: (headerY + shelfY) / 2)
                        .transition(.opacity)
                }
                if !leadAside, mascots.count > 1 {
                    let hh = h * AnimeSize.pick(tv: 0.17, pad: 0.15, phone: 0.09)
                    DieCutSticker(image: mascots[1], height: hh, tilt: -4,
                                  shadow: AnimeSize.pick(tv: 10, pad: 7, phone: 5))
                        .position(x: w * AnimeSize.pick(tv: 0.66, pad: 0.62, phone: 0.72), y: shelfY - hh * 0.42)
                        .transition(.opacity)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: 0.3), value: leadAside)
    }
}
