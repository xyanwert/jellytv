import SwiftUI
import JellyTVKit

#if os(iOS)
/// The Movie screen's two phone tabs. A movie has no seasons/episodes to
/// browse (unlike `PhoneShowTab`, which leads with EPISODES), so DETAILS
/// leads instead — the same real spec-sheet fields the iPad one-sheet's
/// `HairlineRail` already reads, just stacked full width.
enum PhoneMovieTab: CaseIterable {
    case details, cast

    var label: String {
        switch self {
        case .details: return "DETAILS"
        case .cast: return "CAST"
        }
    }
}

/// Generic icon-above-caption phone quick action (RESTART/FAVOURITE/…) —
/// `ShowView` inlines its own copy of this same shape; kept here rather than
/// shared across both files so this pass doesn't touch `ShowView`'s
/// already-verified phone layout at all.
struct PhoneQuickAction: View {
    let icon: String
    let caption: String
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(tint)
                Text(caption).font(Mono.font(10, .bold)).tracking(1.2).foregroundStyle(Palette.text(0.6))
            }
        }
        .buttonStyle(.plain)
    }
}
#endif
