import SwiftUI
import JellyTVKit

/// Inline per-library tag manager, shown inside each `LibraryClassificationCard`.
/// Tags are scoped to one library — the same name in two different libraries
/// is independent, mirroring the reference app's per-library tag model. Local
/// only (Jellyfin has no per-library tag concept of its own); create + delete
/// only, no rename, keeping the tvOS remote interaction simple.
struct LibraryTagsEditor: View {
    let libraryId: String
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: Theme
    @FocusState private var fieldFocused: Bool?
    @State private var draft = ""
    @State private var error: String?

    private var tags: [String] { appState.tags(forLibrary: libraryId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TAGS")
                .font(Mono.font(13, .bold))
                .tracking(2)
                .foregroundStyle(Palette.text(0.5))

            HStack(spacing: 12) {
                AppTextField(
                    placeholder: "New tag",
                    text: $draft,
                    width: 280,
                    accent: theme.accent,
                    field: true,
                    focus: $fieldFocused,
                    onSubmit: addTag
                )
                Button(action: addTag) {
                    Text("Add")
                        .font(Typography.font(16, .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(theme.accent.opacity(trimmedDraft.isEmpty ? 0.3 : 1),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(FocusScaleStyle(scale: 1.05, cornerRadius: 10))
                .disabled(trimmedDraft.isEmpty)
            }

            if let error {
                Text(error)
                    .font(Typography.font(14, .medium))
                    .foregroundStyle(.red)
            }

            if tags.isEmpty {
                Text("No tags in this library yet.")
                    .font(Typography.font(15, .medium))
                    .foregroundStyle(Palette.text(0.35))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(tags, id: \.self) { tag in
                            tagChip(tag)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .horizontalEdgeFade()
            }
        }
        .padding(.vertical, 18)
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tagChip(_ tag: String) -> some View {
        HStack(spacing: 8) {
            Text(tag.uppercased())
                .font(Typography.font(14, .bold))
                .foregroundStyle(Palette.textPrimary)
            Button {
                appState.deleteTag(tag, fromLibrary: libraryId)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.text(0.5))
            }
            .buttonStyle(FocusScaleStyle(scale: 1.2, cornerRadius: 999))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Palette.text(0.08), in: Capsule())
        .overlay(Capsule().stroke(Palette.text(0.14), lineWidth: 1))
    }

    private func addTag() {
        do {
            try appState.addTag(draft, toLibrary: libraryId)
            draft = ""
            error = nil
        } catch let tagError as AppState.LibraryTagError {
            error = tagError.errorDescription
        } catch {
            self.error = error.localizedDescription
        }
    }
}
