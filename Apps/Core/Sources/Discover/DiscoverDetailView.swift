import SwiftUI
import JellyTVKit

/// A discovered title as the app's own one-sheet — the same layout `MovieDetailView`
/// uses, with **download where Play would be**.
///
/// Deliberately not a second detail language. A film's page should look like a film's
/// page whether the file is already on the server or still on somebody else's tracker;
/// the only honest difference is what the big lit bar at the bottom does. So this reuses
/// `PosterBloom`, `DetailSpine`, `OneSheetPoster`, `HairlineRail`, `CastBand` and
/// `NeonTransportBar` unchanged — the poster and bloom already accept an `http` URL, so
/// a TMDB poster drops straight in.
///
/// **This is the screen that carries the granularity requirement.** A film downloads
/// whole; a series offers each season and the whole show, as `YsojAPI.DownloadScope`.
/// The server validates every scope against the title's real seasons before making a job,
/// so "season 9" of a three-season show is refused at the plan rather than an hour into a
/// search that could never succeed.
///
/// **Nothing starts without a confirm.** A scope produces a *plan* — what would be
/// fetched, roughly how big, and any warnings — and only pressing through that plan
/// creates a job. A press that silently commits 18 GB of somebody's disk is not a press
/// to make by accident from a sofa.
struct DiscoverDetailView: View {
    let ref: String
    @ObservedObject var store: DiscoverStore
    let onClose: () -> Void

    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var appState: AppState

    @State private var detail: YsojAPI.DiscoverDetail?
    /// Set when the detail fetch comes back empty. Without it a failure left the page on
    /// a spinner forever, which reads as a hang rather than as an answer — the same
    /// mistake the shelves avoid by distinguishing "unavailable" from "empty".
    @State private var detailFailed = false
    @State private var selectedSeason: Int?
    /// nil = the whole show. Only meaningful for a series.
    @State private var wantsWholeSeries = false
    @State private var plan: YsojAPI.DownloadPlan?
    @State private var isPlanning = false
    @State private var tint: Color = .clear
    @State private var showingTrailer = false

    #if os(tvOS)
    @FocusState private var focus: Field?
    private enum Field: Hashable { case download, trailer, season(Int), whole }
    #endif

    var body: some View {
        ZStack {
            PosterBloom(image: detail?.posterURLString, artwork: artwork, tint: effectiveTint)
            HStack(spacing: 0) {
                DetailSpine(genreLabel: genreLabel,
                            markerTop: markerTop,
                            markerBottom: "GET",
                            onBack: onClose,
                            accent: effectiveTint)
                content
            }
            .ignoresSafeArea()
            // Off the focus pool while a sheet is up, or the plan's Start sits
            // focus-adjacent to the season chips beneath it.
            .disabled(plan != nil || showingTrailer)

            #if os(iOS)
            if showingTrailer, let trailer {
                TrailerSheet(trailer: trailer, accent: effectiveTint,
                             onClose: { showingTrailer = false })
                    .zIndex(15)
            }
            #endif

            if let plan {
                DownloadPlanSheet(
                    plan: plan, accent: effectiveTint,
                    onConfirm: { Task { await confirm(plan) } },
                    onCancel: { self.plan = nil }
                )
                .zIndex(20)
            }
        }
        .background(Palette.page)
        // Keyed on the ref: a page that is handed another title without passing through
        // nil must reload, or it would plan a download for the wrong one.
        .task(id: ref) {
            detailFailed = false
            plan = nil
            showingTrailer = false
            wantsWholeSeries = false
            detail = await store.loadDetail(ref: ref)
            detailFailed = detail == nil
            selectedSeason = detail?.downloadableSeasons.first?.seasonNumber
            // Focus before the tint: the tint downloads the whole poster, and until it
            // returned nothing on the page was focused, so the remote drove the screen
            // underneath.
            #if os(tvOS)
            focus = .download
            #endif
            await loadTint()
        }
        #if os(tvOS)
        .onExitCommand { plan == nil ? onClose() : (plan = nil) }
        #endif
    }

    // MARK: - The one-sheet

    @ViewBuilder
    private var content: some View {
        if let detail {
            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 0) {
                    let posterH = posterHeight(in: geo.size)
                    let posterW = OneSheetPoster.width(for: posterH)
                    // Both columns sized explicitly — left to negotiate inside a
                    // GeometryReader the text column takes its single-line ideal width
                    // from the synopsis and runs off the right edge, same as the movie
                    // one-sheet had to solve.
                    let infoW = max(340, geo.size.width - spineAllowance - posterW - columnGap)
                    HStack(alignment: .top, spacing: columnGap) {
                        OneSheetPoster(image: detail.posterURLString, artwork: artwork,
                                       height: posterH)
                        info(detail, height: posterH, width: infoW)
                    }
                    .padding(.top, 34)

                    if !detail.cast.isEmpty {
                        Spacer(minLength: 20)
                        CastBand(cast: castMembers(detail))
                    }
                }
                .padding(pagePadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else if detailFailed {
            LibraryEmptyState(
                message: "Couldn't load this title",
                hint: "Its source didn't answer. Go back and try another, or try again in a moment.",
                systemImage: "exclamationmark.triangle",
                centered: true
            )
        } else {
            ProgressView().controlSize(.large).tint(theme.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The text column, held to the poster's exact height so the download bar lands on
    /// the poster's bottom edge rather than floating.
    private func info(_ detail: YsojAPI.DiscoverDetail,
                      height: CGFloat, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(detail.sourceName.uppercased())
                    .font(Typography.font(eyebrowSize, .heavy)).tracking(4)
                    .foregroundStyle(effectiveTint)
                if detail.alreadyOwned {
                    Label("IN YOUR LIBRARY", systemImage: "checkmark.circle.fill")
                        .font(Typography.font(eyebrowSize, .heavy)).tracking(2)
                        .foregroundStyle(Color(hex: "#58D399"))
                }
            }
            .lineLimit(1)

            Text(detail.title)
                .font(Typography.font(titleSize, .black))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.42).lineSpacing(-12)
                .padding(.top, 10)

            HairlineRail {
                RailCell(label: "Rating", first: true) { railValue(ratingText) }
            } second: {
                RailCell(label: detail.isSeries ? "Episodes" : "Runtime") { railValue(lengthText) }
            } third: {
                RailCell(label: "Year") { railValue(detail.year.map(String.init)) }
            } fourth: {
                RailCell(label: "Genre") { railValue(detail.genres.first) }
            }
            .padding(.top, 24)

            if !detail.overview.isEmpty {
                Text(detail.overview)
                    .font(Typography.font(synopsisSize, .regular))
                    .foregroundStyle(Palette.text(0.74))
                    .lineSpacing(7).lineLimit(4)
                    .padding(.top, 22)
            }

            Spacer(minLength: 20)

            if detail.isSeries { seasonPicker(detail) }
            downloadBar(detail)
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    // MARK: - What to get

    /// Season chips plus "Whole show" — the granularity choice, in the same chip language
    /// the library screens use for filters.
    @ViewBuilder
    private func seasonPicker(_ detail: YsojAPI.DiscoverDetail) -> some View {
        let seasons = detail.downloadableSeasons
        if seasons.isEmpty {
            Text("This source doesn't list seasons for this show yet, so there's nothing to choose from.")
                .font(Typography.font(synopsisSize - 2, .medium))
                .foregroundStyle(Palette.text(0.5))
                .padding(.bottom, 14)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("WHAT TO GET")
                    .font(Mono.font(eyebrowSize - 2, .bold)).tracking(2.6)
                    .foregroundStyle(Palette.text(0.45))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(seasons) { season in
                            LibraryFilterChip(
                                label: season.name,
                                isOn: !wantsWholeSeries && selectedSeason == season.seasonNumber,
                                action: {
                                    wantsWholeSeries = false
                                    selectedSeason = season.seasonNumber
                                },
                                accent: effectiveTint
                            )
                            #if os(tvOS)
                            .focused($focus, equals: .season(season.seasonNumber))
                            #endif
                        }
                        if seasons.count > 1 {
                            LibraryFilterChip(
                                label: "Whole show",
                                isOn: wantsWholeSeries,
                                action: { wantsWholeSeries = true },
                                accent: effectiveTint
                            )
                            #if os(tvOS)
                            .focused($focus, equals: .whole)
                            #endif
                        }
                    }
                    .padding(.vertical, 4)
                }
                .horizontalEdgeFade()
                #if os(tvOS)
                // Scoped to this row alone: without it, Left/Right at the row's edge lets
                // the focus engine search the whole screen and jump somewhere unrelated.
                .focusSection()
                #endif
            }
            .padding(.bottom, 14)
        }
    }

    /// The same lit bar as the movie one-sheet's Play control, doing the one thing this
    /// page is for. `progress: 0` — there is nothing to resume; the bar is an action, and
    /// its readout carries what the press is about to cost.
    @ViewBuilder
    private func downloadBar(_ detail: YsojAPI.DiscoverDetail) -> some View {
        if !appState.canStartDownloads {
            Text("Only the owner of this server can add to the library.")
                .font(Typography.font(synopsisSize, .semibold))
                .foregroundStyle(Palette.text(0.5))
        } else {
            #if os(tvOS)
            // tvOS has no readout on this bar, on purpose: the iPad's TRAILER / AUDIO /
            // SUBS items aren't settings this app has, and unlit glass nobody can select
            // reads as broken from across a room. So the bar is the one control here.
            HStack(spacing: 18) {
                TVNeonPlayBar(
                    icon: isPlanning ? "hourglass" : "arrow.down.circle.fill",
                    label: isPlanning ? "Checking…" : "Download",
                    sub: scopeSubtitle(detail),
                    progress: 0,
                    tint: effectiveTint,
                    action: { Task { await makePlan(detail) } }
                )
                .frame(maxWidth: 420)
                .disabled(isPlanning)
                .focused($focus, equals: .download)

                // The YouTube app, or nothing: tvOS has no browser, so the control only
                // exists when that app is installed to claim the link.
                if let trailer, TrailerAvailability.canOpen(trailer) {
                    Button { TrailerAvailability.open(trailer) } label: {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(effectiveTint)
                            .frame(width: 84, height: 84)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(effectiveTint.opacity(0.14))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(effectiveTint.opacity(0.45), lineWidth: 1.5)
                                    )
                            )
                    }
                    .buttonStyle(FocusScaleStyle(scale: 1.08, cornerRadius: 16))
                    .focused($focus, equals: .trailer)
                    .accessibilityLabel("Play trailer in YouTube")
                }
            }
            #else
            // **The trailer is a button, not a readout item.** It lived in the bar's
            // readout first, which was wrong: that row is a *status* display — it lights
            // what is switched on — so an action with no value to light rendered as dim
            // grey text nobody could tell was pressable. Same failure as unlit glass on
            // tvOS, which is why both platforms now put it beside the bar instead.
            HStack(spacing: 14) {
            NeonTransportBar(
                icon: isPlanning ? "hourglass" : "arrow.down.circle.fill",
                label: isPlanning ? "Checking…" : "Download",
                sub: scopeSubtitle(detail),
                progress: 0,
                tint: effectiveTint,
                action: { Task { await makePlan(detail) } }
            ) {
                // The values alone, as chips. `NeonReadoutItem`'s label/value pair is
                // right for a *setting* whose name you need in order to read its state
                // ("AUDIO — EN 5.1"); here the values name themselves. "SOURCE TMDB"
                // said TMDB twice, and the labels were the loudest thing in the row.
                // No quality chip here: nothing has promised a quality until the plan
                // exists, and a chip saying "1080p" before then was an invented fact.
                HStack(spacing: 9) {
                    SpecChip(text: detail.sourceName, tint: effectiveTint)
                    if detail.alreadyOwned {
                        SpecChip(text: "OWNED", tint: Color(hex: "#58D399"), filled: true)
                    }
                }
            }
            .disabled(isPlanning)
            .layoutPriority(1)

            if let trailer, TrailerAvailability.canOpen(trailer) {
                Button { showingTrailer = true } label: {
                    // Icon-only, and narrow. With a label it crowded the bar enough to
                    // wrap "Download" onto two lines — and the bar is the primary action
                    // on this page, so it wins the space. The glyph plus its
                    // accessibility label carries the meaning.
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: isPhone ? 20 : 24, weight: .semibold))
                        .foregroundStyle(effectiveTint)
                        .frame(width: isPhone ? 54 : 64, height: isPhone ? 58 : 78)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(effectiveTint.opacity(0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(effectiveTint.opacity(0.45), lineWidth: 1.5)
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play trailer")
            }
            }
            #endif
        }
    }

    /// The one trailer worth offering, if the source carried one and this device can open
    /// it. Nil on a server that doesn't send the field, so the control isn't drawn at all.
    private var trailer: YsojAPI.Trailer? { detail?.bestTrailer }

    /// What the bar is about to fetch, in words — this is the only place the chosen scope
    /// is stated before the confirm sheet repeats it.
    private func scopeSubtitle(_ detail: YsojAPI.DiscoverDetail) -> String {
        guard detail.isSeries else {
            return [detail.year.map(String.init), detail.runtimeMinutes.map { "\($0) min" }]
                .compactMap { $0 }.joined(separator: " · ")
        }
        if wantsWholeSeries {
            let seasons = detail.downloadableSeasons
            let episodes = seasons.reduce(0) { $0 + $1.episodeCount }
            return episodes > 0
                ? "Whole show · \(seasons.count) seasons · \(episodes) episodes"
                : "Whole show"
        }
        guard let number = selectedSeason,
              let season = detail.downloadableSeasons.first(where: { $0.seasonNumber == number })
        else { return "Choose a season" }
        return season.episodeCount > 0
            ? "\(season.name) · \(season.episodeCount) episodes"
            : season.name
    }

    private func currentScope(_ detail: YsojAPI.DiscoverDetail) -> YsojAPI.DownloadScope? {
        guard detail.isSeries else { return .movie }
        if wantsWholeSeries { return .wholeSeries }
        guard let selectedSeason else { return nil }
        return .season(selectedSeason)
    }

    // MARK: - Plan / confirm

    private func makePlan(_ detail: YsojAPI.DiscoverDetail) async {
        guard let scope = currentScope(detail) else {
            store.actionError = "Choose which season to download."
            return
        }
        isPlanning = true
        defer { isPlanning = false }
        plan = await store.plan(ref: ref, scope: scope)
    }

    private func confirm(_ plan: YsojAPI.DownloadPlan) async {
        let started = await store.confirm(planId: plan.planId)
        self.plan = nil
        guard started else { return }
        await store.refreshDownloads()
        onClose()
    }

    // MARK: - Trimmings

    /// The poster's own colour, thrown across the screen — the same treatment the movie
    /// one-sheet uses, so a Discover page feels like the film's page and not a form.
    private func loadTint() async {
        guard let string = detail?.posterURLString, let url = URL(string: string) else { return }
        tint = await DominantColor.of(url: url, fallback: theme.accent)
    }

    private var effectiveTint: Color { tint == .clear ? theme.accent : tint }

    /// A deterministic per-title gradient, so a poster-less entry still has a ground to
    /// sit on rather than falling back to flat black.
    private var artwork: Artwork {
        let hue = Double(abs(ref.hashValue) % 360)
        return .gradient(l: 0.42, c: 0.11, hue: hue)
    }

    private var genreLabel: String {
        detail?.genres.first?.uppercased() ?? (detail?.isSeries == true ? "SERIES" : "FILM")
    }

    private var markerTop: String { detail?.isSeries == true ? "SERIES" : "FILM" }

    private var ratingText: String? {
        detail?.rating.map { String(format: "%.1f", $0) }
    }

    private var lengthText: String? {
        guard let detail else { return nil }
        if detail.isSeries {
            let episodes = detail.downloadableSeasons.reduce(0) { $0 + $1.episodeCount }
            let total = episodes > 0 ? episodes : (detail.episodeCount ?? 0)
            return total > 0 ? "\(total)" : nil
        }
        return detail.runtimeMinutes.map { "\($0) min" }
    }

    @ViewBuilder
    private func railValue(_ value: String?) -> some View {
        // Absent renders as a dash, never as an invented value — the same rule the
        // library heroes follow.
        Text(value?.isEmpty == false ? value! : "—")
            .font(Typography.font(railSize, .bold))
            .foregroundStyle(Palette.text(value?.isEmpty == false ? 0.9 : 0.3))
    }

    private func castMembers(_ detail: YsojAPI.DiscoverDetail) -> [CastMember] {
        detail.cast.enumerated().map { index, person in
            CastMember(id: "\(ref)#\(index)", name: person.name,
                       role: person.role.isEmpty ? nil : person.role,
                       imageURL: person.imageURLString,
                       isLead: index < 2)
        }
    }

    private func posterHeight(in size: CGSize) -> CGFloat {
        min(maxPosterHeight, max(260, size.height - posterInset))
    }

    // MARK: - Sizing

    #if os(tvOS)
    private var pagePadding: EdgeInsets { .init(top: 56, leading: 72, bottom: 48, trailing: 72) }
    private var spineAllowance: CGFloat { 150 }
    private var columnGap: CGFloat { 64 }
    private var maxPosterHeight: CGFloat { 700 }
    private var posterInset: CGFloat { 300 }
    private var titleSize: CGFloat { 96 }
    private var eyebrowSize: CGFloat { 17 }
    private var synopsisSize: CGFloat { 24 }
    private var railSize: CGFloat { 22 }
    #else
    private var isPhone: Bool { DeviceClass.current == .phone }
    private var pagePadding: EdgeInsets {
        isPhone ? .init(top: 20, leading: 18, bottom: 24, trailing: 18)
                : .init(top: 44, leading: 64, bottom: 40, trailing: 64)
    }
    private var spineAllowance: CGFloat { isPhone ? 40 : 128 }
    private var columnGap: CGFloat { isPhone ? 20 : 56 }
    private var maxPosterHeight: CGFloat { isPhone ? 300 : 560 }
    private var posterInset: CGFloat { isPhone ? 220 : 240 }
    private var titleSize: CGFloat { isPhone ? 40 : 88 }
    private var eyebrowSize: CGFloat { isPhone ? 12 : 15 }
    private var synopsisSize: CGFloat { isPhone ? 15 : 20 }
    private var railSize: CGFloat { isPhone ? 15 : 19 }
    #endif
}

/// The confirm sheet: what will be fetched, how big, and what to know before saying yes.
///
/// The warnings are why this exists rather than a one-press download. They carry what the
/// poster cannot show — that the title is already in the library, that this server's
/// engine is a stub and will fetch nothing, that "everything" means 200 episodes — and
/// they come from the server verbatim, because it is the side that knows.
struct DownloadPlanSheet: View {
    let plan: YsojAPI.DownloadPlan
    let accent: Color
    let onConfirm: () -> Void
    let onCancel: () -> Void

    #if os(tvOS)
    @FocusState private var confirmFocused: Bool
    #endif

    var body: some View {
        ZStack {
            Color.black.opacity(0.86).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                Text("CONFIRM DOWNLOAD")
                    .font(Mono.font(eyebrow, .bold)).tracking(3)
                    .foregroundStyle(accent)

                VStack(alignment: .leading, spacing: 6) {
                    Text(plan.title)
                        .font(Typography.font(titleSize, .heavy))
                        .foregroundStyle(Palette.text(0.95))
                        .lineLimit(2)
                    if let subtitle = plan.subtitle {
                        Text(subtitle)
                            .font(Typography.font(bodySize, .semibold))
                            .foregroundStyle(Palette.text(0.6))
                    }
                }

                HStack(spacing: 26) {
                    fact("SIZE", DownloadFormatting.bytes(plan.estimatedBytes) + " est.")
                    if plan.episodeCount > 0 { fact("EPISODES", "\(plan.episodeCount)") }
                    if let quality = plan.quality { fact("QUALITY", quality) }
                }

                ForEach(plan.warnings, id: \.self) { warning in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color(hex: "#E8B44A"))
                        Text(warning)
                            .font(Typography.font(bodySize, .medium))
                            .foregroundStyle(Palette.text(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 14) {
                    Button(action: onConfirm) {
                        Text("Start download")
                            .font(Typography.font(bodySize + 2, .heavy))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 28).padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(accent))
                    }
                    .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 13))
                    #if os(tvOS)
                    .focused($confirmFocused)
                    #endif

                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(Typography.font(bodySize + 2, .semibold))
                            .foregroundStyle(Palette.text(0.8))
                            .padding(.horizontal, 28).padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Palette.text(0.1)))
                    }
                    .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 13))
                }
                .padding(.top, 4)
            }
            .padding(sheetPadding)
            .frame(maxWidth: sheetWidth, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Palette.sheet)
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Palette.text(0.12), lineWidth: 1))
            )
        }
        #if os(tvOS)
        .onAppear { confirmFocused = true }
        .onExitCommand(perform: onCancel)
        #endif
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Mono.font(eyebrow - 2, .bold)).tracking(1.8)
                .foregroundStyle(Palette.text(0.38))
            Text(value)
                .font(Typography.font(bodySize + 1, .bold))
                .foregroundStyle(Palette.text(0.88))
        }
    }

    #if os(tvOS)
    private var sheetWidth: CGFloat { 900 }
    private var sheetPadding: CGFloat { 46 }
    private var titleSize: CGFloat { 40 }
    private var bodySize: CGFloat { 20 }
    private var eyebrow: CGFloat { 16 }
    #else
    private var sheetWidth: CGFloat { DeviceClass.current == .phone ? 340 : 560 }
    private var sheetPadding: CGFloat { DeviceClass.current == .phone ? 22 : 34 }
    private var titleSize: CGFloat { DeviceClass.current == .phone ? 24 : 30 }
    private var bodySize: CGFloat { DeviceClass.current == .phone ? 14 : 17 }
    private var eyebrow: CGFloat { DeviceClass.current == .phone ? 11 : 13 }
    #endif
}

/// A small technical readout on the one-sheet's action row — the source, the quality.
///
/// `Mono` because this is the "readout" voice the design system reserves for ids, counts
/// and keys, and a chip rather than a label/value pair because these values name
/// themselves: "SOURCE TMDB" said TMDB twice and made the label the loudest thing in the
/// row. Tinted from the poster, like everything else on this page, so it belongs to the
/// film rather than to the chrome.
struct SpecChip: View {
    let text: String
    let tint: Color
    /// A filled chip for the one state worth shouting (already in your library);
    /// outlined for ordinary facts, so a row of them stays quiet.
    var filled: Bool = false

    private var isPhone: Bool { DeviceClass.current == .phone }

    var body: some View {
        // Not `.uppercased()` — these values already carry their own casing, and forcing
        // it turned "1080p" into "1080P", which is not how anyone writes it.
        Text(text)
            .font(Mono.font(isPhone ? 10 : 12, .bold))
            .tracking(1.6)
            .foregroundStyle(filled ? Color.black : tint)
            .padding(.horizontal, isPhone ? 8 : 11)
            .padding(.vertical, isPhone ? 4 : 6)
            .background {
                Capsule(style: .continuous)
                    .fill(filled ? tint : tint.opacity(0.14))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(tint.opacity(filled ? 0 : 0.5), lineWidth: 1)
                    }
            }
            .shadow(color: tint.opacity(filled ? 0.5 : 0.25), radius: 8, y: 1)
    }
}
