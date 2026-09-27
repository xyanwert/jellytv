import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import JellyTVKit

#if os(iOS)
/// Poster Mode's iPhone show page, top block (design canvas, "iPhone · Show"):
/// grid paper, the title set enormous and faint behind everything, the key
/// art's subject cut out and standing on the left with the lead's name
/// sticker slapped at its feet, the show's poster held up tilted on the
/// right in a white frame, and the teal/coral stripes running out along the
/// foot where the page turns to ink.
///
/// Without a cut-out (the simulator; a Vision miss) the key art itself is
/// printed into the paper (`.multiply`) and fades out before the poster, so
/// the block is still a key visual rather than an empty sheet.
struct PhonePosterShowHero: View {
    let title: String
    let keyArt: String?
    let posterArt: String?
    let artwork: Artwork
    /// The lead, for the name sticker — nil until the detail lands.
    let lead: CastMember?
    /// "VA:" on the sticker's second line — the credit is a voice.
    let isAnimated: Bool
    let onBack: () -> Void

    @State private var cutout: UIImage?

    static let height: CGFloat = 340
    /// Clear of the status bar / Dynamic Island — the block runs under it.
    private static let topInset: CGFloat = 58

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                Palette.posterPaper
                PosterPaper()

                ghostTitle(width: width)

                figure(width: width)

                poster
                    // A new season's poster is slapped on over the last.
                    .id(posterArt)
                    .transition(.posterSlap)
                    .frame(width: width, height: Self.height, alignment: .topTrailing)
                    .padding(.top, Self.topInset + 4)
                    .offset(x: -18)

                if let lead {
                    nameSticker(lead)
                        .frame(width: width * 0.62, height: Self.height, alignment: .bottomLeading)
                        .padding(.leading, 16)
                        .offset(y: -40)
                        .transition(.posterSlap)
                }

                PosterAccentStripes(angle: .degrees(-7), length: width * 1.4, scale: 0.62)
                    .frame(width: width, height: Self.height, alignment: .bottom)
                    .offset(x: -width * 0.1, y: 4)

                backButton
                    .padding(.top, Self.topInset)
                    .padding(.leading, 16)
            }
            .frame(width: width, height: Self.height)
            .clipped()
            .animation(.spring(response: 0.42, dampingFraction: 0.6), value: lead?.id)
            .animation(.spring(response: 0.42, dampingFraction: 0.6), value: posterArt)
        }
        .frame(height: Self.height)
        .task(id: keyArt) {
            guard PortraitCutoutCache.isSupported, let keyArt, keyArt.hasPrefix("http") else { return }
            let image = await PortraitCutoutCache.shared.cutout(for: keyArt)
            withAnimation(.easeOut(duration: 0.3)) { cutout = image }
        }
    }

    // MARK: Layers

    /// Two lines of the title in grey on the paper, cropped by the block's
    /// own edges like the poster crops its type.
    private func ghostTitle(width: CGFloat) -> some View {
        let words = title.uppercased().split(separator: " ").map(String.init)
        let lines: [String] = words.count > 1
            ? [words.prefix((words.count + 1) / 2).joined(separator: " "),
               words.dropFirst((words.count + 1) / 2).joined(separator: " ")]
            : [title.uppercased()]
        return VStack(alignment: .leading, spacing: -34) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(Display.font(128))
                    .foregroundStyle(Palette.posterInk.opacity(0.09))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.leading, 6)
        .padding(.top, 30)
        .frame(width: width, height: Self.height, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The cut-out subject at the art's own framing, or the art printed into
    /// the paper while there is none.
    @ViewBuilder
    private func figure(width: CGFloat) -> some View {
        let box = CGSize(width: width * 0.78, height: Self.height)
        if let cutout {
            Image(uiImage: cutout)
                .resizable()
                .scaledToFill()
                .frame(width: box.width * 1.25, height: box.height * 1.1)
                .frame(width: box.width, height: box.height, alignment: .bottomLeading)
                .clipped()
                .shadow(color: Palette.posterInk.opacity(0.35), radius: 14, x: 8, y: 6)
                .accessibilityHidden(true)
        } else if let keyArt, let url = URL(string: keyArt), keyArt.hasPrefix("http") {
            JellyfinAsyncImage(url: url, fallback: artwork.gradient)
                .frame(width: box.width, height: box.height)
                .clipped()
                .grayscale(0.2)
                .opacity(0.9)
                .blendMode(.multiply)
                .mask {
                    LinearGradient(stops: [.init(color: .white, location: 0.25),
                                           .init(color: .clear, location: 0.85)],
                                   startPoint: .leading, endPoint: .trailing)
                }
                .mask {
                    LinearGradient(stops: [.init(color: .clear, location: 0.1),
                                           .init(color: .white, location: 0.4)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .accessibilityHidden(true)
        }
    }

    private var poster: some View {
        Group {
            if let posterArt, posterArt.hasPrefix("http"), let url = URL(string: posterArt) {
                JellyfinAsyncImage(url: url, fallback: artwork.gradient)
            } else if let posterArt {
                Image(posterArt).resizable().scaledToFill()
            } else {
                artwork.gradient
            }
        }
        .frame(width: 136, height: 204)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Palette.posterInk, lineWidth: 2))
        .padding(5)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Palette.posterInk, lineWidth: 3))
        .rotationEffect(.degrees(5))
        .shadow(color: Palette.posterInk.opacity(0.3), radius: 16, x: -4, y: 10)
        .accessibilityHidden(true)
    }

    /// Character on the yellow, the actor on the ink bar — the credit a key
    /// visual prints at its hero's feet.
    private func nameSticker(_ member: CastMember) -> some View {
        // Jellyfin joins several parts with "|" or "/" ("Liane Cartman|Sheila
        // Broflovski|…") — the sticker names the first.
        let role = member.role?.split(whereSeparator: { $0 == "|" || $0 == "/" }).first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let name = role.isEmpty ? member.name : role
        let sub = role.isEmpty ? nil : (isAnimated ? "VA: \(member.name)" : member.name)
        return PosterStickerTag(name: name, sub: sub, paper: Color(hex: "#F2E14C"), size: 22)
            .accessibilityLabel(role.isEmpty ? member.name : "\(role), \(member.name)")
    }

    private var backButton: some View {
        Button(action: onBack) {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Palette.posterInk, in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }
}

/// "SEASON [1]" — the sticker that names the season on screen and opens the
/// wall of every season.
struct PhonePosterSeasonSticker: View {
    let number: Int
    let isSpecials: Bool
    let canPick: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(isSpecials ? "SPECIALS" : "SEASON")
                .font(Display.font(15)).tracking(0.6)
                .foregroundStyle(Palette.posterInk)
            if !isSpecials {
                Text("\(number)")
                    .font(Display.font(15))
                    .foregroundStyle(.white)
                    .frame(minWidth: 20)
                    .padding(.horizontal, 3)
                    .background(Palette.posterInk, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            if canPick {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Palette.posterInk)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// The resume bar: the label in the display face on white, a teal rim, and
/// the ink disc with the arrow at its end.
struct PhonePosterResumeBar: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title.uppercased())
                .font(Display.font(21))
                .foregroundStyle(Palette.posterInk)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            Image(systemName: "arrow.right")
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Palette.posterInk, in: Circle())
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .frame(height: 58)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: Capsule())
        .padding(3)
        .background(Palette.posterTeal, in: Capsule())
        .shadow(color: Palette.posterTeal.opacity(0.35), radius: 16, y: 6)
    }
}

/// Random beside the resume bar — the glyph alone, in the bar's own clothes
/// (white, teal rim), a spinner while the queue is being drawn so a second
/// press has something to see.
struct PhonePosterShuffleDisc: View {
    let busy: Bool

    var body: some View {
        ZStack {
            if busy {
                ProgressView().tint(Palette.posterInk)
            } else {
                Image(systemName: "shuffle")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(Palette.posterInk)
            }
        }
        .frame(width: 58, height: 58)
        .background(Color.white, in: Circle())
        .padding(3)
        .background(Palette.posterTeal, in: Circle())
        .shadow(color: Palette.posterTeal.opacity(0.35), radius: 16, y: 6)
    }
}

/// One episode on the ink: a still, the number big in the display face
/// (coral while unwatched, grey once seen), the title in capitals and the
/// runtime. The one to watch next is filled teal with ink type — the row
/// the page is pointing at.
struct PhonePosterEpisodeRow: View {
    let episode: Episode
    let isNext: Bool
    var action: () -> Void

    private static let coral = Color(hex: "#F0525F")

    private var ink: Color { isNext ? Palette.posterInk : .white }
    private var numberColor: Color {
        if isNext { return Palette.posterInk }
        return episode.isPlayed ? Palette.text(0.3) : Self.coral
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                thumb
                Text(episode.numberLabel)
                    .font(Display.font(26))
                    .foregroundStyle(numberColor)
                    .frame(width: 34, alignment: .leading)
                Text(episode.title.uppercased())
                    .font(Display.font(16))
                    .foregroundStyle(episode.isPlayed && !isNext ? Palette.text(0.5) : ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 6)
                if isNext, episode.isCurrent, !episode.resumeRemaining.isEmpty {
                    Text(episode.resumeRemaining.components(separatedBy: " · ").first ?? "")
                        .font(Mono.font(10, .bold))
                        .foregroundStyle(Palette.posterInk.opacity(0.7))
                        .lineLimit(1)
                        .fixedSize()
                } else if !episode.runtime.isEmpty {
                    Text(episode.runtime.uppercased())
                        .font(Mono.font(10, .bold))
                        .foregroundStyle(isNext ? Palette.posterInk.opacity(0.7) : Palette.text(0.45))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.leading, 7)
            .padding(.trailing, 14)
            .frame(height: 58)
            .contentShape(Rectangle())
            .background(isNext ? Palette.posterTeal : Color(hex: "#1D1E23"),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isNext ? Color.white.opacity(0.7) : Palette.text(0.05), lineWidth: isNext ? 2 : 1))
        }
        .buttonStyle(FocusScaleStyle(scale: 1.02, cornerRadius: 12))
        .accessibilityLabel("Episode \(episode.number), \(episode.title)\(episode.isPlayed ? ", watched" : "")")
    }

    private var thumb: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image = episode.image, image.hasPrefix("http"), let url = URL(string: image) {
                    JellyfinAsyncImage(url: url, fallback: episode.artwork.gradient)
                } else if let image = episode.image {
                    Image(image).resizable().scaledToFill()
                } else {
                    episode.artwork.gradient
                }
            }
            .frame(width: 62, height: 40)
            .clipped()
            .grayscale(episode.isPlayed && !isNext ? 0.85 : 0)
            // Watched: a full coral rule under the still. In progress: how far.
            let progress = episode.isPlayed ? 1 : (episode.isCurrent ? episode.resumeProgress : 0)
            if progress > 0 {
                Rectangle().fill(Self.coral)
                    .frame(width: 62 * progress, height: 3)
            }
        }
        .frame(width: 62, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
#endif
