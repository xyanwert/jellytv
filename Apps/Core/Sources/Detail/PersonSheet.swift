import SwiftUI
import JellyTVKit

#if os(tvOS)
/// A person, full size: the cut-out, the whole biography, the facts, and
/// everything else of theirs in this library as a row you can open. Presented
/// over the movie page as a same-`ZStack` overlay (the page's content is
/// `.disabled` beneath it) — the "oh, she's also in…" turn a movie night
/// takes.
///
/// Menu closes it. Focus lands on the close control first (a sheet with
/// nothing focused is a sheet Menu can't reach — see `MovieDetailView`'s
/// note), then Right/Down walk the posters.
struct PersonSheet: View {
    let member: CastMember
    let releaseYear: Int?
    let currentItemId: String
    let tint: Color
    var onOpen: (MediaItem) -> Void
    var onDismiss: () -> Void

    @EnvironmentObject private var appState: AppState
    @State private var person: Person?
    @State private var credits: [MediaItem] = []
    @State private var loaded = false
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case close
        case credit(String)
    }

    var body: some View {
        // No scrim of its own: the sheet zooms out of the coin, and a scrim
        // that zoomed with it showed its rectangular edge mid-flight. The
        // presenting page fades one in underneath instead (`MovieDetailView`).
        ZStack(alignment: .topLeading) {
            HStack(alignment: .top, spacing: 64) {
                VStack(spacing: 0) {
                    // The hero coin: always live, so it spins in with the sheet.
                    CastCoin(member: member, tint: tint, size: 440, live: true)
                    Ellipse()
                        .fill(RadialGradient(colors: [.black.opacity(0.7), .clear],
                                             center: .center, startRadius: 0, endRadius: 220))
                        .frame(width: 440, height: 80)
                        .offset(y: -18)
                }
                .frame(width: 480, alignment: .bottom)

                VStack(alignment: .leading, spacing: 16) {
                    Text(member.name)
                        .font(Typography.font(64, .black))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    if let role = member.role, !role.isEmpty {
                        Text("as \(role)")
                            .font(Typography.font(24, .medium)).italic()
                            .foregroundStyle(tint)
                    }

                    let facts = CastLineup.facts(for: member, person: person, releaseYear: releaseYear,
                                                 otherCredits: credits.count)
                    if !facts.isEmpty {
                        MovieNightFactsRow(facts: facts, tint: tint)
                    }

                    if let bio = person?.bio, !bio.isEmpty {
                        Text(bio)
                            .font(Typography.font(20, .medium))
                            .foregroundStyle(Palette.text(0.78))
                            .lineSpacing(6)
                            .lineLimit(7)
                            .frame(maxWidth: 1000, alignment: .leading)
                    } else if !loaded {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small).tint(tint)
                            Text("Looking them up…")
                                .font(Typography.font(16, .medium))
                                .foregroundStyle(Palette.text(0.4))
                        }
                    }

                    Spacer(minLength: 12)

                    if !credits.isEmpty {
                        creditsRow
                    } else if loaded {
                        Text("Nothing else of theirs in your library.")
                            .font(Typography.font(17, .medium))
                            .foregroundStyle(Palette.text(0.4))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.init(top: 120, leading: 96, bottom: 72, trailing: 96))

            closeButton
                .padding(.top, 44)
                .padding(.leading, 48)
        }
        .onExitCommand(perform: onDismiss)
        .onAppear { focus = .close }
        .task(id: member.id) {
            person = await appState.person(for: member.id)
            credits = await appState.libraryCredits(personId: member.id, excluding: currentItemId)
            loaded = true
        }
    }

    private var closeButton: some View {
        Button(action: onDismiss) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .bold))
                Text("BACK").font(Typography.font(18, .heavy))
            }
            .foregroundStyle(.white)
            .padding(.leading, 18).padding(.trailing, 24).padding(.vertical, 12)
            .background(tint, in: Capsule())
        }
        .buttonStyle(FocusScaleStyle(cornerRadius: 30))
        .focused($focus, equals: .close)
    }

    private var creditsRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("IN YOUR LIBRARY")
                .font(Mono.font(13, .bold)).tracking(2)
                .foregroundStyle(Palette.text(0.45))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) {
                    ForEach(credits) { item in
                        LibraryPosterCard(item: item, onSelect: { onOpen(item) })
                            .focused($focus, equals: .credit(item.id))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
            }
            .horizontalEdgeFade()
            .focusSection()
        }
    }
}
#endif
