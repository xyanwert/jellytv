import SwiftUI
import JellyTVKit

/// The Settings screen: rail (Settings active) + category list + detail pane.
/// A full-screen peer of Home, not an overlay.
struct SettingsView: View {
    let isLibrariesOpen: Bool
    let onSelectRail: (RailTarget) -> Void

    @State private var selected: SettingsCategory.Kind = .playback
    @FocusState private var focusedCategory: SettingsCategory.Kind?
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            NavRail(
                destination: .settings,
                isLibrariesOpen: isLibrariesOpen,
                onSelect: onSelectRail
            )
            LibrariesOverlayContent(isOpen: isLibrariesOpen, libraries: appState.libraryUIItems()) {
                HStack(spacing: 0) {
                    SettingsCategoryList(
                        categories: SampleCatalog.settingsCategories,
                        selected: $selected,
                        focus: $focusedCategory
                    )
                    detail
                        .padding(.horizontal, 60)
                        .padding(.vertical, 52)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Without this, Right from a category row far down the list
                        // (Appearance, Metadata, …) has no on-axis candidate — the
                        // detail pane's content always starts back at its own top,
                        // so the vertical mismatch grows with each row and the
                        // engine rejects every candidate as too far off-axis, and
                        // Right does nothing. Marking the pane its own section lets
                        // the engine treat it as one entry point instead of raycasting
                        // to a specific row.
                        .focusSection()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea())
        .ignoresSafeArea()
        .defaultFocus($focusedCategory, .playback)
        .onExitCommand { onSelectRail(isLibrariesOpen ? .libraries : .home) }
    }

    @ViewBuilder
    private var detail: some View {
        switch selected {
        case .playback: PlaybackDetail()
        case .libraries: LibrariesDetail()
        case .home: HomeDetail()
        case .appearance: AppearanceDetail()
        case .metadata: MetadataDetail()
        case .server: ServerDetail()
        case .account: AccountDetail()
        }
    }
}
