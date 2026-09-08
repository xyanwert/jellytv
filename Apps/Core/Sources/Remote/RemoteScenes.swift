import SwiftUI
import UIKit
import JellyTVKit

#if os(iOS)
/// Scenes, one at a time, a minute apart — the remote's way of moving through a film.
///
/// One frame fills the width; swipe for the next or previous minute; tap it and the TV
/// goes there. That is the whole control: no arrows, no strip, no slider, because the
/// finger is already doing the one gesture that means "next". The frames are the same
/// trickplay sprites the TV's own scenes panel and the home-video cards cut from — one
/// sheet download covers a hundred of them — never a seek of the video.
struct RemoteScenes: View {
    let item: JellyfinAPI.JellyfinItem
    /// Where the TV is now, so the first frame shown is the current minute.
    let currentSeconds: Double
    let onPick: (Double) -> Void
    let onClose: () -> Void

    @EnvironmentObject private var theme: Theme
    /// The minute on screen, by its own time — positional identity would let a stale
    /// page index look valid against a new item's minutes.
    @State private var selected: Double = 0
    @State private var picked: Double?

    private var isPhone: Bool { DeviceClass.current == .phone }

    /// Every minute of the runtime, from the start; the tail under five seconds is not a
    /// scene anyone means to jump to.
    private var times: [Double] {
        let runtime = Double(item.runTimeTicks ?? 0) / 10_000_000
        guard runtime > 65 else { return [0] }
        return Array(stride(from: 0.0, to: runtime - 5, by: 60))
    }

    var body: some View {
        VStack(spacing: 14) {
            TabView(selection: $selected) {
                ForEach(times, id: \.self) { seconds in
                    SceneFrame(item: item, seconds: seconds, isPicked: picked == seconds,
                               accent: theme.accent,
                               shouldLoad: abs(seconds - selected) <= 60) {
                        picked = seconds
                        onPick(seconds)
                    }
                    .tag(seconds)
                    .padding(.horizontal, 2)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity)

            HStack(spacing: 14) {
                Text("SWIPE FOR THE NEXT MINUTE · TAP TO PLAY IT THERE")
                    .font(Mono.font(10, .bold))
                    .tracking(1.4)
                    .foregroundStyle(Palette.text(0.4))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Palette.text(0.9))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Palette.text(0.12)))
                        .overlay(Circle().stroke(Palette.text(0.16), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close scenes")
            }
        }
        .onAppear {
            // Open on the minute the TV is in, not the opening shot.
            selected = times.min { abs($0 - currentSeconds) < abs($1 - currentSeconds) } ?? 0
        }
    }
}

/// One trickplay frame with its minute stamped on it. Loads itself; an empty dark tile
/// while the sheet is on its way, and stays empty when the server has no frame for it.
private struct SceneFrame: View {
    let item: JellyfinAPI.JellyfinItem
    let seconds: Double
    let isPicked: Bool
    let accent: Color
    /// Only the page on screen and its neighbours fetch: a paged `TabView` builds every
    /// page up front, and a two-hour film is a hundred and twenty of them.
    let shouldLoad: Bool
    let onTap: () -> Void

    @EnvironmentObject private var appState: AppState
    @State private var image: UIImage?

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                Rectangle().fill(Palette.pageBase)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                } else {
                    Image(systemName: "film")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Palette.text(0.18))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Text(formatPlayerClock(seconds, matching: Double(item.runTimeTicks ?? 0) / 10_000_000))
                    .font(Mono.font(13, .bold))
                    .monospacedDigit()
                    .tracking(1.2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.black.opacity(0.62)))
                    .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isPicked ? accent : Palette.text(0.14), lineWidth: isPicked ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scene at \(Int(seconds / 60)) minutes")
        .task(id: shouldLoad) {
            guard shouldLoad, image == nil, let trickplay = appState.cardTrickplay,
                  let best = HomeVideoRoll.bestTrickplay(item.trickplay) else { return }
            let loaded = await trickplay.thumbnail(forSeconds: seconds, itemId: item.id,
                                                   widthKey: best.widthKey, info: best.info,
                                                   mediaSourceId: best.mediaSourceId)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}
#endif
