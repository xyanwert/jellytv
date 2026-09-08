import SwiftUI
import JellyTVKit

/// The pieces Discover and the download centre share, so the two screens cannot drift:
/// one header, one set of sizes per device, one place the server's refusals are shown.

/// The eyebrow + title + count header both Discover screens open with.
struct DiscoverPageHeader: View {
    let eyebrow: String
    let title: String
    var count: String? = nil

    @EnvironmentObject private var theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(Mono.font(DiscoverMetrics.eyebrow, .bold))
                .tracking(3.4)
                .foregroundStyle(theme.accent)
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(title)
                    .font(Typography.font(DiscoverMetrics.title, .heavy))
                    .foregroundStyle(Palette.text(0.95))
                if let count {
                    Text(count)
                        .font(Mono.font(DiscoverMetrics.count, .medium))
                        .foregroundStyle(Palette.text(0.4))
                }
            }
        }
    }
}

/// Sizes that differ by viewing distance, spelled once. They were character-identical
/// across three screens before this existed.
enum DiscoverMetrics {
    #if os(tvOS)
    static let pagePadding: CGFloat = 70
    static let topPadding: CGFloat = 46
    static let sectionGap: CGFloat = 26
    static let eyebrow: CGFloat = 17
    static let title: CGFloat = 46
    static let count: CGFloat = 18
    static let body: CGFloat = 20
    #else
    private static var isPhone: Bool { DeviceClass.current == .phone }
    static var pagePadding: CGFloat { isPhone ? 18 : 34 }
    static var topPadding: CGFloat { isPhone ? 14 : 26 }
    static var sectionGap: CGFloat { isPhone ? 16 : 22 }
    static var eyebrow: CGFloat { isPhone ? 12 : 14 }
    static var title: CGFloat { isPhone ? 28 : 36 }
    static var count: CGFloat { isPhone ? 13 : 15 }
    static var body: CGFloat { isPhone ? 15 : 17 }
    #endif
}

extension View {
    /// The server's refusal, verbatim, wherever a Discover action can fail. It was on
    /// Discover alone once, so a cancel that failed in the download centre said nothing
    /// there and popped up later on the other screen, out of context.
    func discoverActionAlert(_ store: DiscoverStore) -> some View {
        alert("Couldn't do that",
              isPresented: Binding(get: { store.actionError != nil },
                                   set: { if !$0 { store.actionError = nil } })) {
            Button("OK", role: .cancel) { store.actionError = nil }
        } message: {
            // Written by the server for a person to read — "Season 9 isn't listed
            // (available: 1, 2, 3)" — so shown as sent.
            Text(store.actionError ?? "")
        }
    }
}
