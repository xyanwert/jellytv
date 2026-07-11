import SwiftUI

/// Detail pane for categories with no real backend or design content yet
/// (Subtitles, Audio, Parental, About) — same non-blocking placeholder pattern
/// used for the rail's Search/Movies/TV Shows destinations.
struct PlaceholderDetail: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(title: title)
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 56))
                    .foregroundStyle(Palette.text(0.5))
                Text("\(title) — coming soon")
                    .font(Typography.section)
                    .foregroundStyle(Palette.text(0.7))
            }
            .frame(maxWidth: .infinity, minHeight: 420)
            Spacer(minLength: 0)
        }
    }
}
