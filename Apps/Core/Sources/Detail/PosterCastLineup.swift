import SwiftUI
import JellyTVKit
#if canImport(UIKit)
import UIKit
#endif

/// Poster Mode's cast (`AppStyle.poster`): the people themselves, cut out of
/// their headshots and stood shoulder to shoulder on the ink band like a
/// character-select screen. Same inputs, focus tags and Select behaviour as
/// `CastLineup`, which Classic keeps — `MovieDetailView` swaps one for the other.
///
/// **Focus is the spotlight.** The person under the remote steps forward in
/// full colour with a white sticker outline and their name tag; everyone else
/// stands back in greyscale. That motion is one figure's worth of pixels, the
/// same budget `CardFocusStyle` spends on a poster.
///
/// **The cut-out is the portrait.** `PortraitCutoutCache` does the Vision work
/// (on device, once, cached); until it answers — or where it can't, like the
/// tvOS simulator — the headshot stands in as a tilted, white-framed photo
/// sticker, which still belongs in the lineup rather than reading as missing.
struct PosterCastLineup: View {
    let cast: [CastMember]
    let releaseYear: Int?
    let currentItemId: String
    let tint: Color
    let focusedMemberId: String?
    var focus: FocusState<MovieField?>.Binding
    var onSelect: (CastMember) -> Void

    @EnvironmentObject private var appState: AppState
    @State private var people: [String: Person] = [:]
    @State private var creditCounts: [String: Int] = [:]
    @State private var lastShownId: String?
    /// Touch: who the spotlight is on. There is no focus on iOS, so the first
    /// tap on a figure spotlights them (colour, outline, name, facts) and a
    /// second tap is the Select.
    @State private var tappedId: String?

    private static let maxMembers = 8
    static var bandHeight: CGFloat {
        switch DeviceClass.current { case .tv: return 210; case .pad: return 140; case .phone: return 96 }
    }
    static var stageHeight: CGFloat {
        switch DeviceClass.current { case .tv: return 430; case .pad: return 300; case .phone: return 214 }
    }

    private var members: [CastMember] { Array(cast.prefix(Self.maxMembers)) }

    /// Who is in the spotlight: the focused figure on TV; on touch the tapped
    /// one, else the lead.
    private var spotlightId: String? {
        #if os(tvOS)
        focusedMemberId
        #else
        tappedId ?? members.first?.id
        #endif
    }

    private var shown: CastMember? {
        members.first { $0.id == spotlightId }
            ?? members.first { $0.id == lastShownId }
            ?? members.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 18) {
                // The header pads for a full-bleed row; this one sits in the
                // page's own margin.
                PosterSectionHeader(title: "The Cast", count: cast.count)
                    .padding(.horizontal, DeviceClass.current == .phone ? -20 : -56)
                    .frame(maxWidth: DeviceClass.current == .tv ? 520 : 320, alignment: .leading)
                if DeviceClass.current != .phone { factChips }
                Spacer(minLength: 0)
            }
            .frame(height: DeviceClass.current == .tv ? 50 : 34)
            // A phone row has no room beside the header; the facts go under it.
            if DeviceClass.current == .phone {
                ScrollView(.horizontal, showsIndicators: false) { factChips }
            }

            stage
        }
        .onChange(of: focusedMemberId) { old, new in
            guard let new else { return }
            // Entering the lineup lands on whoever the chips already describe
            // — the lead or the last person looked at — not on whichever
            // figure happens to sit under the Play pill. Same rule as
            // `CastLineup`.
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

    // MARK: - Stage

    private var stage: some View {
        ZStack(alignment: .bottom) {
            // The band the figures stand on, with the teal/coral edge.
            VStack(spacing: 0) {
                Rectangle().fill(Palette.posterTeal).frame(height: 10)
                Rectangle().fill(Color(hex: "#F0525F")).frame(height: 4).padding(.top, 5)
                PosterStripeBand()
            }
            .frame(height: Self.bandHeight)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: -28) {
                    ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                        Button { select(member) } label: {
                            PosterCastFigure(member: member, tint: tint,
                                             focused: spotlightId == member.id,
                                             lean: index.isMultiple(of: 2) ? -3 : 3)
                        }
                        .buttonStyle(PosterFigureButtonStyle())
                        .focused(focus, equals: .cast(member.id))
                        // The figure in front always wins the overlap.
                        .zIndex(spotlightId == member.id ? 10 : Double(members.count - index))
                    }
                }
                .padding(.horizontal, DeviceClass.current == .phone ? 16 : 40)
                .padding(.top, DeviceClass.current == .tv ? 30 : 20)
            }
            .frame(height: Self.stageHeight, alignment: .bottom)
            #if os(tvOS)
            .focusSection()
            #endif
        }
        .frame(height: Self.stageHeight, alignment: .bottom)
    }

    // MARK: - Facts

    /// What `CastLineup`'s fact card says, as chips beside the header: age at
    /// release, birthplace, what else of theirs is here, the Oscar. Absent
    /// rather than invented, and a small spinner while the person loads.
    @ViewBuilder private var factChips: some View {
        if let member = shown {
            let person = people[member.id]
            let facts = CastFacts.facts(for: member, person: person, releaseYear: releaseYear,
                                         otherCredits: creditCounts[member.id])
            HStack(spacing: 10) {
                ForEach(facts.prefix(3)) { fact in
                    PosterChip(text: fact.text, inverted: fact.id == "oscar",
                               size: DeviceClass.current == .tv ? 24 : 13)
                }
                if person == nil {
                    ProgressView().controlSize(.small).tint(Palette.posterTeal)
                }
            }
            .id(member.id)
            .transition(.posterSlap)
            .animation(.spring(response: 0.36, dampingFraction: 0.6), value: member.id)
        }
    }

    private func select(_ member: CastMember) {
        #if os(tvOS)
        onSelect(member)
        #else
        if member.id == spotlightId {
            onSelect(member)
        } else {
            tappedId = member.id
            lastShownId = member.id
        }
        #endif
    }

    private func load(_ member: CastMember) async {
        // Debounced: the remote crosses six figures in a second.
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

/// One person on the stage: the cut-out (or the photo sticker standing in for
/// it), their name tag across the chest.
struct PosterCastFigure: View {
    let member: CastMember
    let tint: Color
    let focused: Bool
    var lean: Double = 0

    @State private var cutout: UIImage?

    private static var width: CGFloat {
        switch DeviceClass.current { case .tv: return 232; case .pad: return 150; case .phone: return 104 }
    }
    private static var height: CGFloat {
        switch DeviceClass.current { case .tv: return 330; case .pad: return 215; case .phone: return 150 }
    }
    private static var tagSize: (focused: CGFloat, resting: CGFloat) {
        switch DeviceClass.current { case .tv: return (26, 19); case .pad: return (17, 12); case .phone: return (13, 9) }
    }
    private static let focusScale: CGFloat = 1.22

    var body: some View {
        ZStack(alignment: .bottom) {
            portrait
                .frame(width: Self.width, height: Self.height, alignment: .bottom)
            PosterStickerTag(name: member.name,
                             sub: focused ? member.role : nil,
                             nameColor: focused ? tint : Palette.posterInk,
                             size: focused ? Self.tagSize.focused : Self.tagSize.resting,
                             tilt: .degrees(-3))
                // At rest a tag stays inside the figure's own middle — the
                // outer 28pt each side is under a neighbour — and a long name
                // shrinks to fit. The focused figure is scaled up and in
                // front, so its tag may run a little wider than the figure.
                .frame(maxWidth: focused ? Self.width * 1.12 : Self.width * 0.74)
                .padding(.bottom, DeviceClass.current == .tv ? 26 : 12)
        }
        .frame(width: Self.width, height: Self.height * Self.focusScale, alignment: .bottom)
        .scaleEffect(focused ? Self.focusScale : 1, anchor: .bottom)
        .spring(focused)
        .task(id: member.imageURL) {
            guard PortraitCutoutCache.isSupported, let url = member.imageURL else { return }
            cutout = await PortraitCutoutCache.shared.cutout(for: url)
        }
    }

    @ViewBuilder private var portrait: some View {
        if let cutout {
            Image(uiImage: cutout)
                .resizable()
                .scaledToFit()
                .grayscale(focused ? 0 : 1)
                .brightness(focused ? 0 : -0.08)
                // A sticker's white edge around the focused figure — four
                // hard shadows, redrawn only when focus changes.
                .shadow(color: focused ? .white : .clear, radius: 0, x: 3, y: 0)
                .shadow(color: focused ? .white : .clear, radius: 0, x: -3, y: 0)
                .shadow(color: focused ? .white : .clear, radius: 0, x: 0, y: -3)
                .shadow(color: focused ? tint.opacity(0.7) : .clear, radius: 22, y: 0)
        } else {
            photoSticker
        }
    }

    /// The stand-in: the headshot in a white frame, tilted, or the monogram
    /// where there is no photo at all.
    @ViewBuilder private var photoSticker: some View {
        Group {
            if let string = member.imageURL, let url = URL(string: string) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        monogram
                    }
                }
            } else {
                monogram
            }
        }
        .frame(width: Self.width * 0.8, height: Self.height * 0.72)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white, lineWidth: 6))
        .grayscale(focused ? 0 : 1)
        .rotationEffect(.degrees(focused ? 0 : lean))
        .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
        .padding(.bottom, Self.height * 0.18)
    }

    private var monogram: some View {
        let hue = Double(member.id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % 360) / 360
        return ZStack {
            LinearGradient(colors: [Color(hue: hue, saturation: 0.45, brightness: 0.55),
                                    Color(hue: hue, saturation: 0.5, brightness: 0.22)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(member.name.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined())
                .font(Display.font(72))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

private extension View {
    func spring(_ value: Bool) -> some View {
        animation(.spring(response: 0.34, dampingFraction: 0.62), value: value)
    }
}

/// The figure draws its own focus, so the button style stays out of the way.
private struct PosterFigureButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.9 : 1)
    }
}
