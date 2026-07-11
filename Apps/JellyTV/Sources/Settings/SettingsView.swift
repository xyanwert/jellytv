import SwiftUI
import JellyTVKit

/// The Settings screen: rail (Settings active) + category list + detail pane.
/// A full-screen peer of Home, not an overlay.
struct SettingsView: View {
    let onSelectRail: (RailTarget) -> Void

    @State private var selected: SettingsCategory.Kind = .playback
    @FocusState private var focusedCategory: SettingsCategory.Kind?

    var body: some View {
        HStack(spacing: 0) {
            NavRail(
                destination: .settings,
                isLibrariesOpen: false,
                isServerConnected: SampleCatalog.server.isConnected,
                onSelect: onSelectRail
            )
            SettingsCategoryList(
                categories: SampleCatalog.settingsCategories,
                selected: $selected,
                focus: $focusedCategory
            )
            detail
                .padding(.horizontal, 60)
                .padding(.vertical, 52)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea())
        .defaultFocus($focusedCategory, .playback)
        .onExitCommand { onSelectRail(.home) }
    }

    @ViewBuilder
    private var detail: some View {
        switch selected {
        case .playback: PlaybackDetail()
        case .account: AccountDetail()
        case .server: ServerDetail()
        case .subtitles: PlaceholderDetail(title: "Subtitles")
        case .audio: PlaceholderDetail(title: "Audio")
        case .parental: PlaceholderDetail(title: "Parental")
        case .about: PlaceholderDetail(title: "About")
        }
    }
}
