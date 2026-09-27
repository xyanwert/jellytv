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
// remote has rested on a title that has a clean figure of its own — its
// colour takes the ground, its logo the column and its character the stage),
// and the empty shelf.
//
// Static by construction: the ground's texture is one flattened `Canvas`, the
// stickers are baked images (`StickerCut`), and what moves is card-sized — the
// figure arriving, the disc behind it, a crossfade of the stage. The ground's
// *colour* changes per title, and that is one flat quad and one band under
// the static texture, never a repaint of the halftone (CLAUDE.md, "Movie
// Night": the area animated is what costs).

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

    /// The word or two printed huge in scanlines behind a figure: the title
    /// with its brackets and punctuation stripped, cut at a word boundary
    /// around twelve letters — "DAN DA DAN", "FRIEREN", "WORLD'S END" — since
    /// the ghost is texture, not a label, and half a subtitle is noise.
    static func ghost(_ title: String, limit: Int = 12) -> String {
        let cleaned = title
            .replacingOccurrences(of: "[^A-Za-z0-9' ]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        var out: [String] = []
        for word in cleaned.split(separator: " ").map(String.init) {
            let next = (out + [word]).joined(separator: " ")
            if !out.isEmpty, next.count > limit { break }
            out.append(word)
        }
        return out.isEmpty ? cleaned : out.joined(separator: " ")
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
    var isAdult: Bool { self == .lateNight }
}

/// The colours a title focus dresses the screen in, **keyed to the figure**:
/// the dominant hue of the character's own art gives the slash and the disc
/// behind them, and its complement the ground — the pairing every key visual
/// is built on, and the reason a purple-haired girl stands on a lime field
/// rather than on the same coral as everyone else. A figure with no hue to
/// speak of (a greyscale cut) keeps the variant's own ground.
struct AnimeKeyPalette: Equatable {
    var ground: Color
    var slash: Color
    var rule: Color
    /// The flat disc behind the figure's head and shoulders.
    var disc: Color
    /// Type set straight on the ground.
    var ink: Color
    /// The scanline ghost title's white, over the ground.
    var ghostOpacity: Double

    static func standard(_ variant: AnimeSkinVariant) -> AnimeKeyPalette {
        AnimeKeyPalette(ground: variant.ground, slash: variant.slash, rule: variant.rule,
                        disc: variant == .anime ? Palette.posterBlush : Color(hex: "#3A1F52"),
                        ink: variant.ink, ghostOpacity: variant == .anime ? 0.45 : 0.3)
    }

    static func keyed(to hue: Double?, variant: AnimeSkinVariant) -> AnimeKeyPalette {
        guard let hue else { return standard(variant) }
        let across = (hue + 180).truncatingRemainder(dividingBy: 360)
        switch variant {
        case .anime:
            return AnimeKeyPalette(ground: Color(OKLCH(l: 0.70, c: 0.145, h: across)),
                                   slash: Color(OKLCH(l: 0.86, c: 0.16, h: hue)),
                                   rule: Palette.posterInk,
                                   disc: Color(OKLCH(l: 0.88, c: 0.10, h: hue)),
                                   ink: Palette.posterInk, ghostOpacity: 0.45)
        case .lateNight:
            return AnimeKeyPalette(ground: Color(OKLCH(l: 0.26, c: 0.10, h: across)),
                                   slash: Color(OKLCH(l: 0.66, c: 0.21, h: hue)),
                                   rule: AnimePalette.lime,
                                   disc: Color(OKLCH(l: 0.42, c: 0.14, h: hue)),
                                   ink: .white, ghostOpacity: 0.3)
        }
    }
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

/// The ground: a flat colour, the halftone and hatched ink shelf as one static
/// `Canvas` over it, and the slash as a shape with its rule. Split this way so
/// a palette change — a title focus keying the screen to its figure — is a
/// colour crossfade of one quad and one band, not a redraw of four thousand
/// dots on every frame of the fade.
struct AnimeGround: View {
    var variant: AnimeSkinVariant = .anime
    /// The title focus's palette; nil is the variant's own.
    var palette: AnimeKeyPalette? = nil
    /// Where the shelf starts, as a fraction of the height.
    var shelfTop: CGFloat

    private var colors: AnimeKeyPalette { palette ?? .standard(variant) }

    var body: some View {
        ZStack {
            Rectangle().fill(colors.ground)
            AnimeGroundTexture(variant: variant, shelfTop: shelfTop)
            AnimeSlash(shelfTop: shelfTop)
                .fill(colors.slash)
            AnimeSlashRule(shelfTop: shelfTop)
                .stroke(colors.rule, style: StrokeStyle(lineWidth: AnimeSize.pick(tv: 10, pad: 7, phone: 5)))
        }
        .animation(.easeInOut(duration: 0.4), value: colors)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The lime slash, rising 6° to the right just above the shelf.
private struct AnimeSlash: Shape {
    let shelfTop: CGFloat
    func path(in rect: CGRect) -> Path {
        let size = rect.size
        let slope = size.width * tan(6 * .pi / 180)
        let base = size.height * shelfTop - size.height * 0.02
        let band = size.height * 0.1
        var p = Path()
        p.move(to: CGPoint(x: 0, y: base))
        p.addLine(to: CGPoint(x: size.width, y: base - slope))
        p.addLine(to: CGPoint(x: size.width, y: base - slope - band))
        p.addLine(to: CGPoint(x: 0, y: base - band))
        p.closeSubpath()
        return p
    }
}

private struct AnimeSlashRule: Shape {
    let shelfTop: CGFloat
    func path(in rect: CGRect) -> Path {
        let size = rect.size
        let slope = size.width * tan(6 * .pi / 180)
        let base = size.height * shelfTop - size.height * 0.02
        let band = size.height * 0.1
        var p = Path()
        p.move(to: CGPoint(x: 0, y: base - band * 0.55))
        p.addLine(to: CGPoint(x: size.width, y: base - slope - band * 0.55))
        return p
    }
}

/// The halftone above the shelf and the hatched ink shelf below it. One
/// flattened `Canvas`, drawn once.
private struct AnimeGroundTexture: View {
    let variant: AnimeSkinVariant
    let shelfTop: CGFloat

    var body: some View {
        Canvas { ctx, size in
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

// MARK: - Title focus

/// The title the remote has rested on, with everything its key visual needs:
/// its character struck as a sticker, its logo as one too (when the server
/// has a logo — every anime here does), and the palette keyed to the figure.
struct AnimeLead: Equatable {
    let item: MediaItem
    let figure: UIImage
    let logo: UIImage?
    let palette: AnimeKeyPalette

    static func == (a: AnimeLead, b: AnimeLead) -> Bool {
        a.item.id == b.item.id && a.palette == b.palette
    }
}

/// The title focus's column: the crumb, the show's own logo (or its title
/// die-cut when there is none), its facts and two lines of synopsis. The
/// figure, the disc and the ghost title are the `AnimeFigureLayer`'s — they
/// stand on the shelf line, which the stage's fixed frame doesn't reach.
///
/// Every slot is a fixed size, so one title's three-line logo and the next's
/// one-line wordmark leave the chips and card exactly where they were.
struct AnimeTitleFocusStage: View {
    var variant: AnimeSkinVariant = .anime
    let lead: AnimeLead
    let count: Int
    /// Size, off the TV's 1 — the iPad and the phone take the same column.
    var s: CGFloat = 1

    private var item: MediaItem { lead.item }

    var body: some View {
        VStack(alignment: .leading, spacing: 18 * s) {
            HStack(spacing: 14 * s) {
                DieCutText(text: variant.kana, font: .system(size: 34 * s, weight: .black),
                           fill: Palette.posterInk, stroke: .white, width: 4 * s)
                Text("\(variant.crumb) · \(count) SERIES")
                    .font(Mono.font(20 * s, .bold)).tracking(3 * s)
                    .foregroundStyle(lead.palette.ink)
            }
            title
                .frame(width: 860 * s, height: 210 * s, alignment: .leading)
            HStack(spacing: 12 * s) {
                ForEach(chips, id: \.self) { chip in
                    Text(chip.uppercased())
                        .font(Display.font(28 * s))
                        .foregroundStyle(Palette.posterInk)
                        .padding(.horizontal, 14 * s).padding(.vertical, 4 * s)
                        .background(.white, in: RoundedRectangle(cornerRadius: 8 * s, style: .continuous))
                }
            }
            .frame(height: 44 * s, alignment: .leading)
            if let synopsis = item.synopsis.map(AnimeText.plain), !synopsis.isEmpty {
                // Carded, like the library stage's: the slash runs behind.
                Text(synopsis)
                    .font(Typography.font(max(13, 22 * s), .bold))
                    .foregroundStyle(Palette.posterInk)
                    .lineLimit(2)
                    .frame(width: 780 * s, alignment: .leading)
                    .padding(.horizontal, 18 * s).padding(.vertical, 12 * s)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12 * s, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12 * s, style: .continuous)
                        .strokeBorder(Palette.posterInk, lineWidth: max(2, 3 * s)))
                    .compositingGroup()
                    .shadow(color: Palette.posterInk, radius: 0, x: 6 * s, y: 6 * s)
                    .rotationEffect(.degrees(-1.5))
            }
        }
    }

    /// The logo is the title where there is one (CLAUDE.md: where an item has
    /// logo artwork, that artwork *is* the title), struck with an ink outline
    /// and a white keyline so a white wordmark still stands off the ground.
    @ViewBuilder private var title: some View {
        if let logo = lead.logo {
            Image(uiImage: logo)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(maxWidth: 760 * s, maxHeight: 210 * s, alignment: .leading)
                .shadow(color: Palette.posterInk.opacity(0.9), radius: 0, x: 8 * s, y: 8 * s)
                .rotationEffect(.degrees(-2), anchor: .leading)
        } else {
            DieCutText(text: item.title.uppercased(), font: Display.font(titleSize * s),
                       fill: .white, stroke: Palette.posterInk, width: 12 * s, shadow: 10 * s)
                .frame(maxWidth: 860 * s, alignment: .leading)
                .clipped()
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
    /// The band the figures stand in starts under the header row.
    static var bandTop: CGFloat { AnimeSize.pick(tv: 0.13, pad: 0.14, phone: 0.12) }
}

/// The stage above the shelf: the title focus's column when one is up, else
/// the library stage. Fixed height, top-aligned, so the shelf never moves.
struct AnimeSkinStage: View {
    let variant: AnimeSkinVariant
    let item: MediaItem?
    let count: Int
    let lead: AnimeLead?
    /// Touch only: the stage scrolls with the shelf there, so the character
    /// rides on it rather than being pinned to the screen (`AnimeFigureLayer`
    /// is the TV's). The featured title's own figure when it has one, else a
    /// figure from the shelf.
    var figure: UIImage? = nil

    var body: some View {
        Group {
            if let lead {
                Group {
                    if DeviceClass.current == .tv {
                        AnimeTitleFocusStage(variant: variant, lead: lead, count: count)
                    } else {
                        // Touch opens on the key visual too: the featured
                        // title's column, its character staged at the stage's
                        // trailing end (behind the column on the phone, where
                        // it stands partly off the edge).
                        let phone = DeviceClass.current == .phone
                        ZStack(alignment: .topLeading) {
                            AnimeStagedFigure(lead: lead, variant: variant,
                                              height: AnimeSkinLayout.stageHeight * (phone ? 0.78 : 0.96))
                                .frame(maxWidth: .infinity, maxHeight: .infinity,
                                       alignment: phone ? .bottomTrailing : .bottomTrailing)
                                .offset(x: phone ? 60 : 0, y: phone ? 10 : 0)
                                .opacity(phone ? 0.95 : 1)
                            AnimeTitleFocusStage(variant: variant, lead: lead, count: count,
                                                 s: AnimeSize.pick(tv: 1, pad: 0.62, phone: 0.42))
                        }
                        .frame(width: phone ? 370 : nil, height: AnimeSkinLayout.stageHeight)
                        // Cut at the stage's foot, so the character stands
                        // behind the shelf as on the TV and the burst never
                        // reaches the posters; free sideways, off the edge.
                        .mask(alignment: .top) { Rectangle().padding(.horizontal, -600) }
                    }
                }
                // One title to the next is a plain crossfade: without its
                // own identity the stage re-laid out in place, and the
                // logo visibly shrank and grew between two sizes.
                .id(lead.item.id)
                .transition(.opacity)
            } else {
                AnimeLibraryStage(variant: variant, item: item, count: count)
            }
        }
        .overlay(alignment: DeviceClass.current == .phone ? .topLeading : .bottomLeading) {
            // Touch: the character stands right of the key art card, partly
            // off the edge — anchored by its *left* edge just past the card,
            // never centred off the trailing edge: a wide duo placed that way
            // ran back over the card's name tag (verified on the iPad). On
            // the phone the stage is only as wide as its content (a vertical
            // ScrollView proposes no width), so it is placed the same way.
            if DeviceClass.current != .tv, lead == nil, let figure {
                let phone = DeviceClass.current == .phone
                let s = AnimeSize.pick(tv: 1, pad: 0.62, phone: 0.5)
                AnimeSceneFigure(image: figure, height: AnimeSkinLayout.stageHeight * (phone ? 0.7 : 0.82))
                    .offset(x: phone ? 226 : 1300 * s + 12, y: phone ? 96 : 0)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: AnimeSkinLayout.stageHeight, alignment: .top)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: lead?.item.id)
    }
}

/// The characters on the TV screen — **never over anything the remote can
/// reach** (the first cut stood across the search field and the last posters;
/// verified). Nothing here is focusable, nothing here is clipped: a die-cut
/// sticker cut off by an invisible rectangle reads as broken, so a figure is
/// sized to the band and allowed off the screen's edge instead.
///
/// With no title focus, one figure from the shelf stands at the right of the
/// stage band. With one, that figure gives way to the focused title's key
/// visual (`AnimeKeyVisual`): its character on the shelf line under a disc of
/// its own colour, its title in scanlines behind.
struct AnimeFigureLayer: View {
    var variant: AnimeSkinVariant = .anime
    let lead: AnimeLead?
    let mascots: [UIImage]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let shelfY = h * AnimeSkinLayout.shelfTop
            let bandTop = h * AnimeSkinLayout.bandTop
            ZStack(alignment: .topLeading) {
                if let lead {
                    AnimeKeyVisual(variant: variant, lead: lead, size: geo.size, shelfY: shelfY, bandTop: bandTop)
                        .id(lead.item.id)
                        .transition(.opacity)
                } else if let first = mascots.first {
                    // Standing behind the shelf's lip like the title focus's
                    // figure, so the art's own crop line is never seen.
                    // The same staging as a title focus, quieter: the burst
                    // and the disc in the variant's own colours.
                    let mh = (shelfY - bandTop) * 1.02
                    let palette = AnimeKeyPalette.standard(variant)
                    let center = CGPoint(x: w * 0.915, y: shelfY + mh * 0.06 - mh * 0.62)
                    ZStack {
                        AnimeSpeedLines(color: palette.slash.opacity(0.6), seed: 7)
                            .frame(width: mh * 1.3, height: mh * 1.3) // never reaches the key-art card
                            .position(center)
                        AnimeHalftoneDisc(color: palette.disc, diameter: mh * 0.72)
                            .position(center)
                        AnimeSceneFigure(image: first, height: mh)
                            .position(x: w * 0.915, y: shelfY + mh * 0.06 - mh / 2)
                    }
                    .frame(width: w, height: h)
                    .mask(alignment: .top) {
                        VStack(spacing: 0) {
                            LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom)
                                .frame(height: bandTop * 0.8)
                            Rectangle()
                        }
                        .frame(width: w + 800, height: shelfY - bandTop * 0.5)
                        .offset(y: bandTop * 0.5)
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: w, height: h, alignment: .topLeading)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: 0.3), value: lead?.item.id)
    }
}

/// The key visual proper: a disc of the title's colour, the title printed in
/// scanlines running out from behind the figure, and the character standing
/// on the shelf line; one title to the next is a crossfade (the layer's
/// `.id` + `.transition(.opacity)`), nothing scales or slides. Positioned in the layer's
/// own coordinates so the three parts line up with each other and with the
/// shelf, whatever the figure's proportions.
private struct AnimeKeyVisual: View {
    let variant: AnimeSkinVariant
    let lead: AnimeLead
    let size: CGSize
    let shelfY: CGFloat
    let bandTop: CGFloat

    var body: some View {
        // Sized to the band, and capped in width: a wide duo or trio must not
        // reach back over the column, so it stands shorter instead. It runs
        // on past the shelf line and the shelf hides the rest — the figure
        // stands *behind the counter*, so the art's own crop (most cuts end
        // at the waist or the knee) is never an edge anyone sees.
        let ratio = lead.figure.size.width / max(1, lead.figure.size.height)
        let height = min(shelfY - bandTop + 20, 600, size.width * 0.38 / max(ratio, 0.01))
        let width = height * ratio
        let bottom = shelfY + height * 0.07, top = bottom - height
        let cx = size.width * 0.83
        let disc = height * 0.86
        let discCenter = CGPoint(x: cx + height * 0.06, y: top + height * 0.38)
        ZStack {
            PosterScanlineTitle(text: AnimeText.ghost(lead.item.title), size: height * 0.48,
                                ink: .white.opacity(lead.palette.ghostOpacity), blend: .overlay)
                .frame(width: size.width * 0.47, alignment: .leading)
                .clipped()
                // Faded at both ends: in from under the column's edge, and
                // out before the screen's, so a letter can't peek out past
                // the figure as a stray glyph.
                .mask {
                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.14),
                                           .init(color: .white, location: 0.78), .init(color: .clear, location: 0.97)],
                                   startPoint: .leading, endPoint: .trailing)
                }
                .position(x: size.width * 0.53 + size.width * 0.235, y: top + height * 0.30)
            // The burst the character lands in.
            AnimeSpeedLines(color: lead.palette.slash.opacity(0.75), seed: lead.item.id.count)
                .frame(width: disc * 2.3, height: disc * 2.3)
                .position(discCenter)
            AnimeHalftoneDisc(color: lead.palette.disc, diameter: disc)
                .position(discCenter)
            AnimeSceneFigure(image: lead.figure, height: height)
                .position(x: cx, y: bottom - height / 2)
            // Lettered into the panel over the shoulder.
            DieCutText(text: AnimeSFX.word(for: lead.item.id, variant: variant),
                       font: .system(size: height * 0.17, weight: .black),
                       fill: lead.palette.slash, stroke: Palette.posterInk, width: height * 0.012,
                       shadow: height * 0.012)
                .rotationEffect(.degrees(-12))
                .position(x: cx - width / 2 - height * 0.02, y: top + height * 0.16)
        }
        .frame(width: size.width, height: size.height)
        // The shelf is in front: nothing of the visual crosses onto the row
        // the remote walks, and the burst stays out of the header. Wider than
        // the layer, so the burst runs off the screen's edge rather than
        // stopping at an invisible one.
        .mask(alignment: .top) {
            // Feathered at the top: a burst stopped by a ruled line reads as
            // a clipping bug.
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom)
                    .frame(height: bandTop * 0.8)
                Rectangle()
            }
            .frame(width: size.width + 800, height: shelfY - bandTop * 0.5)
            .offset(y: bandTop * 0.5)
        }
    }
}
