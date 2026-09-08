import SwiftUI
import JellyTVKit

#if os(tvOS)
/// The remote panel over Home: the receiver switch, *Pair a remote*, and who is paired.
///
/// One overlay, three states of the pairing row beneath the buttons: the instructions
/// with a spinner while the beacon is live, a green line naming the phone once one has
/// answered, or "no remote found" after two minutes. Menu closes it (`.onExitCommand`);
/// the screen beneath is `.disabled` so its controls leave the focus pool.
struct RemotePanel: View {
    @EnvironmentObject private var remote: RemoteControl
    @EnvironmentObject private var host: RemotePairingHost
    @EnvironmentObject private var theme: Theme
    @FocusState private var focus: Field?

    private enum Field: Hashable { case pair, receiver, forget(String), close }

    var body: some View {
        ZStack {
            Color.black.opacity(0.86)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 28) {
                header
                receiverRow
                Rectangle().fill(Palette.text(0.1)).frame(height: 1)
                pairingBlock
                if !host.pairings.isEmpty {
                    Rectangle().fill(Palette.text(0.1)).frame(height: 1)
                    pairedList
                }
            }
            .padding(48)
            .frame(width: 880, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Palette.sheet)
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Palette.text(0.12), lineWidth: 1))
            )
        }
        .onAppear { focus = host.offersPairing ? .pair : .receiver }
        // The flag can land after the panel opened (it is fetched right after connect);
        // when it does, the primary action is the one to be standing on.
        .onChange(of: host.offersPairing) { _, offers in
            if offers, focus == .receiver { focus = .pair }
        }
        .onExitCommand { host.isPanelOpen = false }
        .animation(.easeOut(duration: 0.25), value: host.phase)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("REMOTE")
                    .font(Mono.font(14, .bold))
                    .tracking(2.6)
                    .foregroundStyle(Palette.text(0.45))
                Text(DeviceIdentity.name)
                    .font(Typography.font(40, .black))
                    .foregroundStyle(Palette.textPrimary)
            }
            Spacer(minLength: 20)
            HStack(spacing: 10) {
                Circle()
                    .fill(remote.status == .on ? Palette.connected : Palette.text(0.3))
                    .frame(width: 12, height: 12)
                Text(statusWord)
                    .font(Mono.font(15, .semibold))
                    .tracking(1.4)
                    .foregroundStyle(remote.status == .on ? Palette.connected : Palette.text(0.5))
            }
        }
    }

    private var statusWord: String {
        switch remote.status {
        case .on: return "LISTENING"
        case .connecting: return "CONNECTING"
        case .failed: return "NO SERVER"
        case .off: return "OFF"
        }
    }

    private var receiverRow: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Remote control")
                    .font(Typography.font(26, .bold))
                    .foregroundStyle(Palette.textPrimary)
                Text("Lets a paired iPhone or iPad — and any Jellyfin app on this server — play to this TV")
                    .font(Typography.font(18, .medium))
                    .foregroundStyle(Palette.text(0.5))
            }
            Spacer(minLength: 20)
            Button { remote.toggle() } label: {
                Capsule()
                    .fill(remote.isEnabled ? theme.accent : Palette.text(0.14))
                    .frame(width: 72, height: 40)
                    .overlay(alignment: remote.isEnabled ? .trailing : .leading) {
                        Circle().fill(.white).frame(width: 32, height: 32).padding(4)
                    }
            }
            .buttonStyle(FocusScaleStyle(scale: 1.12, cornerRadius: 999))
            .focused($focus, equals: .receiver)
            .accessibilityLabel(remote.isEnabled ? "Remote control on" : "Remote control off")
        }
    }

    @ViewBuilder
    private var pairingBlock: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 20) {
                Button {
                    if host.isSearching { host.cancelPairing() } else { host.beginPairing() }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: host.isSearching ? "xmark" : "iphone.radiowaves.left.and.right")
                            .font(.system(size: 22, weight: .bold))
                        Text(host.isSearching ? "Stop looking" : "Pair a remote")
                            .font(Typography.font(22, .bold))
                    }
                    .foregroundStyle(host.offersPairing ? .black : Palette.text(0.4))
                    .padding(.horizontal, 30)
                    .frame(height: 68)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(host.offersPairing ? theme.accent : Palette.text(0.08)))
                }
                .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 16))
                .focused($focus, equals: .pair)
                .disabled(!host.offersPairing)

                if !host.offersPairing {
                    Text(RemoteCopy.needsYsoj)
                        .font(Typography.font(17, .medium))
                        .foregroundStyle(Palette.text(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            switch host.phase {
            case .idle:
                if host.offersPairing {
                    Text("Then open Why.So.Jelly? on an iPhone or iPad on this Wi‑Fi. It will ask to become this TV's remote.")
                        .font(Typography.font(18, .medium))
                        .foregroundStyle(Palette.text(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .searching:
                HStack(spacing: 16) {
                    ProgressView().tint(theme.accent)
                    Text("Looking for a remote… open Why.So.Jelly? on an iPhone or iPad on this Wi‑Fi and say yes.")
                        .font(Typography.font(19, .semibold))
                        .foregroundStyle(Palette.text(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .paired(let pairing):
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Palette.connected)
                    Text("\(pairing.remoteName) is now a remote for this TV.")
                        .font(Typography.font(20, .bold))
                        .foregroundStyle(Palette.textPrimary)
                }
            case .expired:
                Text("No remote found. Press Pair a remote again with the phone open.")
                    .font(Typography.font(19, .semibold))
                    .foregroundStyle(.orange)
            case .failed(let message):
                Text(message)
                    .font(Typography.font(19, .semibold))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Two iPhones pair as "iPhone" (iOS hides the owner's name), so when names collide
    /// the tail of the device id tells the rows apart before someone presses Forget.
    private func displayName(for pairing: YsojAPI.RemotePairing) -> String {
        let twins = host.pairings.filter { $0.remoteName == pairing.remoteName }.count
        guard twins > 1 else { return pairing.remoteName }
        return "\(pairing.remoteName) · \(pairing.remoteDeviceId.suffix(4))"
    }

    private var pairedList: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PAIRED REMOTES")
                .font(Mono.font(13, .bold))
                .tracking(2.2)
                .foregroundStyle(Palette.text(0.45))
            ForEach(host.pairings) { pairing in
                HStack(spacing: 18) {
                    Image(systemName: pairing.remoteName.localizedCaseInsensitiveContains("ipad") ? "ipad" : "iphone")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Palette.text(0.7))
                        .frame(width: 40)
                    Text(displayName(for: pairing))
                        .font(Typography.font(21, .bold))
                        .foregroundStyle(Palette.textPrimary)
                    Spacer(minLength: 20)
                    Button {
                        Task { await host.forget(pairing) }
                    } label: {
                        Text("Forget")
                            .font(Typography.font(17, .bold))
                            .foregroundStyle(.red.opacity(0.9))
                            .padding(.horizontal, 22)
                            .frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Palette.text(0.08)))
                    }
                    .buttonStyle(FocusScaleStyle(scale: 1.08, cornerRadius: 12))
                    .focused($focus, equals: .forget(pairing.id))
                }
            }
        }
    }
}
#endif
