import SwiftUI
import JellyTVKit

/// Lets other Jellyfin apps drive this one — the phone's "Play On" picker.
///
/// **This is what the top bar's "connect remote" icon does.** There is no
/// pairing of its own to do: Jellyfin's remote control is server-relayed.
/// Once this session has posted its capabilities and holds the server's
/// WebSocket open, every other client signed into the same server lists it
/// as "JellyTV" under Play On / Cast, and whatever they pick arrives here as
/// a `Play` command; their transport buttons arrive as `Playstate`. Switch it
/// off and the session drops out of those lists within the keep-alive window.
///
/// Off by default and remembered. A TV that can be started by any phone in
/// the house is a feature some households want and a prank others don't, so
/// it is a press away rather than always on — and a press away in the one
/// place the whole household looks at, the Home screen.
///
/// **Commands become the same requests a tap here would make.** A single
/// item goes through `AppState.resumeRequest` — a film alone, an episode with
/// the rest of its show queued behind it, exactly as Continue Watching does
/// — so auto-advance and the scenes panel's Next tile work for a remote start
/// too. A list of items becomes a queue in the order sent. Transport commands
/// go to `AppState.activePlayerController`, the controller of whatever is
/// playing; with nothing playing they are dropped, since there is nothing to
/// pause.
@MainActor
final class RemoteControl: ObservableObject {
    enum Status: Equatable {
        case off
        case connecting
        case on
        /// Enabled, but the socket couldn't be built — no server yet.
        case failed
    }

    @Published private(set) var isEnabled: Bool
    @Published private(set) var status: Status = .off
    /// A line worth showing for a beat beside the icon: what a press just
    /// did, or a `DisplayMessage` a controlling app sent.
    @Published private(set) var notice: String?

    private weak var appState: AppState?
    private var socket: JellyfinSocket?
    private var commandTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?

    private static let enabledKey = "jelly:remote.enabled"
    static let deviceLabel = "JellyTV"

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    /// The server connection came up (or changed). A new client means a new
    /// socket; if the user left this on, it comes back on its own.
    func attach(_ appState: AppState) {
        self.appState = appState
        stopSocket()
        if isEnabled { start() }
    }

    /// The server connection went away — nothing to be connected to, but the
    /// user's choice survives for when it comes back.
    func detach() {
        stopSocket()
        appState = nil
    }

    func toggle() {
        setEnabled(!isEnabled)
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if enabled {
            start()
            show("Remote control on — this TV appears as “\(Self.deviceLabel)” in Jellyfin apps")
        } else {
            stopSocket()
            show("Remote control off")
        }
    }

    // MARK: - Socket

    private func start() {
        guard let appState, let client = appState.jellyfinClient, let socket = client.makeSocket() else {
            status = .failed
            return
        }
        self.socket = socket
        status = .connecting
        stateTask = Task { [weak self] in
            for await state in socket.states {
                guard let self, !Task.isCancelled else { return }
                switch state {
                case .connected: status = .on
                case .connecting: status = .connecting
                case .disconnected: status = isEnabled ? .connecting : .off
                }
            }
        }
        commandTask = Task { [weak self] in
            for await command in socket.commands {
                guard let self, !Task.isCancelled else { return }
                await handle(command)
            }
        }
        Task {
            // Capabilities first, so the session is already "controllable"
            // by the time the socket makes it "active" — the other order
            // shows up in a phone's list for a beat as a device that can't
            // be told anything.
            do {
                try await client.postRemoteControlCapabilities()
            } catch {
                show("Couldn't register with the server for remote control")
            }
            await socket.connect()
        }
    }

    private func stopSocket() {
        commandTask?.cancel()
        stateTask?.cancel()
        commandTask = nil
        stateTask = nil
        if let socket {
            Task { await socket.disconnect() }
        }
        socket = nil
        status = .off
    }

    // MARK: - Commands

    private func handle(_ command: RemoteCommand) async {
        guard let appState else { return }
        switch command {
        case .play(let ids, let startIndex, let ticks, _):
            guard let request = await appState.playbackRequest(forItemIds: ids, startIndex: startIndex,
                                                               startPositionTicks: ticks) else { return }
            appState.requestPlayback(request)

        case .playState(let state, let seekTicks):
            guard let controller = appState.activePlayerController else { return }
            switch state {
            case .pause: controller.pause()
            case .unpause: controller.play()
            case .playPause: controller.togglePlay()
            case .stop: appState.activePlaybackRequest = nil
            case .nextTrack: _ = await controller.next()
            case .previousTrack: _ = await controller.previous()
            case .seek:
                if let seekTicks { await controller.seek(to: Double(seekTicks) / 10_000_000) }
            case .rewind: controller.jump(by: -30)
            case .fastForward: controller.jump(by: 30)
            }

        case .general(let name, let arguments):
            switch name {
            case "DisplayMessage":
                let text = [arguments["Header"], arguments["Text"]]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
                if !text.isEmpty { show(text) }
            case "GoHome":
                appState.activePlaybackRequest = nil
            default:
                break
            }
        }
    }

    // MARK: - Notice

    private func show(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }
}
