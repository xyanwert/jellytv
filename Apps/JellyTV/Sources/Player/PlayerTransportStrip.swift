import SwiftUI
import JellyTVKit

/// The 7-tile bottom seek strip: ±1min / ±30s / ±10s around a center SCENES
/// tile. Column widths follow the design's 1.35fr/1fr×5/1.35fr proportions
/// (the ±1min tiles read wider/heavier than the rest).
struct PlayerTransportStrip: View {
    let controller: PlayerController
    let accent: Color
    let onInteract: () -> Void
    let onOpenScenes: () -> Void
    @FocusState.Binding var focus: PlayerFocusField?

    private let blue = Color(OKLCH(l: 0.62, c: 0.16, h: 245))
    private let blueDim = Color(OKLCH(l: 0.55, c: 0.15, h: 245))
    private let violet = Color(OKLCH(l: 0.58, c: 0.19, h: 292))

    private struct Tile {
        let label: String
        let systemImage: String
        let weight: CGFloat
        let color: Color
        let action: () -> Void
    }

    private var tiles: [Tile] {
        [
            Tile(label: "−1 MIN", systemImage: "gobackward.60", weight: 1.35, color: accent) {
                onInteract(); Task { await controller.seekRelative(by: -60) }
            },
            Tile(label: "−30 S", systemImage: "gobackward.30", weight: 1, color: blue) {
                onInteract(); Task { await controller.seekRelative(by: -30) }
            },
            Tile(label: "−10 S", systemImage: "gobackward.10", weight: 1, color: blueDim) {
                onInteract(); Task { await controller.seekRelative(by: -10) }
            },
            Tile(label: "SCENES", systemImage: "square.grid.2x2.fill", weight: 1, color: violet) {
                onInteract(); onOpenScenes()
            },
            Tile(label: "+10 S", systemImage: "goforward.10", weight: 1, color: blueDim) {
                onInteract(); Task { await controller.seekRelative(by: 10) }
            },
            Tile(label: "+30 S", systemImage: "goforward.30", weight: 1, color: blue) {
                onInteract(); Task { await controller.seekRelative(by: 30) }
            },
            Tile(label: "+1 MIN", systemImage: "goforward.60", weight: 1.35, color: accent) {
                onInteract(); Task { await controller.seekRelative(by: 60) }
            },
        ]
    }

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 16
            let totalWeight = tiles.reduce(0) { $0 + $1.weight }
            let totalGap = gap * CGFloat(tiles.count - 1)
            let unit = (geo.size.width - totalGap) / totalWeight

            HStack(spacing: gap) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { index, tile in
                    Button(action: tile.action) {
                        VStack(spacing: 12) {
                            Image(systemName: tile.systemImage)
                                .font(.system(size: 30, weight: .semibold))
                            Text(tile.label)
                                .font(Mono.font(18, .bold))
                                .tracking(1)
                        }
                        .foregroundStyle(.white)
                        .frame(width: unit * tile.weight, height: 128)
                        .background(tile.color, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: tile.color.opacity(0.3), radius: 14, y: 8)
                    }
                    .buttonStyle(FocusScaleStyle(cornerRadius: 20))
                    .focused($focus, equals: .transport(index))
                }
            }
        }
        .frame(height: 128)
    }
}
