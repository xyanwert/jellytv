import SwiftUI
import JellyTVKit

/// Settings → Remote.
///
/// On the phone and iPad: the TVs this device is a remote for, and whether plays go to
/// the TV while it is on. On the Apple TV: the receiver switch, *Pair a remote*, and the
/// remotes paired to it — the same panel Home's remote button opens, reachable from
/// Settings for the person who does not know that button is there.
struct RemoteDetail: View {
    #if os(iOS)
    @EnvironmentObject private var link: TVLink
    #else
    @EnvironmentObject private var remote: RemoteControl
    @EnvironmentObject private var host: RemotePairingHost
    #endif
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(title: "Remote", readout: appState.offersRemote ? "YSOJ · PAIRING" : nil)
            #if os(iOS)
            phoneBody
            #else
            tvBody
            #endif
            Spacer(minLength: 0)
        }
    }

    #if os(iOS)
    @ViewBuilder
    private var phoneBody: some View {
        if link.pairings.isEmpty {
            DetailRow(label: "No TV paired",
                      description: appState.offersRemote
                        ? "On the Apple TV, press the remote button on Home, then Pair a remote. This \(DeviceIdentity.name) will ask to join."
                        : RemoteCopy.needsYsoj) {
                Image(systemName: "tv")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Palette.text(0.35))
            }
            DetailDivider()
        } else {
            ForEach(link.pairings) { pairing in
                let isActive = pairing.id == link.activePairing?.id
                DetailRow(label: pairing.tvName,
                          description: isActive ? "This \(DeviceIdentity.name) is its remote" : "Paired") {
                    HStack(spacing: 12) {
                        if !isActive {
                            Button("Use") { link.select(pairing) }
                                .buttonStyle(.bordered)
                                .tint(theme.accent)
                        }
                        Button {
                            Task { await link.forget(pairing) }
                        } label: {
                            Text("Forget")
                                .font(Typography.font(16, .bold))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                DetailDivider()
            }
            DetailRow(label: "Send plays to the TV",
                      description: "While the TV is on, playing here plays there") {
                ToggleSwitch(isOn: $link.sendToTV)
            }
            DetailDivider()
        }
    }
    #else
    @ViewBuilder
    private var tvBody: some View {
        DetailRow(label: "Remote control",
                  description: "Lets a paired iPhone or iPad, and any Jellyfin app, play to this TV") {
            ToggleSwitch(isOn: Binding(get: { remote.isEnabled }, set: { remote.setEnabled($0) }))
        }
        DetailDivider()

        DetailRow(label: "Pair a remote",
                  description: host.offersPairing
                    ? "Opens the pairing panel; then say yes on the phone"
                    : RemoteCopy.needsYsojShort) {
            Button {
                host.isPanelOpen = true
            } label: {
                Text("Pair…")
                    .font(Typography.font(18, .bold))
                    .foregroundStyle(host.offersPairing ? .black : Palette.text(0.4))
                    .padding(.horizontal, 24)
                    .frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(host.offersPairing ? theme.accent : Palette.text(0.08)))
            }
            .buttonStyle(FocusScaleStyle(scale: 1.08, cornerRadius: 12))
            .disabled(!host.offersPairing)
        }
        DetailDivider()

        ForEach(host.pairings) { pairing in
            DetailRow(label: pairing.remoteName, description: "Paired remote") {
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
            }
            DetailDivider()
        }
    }
    #endif
}
