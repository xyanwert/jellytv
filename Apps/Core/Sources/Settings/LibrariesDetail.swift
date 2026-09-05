import SwiftUI
import JellyTVKit

/// Settings → Libraries: every Jellyfin library the server exposes (movies,
/// TV shows, home videos), with the extra classification Jellyfin has no
/// concept of — NSFW and anime — plus a per-library tag manager. The base
/// kind (movies/TV shows/home videos) comes straight from Jellyfin's own
/// `CollectionType` and isn't editable here; only the two extra flags are.
///
/// Rows are collapsed by default (accordion, one open at a time) — the user
/// opens whichever library they want to change rather than scrolling past
/// every toggle on every library at once.
struct LibrariesDetail: View {
    @EnvironmentObject private var appState: AppState
    @State private var expandedLibraryId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(title: "Libraries", readout: readout)

            if appState.libraries.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        ForEach(appState.libraries) { library in
                            LibraryClassificationCard(library: library, expandedLibraryId: $expandedLibraryId)
                        }
                    }
                    .padding(.vertical, 4)
                }
                // Without this, Down running out of focusable rows inside the
                // scroll view sends focus hunting for the nearest geometric
                // target on the whole screen — which is the left category
                // rail, not the next card. Same fix as ShowView's episode
                // strip/season selector.
                #if os(tvOS)
                .focusSection()
                #endif
            }
        }
    }

    private var readout: String? {
        guard !appState.libraries.isEmpty else { return nil }
        return "\(appState.libraries.count) connected"
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.stack")
                .font(.system(size: 56))
                .foregroundStyle(Palette.text(0.5))
            Text("No libraries yet")
                .font(Typography.section)
                .foregroundStyle(Palette.text(0.7))
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }
}

/// One library's accordion row: a collapsed head (name, kind, and a summary
/// of the current classification/tags) that expands to reveal the NSFW/anime
/// toggles the model layer allows for that kind, plus the tag manager.
private struct LibraryClassificationCard: View {
    let library: JellyfinAPI.JellyfinUserView
    @Binding var expandedLibraryId: String?
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: Theme

    private var isExpanded: Bool { expandedLibraryId == library.id }

    private var flags: (isNSFW: Bool, isAnime: Bool) {
        appState.classificationFlags(for: library)
    }

    private var collectionType: String { library.collectionType ?? "" }
    private var supportsNSFW: Bool { MetaCategory.supportsNSFW(collectionType: collectionType) }
    private var supportsAnime: Bool { MetaCategory.supportsAnime(collectionType: collectionType) }
    /// Movies has no combined NSFW+anime category (unlike TV shows' hentai),
    /// so the two toggles are kept mutually exclusive for that kind only.
    private var isMutuallyExclusive: Bool { collectionType == "movies" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            if isExpanded {
                expandedBody
                    // Opacity only, no move/slide — the parent's spacing
                    // animation already grows the card around this content,
                    // so a combined transition would double-animate and the
                    // body would visibly slide in from outside the card.
                    .transition(.opacity)
            }
        }
        .background(Palette.text(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isExpanded ? theme.accent.opacity(0.5) : Palette.text(0.08), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.2), value: isExpanded)
    }

    private var head: some View {
        Button {
            expandedLibraryId = isExpanded ? nil : library.id
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(library.name)
                        .font(Typography.font(22, .bold))
                        .foregroundStyle(Palette.textPrimary)
                    Text(summaryText)
                        .font(Typography.font(15, .medium))
                        .foregroundStyle(Palette.text(0.45))
                }
                Spacer(minLength: 12)
                Text(typeLabel.uppercased())
                    .font(Typography.font(13, .heavy))
                    .tracking(1.4)
                    .foregroundStyle(Palette.text(0.45))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Palette.text(0.08), in: Capsule())
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.text(0.4))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .contentShape(Rectangle())
        }
        // No focus scale: the card around this head is drawn by the parent
        // and doesn't grow with it, so a scaled label pushed the chip and
        // chevron out past the card's edge. Tint + bar + glow do the job.
        .buttonStyle(RowFocusStyle(isActive: isExpanded, cornerRadius: 18, scale: 1))
    }

    private var summaryText: String {
        var parts: [String] = []
        if flags.isNSFW { parts.append("NSFW") }
        if flags.isAnime { parts.append("Anime") }
        let tagCount = appState.tags(forLibrary: library.id).count
        if tagCount > 0 { parts.append("\(tagCount) tag\(tagCount == 1 ? "" : "s")") }
        return parts.isEmpty ? "No extra classification" : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailDivider()
            if supportsNSFW {
                DetailRow(label: "Adult content", description: "Flags this library NSFW — hidden from Home when \"Hide NSFW\" is on") {
                    ToggleSwitch(isOn: Binding(
                        get: { flags.isNSFW },
                        set: { newValue in
                            appState.setLibraryClassification(
                                libraryId: library.id,
                                isNSFW: newValue,
                                isAnime: (newValue && isMutuallyExclusive) ? false : flags.isAnime
                            )
                        }
                    ))
                }
                if supportsAnime { DetailDivider() }
            }
            if supportsAnime {
                DetailRow(label: "Anime", description: "Classifies this library's content as anime") {
                    ToggleSwitch(isOn: Binding(
                        get: { flags.isAnime },
                        set: { newValue in
                            appState.setLibraryClassification(
                                libraryId: library.id,
                                isNSFW: (newValue && isMutuallyExclusive) ? false : flags.isNSFW,
                                isAnime: newValue
                            )
                        }
                    ))
                }
            }
            if supportsNSFW || supportsAnime { DetailDivider() }
            LibraryTagsEditor(libraryId: library.id)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }

    private var typeLabel: String {
        switch collectionType {
        case "movies": return "Movies"
        case "tvshows": return "TV Shows"
        case "homevideos": return "Home Videos"
        default: return collectionType.isEmpty ? "Library" : collectionType.capitalized
        }
    }
}
