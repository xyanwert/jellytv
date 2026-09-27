import SwiftUI
import JellyTVKit

// Poster Mode's player chrome (design canvas "Player Chrome — Poster Mode"):
// the same Grandma layout — opinions over the transport over the clock, then
// PREV · SCENES · NEXT — every control a sticker (thick white rim, a hard ink
// offset shadow), over the picture tinted teal with the episode number printed
// huge in scanlines behind it and the teal/coral stripes under the foot.
//
// Behaviour is untouched: every component keeps its fields, actions and
// focus; only the drawing branches on `theme.isPoster`.
//
// **Area, not effect, is what costs on the TV** (CLAUDE.md, "Movie Night").
// The dressing here is static — a colour blend, one masked `Canvas` for the
// scanlines, two rectangles of stripe — and only the control under the remote
// animates, the same area `FocusScaleStyle` always animated.

/// Sizes for the Poster chrome, straight off the design's three artboards:
/// TV at 1920×1080, iPad at 1194×834, iPhone landscape at 874×402.
enum PosterPlayerSize {
    private static var device: DeviceClass { DeviceClass.current }

    static var opinion: CGFloat { pick(tv: 104, pad: 68, phone: 54) }
    static var jump: CGFloat { pick(tv: 140, pad: 92, phone: 64) }
    static var play: CGFloat { pick(tv: 212, pad: 138, phone: 96) }
    static var transportGap: CGFloat { pick(tv: 48, pad: 30, phone: 20) }
    static var rim: CGFloat { pick(tv: 6, pad: 4, phone: 3) }
    static var playRim: CGFloat { pick(tv: 9, pad: 6, phone: 4.5) }
    /// The hard ink shadow a sticker casts at rest.
    static var lift: CGFloat { pick(tv: 6, pad: 4, phone: 3) }
    static var jumpGlyph: CGFloat { pick(tv: 40, pad: 27, phone: 20) }
    static var jumpNumber: CGFloat { pick(tv: 38, pad: 25, phone: 18) }
    static var playGlyph: CGFloat { pick(tv: 84, pad: 54, phone: 38) }

    static var footHeight: CGFloat { pick(tv: 118, pad: 76, phone: 50) }
    static var footNarrow: CGFloat { pick(tv: 250, pad: 160, phone: 108) }
    static var scenesHeight: CGFloat { pick(tv: 132, pad: 86, phone: 54) }
    static var scenesWidth: CGFloat { pick(tv: 400, pad: 250, phone: 170) }
    static var footRadius: CGFloat { pick(tv: 22, pad: 16, phone: 12) }
    static var footLabel: CGFloat { pick(tv: 40, pad: 26, phone: 18) }
    static var scenesLabel: CGFloat { pick(tv: 52, pad: 34, phone: 23) }
    static var footGap: CGFloat { pick(tv: 28, pad: 18, phone: 12) }

    static var clock: CGFloat { pick(tv: 84, pad: 54, phone: 34) }
    static var clockTotal: CGFloat { pick(tv: 44, pad: 28, phone: 18) }
    static var chip: CGFloat { pick(tv: 22, pad: 14, phone: 11) }

    static var back: CGFloat { pick(tv: 96, pad: 60, phone: 44) }
    static var control: CGFloat { pick(tv: 72, pad: 48, phone: 44) }
    static var tag: CGFloat { pick(tv: 26, pad: 17, phone: 13) }

    private static func pick(tv: CGFloat, pad: CGFloat, phone: CGFloat) -> CGFloat {
        switch device {
        case .tv: return tv
        case .phone: return phone
        default: return pad
        }
    }
}

/// A sticker under the remote or the finger. At rest it casts a hard ink
/// shadow; focused (tvOS) it lifts — bigger, a longer shadow, a faint teal
/// halo — instead of `FocusScaleStyle`'s LED ring, which reads as a glow
/// around a sticker rather than the sticker coming off the page. A press
/// pushes it flat.
struct StickerButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat
    var lift: CGFloat = PosterPlayerSize.lift
    var focusScale: CGFloat = 1.1

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, cornerRadius: cornerRadius,
                lift: lift, focusScale: focusScale)
    }

    private struct Content: View {
        #if os(tvOS)
        @Environment(\.isFocused) private var focused: Bool
        #else
        private let focused = false
        #endif
        let configuration: StickerButtonStyle.Configuration
        let cornerRadius: CGFloat
        let lift: CGFloat
        let focusScale: CGFloat

        var body: some View {
            let pressed = configuration.isPressed
            let offset = pressed ? lift * 0.3 : (focused ? lift * 2 : lift)
            configuration.label
                .background {
                    if focused {
                        RoundedRectangle(cornerRadius: cornerRadius + 16, style: .continuous)
                            .fill(Palette.posterTeal.opacity(0.3))
                            .padding(-16)
                            .transition(.opacity)
                    }
                }
                .compositingGroup()
                .shadow(color: Palette.posterInk.opacity(0.9), radius: 0, x: offset, y: offset)
                .scaleEffect((focused ? focusScale : 1) * (pressed ? 0.95 : 1))
                .animation(.spring(response: 0.26, dampingFraction: 0.6), value: focused)
                .animation(.easeOut(duration: 0.12), value: pressed)
        }
    }
}

/// The chrome's ground in Poster Mode: the picture tinted teal and dimmed,
/// darker at the foot, the episode number printed huge in scanlines on the
/// right, the teal/coral stripes running under the foot. Static; never
/// hit-testable.
struct PosterPlayerBackdrop: View {
    let item: PlayableItem?

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                Palette.posterTeal.opacity(0.55).blendMode(.color)
                Palette.posterInk.opacity(0.55)
                LinearGradient(colors: [.clear, Palette.posterInk.opacity(0.9)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: h * 0.4)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                if let number = item?.posterNumber {
                    PosterScanlineTitle(text: number, size: h * 0.9)
                        .opacity(0.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .offset(x: h * 0.03, y: -h * 0.1)
                }
                stripes(width: geo.size.width, height: h)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func stripes(width: CGFloat, height: CGFloat) -> some View {
        let unit = height / 1080
        return VStack(spacing: 18 * unit) {
            Rectangle().fill(Palette.posterTeal).frame(height: max(8, 30 * unit))
            Rectangle().fill(Color(hex: "#F0525F")).frame(height: max(4, 12 * unit))
        }
        .frame(width: width * 1.4)
        .rotationEffect(.degrees(-4))
        .frame(width: width, height: height, alignment: .bottom)
        .offset(y: -height * 0.15)
    }
}

extension PlayableItem {
    /// "03" off "S28 · E3 — …": the number the backdrop prints and a foot tile
    /// names. Nil for a movie or anything without an episode number.
    var posterNumber: String? {
        guard let n = episodeNumberValue else { return nil }
        return String(format: "%02d", n)
    }

    /// "E04" for a foot tile.
    var posterEpisodeTag: String? {
        episodeNumberValue.map { "E\(String(format: "%02d", $0))" }
    }

    /// The episode's own title and its "S28 · E3" line, split off
    /// `subtitle` ("S28 · E3 — \"Sora Not Sorry\"") for the identity sticker.
    var posterEpisodeParts: (code: String, title: String)? {
        guard let subtitle, !hidesTitle else { return nil }
        let parts = subtitle.components(separatedBy: " — ")
        guard parts.count >= 2 else { return (subtitle, "") }
        let title = parts.dropFirst().joined(separator: " — ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“” "))
        return (parts[0], title)
    }

    private var episodeNumberValue: Int? {
        guard let subtitle, let range = subtitle.range(of: #"E(\d+)"#, options: .regularExpression) else { return nil }
        return Int(subtitle[range].dropFirst())
    }
}

/// A button style chosen at runtime — Poster's sticker or Classic's focus
/// scale on the same control.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}
