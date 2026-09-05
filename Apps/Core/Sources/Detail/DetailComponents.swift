import SwiftUI
import JellyTVKit

// Chrome shared by the Show and Movie detail screens: the left spine, and the
// edge fade every horizontally scrolling strip uses. Everything else that used
// to live here — `DetailBackground`, the 2×2 `SpecSheet`, `KeyArtPanel` with
// its floating `ResumeCard`, `DetailPill`, `DetailRightBackdrop` — belonged to
// the tvOS "signal dossier" movie page and an earlier iPad dossier, both since
// replaced by the one-sheet (`MovieOneSheet.swift`) and the show hero. Nothing
// referenced them any more, so they are gone rather than kept for company.

/// The detail screens' left spine: vertical genre label, a focusable back
/// control, and a small index marker (e.g. "EP 04" / "FILM 001").
struct DetailSpine: View {
    let genreLabel: String
    let markerTop: String
    let markerBottom: String
    let onBack: () -> Void
    /// Overrides the marker's colour — the Movie one-sheet tints its whole
    /// screen from the poster, spine included, rather than the app accent.
    var accent: Color? = nil

    @EnvironmentObject private var theme: Theme

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text(genreLabel.uppercased())
                .font(Typography.font(15, .semibold))
                .tracking(6)
                .foregroundStyle(Palette.text(0.32))
                .fixedSize()
                .rotationEffect(.degrees(90))
                .frame(height: 320)

            Spacer()

            VStack(spacing: 22) {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Palette.text(0.85))
                        .frame(width: 54, height: 54)
                        .background(Palette.text(0.06), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Palette.text(0.12), lineWidth: 1))
                }
                .buttonStyle(FocusScaleStyle(scale: 1.12, cornerRadius: 15))

                Text("\(markerTop)\n\(markerBottom)")
                    .font(Typography.font(13, .heavy))
                    .tracking(2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .foregroundStyle(accent ?? theme.accent)
            }
        }
        .padding(.vertical, 40)
        .frame(width: 118)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .trailing) { Rectangle().fill(Palette.text(0.08)).frame(width: 1) }
    }
}

extension View {
    /// Soft alpha fade at the leading/trailing edges of a horizontally
    /// scrolling strip — content dissolves as it nears the edge instead of
    /// hard-cutting at the scroll view's bounds.
    /// - Parameter edges: which side(s) actually get the fade. The mask sits
    ///   at the *view's own bounds*, not at the scroll offset, so a leading
    ///   fade darkens whatever is first in the strip even when nothing is
    ///   scrolled off that edge to hint at — right for a strip with real
    ///   content on both sides once scrolled (a cast row), wrong for one
    ///   whose first item never moves (a row of sort chips, where it read as
    ///   a stray shadow over the always-visible first chip). Default is both,
    ///   matching every existing call site.
    func horizontalEdgeFade(width: CGFloat = 36, edges: Edge.Set = [.leading, .trailing]) -> some View {
        mask(
            HStack(spacing: 0) {
                if edges.contains(.leading) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: width)
                }
                Rectangle().fill(.black)
                if edges.contains(.trailing) {
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: width)
                }
            }
        )
    }
}
