import SwiftUI
import JellyTVKit

#if os(tvOS)
/// The film's chapters as a strip of frames — a look inside before committing
/// to it. Select starts playback at that chapter. Only the chapters Jellyfin
/// extracted a frame for are shown, and the strip only appears at all with
/// three or more of them (`MovieDetailView.scenes`): two thumbnails is not a
/// strip, it is a gap with pictures in it.
struct ScenesStrip: View {
    let chapters: [Chapter]
    let tint: Color
    var focus: FocusState<MovieField?>.Binding
    var onSelect: (Chapter) -> Void

    private static let thumbSize = CGSize(width: 320, height: 180)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("SCENES")
                    .font(Mono.font(13, .bold)).tracking(2)
                    .foregroundStyle(Palette.text(0.45))
                Spacer(minLength: 12)
                Text("\(chapters.count) CHAPTERS · SELECT ONE TO START THERE")
                    .font(Mono.font(13, .bold)).tracking(1.5)
                    .foregroundStyle(Palette.text(0.38))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 22) {
                    ForEach(chapters) { chapter in
                        Button { onSelect(chapter) } label: {
                            tile(chapter)
                        }
                        .buttonStyle(CardFocusStyle(glow: tint, scale: 1.06))
                        .focused(focus, equals: .scene(chapter.index))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 22)
            }
            .horizontalEdgeFade()
            .focusSection()
        }
    }

    private func tile(_ chapter: Chapter) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                if let image = chapter.imageURL, let url = URL(string: image) {
                    JellyfinAsyncImage(url: url, fallback: LinearGradient(
                        colors: [Palette.text(0.12), Palette.text(0.04)], startPoint: .top, endPoint: .bottom))
                } else {
                    Palette.text(0.06)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                Text(chapter.timestamp)
                    .font(Mono.font(13, .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(10)
            }
            .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Palette.text(0.12), lineWidth: 1))

            Text(chapter.title)
                .font(Typography.font(17, .semibold))
                .foregroundStyle(Palette.text(0.85))
                .lineLimit(1)
                .frame(width: Self.thumbSize.width, alignment: .leading)
        }
    }
}
#endif
