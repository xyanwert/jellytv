import SwiftUI
import UIKit
import JellyTVKit

/// One trickplay frame of the playing item — the picture at a moment, cut
/// from the same sprite sheets the scenes panel uses (`TrickplayClient`), so
/// it costs no seek and, once a sheet is cached, no request.
///
/// It keeps the frame it has while the next one loads (no blink between two
/// jumps), and draws nothing at all for an item without trickplay — the
/// clock beside it already says where you are.
struct PlayerSceneFrame: View {
    let controller: PlayerController
    let time: Double
    let width: CGFloat

    @EnvironmentObject private var theme: Theme
    @State private var image: UIImage?

    var body: some View {
        let radius: CGFloat = theme.isPoster ? width * 0.03 : width * 0.05
        let border: CGFloat = theme.isPoster ? max(3, width * 0.014) : 1
        Rectangle()
            .fill(Palette.text(0.08))
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .frame(width: width, height: width * 9 / 16)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(theme.isPoster ? .white : Palette.text(0.25), lineWidth: border)
            )
            .compositingGroup()
            .shadow(color: theme.isPoster ? Palette.posterInk.opacity(0.9) : .black.opacity(0.45),
                    radius: theme.isPoster ? 0 : 18,
                    x: theme.isPoster ? width * 0.025 : 0,
                    y: theme.isPoster ? width * 0.025 : 8)
            .rotationEffect(.degrees(theme.isPoster ? -2 : 0))
            .opacity(image == nil ? 0 : 1)
            // Keyed to the sheet's own frame step (10s), not the 4Hz clock,
            // so a settled position asks once.
            .task(id: Int(time / 10)) {
                if let frame = await controller.sceneFrame(at: time) { image = frame }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Where a jump will land, beside the transport while it happens: a burst of
/// ↺30 / ↻30 / ↻1min taps shows the frame at the *target* on the side it is
/// heading (left for back, right for forward), and it lingers a beat after
/// the seek commits. The number under the circles already moves on the tap
/// (`displayTime`); this is the picture to go with it — the answer to "is
/// this where I meant?" before the video has caught up, which over a
/// transcoded stream can take a couple of seconds.
///
/// Laid over the transport block and offset *outside* its edges, so it takes
/// no layout space and never covers a circle.
struct PlayerJumpPreview: View {
    let controller: PlayerController
    let width: CGFloat
    var gap: CGFloat = 28
    /// Vertical nudge off the row's centre line. The phone's opinion stickers
    /// sit at the screen's edges at the transport's height, closer to 1M than
    /// a frame is wide — so there the preview rises into the clear band above
    /// them instead of landing on the heart.
    var lift: CGFloat = 0

    /// How long the frame stays after the seek commits. Held for half a
    /// minute under the `JT_TRY_JUMP` / `RT_TRY_JUMP` hook: the phone
    /// simulator's screenshots stall for seconds while a seek is loading,
    /// and missed the real 1.3s every time.
    private static let linger: Double = {
        let env = ProcessInfo.processInfo.environment
        return (env["JT_TRY_JUMP"] ?? env["RT_TRY_JUMP"]) == nil ? 1.3 : 30
    }()

    @State private var target: Double?
    @State private var forward = true
    @State private var hide: Task<Void, Never>?

    var body: some View {
        Color.clear
            .overlay(alignment: forward ? .trailing : .leading) {
                if let target {
                    PlayerSceneFrame(controller: controller, time: target, width: width)
                        // Pinned to the row's edge, then pushed its own width
                        // past it. Alignment guides were tried first and the
                        // overlay ignored them: the frame sat on top of ↻30
                        // and 1M (seen on the iPad).
                        .offset(x: forward ? width + gap : -(width + gap), y: lift)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .allowsHitTesting(false)
            .onChange(of: controller.pendingSeekTarget) { _, pending in
                if let pending {
                    hide?.cancel()
                    let heading = pending >= controller.currentTime
                    withAnimation(.easeOut(duration: 0.15)) {
                        forward = heading
                        target = pending
                    }
                } else {
                    hide = Task {
                        try? await Task.sleep(for: .seconds(Self.linger))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeOut(duration: 0.3)) { target = nil }
                    }
                }
            }
            .onDisappear { hide?.cancel() }
    }
}

extension View {
    /// Hangs `PlayerJumpPreview` off a transport row, sized per device: the
    /// room beside the circles is ~500pt a side on the TV, ~290 on the iPad,
    /// and on a landscape phone ~150 before the opinion stickers at the edges.
    func jumpPreview(_ controller: PlayerController) -> some View {
        let device = DeviceClass.current
        let width: CGFloat = device == .tv ? 340 : (device == .phone ? 128 : 230)
        let gap: CGFloat = device == .tv ? 40 : (device == .phone ? 12 : 28)
        let lift: CGFloat = device == .phone ? -52 : 0
        return overlay { PlayerJumpPreview(controller: controller, width: width, gap: gap, lift: lift) }
    }
}
