import SwiftUI
import JellyTVKit

#if os(iOS)
/// The remote: what the TV is playing, its clock, the transport, and the two switches
/// that decide where plays go.
///
/// A same-`ZStack` overlay (like the trailer and the download plan), not a `.sheet`:
/// this is a control surface over the app, not a different screen.
struct TVRemoteSheet: View {
    let onClose: () -> Void

    @EnvironmentObject private var link: TVLink
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: Theme
    /// Scenes mode: one frame a minute apart in place of the transport, until the X.
    @State private var scenesOpen = false

    private var isPhone: Bool { DeviceClass.current == .phone }

    var body: some View {
        ZStack(alignment: isPhone ? .bottom : .center) {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                header
                    .padding(.bottom, link.pairings.count > 1 ? 12 : 18)
                if link.pairings.count > 1 {
                    tvPicker
                        .padding(.bottom, 16)
                }
                nowPlaying
                    .padding(.bottom, 22)
                if scenesOpen, let item = link.nowPlaying {
                    RemoteScenes(item: item,
                                 currentSeconds: link.position(at: Date())?.current ?? 0,
                                 onPick: { link.seek(to: $0) },
                                 onClose: { scenesOpen = false })
                        // A new item (auto-advance mid-sheet) is a new set of minutes;
                        // without this the page index outlived the film it belonged to.
                        .id(item.id)
                        .padding(.bottom, 18)
                } else {
                    transport
                        .padding(.bottom, 18)
                    queueRow
                        .padding(.bottom, 10)
                    scenesRow
                        .padding(.bottom, 6)
                }
                footer
            }
            .animation(.easeOut(duration: 0.22), value: scenesOpen)
            .onChange(of: link.nowPlaying == nil) { _, nothing in
                if nothing { scenesOpen = false }
            }
            .padding(isPhone ? 20 : 28)
            .padding(.bottom, isPhone ? 12 : 0)
            .frame(maxWidth: isPhone ? .infinity : 520)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Palette.sheet)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(Palette.text(0.12), lineWidth: 1)
                    )
            )
            .padding(.horizontal, isPhone ? 8 : 0)
            .padding(.bottom, isPhone ? 8 : 0)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(link.tvName)
                    .font(Typography.font(22, .black))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 7) {
                    Circle()
                        .fill(link.isOnline ? Palette.connected : Palette.text(0.3))
                        .frame(width: 8, height: 8)
                    Text(statusLine)
                        .font(Mono.font(12, .semibold))
                        .tracking(1.2)
                        .foregroundStyle(link.isOnline ? Palette.connected : Palette.text(0.5))
                }
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.text(0.85))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Palette.text(0.1)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close remote")
        }
    }

    /// Which TV, first: one row per paired TV — lit while it is up, ticked when it is the
    /// one — and a wave on each that flashes a banner on that screen, for the moment two
    /// boxes out of the carton look alike. Rows, not chips: two default names are too
    /// long to sit side by side, and the second one scrolled out of reach.
    private var tvPicker: some View {
        VStack(spacing: 6) {
            ForEach(link.pairings) { pairing in
                let isOn = pairing.id == link.activePairing?.id
                let online = link.isOnline(pairing)
                HStack(spacing: 10) {
                    Button { link.select(pairing) } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(online ? Palette.connected : Palette.text(0.3))
                                .frame(width: 8, height: 8)
                            Text(pairing.tvDisplayName(among: link.pairings))
                                .font(Typography.font(15, isOn ? .bold : .semibold))
                                .foregroundStyle(isOn ? Palette.textPrimary : Palette.text(0.7))
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            if isOn {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .black))
                                    .foregroundStyle(theme.accent)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isOn ? theme.accent.opacity(0.16) : Palette.text(0.05))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(isOn ? theme.accent.opacity(0.6) : Palette.text(0.1), lineWidth: 1))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(online ? 1 : 0.55)
                    .accessibilityLabel("\(pairing.tvDisplayName(among: link.pairings)), \(online ? "on" : "off")\(isOn ? ", selected" : "")")

                    Button {
                        link.identify(pairing)
                    } label: {
                        Image(systemName: "hand.wave.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Palette.text(0.85))
                            .frame(width: 42, height: 42)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Palette.text(0.08)))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Palette.text(0.14), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(!online)
                    .opacity(online ? 1 : 0.4)
                    .accessibilityLabel("Flash a banner on \(pairing.tvDisplayName(among: link.pairings))")
                }
            }
        }
    }

    private var statusLine: String {
        switch link.presence {
        case .online: return link.nowPlaying == nil ? "READY" : "PLAYING"
        case .checking: return "CHECKING"
        case .offline: return "NOT OPEN"
        case .none: return "NOT PAIRED"
        }
    }

    // MARK: - Now playing

    @ViewBuilder
    private var nowPlaying: some View {
        if let item = link.nowPlaying {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                VStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 14) {
                        poster(for: item)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.type == "Episode" ? (item.seriesName ?? item.name ?? "") : (item.name ?? ""))
                                .font(Typography.font(18, .bold))
                                .foregroundStyle(Palette.textPrimary)
                                .lineLimit(2)
                            if item.type == "Episode" {
                                Text(item.episodeLine)
                                    .font(Typography.font(14, .medium))
                                    .foregroundStyle(Palette.text(0.6))
                                    .lineLimit(2)
                            } else if let year = item.productionYear {
                                Text(String(year))
                                    .font(Mono.font(12, .semibold))
                                    .foregroundStyle(Palette.text(0.5))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    if let position = link.position(at: context.date) {
                        clock(current: position.current, duration: position.duration)
                    }
                }
            }
        } else {
            HStack(spacing: 12) {
                Image(systemName: "sparkles.tv")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Palette.text(0.4))
                Text(idleLine)
                    .font(Typography.font(15, .medium))
                    .foregroundStyle(Palette.text(0.6))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
        }
    }

    private var idleLine: String {
        switch link.presence {
        case .online: return "Nothing playing. Pick something here and it plays on the TV."
        case .checking: return "Looking for the TV…"
        case .offline: return "Open Why.So.Jelly? on the Apple TV — it will show up here."
        case .none: return "No TV paired."
        }
    }

    @ViewBuilder
    private func poster(for item: JellyfinAPI.JellyfinItem) -> some View {
        let id = item.type == "Episode" ? (item.seriesId ?? item.id) : item.id
        let tag = item.type == "Episode" ? nil : item.imageTags?["Primary"]
        if let base = appState.serverImageBaseURL,
           let url = JellyfinAPI.imageURL(baseURL: base, itemId: id, tag: tag, maxWidth: 240) {
            JellyfinAsyncImage(url: url, fallback: Palette.background)
                .aspectRatio(2 / 3, contentMode: .fill)
                .frame(width: 64, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.text(0.08))
                .frame(width: 64, height: 96)
        }
    }

    private func clock(current: Double, duration: Double) -> some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.text(0.12))
                    Capsule()
                        .fill(theme.accent)
                        .frame(width: duration > 0 ? proxy.size.width * min(1, current / duration) : 0)
                }
            }
            .frame(height: 4)
            HStack {
                Text(formatPlayerClock(current, matching: duration))
                    .foregroundStyle(Palette.text(0.9))
                Spacer()
                Text(formatPlayerClock(duration, matching: duration))
                    .foregroundStyle(Palette.text(0.45))
            }
            .font(Mono.font(13, .bold))
            .monospacedDigit()
            .tracking(1)
        }
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: isPhone ? 22 : 28) {
            circle(glyph: "gobackward.30", diameter: isPhone ? 66 : 76, glyphSize: isPhone ? 24 : 27,
                   fill: .black.opacity(0.52), tint: .white, label: "30 seconds back") {
                link.jump(by: -30)
            }
            circle(glyph: link.isPaused ? "play.fill" : "pause.fill",
                   diameter: isPhone ? 92 : 104, glyphSize: isPhone ? 36 : 40,
                   fill: theme.accent, tint: .white, glow: theme.accent,
                   label: link.isPaused ? "Play" : "Pause") {
                link.togglePlayPause()
            }
            circle(glyph: "goforward.30", diameter: isPhone ? 66 : 76, glyphSize: isPhone ? 24 : 27,
                   fill: .black.opacity(0.52), tint: .white, label: "30 seconds ahead") {
                link.jump(by: 30)
            }
        }
        .disabled(link.nowPlaying == nil)
        .opacity(link.nowPlaying == nil ? 0.35 : 1)
    }

    private func circle(glyph: String, diameter: CGFloat, glyphSize: CGFloat, fill: Color,
                        tint: Color, glow: Color? = nil, label: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: glyph)
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: diameter, height: diameter)
                .background(fill, in: Circle())
                .overlay(Circle().stroke(Palette.text(glow == nil ? 0.2 : 0), lineWidth: 1))
                .shadow(color: (glow ?? .black).opacity(glow == nil ? 0.4 : 0.45),
                        radius: glow == nil ? 18 : 24, y: 8)
        }
        .buttonStyle(FocusScaleStyle(cornerRadius: diameter / 2))
        .accessibilityLabel(label)
    }

    private var queueRow: some View {
        HStack(spacing: 10) {
            pill("PREV", glyph: "backward.end.fill") { link.previous() }
            pill("STOP", glyph: "stop.fill") { link.stop() }
            pill("NEXT", glyph: "forward.end.fill") { link.next() }
        }
        .disabled(link.nowPlaying == nil)
        .opacity(link.nowPlaying == nil ? 0.35 : 1)
    }

    private func pill(_ label: String, glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: glyph).font(.system(size: 13, weight: .bold))
                Text(label).font(Mono.font(12, .bold)).tracking(1.6)
            }
            .foregroundStyle(Palette.text(0.85))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Capsule().fill(Palette.text(0.08)))
            .overlay(Capsule().stroke(Palette.text(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Scenes

    /// The TV player's own SCENES violet, so the two read as the same thing.
    private let scenesTint = Palette.scenesViolet

    private var hasScenes: Bool {
        guard let item = link.nowPlaying else { return false }
        return HomeVideoRoll.bestTrickplay(item.trickplay) != nil
    }

    private var scenesRow: some View {
        Button {
            scenesOpen = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2.fill").font(.system(size: 14, weight: .bold))
                Text("SCENES").font(Mono.font(12, .bold)).tracking(1.8)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(Capsule().fill(scenesTint.opacity(0.9)))
            .shadow(color: scenesTint.opacity(0.35), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(!hasScenes)
        .opacity(hasScenes ? 1 : 0.35)
        .accessibilityLabel("Scenes")
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.text(0.08)).frame(height: 1)
            Button {
                // Closes whether or not a pairing is still there to forget — a button
                // that does nothing because the pairing vanished underneath is a stuck sheet.
                if let pairing = link.activePairing { Task { await link.forget(pairing) } }
                onClose()
            } label: {
                HStack {
                    Text("Forget this TV")
                        .font(Typography.font(15, .bold))
                        .foregroundStyle(.red.opacity(0.9))
                    Spacer()
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.red.opacity(0.9))
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// "*Living Room* is looking for a remote." Shown the moment the TV's beacon is seen.
struct PairingPrompt: View {
    let beacon: YsojAPI.RemoteBeacon

    @EnvironmentObject private var link: TVLink
    @EnvironmentObject private var theme: Theme

    private var isPhone: Bool { DeviceClass.current == .phone }

    /// The TV's name, with its id tail when a TV already paired shares the name.
    private var beaconName: String {
        let twin = link.pairings.contains { $0.tvName == beacon.tvName && $0.tvDeviceId != beacon.tvDeviceId }
        return twin ? "\(beacon.tvName) · \(beacon.tvDeviceId.suffix(4))" : beacon.tvName
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()
                .onTapGesture { link.declinePairing() }

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "tv.and.mediabox")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(theme.accent)
                    Text("REMOTE")
                        .font(Mono.font(12, .bold))
                        .tracking(2.2)
                        .foregroundStyle(Palette.text(0.5))
                }
                Text("\(beaconName) is looking for a remote")
                    .font(Typography.font(isPhone ? 24 : 28, .black))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Use this \(DeviceIdentity.name) as its remote? Whatever you play here will play on the TV while it's on, and the link is remembered.")
                    .font(Typography.font(15, .medium))
                    .foregroundStyle(Palette.text(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                if beacon.sameNetwork == false {
                    Label("You don't seem to be on the TV's Wi‑Fi.", systemImage: "wifi.exclamationmark")
                        .font(Typography.font(13, .semibold))
                        .foregroundStyle(.orange)
                }
                HStack(spacing: 12) {
                    Button {
                        link.declinePairing()
                    } label: {
                        Text("Not now")
                            .font(Typography.font(16, .bold))
                            .foregroundStyle(Palette.text(0.85))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Palette.text(0.1)))
                    }
                    .buttonStyle(.plain)
                    Button {
                        Task { await link.acceptPairing() }
                    } label: {
                        ZStack {
                            if link.isPairing {
                                ProgressView().tint(.black)
                            } else {
                                Text("Pair")
                                    .font(Typography.font(16, .bold))
                                    .foregroundStyle(.black)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(theme.accent))
                    }
                    .buttonStyle(.plain)
                    .disabled(link.isPairing)
                }
            }
            .padding(isPhone ? 22 : 30)
            .frame(maxWidth: isPhone ? .infinity : 480, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Palette.sheet)
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Palette.text(0.12), lineWidth: 1))
            )
            .padding(.horizontal, isPhone ? 18 : 0)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
    }
}
#endif
