import Foundation

// The sending half of remote control: a phone driving a TV.
//
// **A pairing is a record, not a connection.** The phone and the TV never talk to each
// other. The TV keeps the Jellyfin websocket it already holds (`RemoteControl`); the phone
// posts to Jellyfin's `/Sessions/{id}/Playing…`; Jellyfin relays. So there is nothing to
// "reconnect" — the Apple TV Remote's whole failure mode — and "is the TV ready?" is one
// `GET /Sessions?deviceId=` answered in tens of milliseconds. Everything in this file is
// the arithmetic around that, kept in the kit so it can be tested without a simulator.

extension JellyfinAPI {

    /// One row of `GET /Sessions` — another signed-in client, as the server sees it.
    ///
    /// Only the fields a remote needs. `SupportsRemoteControl` is the one that matters:
    /// Jellyfin computes it as "capabilities say media control **and** a websocket is
    /// open right now", which is the only truthful "the TV app is up" the server can give.
    /// `IsActive` alone is not — a session created by plain HTTP requests has no socket
    /// controller and reports `IsActive: true` forever (verified live). Neither is
    /// `LastActivityDate`: an idle socket never refreshes it (a session two hours quiet
    /// failed `activeWithinSeconds=30` while its socket was open).
    public struct SessionInfo: Decodable, Sendable, Equatable, Identifiable {
        public let id: String
        public let deviceId: String?
        public let deviceName: String?
        public let client: String?
        public let userId: String?
        public let isActive: Bool?
        public let supportsRemoteControl: Bool?
        public let supportsMediaControl: Bool?
        public let lastActivityDate: String?
        public let nowPlayingItem: JellyfinItem?
        public let playState: PlayState?

        public struct PlayState: Decodable, Sendable, Equatable {
            public let positionTicks: Int64?
            public let isPaused: Bool?
            public let canSeek: Bool?

            enum CodingKeys: String, CodingKey {
                case positionTicks = "PositionTicks"
                case isPaused = "IsPaused"
                case canSeek = "CanSeek"
            }
        }

        /// "S2 · E4" for an episode with both numbers, else nil.
        public var episodeMarker: String? { nowPlayingItem?.episodeMarker }

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case deviceId = "DeviceId"
            case deviceName = "DeviceName"
            case client = "Client"
            case userId = "UserId"
            case isActive = "IsActive"
            case supportsRemoteControl = "SupportsRemoteControl"
            case supportsMediaControl = "SupportsMediaControl"
            case lastActivityDate = "LastActivityDate"
            case nowPlayingItem = "NowPlayingItem"
            case playState = "PlayState"
        }
    }
}

/// Is a TV there to be driven, and which session is it?
public enum TVPresence {

    /// Online means a socket open *right now* on a session that accepts commands — which
    /// is exactly what Jellyfin's `SupportsRemoteControl` asserts. `IsActive` is checked
    /// too only so a server that ever reported a closed socket there is believed.
    public static func isOnline(_ session: JellyfinAPI.SessionInfo) -> Bool {
        guard session.isActive ?? true else { return false }
        return session.supportsRemoteControl ?? session.supportsMediaControl ?? false
    }

    /// The TV's session among a `/Sessions` answer, by the one durable key it has.
    public static func session(
        forDevice deviceId: String, in sessions: [JellyfinAPI.SessionInfo]
    ) -> JellyfinAPI.SessionInfo? {
        sessions.first { $0.deviceId == deviceId }
    }
}

/// Turning what the phone was about to play into what it tells the TV to play.
public enum RemoteDispatch {

    /// `itemIds` rides on the query string, and Kestrel's request line tops out at 8 KB —
    /// the same ceiling the server's own `ids=` injection chunks at. A queue longer than
    /// this is a shuffle nobody reaches the end of anyway.
    public static let maxItemIds = 150

    public struct PlayCommand: Equatable, Sendable {
        public let itemIds: [String]
        public let startIndex: Int
        public let startPositionTicks: Int64?

        public init(itemIds: [String], startIndex: Int, startPositionTicks: Int64?) {
            self.itemIds = itemIds
            self.startIndex = startIndex
            self.startPositionTicks = startPositionTicks
        }
    }

    /// The `POST /Sessions/{id}/Playing` the phone sends instead of opening its player.
    ///
    /// A single item goes alone, so the TV can do what it does for any one id — an
    /// episode becomes the rest of its show (`AppState.resumeRequest`), which a list of
    /// ids would prevent. A queue is sent from its start item on, capped, re-based to
    /// index 0; the start item's resume position rides along so a Continue Watching tap
    /// lands where the viewer left off. Items before the start were already skipped on
    /// the phone and stay skipped.
    public static func playCommand(for request: PlaybackRequest) -> PlayCommand? {
        guard !request.items.isEmpty else { return nil }
        if request.items.count == 1 {
            let only = request.items[0]
            return PlayCommand(itemIds: [only.id], startIndex: 0,
                               startPositionTicks: only.resumePositionTicks)
        }
        let start = min(max(request.startIndex, 0), request.items.count - 1)
        let slice = Array(request.items[start...].prefix(maxItemIds))
        return PlayCommand(itemIds: slice.map(\.id), startIndex: 0,
                           startPositionTicks: slice.first?.resumePositionTicks)
    }
}

/// Where the TV is in its film, between the reports it sends.
///
/// The TV reports its position every ten seconds while playing and at once on pause,
/// resume and seek. The phone polls the session more often than that and sees the *same*
/// ticks on every poll until the next report — so the clock only re-bases when the ticks
/// (or the paused flag) actually change, and otherwise keeps counting from the last real
/// report. Re-basing on every poll would make the readout jump backwards every second and
/// a half.
public struct RemoteClock: Equatable, Sendable {
    public let reportedTicks: Int64
    public let isPaused: Bool
    public let reportedAt: Date
    /// Which item the report was about: a new item whose first report carries the same
    /// ticks and paused flag as the old one (0, playing — the common pair) must still
    /// re-base, or the readout counts on from the previous film's clock.
    public let itemId: String?

    public init(reportedTicks: Int64, isPaused: Bool, reportedAt: Date, itemId: String? = nil) {
        self.reportedTicks = reportedTicks
        self.isPaused = isPaused
        self.reportedAt = reportedAt
        self.itemId = itemId
    }

    /// A clock for a session that is playing something, or nil when it is not.
    public init?(session: JellyfinAPI.SessionInfo, at now: Date) {
        guard let item = session.nowPlayingItem, let state = session.playState else { return nil }
        self.init(reportedTicks: state.positionTicks ?? 0,
                  isPaused: state.isPaused ?? false, reportedAt: now, itemId: item.id)
    }

    /// The clock after another poll: the same report keeps the old base, a new one
    /// re-bases, and nothing playing is no clock at all.
    public func updated(with session: JellyfinAPI.SessionInfo, at now: Date) -> RemoteClock? {
        guard let item = session.nowPlayingItem, let state = session.playState else { return nil }
        let ticks = state.positionTicks ?? 0
        let paused = state.isPaused ?? false
        if ticks == reportedTicks && paused == isPaused && item.id == itemId { return self }
        return RemoteClock(reportedTicks: ticks, isPaused: paused, reportedAt: now, itemId: item.id)
    }

    /// The same clock re-based to what the viewer just asked for, before the TV has
    /// confirmed it — a pause pressed here should read as paused at once.
    public func optimistic(ticks: Int64, isPaused: Bool, at now: Date) -> RemoteClock {
        RemoteClock(reportedTicks: ticks, isPaused: isPaused, reportedAt: now, itemId: itemId)
    }

    /// Seconds into the item right now, counting forward from the last report unless the
    /// TV said it was paused.
    public func positionSeconds(at now: Date, runtimeSeconds: Double? = nil) -> Double {
        var seconds = Double(reportedTicks) / 10_000_000
        if !isPaused { seconds += max(0, now.timeIntervalSince(reportedAt)) }
        if let runtimeSeconds, runtimeSeconds > 0 { seconds = min(seconds, runtimeSeconds) }
        return max(0, seconds)
    }
}

// MARK: - The YSOJ pairing surface

extension YsojAPI {

    /// A TV saying "I am looking for a remote" — two minutes of state on the server.
    public struct RemoteBeacon: Decodable, Sendable, Equatable, Identifiable {
        public let id: String
        public let tvDeviceId: String
        public let tvName: String
        public let expiresAt: Double
        /// `waiting`, `paired` or `expired`. Unknown strings read as expired, so an
        /// overlay never spins on a state it does not understand.
        public let state: String
        public let pairing: RemotePairing?
        /// Advisory, from the server's view of both source addresses; the refusal itself
        /// happens when the phone answers. `nil` when the server could not tell.
        public let sameNetwork: Bool?

        public var isWaiting: Bool { state == "waiting" }
        public var isPaired: Bool { state == "paired" }
    }

    /// A phone that answered a beacon. `Codable` because the same shape is the local
    /// mirror each device keeps so the link is ready before the network is.
    public struct RemotePairing: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let tvDeviceId: String
        public let tvName: String
        public let remoteDeviceId: String
        public let remoteName: String
        public let createdAt: Double?
        public let lastSeenAt: Double?

        public init(id: String, tvDeviceId: String, tvName: String, remoteDeviceId: String,
                    remoteName: String, createdAt: Double? = nil, lastSeenAt: Double? = nil) {
            self.id = id
            self.tvDeviceId = tvDeviceId
            self.tvName = tvName
            self.remoteDeviceId = remoteDeviceId
            self.remoteName = remoteName
            self.createdAt = createdAt
            self.lastSeenAt = lastSeenAt
        }
    }

    public struct RemoteBeaconsResponse: Decodable, Sendable {
        public let beacons: [RemoteBeacon]
    }

    public struct RemotePairingsResponse: Decodable, Sendable {
        public let pairings: [RemotePairing]
    }
}

// MARK: - Words for an item

extension JellyfinAPI.JellyfinItem {
    /// "S2 · E4" when both numbers are known, else nil — the one spelling for every
    /// place an episode is named beside its show.
    public var episodeMarker: String? {
        guard type == "Episode", let season = parentIndexNumber, let episode = indexNumber else {
            return nil
        }
        return "S\(season) · E\(episode)"
    }

    /// "S2 · E4 — Title" for an episode, the name for anything else.
    public var episodeLine: String {
        let title = name ?? "Untitled"
        guard let marker = episodeMarker else { return title }
        return "\(marker) — \(title)"
    }
}

/// The server's own sentence when it sent one (`{"detail": "…"}`), else the fallback —
/// how a refusal reaches the person who pressed the button, on either side of a pairing.
public enum ServerMessage {
    public static func text(for error: Error, fallback: String) -> String {
        if case JellyfinRequestError.server(_, let body) = error,
           let detail = detail(in: body), !detail.isEmpty {
            return detail
        }
        return fallback
    }

    /// The `detail` string of a JSON error body, if the body is one.
    public static func detail(in body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["detail"] as? String
    }
}
