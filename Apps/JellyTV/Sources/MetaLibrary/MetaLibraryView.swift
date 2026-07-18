import SwiftUI
import JellyTVKit

struct MetaLibraryView: View {
    let collectionType: String
    let onSelectRail: (RailTarget) -> Void

    @EnvironmentObject private var appState: AppState

    private var title: String {
        collectionType == "movies" ? "Movies" : "TV Shows"
    }

    private var destination: NavDestination {
        collectionType == "movies" ? .movies : .tv
    }

    var body: some View {
        HStack(spacing: 0) {
            NavRail(
                destination: destination,
                isLibrariesOpen: false,
                onSelect: onSelectRail
            )
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    Text(title)
                        .font(Typography.screenTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.top, 60)

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 4),
                        spacing: 28
                    ) {
                        ForEach(appState.items(for: collectionType)) { item in
                            PosterCard(item: item)
                        }
                    }
                }
                .padding(.horizontal, 56)
                .padding(.bottom, 80)
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .ignoresSafeArea()
        .onExitCommand { onSelectRail(.home) }
    }
}
