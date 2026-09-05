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
    @EnvironmentObject private var theme: Theme

    var body: some View {
        HStack(spacing: 0) {
            NavRail(
                destination: .settings,
                isLibrariesOpen: isLibrariesOpen,
                onSelect: onSelectRail
            )
            LibrariesOverlayContent(isOpen: isLibrariesOpen, libraries: appState.libraryUIItems(),
                                        onDismiss: { onSelectRail(.libraries) }) {
                #if os(iOS)
                if DeviceClass.current == .phone {
                    phoneCategoryList
                } else {
                    padSplitBody
                }
                #else
                padSplitBody
                #endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea())
        .railContentSafeArea()
        .defaultFocus($focusedCategory, .playback)
        #if os(tvOS)
        .onExitCommand { onSelectRail(isLibrariesOpen ? .libraries : .home) }
        #endif
    }

    /// iPad/tvOS: a persistent side-by-side master-detail split, same shape
    /// as the rail beside it.
    private var padSplitBody: some View {
        HStack(spacing: 0) {
            SettingsCategoryList(
                categories: SampleCatalog.settingsCategories,
                selected: $selected,
                focus: $focusedCategory
            )
            detailView(for: selected)
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
                #if os(tvOS)
                .focusSection()
                #endif
        }
    }

    #if os(iOS)
    /// Phone: a side-by-side master-detail split has nowhere to put the
    /// detail column at a portrait phone width, so this pushes each category
    /// onto its own screen instead — the standard iOS Settings pattern
    /// (a plain list of rows, `NavigationLink` pushes the detail, the system
    /// back button/edge-swipe returns) rather than trying to cram both panes
    /// into one narrow column.
    private var phoneCategoryList: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(SampleCatalog.settingsCategories) { category in
                        NavigationLink(value: category.kind) {
                            PhoneCategoryRow(category: category)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: SettingsCategory.Kind.self) { kind in
                detailView(for: kind)
                    .padding(20)
                    .background(Palette.background.ignoresSafeArea())
                    .navigationTitle(SampleCatalog.settingsCategories.first { $0.kind == kind }?.label ?? "Settings")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .tint(theme.accent)
    }
    #endif

    @ViewBuilder
    private func detailView(for kind: SettingsCategory.Kind) -> some View {
        switch kind {
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

#if os(iOS)
/// A full-width row for the phone Settings list — same title/description
/// pairing as `SettingsCategoryList.CategoryRow`, just without that view's
/// fixed 420pt column width and accent left-bar (there's no adjacent active
/// state to contrast against once each category is its own pushed screen).
private struct PhoneCategoryRow: View {
    let category: SettingsCategory

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(category.label)
                    .font(Typography.font(19, .bold))
                    .foregroundStyle(Palette.textPrimary)
                Text(category.description)
                    .font(Typography.font(14, .medium))
                    .foregroundStyle(Palette.text(0.45))
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.text(0.3))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Palette.text(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.text(0.08), lineWidth: 1))
        .contentShape(Rectangle())
    }
}
#endif
