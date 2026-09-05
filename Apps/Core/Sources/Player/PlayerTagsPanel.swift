import SwiftUI
import JellyTVKit

/// TAGS — apply and remove this video's tags without leaving it.
///
/// **Why it's a panel and not a row of chips in the chrome.** v1
/// (`/Users/xyan/code/jelly-tv-ios`, `Core/Components/PlayerTagStrip.swift`)
/// put a wrapping pill strip in the top-right corner of its own Grandma
/// controls, tap-to-toggle in place. That predates this app's chrome
/// doctrine, where anything you have to *aim* at doesn't belong over the
/// picture; tagging is also the one action here that writes to the server and
/// changes what the library looks like afterwards. So it gets a surface of
/// its own with targets the size of the transport circles — the same bargain
/// SCENES makes.
///
/// **The tags are Jellyfin's own** (`Tags` on the item), not a local list.
/// That is the one substantive divergence from v1, which kept tags in a local
/// SwiftData store per library and never wrote one to the server in its life.
/// Real tags are what the chrome and the home-video cards already read, what
/// Jellyfin's own clients show, and what survives a reinstall — see
/// `JellyfinClient.setItemTags` for the read-modify-write that makes writing
/// them safe, and `JellyfinTags` for the rules that stop `gaby`/`Gaby`
/// fragmenting into two.
///
/// Three behaviours carried over from v1 deliberately:
///
/// - **Applied first, then the rest of the vocabulary.** What is on this video
///   is the answer to the question you opened the panel with.
/// - **Opening pauses; closing resumes if it was playing.** Same bracket as
///   `PlayerScenesPanel`.
/// - **Never gate the whole control behind an async step.** v1 hid its strip
///   until both the tag list and an `/Items/{id}/Ancestors` resolve came back,
///   which on a slow server meant no way to create a first tag at all
///   (its commits `de310da` → `c4a472c`). Here the panel always renders; only
///   the affordance that isn't ready is disabled, and it says why.
///
/// **One tag per visit, deliberately not a multi-select session.** Picking an
/// existing suggestion, or typing a new one and pressing ADD, calls
/// `onTagApplied` instead of just flipping the chip: the caller (`PlayerChrome
/// .applyTagAndClose`) closes the whole panel and drops a "stamped"
/// confirmation over the video in the same beat, so tagging reads as one
/// quick gesture — open, pick, done — rather than a settings screen you have
/// to remember to back out of. **Removing an already-applied tag is the one
/// exception**: that still just toggles the chip and leaves the panel open,
/// since a removal has nothing to "stamp" and someone clearing several tags
/// at once shouldn't have to reopen the panel between each one.
struct PlayerTagsPanel: View {
    let controller: PlayerController
    let accent: Color
    let onDismiss: () -> Void
    /// Called with the tag that was just added — never for a removal. See
    /// the type's own doc comment.
    let onTagApplied: (String) -> Void

    @EnvironmentObject private var appState: AppState
    @FocusState private var focus: String?

    @State private var wasPlaying = false
    @State private var draft = ""
    @State private var message: String?
    /// Writes are chained rather than fired in parallel: each one is a
    /// read-modify-write of the whole item, and two of those overlapping is
    /// how a mashed chip row ends up saving a stale list.
    @State private var writeChain: Task<Void, Never>?

    private enum Layout {
        static let inset: CGFloat = 44
        static let pillHeight: CGFloat = 84
        static let radius: CGFloat = 20
        static let spacing: CGFloat = 16
    }

    private var applied: [String] { controller.currentTags }

    /// The second section: what to offer that isn't already on this video.
    ///
    /// **Never the whole vocabulary.** A real Jellyfin library runs to
    /// thousands of tags — 1,266 on the server this was built against, 363 in
    /// one library — so an alphabetical wall of them is not a picker, it's a
    /// dictionary. Empty field: the tags this user actually reaches for, most
    /// recent first (v1's idea, whose strip showed applied-then-recent for the
    /// same reason). Typing: live matches from the vocabulary, prefix first.
    private var suggestions: [String] {
        let pool = draft.isEmpty ? appState.recentTags
                                 : appState.tagSuggestions(matching: draft)
        return pool.filter { !JellyfinTags.contains($0, in: applied) }
    }

    private var suggestionsLabel: String {
        draft.isEmpty ? "RECENT" : "MATCHING “\(draft)”"
    }

    /// Anything but a definite "no". `nil` means the permission check hasn't
    /// landed; the panel stays usable and a 403 would settle it — see
    /// `AppState.canEditItemMetadata`.
    private var canEdit: Bool { appState.canEditItemMetadata != false }

    var body: some View {
        ZStack {
            // Opaque, like SCENES: the panel replaces the chrome rather than
            // floating over it, and the player is paused underneath.
            Color.black.opacity(0.94).ignoresSafeArea()

            VStack(spacing: 22) {
                header
                content
                footer
            }
            .padding(Layout.inset)
        }
        .task {
            appState.loadTagVocabulary()
            wasPlaying = controller.isPlaying
            if wasPlaying { controller.pause() }
        }
        .onDisappear {
            if wasPlaying { controller.play() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            backButton
            Spacer(minLength: 0)
            countPill
        }
        .overlay { title }
    }

    private var backButton: some View {
        Button(action: onDismiss) {
            HStack(spacing: 12) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .bold))
                Text("BACK")
                    .font(Typography.font(20, .heavy))
            }
            .foregroundStyle(.white)
            .padding(.leading, 20)
            .padding(.trailing, 26)
            .padding(.vertical, 14)
            .background(accent, in: Capsule())
            .shadow(color: accent.opacity(0.4), radius: 20, y: 8)
        }
        .buttonStyle(FocusScaleStyle(cornerRadius: 30))
    }

    private var title: some View {
        VStack(spacing: 4) {
            Text("TAGS")
                .font(Mono.font(14, .bold))
                .tracking(2.4)
                .foregroundStyle(accent)
            Text(applied.isEmpty
                 ? (controller.tagsBelongToSeries ? "Nothing on this show yet" : "Nothing tagged yet")
                 : applied.joined(separator: " · "))
                .font(Typography.font(24, .bold))
                .foregroundStyle(Palette.text(0.92))
                .lineLimit(1)
        }
        .allowsHitTesting(false)
    }

    private var countPill: some View {
        Text("\(applied.count) ON")
            .font(Mono.font(15, .bold))
            .monospacedDigit()
            .foregroundStyle(Palette.text(0.6))
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(Palette.text(0.07), in: Capsule())
    }

    // MARK: - The pills

    @ViewBuilder
    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                if !applied.isEmpty {
                    section(controller.tagsBelongToSeries ? "ON THIS SHOW" : "ON THIS VIDEO",
                            tags: applied)
                }
                if !suggestions.isEmpty {
                    section(suggestionsLabel, tags: suggestions)
                }
                if applied.isEmpty && suggestions.isEmpty {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .frame(maxHeight: .infinity)
    }

    private func section(_ label: String, tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label)
                .font(Mono.font(14, .bold))
                .tracking(2)
                .foregroundStyle(Palette.text(0.45))
                .lineLimit(1)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 420),
                                         spacing: Layout.spacing)],
                      spacing: Layout.spacing) {
                ForEach(tags, id: \.self) { tag in
                    pill(tag)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tag")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(Palette.text(0.25))
            Text(draft.isEmpty
                 ? (controller.tagsBelongToSeries
                    ? "Nothing on this show yet.\nType a word below to put the first one on."
                    : "Nothing tagged yet.\nType a word below to put the first one on.")
                 : "No existing tag matches. ADD makes it a new one.")
                .multilineTextAlignment(.center)
                .font(Typography.font(22, .medium))
                .foregroundStyle(Palette.text(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    /// Filled and ticked when it's on this video, hollow when it isn't —
    /// which is the only way to read the state of a row of words at a glance.
    private func pill(_ tag: String) -> some View {
        let on = JellyfinTags.contains(tag, in: applied)
        let shape = RoundedRectangle(cornerRadius: Layout.radius, style: .continuous)
        return Button { toggle(tag) } label: {
            HStack(spacing: 14) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(on ? .white : Palette.text(0.35))
                Text(tag)
                    .font(Typography.font(23, .bold))
                    .foregroundStyle(on ? .white : Palette.text(0.86))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .frame(height: Layout.pillHeight)
            .frame(maxWidth: .infinity)
            .background(on ? accent : .black.opacity(0.46), in: shape)
            .overlay(shape.stroke(on ? accent : Palette.text(0.16), lineWidth: 1))
            .opacity(canEdit ? 1 : 0.5)
        }
        .buttonStyle(FocusScaleStyle(cornerRadius: Layout.radius))
        .disabled(!canEdit)
        .accessibilityLabel(on ? "\(tag), on. Tap to remove." : "\(tag), off. Tap to add.")
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                AppTextField(
                    placeholder: "Find or add a tag…",
                    text: $draft,
                    width: 420,
                    accent: accent,
                    field: "player-new-tag",
                    focus: $focus,
                    onSubmit: addDraft
                )
                .disabled(!canEdit)

                Button(action: addDraft) {
                    Text("ADD")
                        .font(Mono.font(20, .bold))
                        .tracking(1.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 30)
                        .frame(height: 62)
                        .background(accent.opacity(addable ? 1 : 0.3),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(FocusScaleStyle(cornerRadius: 14))
                .disabled(!addable)

                Spacer(minLength: 0)
            }

            if let note {
                Text(note)
                    .font(Typography.font(16, .medium))
                    .foregroundStyle(noteIsError ? Color(hex: "#E0457B") : Palette.text(0.45))
            }
        }
    }

    private var addable: Bool {
        canEdit && JellyfinTags.normalized(draft) != nil
    }

    /// One line, and it says the most useful true thing available: a failure
    /// first, then the permission problem, then nothing.
    private var note: String? {
        if let message { return message }
        if appState.canEditItemMetadata == false {
            return "This account can't edit metadata on the server, so tags are read-only here."
        }
        return nil
    }

    private var noteIsError: Bool { message != nil || !canEdit }

    // MARK: - Actions

    private func toggle(_ tag: String) {
        let wasApplied = JellyfinTags.contains(tag, in: applied)
        apply(JellyfinTags.toggling(tag, in: applied))
        // Only an add closes the panel — see the type's own doc comment on
        // why removal stays a plain in-place toggle.
        if !wasApplied {
            onTagApplied(tag)
        }
    }

    private func addDraft() {
        guard let tag = JellyfinTags.canonical(draft, in: appState.tagVocabulary) else { return }
        guard !JellyfinTags.contains(tag, in: applied) else {
            draft = ""
            message = "“\(tag)” is already on this video."
            return
        }
        draft = ""
        apply(applied + [tag])
        onTagApplied(tag)
    }

    /// Optimistic: the chip flips now, the server catches up. On failure the
    /// old list goes back and the panel says so — a tag that silently didn't
    /// save is worse than one that visibly didn't.
    private func apply(_ tags: [String]) {
        guard canEdit, let id = controller.tagTargetId else { return }
        let previous = applied
        message = nil
        controller.setTagsLocally(tags, for: id)
        let earlier = writeChain
        writeChain = Task {
            _ = await earlier?.value
            let saved = await appState.setTags(tags, forItem: id)
            guard !saved else { return }
            controller.setTagsLocally(previous, for: id)
            message = "Couldn't save that to the server."
        }
    }
}
