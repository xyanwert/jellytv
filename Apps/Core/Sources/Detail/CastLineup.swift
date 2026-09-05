import SwiftUI
import JellyTVKit

#if os(tvOS)
/// The cast as a lineup of cut-out figures on a lit stage, with a fact card
/// for whoever the remote is on — the movie page's second fold.
///
/// **The card is fixed-size and always showing someone.** Focus anywhere else
/// on the page leaves it on the lead (or the last person looked at), never
/// blank; it holds one footprint across loading / sparse / rich people, and
/// carries its own small indicator while the person fetch is in flight
/// ("panels don't jump", and a panel finishing later than its neighbour
/// reads as broken). Facts come from `MovieNightFacts` off the person's
/// Jellyfin item — age in the release year, birthplace, lifespan, how many
/// other films of theirs are here, an Oscar — and each is absent rather than
/// invented when the server never fetched that person.
///
/// Select opens `PersonSheet`; the cut-outs are the buttons.
struct CastLineup: View {
    let cast: [CastMember]
    let releaseYear: Int?
    let currentItemId: String
    let tint: Color
    /// Which member the page's focus is on, if any — the lineup shares the
    /// page's `@FocusState`, so Down from the Play bar lands here.
    let focusedMemberId: String?
    var focus: FocusState<MovieField?>.Binding
    var onSelect: (CastMember) -> Void

    @EnvironmentObject private var appState: AppState
    @State private var people: [String: Person] = [:]
    @State private var creditCounts: [String: Int] = [:]
    @State private var lastShownId: String?

    static let figureHeight: CGFloat = 230
    private static let cardSize = CGSize(width: 560, height: 300)
    private static let maxMembers = 8

    private var members: [CastMember] { Array(cast.prefix(Self.maxMembers)) }

    /// The member the card describes: the focused one, else the last one it
    /// showed, else the lead.
    private var shown: CastMember? {
        members.first { $0.id == focusedMemberId }
            ?? members.first { $0.id == lastShownId }
            ?? members.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("THE CAST")
                    .font(Mono.font(13, .bold)).tracking(2)
                    .foregroundStyle(Palette.text(0.45))
                Spacer(minLength: 12)
                Text("\(cast.count) CREDITED")
                    .font(Mono.font(13, .bold)).tracking(1.5)
                    .foregroundStyle(Palette.text(0.38))
            }

            HStack(alignment: .bottom, spacing: 36) {
                lineup
                factCard
            }
        }
        .onChange(of: focusedMemberId) { old, new in
            guard let new else { return }
            // Entering the lineup — Down from the Play bar, Up from the
            // scenes — lands on whoever the card is already showing: the
            // lead, or the last person looked at. Left to geometry, Down
            // from a bar that spans the page landed on the fifth of eight
            // (whichever figure sat under the bar's centre), with the card
            // switching away from the lead nobody had finished reading.
            if old == nil, let target = lastShownId ?? members.first?.id, new != target {
                focus.wrappedValue = .cast(target)
                return
            }
            lastShownId = new
        }
        .task(id: shown?.id) {
            guard let member = shown else { return }
            await load(member)
        }
    }

    // MARK: - Lineup

    private var lineup: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 26) {
                ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                    Button { onSelect(member) } label: {
                        CastFigure(member: member, tint: tint,
                                   focused: focusedMemberId == member.id,
                                   // Alternate leans: a row of coins stood on a table.
                                   lean: index.isMultiple(of: 2) ? -14 : 14)
                    }
                    .buttonStyle(FigureButtonStyle())
                    .focused(focus, equals: .cast(member.id))
                    // The person sheet zooms out of the coin — see `ZoomTransition`.
                    .zoomOrigin(focusedMemberId == member.id)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 36)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The stage: a soft floor line the figures stand on.
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, tint.opacity(0.10)], startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
                .padding(.bottom, 44)
        }
        .horizontalEdgeFade()
        // Left/Right stop at the ends of the lineup rather than hunting the
        // whole page for the nearest thing — see `ShowView.seasonSelector`.
        .focusSection()
    }

    // MARK: - Fact card

    private var factCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let member = shown {
                let person = people[member.id]
                Text(member.name)
                    .font(Typography.font(30, .black))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let role = member.role, !role.isEmpty {
                    Text("as \(role)")
                        .font(Typography.font(18, .medium)).italic()
                        .foregroundStyle(tint)
                        .lineLimit(1)
                }

                if let person {
                    factChips(for: member, person: person)
                    if let bio = person.bio, !bio.isEmpty {
                        Text(bio)
                            .font(Typography.font(17, .medium))
                            .foregroundStyle(Palette.text(0.72))
                            .lineSpacing(4)
                            .lineLimit(4)
                            .padding(.top, 2)
                    }
                } else if member.wonOscar {
                    factChips(for: member, person: nil)
                }

                Spacer(minLength: 0)

                if person == nil {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small).tint(tint)
                        Text("Looking them up…")
                            .font(Typography.font(15, .medium))
                            .foregroundStyle(Palette.text(0.4))
                    }
                }
            }
        }
        .padding(24)
        .frame(width: Self.cardSize.width, height: Self.cardSize.height, alignment: .topLeading)
        .background(Color(hex: "#0A0D14").opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.text(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
        .id(shown?.id)
        .transition(.opacity)
        .animation(.easeOut(duration: 0.25), value: shown?.id)
    }

    @ViewBuilder
    private func factChips(for member: CastMember, person: Person?) -> some View {
        let facts = Self.facts(for: member, person: person, releaseYear: releaseYear,
                               otherCredits: creditCounts[member.id])
        if !facts.isEmpty {
            MovieNightFactsRow(facts: facts, tint: tint)
        }
    }

    /// The card's chips, in the order a viewer cares: how old they were in
    /// it, where they are from, whether they are still with us, what else of
    /// theirs is on this TV, and the Oscar.
    static func facts(for member: CastMember, person: Person?, releaseYear: Int?,
                      otherCredits: Int?) -> [MovieNightFact] {
        var facts: [MovieNightFact] = []
        if let age = MovieNightFacts.ageAtRelease(birthDate: person?.birthDate, releaseYear: releaseYear) {
            facts.append(MovieNightFact(id: "age", icon: "calendar", text: "AGE \(age) AT RELEASE"))
        }
        if let place = person?.birthplace, !place.isEmpty {
            facts.append(MovieNightFact(id: "born", icon: "mappin", text: "BORN \(Self.shortPlace(place).uppercased())"))
        }
        if person?.deathDate != nil,
           let span = MovieNightFacts.lifespan(birthDate: person?.birthDate, deathDate: person?.deathDate) {
            facts.append(MovieNightFact(id: "life", icon: "leaf", text: span))
        }
        if let otherCredits, otherCredits > 0 {
            facts.append(MovieNightFact(id: "credits", icon: "film.stack",
                                        text: otherCredits == 1 ? "1 MORE IN YOUR LIBRARY" : "\(otherCredits) MORE IN YOUR LIBRARY"))
        }
        if member.wonOscar {
            facts.append(MovieNightFact(id: "oscar", icon: "trophy.fill", text: "ACADEMY AWARD WINNER"))
        }
        return facts
    }

    /// "Toronto, Ontario, Canada" → "Toronto, Canada": city and country, the
    /// two parts a chip has room for.
    static func shortPlace(_ place: String) -> String {
        let parts = place.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard parts.count > 2, let first = parts.first, let last = parts.last else { return place }
        return "\(first), \(last)"
    }

    private func load(_ member: CastMember) async {
        // Debounced: the remote crosses six figures in a second, and each
        // would otherwise cost two requests.
        try? await Task.sleep(for: .milliseconds(220))
        guard !Task.isCancelled else { return }
        if people[member.id] == nil, let person = await appState.person(for: member.id) {
            people[member.id] = person
        }
        if creditCounts[member.id] == nil {
            creditCounts[member.id] = await appState.libraryCredits(personId: member.id, excluding: currentItemId).count
        }
    }
}

/// One figure in the lineup: the coin on its own patch of stage, name and
/// role under it. Focus lifts it and makes it live (`CastCoin`).
struct CastFigure: View {
    let member: CastMember
    let tint: Color
    let focused: Bool
    var lean: Double = 0

    private static let width: CGFloat = 200
    private static let coinSize: CGFloat = 190

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottom) {
                // The patch of stage: a shadow at rest, a pool of the film's
                // light under the live coin.
                Ellipse()
                    .fill(RadialGradient(colors: [focused ? tint.opacity(0.6) : .black.opacity(0.5), .clear],
                                         center: .center, startRadius: 0, endRadius: 90))
                    .frame(width: 180, height: 44)
                    .offset(y: 16)
                CastCoin(member: member, tint: tint, size: Self.coinSize, live: focused, restingLean: lean)
                    .scaleEffect(focused ? 1.08 : 1, anchor: .bottom)
                    .offset(y: focused ? -12 : 0)
            }
            .frame(width: Self.width, height: CastLineup.figureHeight + 12, alignment: .bottom)

            VStack(spacing: 3) {
                Text(member.name)
                    .font(Typography.font(17, .bold))
                    .foregroundStyle(focused ? Palette.textPrimary : Palette.text(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let role = member.role, !role.isEmpty {
                    Text(role)
                        .font(Typography.font(14, .medium))
                        .foregroundStyle(Palette.text(0.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(width: Self.width)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: focused)
    }
}

/// The figure draws its own focus (lift, light, longer shadow), so the button
/// style stays out of the way — no ring around a person.
private struct FigureButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}
#endif
