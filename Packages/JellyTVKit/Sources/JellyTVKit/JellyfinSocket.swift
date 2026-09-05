import Foundation

/// A remote-control command relayed by the server from another Jellyfin
/// client — the phone that just picked this device in its "Play On" list.
public enum RemoteCommand: Sendable, Equatable {
    /// `Play`: start these items. `mode` is Jellyfin's `PlayCommand`
    /// (`PlayNow`, `PlayNext`, `PlayLast`); everything is treated as play-now
    /// here, since this player's queue is the thing on screen, not a playlist
    /// to append to.
    case play(itemIds: [String], startIndex: Int, startPositionTicks: Int64?, mode: String)
    /// `Playstate`: transport control of whatever is already playing.
    case playState(PlayStateCommand, seekPositionTicks: Int64?)
    /// `GeneralCommand`: everything else (`DisplayMessage`, `GoHome`, …).
    case general(name: String, arguments: [String: String])
}

public enum PlayStateCommand: String, Sendable {
    case stop = "Stop"
    case pause = "Pause"
    case unpause = "Unpause"
    case playPause = "PlayPause"
    case nextTrack = "NextTrack"
    case previousTrack = "PreviousTrack"
    case seek = "Seek"
    case rewind = "Rewind"
    case fastForward = "FastForward"
}

public enum RemoteSocketState: Sendable, Equatable {
    case disconnected, connecting, connected
}

/// The server's WebSocket (`/socket`), as far as remote control needs it.
///
/// Jellyfin's remote control is server-relayed: a phone tells the server
/// "play X on session S", and the server pushes that to S over this socket.
/// A session only counts as controllable while its socket is up, so this is
/// what "connect remote" actually connects. The protocol on the wire is small:
///
/// - Every message is `{"MessageType": String, "Data": …}`.
/// - The server opens with `ForceKeepAlive` carrying a timeout in seconds; the
///   client must send `{"MessageType":"KeepAlive"}` inside that window or the
///   server drops the socket. Half the window is the usual cadence.
/// - `Play`, `Playstate` and `GeneralCommand` are the three that matter here;
///   `Sessions`, `UserDataChanged`, `LibraryChanged` and friends are ignored.
///
/// Reconnects with capped backoff for as long as `connect()` is the last
/// thing asked of it — a TV that sleeps and wakes should still be on the
/// phone's list without anyone pressing the button again.
public actor JellyfinSocket {
    private let url: URL
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    private var wantsConnection = false
    private var isConnected = false
    private var reconnectDelay: Duration = .seconds(2)

    public nonisolated let commands: AsyncStream<RemoteCommand>
    public nonisolated let states: AsyncStream<RemoteSocketState>
    private let commandContinuation: AsyncStream<RemoteCommand>.Continuation
    private let stateContinuation: AsyncStream<RemoteSocketState>.Continuation

    init(url: URL, session: URLSession) {
        self.url = url
        self.session = session
        let (commands, commandContinuation) = AsyncStream.makeStream(of: RemoteCommand.self)
        let (states, stateContinuation) = AsyncStream.makeStream(of: RemoteSocketState.self)
        self.commands = commands
        self.commandContinuation = commandContinuation
        self.states = states
        self.stateContinuation = stateContinuation
    }

    public func connect() {
        wantsConnection = true
        guard task == nil else { return }
        open()
    }

    public func disconnect() {
        wantsConnection = false
        tearDown()
        stateContinuation.yield(.disconnected)
    }

    // MARK: - Lifecycle

    private func open() {
        stateContinuation.yield(.connecting)
        let socket = session.webSocketTask(with: url)
        task = socket
        socket.resume()
        receiveTask = Task { await receiveLoop(socket) }
    }

    private func receiveLoop(_ socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                handle(try await socket.receive())
            } catch {
                break
            }
        }
        // Superseded by a newer socket (disconnect + connect raced this loop's
        // exit): nothing to clean up that isn't already gone.
        guard task === socket else { return }
        tearDown()
        if wantsConnection {
            scheduleReconnect()
        } else {
            stateContinuation.yield(.disconnected)
        }
    }

    private func tearDown() {
        keepAliveTask?.cancel()
        keepAliveTask = nil
        receiveTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
    }

    private func scheduleReconnect() {
        stateContinuation.yield(.connecting)
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, .seconds(30))
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            await self?.reconnectIfWanted()
        }
    }

    private func reconnectIfWanted() {
        guard wantsConnection, task == nil else { return }
        open()
    }

    /// `URLSessionWebSocketTask` has no "opened" event worth waiting on
    /// without a delegate; the server's first message is the handshake that
    /// matters, so the first thing received is what flips this.
    private func markConnected() {
        guard !isConnected else { return }
        isConnected = true
        reconnectDelay = .seconds(2)
        stateContinuation.yield(.connected)
    }

    // MARK: - Messages

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let text): data = Data(text.utf8)
        case .data(let bytes): data = bytes
        @unknown default: return
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["MessageType"] as? String else { return }
        markConnected()
        let payload = object["Data"]

        switch type {
        case "ForceKeepAlive":
            let seconds = (payload as? NSNumber)?.intValue ?? 60
            startKeepAlive(every: max(5, seconds / 2))

        case "Play":
            guard let body = payload as? [String: Any],
                  let ids = body["ItemIds"] as? [String], !ids.isEmpty else { return }
            commandContinuation.yield(.play(
                itemIds: ids,
                startIndex: (body["StartIndex"] as? NSNumber)?.intValue ?? 0,
                startPositionTicks: (body["StartPositionTicks"] as? NSNumber)?.int64Value,
                mode: body["PlayCommand"] as? String ?? "PlayNow"
            ))

        case "Playstate":
            guard let body = payload as? [String: Any],
                  let raw = body["Command"] as? String,
                  let command = PlayStateCommand(rawValue: raw) else { return }
            commandContinuation.yield(.playState(
                command, seekPositionTicks: (body["SeekPositionTicks"] as? NSNumber)?.int64Value
            ))

        case "GeneralCommand":
            guard let body = payload as? [String: Any], let name = body["Name"] as? String else { return }
            let arguments = (body["Arguments"] as? [String: Any])?.compactMapValues { "\($0)" } ?? [:]
            commandContinuation.yield(.general(name: name, arguments: arguments))

        default:
            break
        }
    }

    private func startKeepAlive(every seconds: Int) {
        keepAliveTask?.cancel()
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { break }
                await self?.sendKeepAlive()
            }
        }
    }

    private func sendKeepAlive() async {
        guard let task else { return }
        try? await task.send(.string("{\"MessageType\":\"KeepAlive\"}"))
    }
}
