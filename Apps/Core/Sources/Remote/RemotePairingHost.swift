import SwiftUI
import Combine
import JellyTVKit

#if os(tvOS)
/// The TV's side of pairing: *Pair a remote*, and who is paired.
///
/// Pressing *Pair a remote* posts a beacon to the YSOJ server — "this TV is looking" —
/// and polls it until a phone on the same Wi‑Fi answers, or two minutes pass. Nothing
/// about the transport lives here: once paired, the phone drives this TV through
/// Jellyfin's own session relay, which `RemoteControl` already receives. Pairing also
/// switches that receiver on, since a paired remote is exactly the sanctioned case its
/// off-by-default guards against.
@MainActor
final class RemotePairingHost: ObservableObject {

    enum Phase: Equatable {
        case idle
        case searching(YsojAPI.RemoteBeacon)
        case paired(YsojAPI.RemotePairing)
        /// Two minutes with no answer.
        case expired
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    /// Remotes paired to this TV — the server's list, mirrored locally.
    @Published private(set) var pairings: [YsojAPI.RemotePairing]
    /// The panel over Home: the switch, *Pair a remote*, the list.
    @Published var isPanelOpen = false {
        didSet { if !isPanelOpen { cancelPairing() } }
    }

    private weak var appState: AppState?
    private weak var remote: RemoteControl?
    private var deviceId = ""
    private var beaconTask: Task<Void, Never>?
    private var capabilitiesSink: AnyCancellable?

    init() {
        pairings = RemotePairingStore.load()
    }

    /// Whether this server can pair at all. A plain Jellyfin still gets the receiver
    /// switch; only the pairing button needs a YSOJ server. Published here — not read
    /// through `AppState` on demand — because the panel observes this object, not that
    /// one, and the capabilities land a beat after the panel can already be open.
    @Published private(set) var offersPairing = false

    var isSearching: Bool {
        if case .searching = phase { return true }
        return false
    }

    func attach(_ appState: AppState, remote: RemoteControl, deviceId: String) {
        self.appState = appState
        self.remote = remote
        self.deviceId = deviceId
        pairings = pairings.filter { $0.tvDeviceId == deviceId }
        offersPairing = appState.offersRemote
        capabilitiesSink = appState.$ysojCapabilities
            .receive(on: RunLoop.main)
            .sink { [weak self] capabilities in
                guard let self else { return }
                self.offersPairing = capabilities?.features.remote?.enabled ?? false
                Task { await self.refreshPairings() }
            }
    }

    func detach() {
        cancelPairing()
        capabilitiesSink = nil
        appState = nil
        remote = nil
        offersPairing = false
    }

    // MARK: - Pairing

    func beginPairing() {
        guard let ysoj = appState?.ysojClient, offersPairing else {
            phase = .failed(RemoteCopy.needsYsoj)
            return
        }
        if let remote, !remote.isEnabled { remote.setEnabled(true) }
        beaconTask?.cancel()
        beaconTask = Task { [weak self] in
            guard let self else { return }
            do {
                let beacon = try await ysoj.openRemoteBeacon(deviceName: DeviceIdentity.name)
                self.phase = .searching(beacon)
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(2))
                    // One failed poll is a Wi‑Fi hiccup, not the end of the search: keep
                    // asking until the beacon's own two minutes run out.
                    guard let polled = try? await ysoj.pollRemoteBeacon(id: beacon.id) else {
                        if Date().timeIntervalSince1970 >= beacon.expiresAt {
                            self.phase = .expired
                            return
                        }
                        continue
                    }
                    if polled.isPaired, let pairing = polled.pairing {
                        self.upsert(pairing)
                        self.phase = .paired(pairing)
                        return
                    }
                    if !polled.isWaiting {
                        self.phase = .expired
                        return
                    }
                }
            } catch {
                // Cancelled by the user (`cancelPairing` already set `.idle` and closes
                // the beacon) — a request cut off mid-flight surfaces as `URLError
                // .cancelled`, not `CancellationError`, so both are checked.
                guard !Task.isCancelled, !(error is CancellationError),
                      (error as? URLError)?.code != .cancelled else { return }
                self.phase = .failed(ServerMessage.text(for: error,
                                                        fallback: "Couldn't reach the server to start pairing."))
            }
        }
    }

    func cancelPairing() {
        beaconTask?.cancel()
        beaconTask = nil
        if case .searching(let beacon) = phase, let ysoj = appState?.ysojClient {
            Task { try? await ysoj.closeRemoteBeacon(id: beacon.id) }
        }
        phase = .idle
    }

    func forget(_ pairing: YsojAPI.RemotePairing) async {
        pairings.removeAll { $0.id == pairing.id }
        persist()
        if let ysoj = appState?.ysojClient {
            try? await ysoj.deleteRemotePairing(id: pairing.id)
        }
    }

    func refreshPairings() async {
        guard let appState, appState.offersRemote, let ysoj = appState.ysojClient else { return }
        guard let remote = try? await ysoj.fetchRemotePairings() else { return }
        pairings = remote.filter { $0.tvDeviceId == deviceId }
        persist()
    }

    private func upsert(_ pairing: YsojAPI.RemotePairing) {
        pairings.removeAll { $0.id == pairing.id }
        pairings.append(pairing)
        persist()
    }

    private func persist() {
        RemotePairingStore.save(pairings)
    }
}
#endif
