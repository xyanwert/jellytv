import SwiftUI
import JellyTVKit

#if os(tvOS)
/// "More like this", for real: what Jellyfin's `/Items/{id}/Similar` finds in
/// *this* library, as the same clean posters the library grids use. Select
/// opens that film's own page. The row this replaced was `SampleCatalog`
/// posters — "Undertow", "Copper Season" — on every real film's page.
struct SimilarRow: View {
    let items: [MediaItem]
    var focus: FocusState<MovieField?>.Binding
    var onOpen: (MediaItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("MORE LIKE THIS")
                    .font(Mono.font(13, .bold)).tracking(2)
                    .foregroundStyle(Palette.text(0.45))
                Spacer(minLength: 12)
                Text("IN YOUR LIBRARY")
                    .font(Mono.font(13, .bold)).tracking(1.5)
                    .foregroundStyle(Palette.text(0.38))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) {
                    ForEach(items) { item in
                        LibraryPosterCard(item: item, onSelect: { onOpen(item) })
                            .focused(focus, equals: .similar(item.id))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 22)
            }
            .horizontalEdgeFade()
            .focusSection()
        }
    }
}
#endif
