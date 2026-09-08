import SwiftUI
import Combine
import JellyTVKit

#if os(iOS)
/// The phone's link to its paired Apple TV — the sending half of remote control.
///
/// **There is no connection here to keep alive.** The phone and the TV never talk to
/// each other: the TV holds the Jellyfin websocket it already holds (`RemoteControl`),
/// this object posts to Jellyfin's `/Sessions/{id}/…` through the server, and Jellyfin
/// relays. The pairing is a *record* (`YsojAPI.RemotePairing`), mirrored locally so the
/// TV bar appears before any network answers, and "is the TV up?" is one
/// `GET /Sessions?deviceId=` — which is why reopening the app finds the link ready in
/// well under a second, and why there is nothing to "reconnect".
///
/// What it does, in order of how often: keeps `presence` truthful (every ten seconds,
/// every second and a half while the remote sheet is open); polls for a TV looking for
/// a remote (`pendingBeacon` → the pairing prompt); and, installed as
/// `AppState.playbackRouter`, sends every play in the app to the TV while it is on and
/// *Send to TV* is on — YouTube's model, the one the owner asked for.
@MainActor
final class TVLink: ObservableObject {

    enum Presence: Equatable {
        /// No TV paired — nothing to draw.
        case none
        /// A pairing exists and the first `/Sessions` answer is on its way.
        case checking
        /// The TV app is open with its socket up; this is its session right now.
        case online(JellyfinAPI.SessionInfo)
        /// Paired, but the TV app is not open (or its receiver is off).
        case offline
    }

    @Published private(set) var pairings: [YsojAPI.RemotePairing]
    @Published private(set) var activePairing: YsojAPI.RemotePairing?
    @Published private(set) var presence: Presence = .none
    /// Where the TV is in its film, interpolated between its reports.
    @Published private(set) var clock: RemoteClock?
    /// Every paired TV that is up right now, by device id. One `/Sessions` call answers
    /// for all of them, which is what lets the remote follow the TV that is on.
    @Published private(set) var sessionsByTV: [String: JellyfinAPI.SessionInfo] = [:]
    /// Whether plays go to the TV while it is on. Default on after pairing — that is
    /// what pairing was for — and a switch in the bar and in Settings turns it off for
    /// an evening on the couch with the phone.
    @Published var sendToTV: Bool {
        didSet { UserDefaults.standard.set(sendToTV, forKey: Self.sendToTVKey) }
    }
    /// A TV that is looking for a remote right now — the pairing prompt's subject.
    @Published private(set) var pendingBeacon: YsojAPI.RemoteBeacon?
    @Published private(set) var isPairing = false
    /// A line worth showing for a beat: what a press just did, or why it did not.
    @Published private(set) var notice: String?
    /// The remote sheet. Tracked here because the presence poll speeds up while it is up.
    @Published var isSheetPresented = false {
        didSet { restartPresenceLoop() }
    }

    private weak var appState: AppState?
    private var deviceId = ""
    private var presenceTask: Task<Void, Never>?
    private var beaconTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var capabilitiesSink: AnyCancellable?
    private var isForeground = true
    private var foregroundedAt = Date()
    /// Until when a transport press is believed over the server: the TV reports at once,
    /// but a poll that lands in between still carries the *pre-press* state, and adopting
    /// it flipped the glyph play → pause → play within two seconds.
    private var optimisticUntil = Date.distantPast
    /// Read once, written on change — it feeds `showsBar`, which every render asks.
    private var wasOnline: Bool {
        didSet { if wasOnline != oldValue { UserDefaults.standard.set(wasOnline, forKey: Self.wasOnlineKey) } }
    }
    /// Beacons the user said "Not now" to. Session-only: the TV's next press is a new
    /// beacon, and a new prompt.
    private var dismissedBeaconIds: Set<String> = []

    static let sendToTVKey = "jelly:remote.sendToTV"
    static let activeTVKey = "jelly:remote.activeTV"
    static let wasOnlineKey = "jelly:remote.wasOnline"
    static let lastUsedKey = "jelly:remote.lastUsed"

    /// The TV the owner picked by hand — sticky while it is up, cleared when it goes
    /// off so the rule takes over cleanly.
    private var manualTV: String? {
        didSet { UserDefaults.standard.set(manualTV, forKey: Self.activeTVKey) }
    }
    /// When each TV was last driven from this phone — the tie-breaker when two are on
    /// and neither is playing.
    private var lastUsed: [String: Date] {
        didSet {
            UserDefaults.standard.set(lastUsed.mapValues(\.timeIntervalSince1970), forKey: Self.lastUsedKey)
        }
    }

    init() {
        let defaults = UserDefaults.standard
        pairings = RemotePairingStore.load()
        sendToTV = defaults.object(forKey: Self.sendToTVKey) as? Bool ?? true
        wasOnline = defaults.bool(forKey: Self.wasOnlineKey)
        manualTV = defaults.string(forKey: Self.activeTVKey)
        lastUsed = (defaults.dictionary(forKey: Self.lastUsedKey) as? [String: Double] ?? [:])
            .mapValues { Date(timeIntervalSince1970: $0) }
    }

    // MARK: - Reading it

    /// The active TV's name, with its id tail when another paired TV shares the name.
    var tvName: String { activePairing?.tvDisplayName(among: pairings) ?? "TV" }

    /// The paired TVs that are up right now, in pairing order.
    var onlinePairings: [YsojAPI.RemotePairing] {
        pairings.filter { sessionsByTV[$0.tvDeviceId] != nil }
    }

    /// More than one TV to point at — the bar shows the switch glyph.
    var canSwitch: Bool { onlinePairings.count > 1 }

    func isOnline(_ pairing: YsojAPI.RemotePairing) -> Bool {
        sessionsByTV[pairing.tvDeviceId] != nil
    }

    var session: JellyfinAPI.SessionInfo? {
        if case .online(let session) = presence { return session }
        return nil
    }

    var isOnline: Bool { session != nil }

    /// The one question `requestPlayback` asks.
    var routesToTV: Bool { sendToTV && isOnline }

    /// Whether the bar should exist at all: a pairing, on a server that can pair.
    var hasTV: Bool { activePairing != nil }

    /// Whether the bar is drawn: the TV is up, or it was last time and the first answer
    /// is still on its way — so reopening the app shows the bar at once rather than a
    /// beat later, without flashing one on every launch while the TV is off for a week.
    var showsBar: Bool {
        if isOnline { return true }
        if case .checking = presence { return wasOnline }
        return false
    }

    var nowPlaying: JellyfinAPI.JellyfinItem? { session?.nowPlayingItem }

    /// Nothing playing reads as paused; something playing with no report yet reads as
    /// playing — a bar saying "Playing on…" beside a play glyph contradicts itself.
    var isPaused: Bool { clock?.isPaused ?? (nowPlaying == nil) }

    /// The TV's current position and runtime, in seconds, for the readout.
    func position(at now: Date) -> (current: Double, duration: Double)? {
        guard let clock, let item = nowPlaying else { return nil }
        let duration = Double(item.runTimeTicks ?? 0) / 10_000_000
        return (clock.positionSeconds(at: now, runtimeSeconds: duration > 0 ? duration : nil), duration)
    }

    // MARK: - Lifecycle

    /// The server connection came up. The local mirror is trusted at once — the bar
    /// draws and the presence check starts before the server has said anything — and
    /// the server's list replaces it as soon as it arrives.
    func attach(_ appState: AppState, deviceId: String) {
        self.appState = appState
        self.deviceId = deviceId
        let mine = pairings.filter { $0.remoteDeviceId == deviceId }
        activePairing = mine.first { $0.tvDeviceId == manualTV } ?? mine.first
        presence = activePairing == nil ? .none : .checking
        clock = nil
        sessionsByTV = [:]
        // Capabilities land a moment after `configure()`; the beacon poll and the
        // server's pairing list both wait on them.
        capabilitiesSink = appState.$ysojCapabilities
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.restartBeaconLoop()
                Task { await self.refreshPairings() }
            }
        restartPresenceLoop()
        restartBeaconLoop()
    }

    func detach() {
        presenceTask?.cancel()
        beaconTask?.cancel()
        capabilitiesSink = nil
        appState = nil
        presence = .none
        clock = nil
        pendingBeacon = nil
    }

    /// Foreground is when a phone is a remote; in the background it polls nothing.
    func setForeground(_ active: Bool) {
        isForeground = active
        if active {
            foregroundedAt = Date()
            if activePairing != nil, presence == .none || presence == .offline { presence = .checking }
            Task { await refreshPairings() }
        }
        restartPresenceLoop()
        restartBeaconLoop()
    }

    // MARK: - Presence

    private func restartPresenceLoop() {
        presenceTask?.cancel()
        presenceTask = nil
        guard appState != nil, activePairing != nil, isForeground else { return }
        presenceTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.checkPresence()
                // Quick while the remote is open, unhurried while the TV is up, and in
                // between while waiting for it to come on.
                let seconds: Double = self.isSheetPresented ? 1.5 : (self.isOnline ? 10 : 5)
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    /// One `/Sessions` call for every paired TV, then the selection rule decides which
    /// one the remote points at. A TV coming on in the other room is seen here; the
    /// active one going off is followed here.
    func checkPresence() async {
        let mine = pairings.filter { $0.remoteDeviceId == deviceId }
        guard let client = appState?.jellyfinClient, !mine.isEmpty else {
            presence = .none
            clock = nil
            sessionsByTV = [:]
            return
        }
        do {
            let sessions = try await client.fetchSessions()
            let now = Date()
            var byTV: [String: JellyfinAPI.SessionInfo] = [:]
            for pairing in mine {
                if let session = TVPresence.session(forDevice: pairing.tvDeviceId, in: sessions),
                   TVPresence.isOnline(session) {
                    byTV[pairing.tvDeviceId] = session
                }
            }
            sessionsByTV = byTV
            let online = Set(byTV.keys)
            let playing = Set(byTV.filter { $0.value.nowPlayingItem != nil }.keys)
            // A hand-picked TV that went off releases the pick, or the rule could never
            // follow the other one.
            if let manual = manualTV, !online.contains(manual) { manualTV = nil }

            let previous = activePairing
            let chosen = TVSelection.choose(pairings: mine, online: online, playing: playing,
                                            manual: manualTV, lastUsed: lastUsed)
            if let chosen {
                if chosen.tvDeviceId != previous?.tvDeviceId {
                    activePairing = chosen
                    clock = nil
                    // Followed over from a TV that went off (not the first sighting).
                    if let previous, isOnlineState(presence), previous.tvDeviceId != chosen.tvDeviceId {
                        show("Now on \(chosen.tvDisplayName(among: mine))")
                    }
                }
                let session = byTV[chosen.tvDeviceId]!
                presence = .online(session)
                let fresh = clock?.updated(with: session, at: now) ?? RemoteClock(session: session, at: now)
                // Inside the optimistic window a report that still says the *old* paused
                // state is the one the press is about to change; keep the press.
                let stale = now < optimisticUntil && clock != nil && fresh != nil
                    && fresh?.itemId == clock?.itemId && fresh?.isPaused != clock?.isPaused
                if !stale { clock = fresh }
                wasOnline = true
            } else {
                presence = .offline
                clock = nil
                wasOnline = false
            }
        } catch {
            // A failed poll is not a TV going away; only a first answer that never came
            // is worth changing the bar for.
            if presence == .checking { presence = .offline }
        }
    }

    private func isOnlineState(_ presence: Presence) -> Bool {
        if case .online = presence { return true }
        return false
    }

    private func touchLastUsed() {
        guard let active = activePairing else { return }
        lastUsed[active.tvDeviceId] = Date()
    }

    // MARK: - Pairing

    private var pollSeconds: Double { Double(appState?.remotePollSeconds ?? 3) }

    private func restartBeaconLoop() {
        beaconTask?.cancel()
        beaconTask = nil
        guard let appState, appState.offersRemote, isForeground else { return }
        beaconTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.pollBeacons()
                // Quick for the two minutes after coming to the foreground — the TV was
                // pressed, the phone was picked up — and lazy after that.
                let recent = Date().timeIntervalSince(self.foregroundedAt) < 120
                try? await Task.sleep(for: .seconds(recent ? self.pollSeconds : 10))
            }
        }
    }

    private func pollBeacons() async {
        // A prompt for a beacon the TV has already given up on would only lead to a
        // refusal; drop it when its two minutes are up.
        if let pending = pendingBeacon, Date().timeIntervalSince1970 >= pending.expiresAt {
            pendingBeacon = nil
        }
        guard let ysoj = appState?.ysojClient, pendingBeacon == nil, !isPairing else { return }
        guard let beacons = try? await ysoj.fetchRemoteBeacons() else { return }
        if let first = beacons.first(where: { $0.isWaiting && !dismissedBeaconIds.contains($0.id) }) {
            pendingBeacon = first
        }
    }

    func declinePairing() {
        if let beacon = pendingBeacon { dismissedBeaconIds.insert(beacon.id) }
        pendingBeacon = nil
    }

    func acceptPairing() async {
        guard let beacon = pendingBeacon, let ysoj = appState?.ysojClient else { return }
        guard Date().timeIntervalSince1970 < beacon.expiresAt else {
            pendingBeacon = nil
            show("\(beacon.tvName) stopped looking. Press Pair a remote on it again.")
            return
        }
        isPairing = true
        defer { isPairing = false }
        do {
            let pairing = try await ysoj.acceptRemotePairing(beaconId: beacon.id,
                                                             deviceName: DeviceIdentity.name)
            upsert(pairing)
            select(pairing)
            sendToTV = true
            pendingBeacon = nil
            show("Paired with \(pairing.tvName)")
        } catch {
            pendingBeacon = nil
            dismissedBeaconIds.insert(beacon.id)
            show(ServerMessage.text(for: error, fallback: "Couldn't pair with \(beacon.tvName)."))
        }
    }

    /// Which TV the bar is about, when there is more than one.
    /// A pick by hand, which the rule keeps for as long as that TV is up.
    func select(_ pairing: YsojAPI.RemotePairing) {
        manualTV = pairing.tvDeviceId
        activePairing = pairing
        clock = nil
        if let session = sessionsByTV[pairing.tvDeviceId] {
            presence = .online(session)
        } else {
            presence = .checking
        }
        restartPresenceLoop()
    }

    /// Flash a banner on that TV's screen — the answer to "which of the two is this?".
    func identify(_ pairing: YsojAPI.RemotePairing) {
        guard let client = appState?.jellyfinClient else { return }
        guard let session = sessionsByTV[pairing.tvDeviceId] else {
            show("\(pairing.tvDisplayName(among: pairings)) isn't on right now")
            return
        }
        let name = pairing.tvDisplayName(among: pairings)
        Task {
            do {
                try await client.sendMessage(toSession: session.id, header: "Why.So.Jelly?",
                                             text: "👋 This is the TV your \(DeviceIdentity.name) is pointing at")
                show("Look at \(name)")
            } catch {
                show("Couldn't reach \(name)")
            }
        }
    }

    /// Name a TV — "Living Room", "Bedroom". Saved on the server so every phone agrees.
    func rename(_ pairing: YsojAPI.RemotePairing, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let ysoj = appState?.ysojClient else { return }
        do {
            let renamed = try await ysoj.renameRemotePairing(id: pairing.id, name: trimmed)
            pairings = pairings.map { row in
                guard row.tvDeviceId == renamed.tvDeviceId else { return row }
                return YsojAPI.RemotePairing(id: row.id, tvDeviceId: row.tvDeviceId, tvName: renamed.tvName,
                                             remoteDeviceId: row.remoteDeviceId, remoteName: row.remoteName,
                                             createdAt: row.createdAt, lastSeenAt: row.lastSeenAt)
            }
            persistPairings()
            if activePairing?.tvDeviceId == renamed.tvDeviceId {
                activePairing = pairings.first { $0.id == activePairing?.id }
            }
        } catch {
            show(ServerMessage.text(for: error, fallback: "Couldn't rename \(pairing.tvName)."))
        }
    }

    func forget(_ pairing: YsojAPI.RemotePairing) async {
        pairings.removeAll { $0.id == pairing.id }
        persistPairings()
        sessionsByTV[pairing.tvDeviceId] = nil
        if manualTV == pairing.tvDeviceId { manualTV = nil }
        if activePairing?.id == pairing.id {
            activePairing = pairings.first { $0.remoteDeviceId == deviceId }
            presence = activePairing == nil ? .none : .checking
            clock = nil
            restartPresenceLoop()
        }
        if let ysoj = appState?.ysojClient {
            do {
                try await ysoj.deleteRemotePairing(id: pairing.id)
            } catch {
                // The next server refresh would bring it back; say so rather than let
                // "forgotten" quietly un-happen.
                show("Couldn't forget \(pairing.tvName) on the server — it may come back.")
            }
        }
    }

    /// The server's list replaces the mirror — a TV that forgot this phone disappears
    /// from the bar here too.
    func refreshPairings() async {
        guard let appState, appState.offersRemote, let ysoj = appState.ysojClient else { return }
        guard let remote = try? await ysoj.fetchRemotePairings() else { return }
        let mine = remote.filter { $0.remoteDeviceId == deviceId }
        pairings = mine
        persistPairings()
        if let active = activePairing, let refreshed = mine.first(where: { $0.id == active.id }) {
            activePairing = refreshed
        } else {
            activePairing = mine.first { $0.tvDeviceId == manualTV } ?? mine.first
            presence = activePairing == nil ? .none : .checking
            clock = nil
        }
        restartPresenceLoop()
    }

    private func upsert(_ pairing: YsojAPI.RemotePairing) {
        pairings.removeAll { $0.id == pairing.id || $0.tvDeviceId == pairing.tvDeviceId }
        pairings.append(pairing)
        persistPairings()
    }

    private func persistPairings() {
        RemotePairingStore.save(pairings)
    }

    // MARK: - Playing there

    /// `AppState.playbackRouter`. True means the TV has it; false means play here.
    func route(_ request: PlaybackRequest) -> Bool {
        guard routesToTV, let session, let client = appState?.jellyfinClient,
              let command = RemoteDispatch.playCommand(for: request) else { return false }
        let name = tvName
        let title = request.items.indices.contains(request.startIndex)
            ? request.items[request.startIndex].title : ""
        touchLastUsed()
        Task {
            do {
                try await client.sendPlay(toSession: session.id, itemIds: command.itemIds,
                                          startIndex: command.startIndex,
                                          startPositionTicks: command.startPositionTicks)
                show(title.isEmpty ? "Playing on \(name)" : "Playing “\(title)” on \(name)")
                // The TV takes a few seconds to resolve, start its transcode and post its
                // start — and its very first progress report can land *before* playback
                // begins, saying paused. A short burst of looks (verified: one look at
                // 1.5 s read that paused report and the ten-second loop left it there)
                // keeps the bar truthful through the whole start-up window.
                for delay in [1.5, 2.0, 2.0, 3.0] {
                    try? await Task.sleep(for: .seconds(delay))
                    await checkPresence()
                }
            } catch {
                show("Couldn't reach \(name) — playing here instead")
                appState?.activePlaybackRequest = request
            }
        }
        return true
    }

    // MARK: - Transport

    func togglePlayPause() {
        let now = Date()
        if let clock {
            self.clock = clock.optimistic(ticks: Int64(clock.positionSeconds(at: now) * 10_000_000),
                                          isPaused: !clock.isPaused, at: now)
            optimisticUntil = now.addingTimeInterval(2)
        }
        send(.playPause)
    }

    /// ±30 s: the TV maps `Rewind`/`FastForward` onto its own coalesced 30-second jump.
    func jump(by seconds: Double) {
        let now = Date()
        if let clock {
            let target = max(0, clock.positionSeconds(at: now) + seconds)
            self.clock = clock.optimistic(ticks: Int64(target * 10_000_000),
                                          isPaused: clock.isPaused, at: now)
        }
        send(seconds < 0 ? .rewind : .fastForward)
    }

    /// An exact position — a scene the viewer tapped. Uncoalesced, like the player's own
    /// `seek(to:)`: the caller already knows the target.
    func seek(to seconds: Double) {
        let now = Date()
        if let clock {
            self.clock = clock.optimistic(ticks: Int64(max(0, seconds) * 10_000_000),
                                          isPaused: clock.isPaused, at: now)
        }
        send(.seek, seekTicks: Int64(max(0, seconds) * 10_000_000))
    }

    func next() { send(.nextTrack) }
    func previous() { send(.previousTrack) }

    func stop() {
        clock = nil
        send(.stop)
    }

    private func send(_ command: PlayStateCommand, seekTicks: Int64? = nil) {
        guard let session, let client = appState?.jellyfinClient else { return }
        let name = tvName
        touchLastUsed()
        Task {
            do {
                try await client.sendPlaystate(toSession: session.id, command, seekPositionTicks: seekTicks)
                // The TV reports at once on pause/resume/seek; give it a beat and read
                // back the truth so the optimistic clock above is corrected, not trusted.
                try? await Task.sleep(for: .milliseconds(700))
                await checkPresence()
            } catch {
                show("Couldn't reach \(name)")
                await checkPresence()
            }
        }
    }

    // MARK: - Fixtures

    /// `RT_SHOW_REMOTE=bar|sheet|prompt`. Stops the polls so the fixture is not replaced
    /// by the real answer a second later.
    func seedDemo(_ mode: String) {
        presenceTask?.cancel()
        beaconTask?.cancel()
        capabilitiesSink = nil
        let decoder = JSONDecoder()
        switch mode {
        case "prompt":
            pendingBeacon = try? decoder.decode(YsojAPI.RemoteBeacon.self, from: Data("""
            {"id":"beacon_demo","tvDeviceId":"tv-demo","tvName":"Living Room","expiresAt":0,
             "state":"waiting","pairing":null,"sameNetwork":true}
            """.utf8))
        case "bar", "sheet":
            let pairing = YsojAPI.RemotePairing(id: "pair_demo", tvDeviceId: "tv-demo",
                                                tvName: "Living Room", remoteDeviceId: deviceId,
                                                remoteName: DeviceIdentity.name)
            pairings = [pairing]
            activePairing = pairing
            let session = try? decoder.decode(JellyfinAPI.SessionInfo.self, from: Data("""
            {"Id":"demo","DeviceId":"tv-demo","DeviceName":"Living Room","IsActive":true,
             "SupportsRemoteControl":true,
             "NowPlayingItem":{"Id":"d1","Name":"The Long Goodbye","Type":"Episode",
               "SeriesName":"Late Shift","ParentIndexNumber":2,"IndexNumber":4,
               "RunTimeTicks":33180000000},
             "PlayState":{"PositionTicks":7620000000,"IsPaused":false,"CanSeek":true}}
            """.utf8))
            if let session {
                presence = .online(session)
                sessionsByTV = ["tv-demo": session]
                clock = RemoteClock(session: session, at: Date())
                wasOnline = true
            }
            // Setting the sheet flag re-arms the presence loop through its `didSet`;
            // the cancel *after* it is what keeps the fixture from being replaced by the
            // real answer a second later.
            isSheetPresented = mode == "sheet"
            presenceTask?.cancel()
        default:
            break
        }
    }

    // MARK: - Notice

    private func show(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }
}
#endif
