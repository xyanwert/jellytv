import SwiftUI
import JellyTVKit
#if canImport(UIKit)
import UIKit
#endif

/// The connect-to-server screen: shown whenever there is no live Jellyfin
/// connection. A split layout — a brand column on the left with a live status
/// line, and a glass panel on the right that swaps between the setup form and
/// an animated connecting log. Ported from the "Connect / Setup" design
/// (Jelly-tv App.dc.html).
struct SetupView: View {
    @ObservedObject var server: ServerConnection
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case host, port, username, password, apiKey, connect
        case server(String)   // a discovered server row, keyed by "host:port"
    }

    /// Which manual-entry fallback is revealed under the discovery list.
    private enum HostMode { case none, reel, manual }

    @StateObject private var scanner = LanScanner()
    @State private var hostMode: HostMode = .none
    @State private var didAutoSelectServer = false

    /// The connect/login screen uses its own neon-purple accent, independent
    /// of the in-app theme color picked in Settings — that color still governs
    /// everything past sign-in.
    private var accent: Color { Self.setupAccent }
    fileprivate static let setupAccent = Color(hex: "#B14EFF")

    var body: some View {
        ZStack {
            SetupBackground()
            SonarMotif()

            HStack(spacing: 0) {
                brandColumn
                panelColumn
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea())
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .defaultFocus($focusedField, .host)
        // Clear a stale error as soon as the user edits anything.
        .onChange(of: fieldsSignature) { server.errorMessage = nil }
        .onExitCommand { /* only screen while disconnected — no-op */ }
        .onAppear {
            // Auto-scan the LAN as soon as the connect screen shows.
            if case .disconnected = server.status { scanner.start() }
        }
        .onDisappear { scanner.stop() }
        // When the first servers appear, auto-SELECT the top result (not just
        // focus it) so the highlighted server is the one Connect actually uses —
        // focus alone doesn't set the host. Fires once, and won't override a
        // choice the user has already made (a discovered server, or reel/manual).
        .onChange(of: scanner.servers) {
            guard !didAutoSelectServer, hostMode == .none, let first = scanner.servers.first else { return }
            let alreadyPicked = scanner.servers.contains { $0.host == server.host && String($0.port) == server.port }
            didAutoSelectServer = true
            guard !alreadyPicked else { return }
            server.host = first.host
            server.port = String(first.port)
            focusedField = .server(first.id)
        }
    }

    private var fieldsSignature: String {
        [server.host, server.port, server.username, server.password, server.apiKey].joined(separator: "\u{1F}")
    }

    // MARK: - Brand column

    private var brandColumn: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(spacing: 22) {
                Image("AppMark")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
                    .shadow(color: .black.opacity(0.6), radius: 20, y: 14)

                VStack(alignment: .leading, spacing: 6) {
                    wordmark
                    Text("JELLYFIN CLIENT")
                        .font(Mono.font(15))
                        .tracking(3.6)
                        .foregroundStyle(Palette.text(0.42))
                }
            }

            Text("Connect\nyour server")
                .font(Typography.font(72, .black))
                .tracking(-2)
                .lineSpacing(-4)
                .foregroundStyle(Palette.textPrimary)

            Text("Point Why.So.Jelly? at your Jellyfin server to stream your library. Sign in with a username and password, or paste an API key.")
                .font(Typography.font(22, .medium))
                .lineSpacing(6)
                .foregroundStyle(Palette.text(0.6))
                .frame(maxWidth: 480, alignment: .leading)

            statusLine
                .padding(.top, 6)
        }
        .padding(.init(top: 96, leading: 110, bottom: 96, trailing: 0))
        .frame(width: 720, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var wordmark: some View {
        (
            Text("Why").foregroundColor(Palette.textPrimary)
            + Text(".").foregroundColor(accent)
            + Text("So").foregroundColor(Palette.textPrimary)
            + Text(".").foregroundColor(accent)
            + Text("Jelly?").foregroundColor(Palette.textPrimary)
        )
        .font(Typography.font(40, .black))
        .tracking(-1)
    }

    /// The live status dot + label under the brand copy. Reflects readiness,
    /// or a failure after a rejected attempt.
    private var statusLine: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 11, height: 11)
                .shadow(color: statusColor.opacity(0.85), radius: 6)
            Text(statusText)
                .font(Mono.font(15))
                .tracking(1.5)
                .foregroundStyle(statusColor.opacity(0.85))
        }
    }

    private var statusColor: Color {
        if server.errorMessage != nil { return Color(hex: "#E8544A") }
        return canConnect ? Color(hex: "#58D399") : Color(hex: "#E8B44A")
    }

    private var statusText: String {
        if server.errorMessage != nil { return "CONNECTION FAILED" }
        return canConnect ? "READY TO CONNECT" : "AWAITING CREDENTIALS"
    }

    // MARK: - Panel column

    private var panelColumn: some View {
        panelCard
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.init(top: 70, leading: 40, bottom: 70, trailing: 110))
    }

    private var panelCard: some View {
        Group {
            if case .connecting = server.status {
                connectingPanel
            } else {
                formPanel
            }
        }
        .frame(width: 760)
        .background(Color(hex: "#0C1018").opacity(0.72), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 60, y: 40)
    }

    // MARK: - Form

    private var formPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow("SETUP // SERVER")
                .padding(.bottom, 26)

            serverSection
                .padding(.bottom, 26)

            AuthBox(
                title: "SIGN IN",
                tag: credTag, tagColor: credTagColor,
                active: hasCred, dim: credDim, accent: accent
            ) {
                field(placeholder: "Username", text: $server.username, field: .username)
                field(placeholder: "Password", text: $server.password, field: .password, secure: false)
            }

            orDivider
                .padding(.vertical, 20)

            AuthBox(
                title: "API KEY",
                tag: keyTag, tagColor: keyTagColor,
                active: hasKey, dim: keyDim, accent: accent
            ) {
                field(placeholder: "Paste API key", text: $server.apiKey, field: .apiKey, mono: true)
            }

            if let error = server.errorMessage {
                errorBanner(error)
                    .padding(.top, 24)
            }

            connectButton
                .padding(.top, 30)

            Text(hintText)
                .font(Typography.font(15, .medium))
                .foregroundStyle(Palette.text(0.35))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 14)
        }
        .padding(.init(top: 46, leading: 48, bottom: 40, trailing: 48))
    }

    // MARK: - Server source (discovery-first)

    /// The HOST area: auto-discovered servers as the primary choice, with a
    /// "Not listed?" fallback that reveals the IP reel or manual entry.
    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("HOST")
                    .font(Mono.font(14)).tracking(2)
                    .foregroundStyle(Palette.text(0.5))
                if let label = scanner.subnetLabel {
                    Text(label)
                        .font(Mono.font(13))
                        .foregroundStyle(Palette.text(0.3))
                }
                Spacer(minLength: 0)
                rescanButton
            }

            discoveryArea
            notListedRow

            if hostMode == .reel {
                reelEntry
            } else if hostMode == .manual {
                manualEntry
            }
        }
        .animation(.easeOut(duration: 0.2), value: hostMode)
        .animation(.easeOut(duration: 0.2), value: scanner.servers)
        .animation(.easeOut(duration: 0.2), value: scanner.phase)
    }

    @ViewBuilder private var discoveryArea: some View {
        if scanner.servers.isEmpty {
            switch scanner.phase {
            case .scanning:
                statusStrip(spinner: true, text: "Scanning your network…")
            case .done:
                statusStrip(spinner: false, text: scanner.subnetLabel == nil
                    ? "Couldn’t detect your network — enter the address below."
                    : "No Jellyfin servers found — enter the address below.")
            case .idle:
                EmptyView()
            }
        } else {
            VStack(spacing: 10) {
                ForEach(scanner.servers) { serverRow($0) }
            }
            if scanner.phase == .scanning {
                statusStrip(spinner: true, text: "Still scanning…").padding(.top, 2)
            }
        }
    }

    private func serverRow(_ s: DiscoveredServer) -> some View {
        let selected = server.host == s.host && server.port == String(s.port)
        return Button {
            server.host = s.host
            server.port = String(s.port)
            hostMode = .none
            focusedField = .username
        } label: {
            HStack(spacing: 16) {
                Image(systemName: selected ? "checkmark.circle.fill" : "server.rack")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(selected ? accent : Palette.text(0.55))
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name)
                        .font(Typography.font(21, .heavy))
                        .foregroundStyle(Palette.textPrimary)
                    Text(s.address)
                        .font(Mono.font(15))
                        .foregroundStyle(Palette.text(0.5))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .frame(height: 68)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selected ? accent.opacity(0.10) : .white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(selected ? accent.opacity(0.5) : .white.opacity(0.10), lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(FocusScaleStyle(scale: 1.02, cornerRadius: 14, outline: true))
        .focused($focusedField, equals: .server(s.id))
    }

    private func statusStrip(spinner: Bool, text: String) -> some View {
        HStack(spacing: 12) {
            if spinner {
                ProgressView().controlSize(.small).tint(accent)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Palette.text(0.4))
            }
            Text(text)
                .font(Typography.font(17, .medium))
                .foregroundStyle(Palette.text(0.5))
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private var rescanButton: some View {
        Button { scanner.start() } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .heavy))
                Text("Rescan").font(Typography.font(15, .heavy))
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 16).frame(height: 42)
            .background(Capsule().fill(accent.opacity(0.12)))
            .overlay(Capsule().stroke(accent.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(FocusScaleStyle(scale: 1.05, cornerRadius: 21, outline: true))
    }

    private var notListedRow: some View {
        HStack(spacing: 12) {
            Text("Not listed?")
                .font(Typography.font(16, .medium))
                .foregroundStyle(Palette.text(0.45))
            modeChip(title: "Enter IP", systemImage: "number", mode: .reel)
            modeChip(title: "Manual", systemImage: "keyboard", mode: .manual)
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private func modeChip(title: String, systemImage: String, mode: HostMode) -> some View {
        let on = hostMode == mode
        return Button {
            hostMode = (hostMode == mode) ? .none : mode
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage).font(.system(size: 14, weight: .heavy))
                Text(title).font(Typography.font(15, .heavy))
            }
            .foregroundStyle(on ? Color.white : Palette.text(0.6))
            .padding(.horizontal, 16).frame(height: 42)
            .background(Capsule().fill(on ? accent : .white.opacity(0.05)))
            .overlay(Capsule().stroke(on ? Color.clear : .white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(FocusScaleStyle(scale: 1.05, cornerRadius: 21, outline: true))
    }

    private var reelEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 16) {
                OctetReel(address: $server.host, accent: accent)
                portField
            }
            Text("Select an octet, then swipe ▲ / ▼ to set it (0–255).")
                .font(Typography.font(14, .medium))
                .foregroundStyle(Palette.text(0.35))
        }
        .padding(.top, 4)
    }

    private var manualEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AppTextField(placeholder: "192.168.1.10  ·  jellyfin.local",
                             text: $server.host,
                             accent: accent, field: .host, focus: $focusedField,
                             onSubmit: { focusedField = .port })
                portField
            }
            Text("Enter an IP or hostname. Default Jellyfin port is 8096.")
                .font(Typography.font(14, .medium))
                .foregroundStyle(Palette.text(0.35))
        }
        .padding(.top, 4)
    }

    private var portField: some View {
        AppTextField(placeholder: "8096",
                     text: $server.port, mono: true, prefix: ":", width: 150,
                     accent: accent, field: .port, focus: $focusedField,
                     onSubmit: { focusedField = .username })
    }

    private var orDivider: some View {
        HStack(spacing: 16) {
            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
            Text("OR")
                .font(Mono.font(13))
                .tracking(3)
                .foregroundStyle(Palette.text(0.4))
            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
        }
    }

    private var connectButton: some View {
        Button {
            Task { await server.connect() }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 22, weight: .heavy))
                Text("Connect")
                    .font(Typography.font(24, .heavy))
            }
            .foregroundStyle(canConnect ? Color.white : Palette.text(0.4))
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(canConnect ? accent : Palette.text(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: canConnect ? accent.opacity(0.4) : .clear, radius: 22, y: 8)
        }
        .buttonStyle(FocusScaleStyle(scale: 1.03, cornerRadius: 16, outline: true))
        .focused($focusedField, equals: .connect)
        .disabled(!canConnect)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color(hex: "#E8544A"))
            Text(message)
                .font(Typography.font(18, .semibold))
                .foregroundStyle(Color(hex: "#F3B0AB"))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Color(hex: "#E8544A").opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color(hex: "#E8544A").opacity(0.4), lineWidth: 1))
    }

    // MARK: - Connecting

    private var connectingPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow("SETUP // CONNECTING")
                .padding(.bottom, 8)
            Text(server.connectStep >= ServerConnection.stepLabels.count ? "All set" : "Connecting…")
                .font(Typography.font(40, .black))
                .foregroundStyle(Palette.textPrimary)
            Text(server.hostReadout)
                .font(Mono.font(16))
                .foregroundStyle(Palette.text(0.45))
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 20) {
                ForEach(Array(ServerConnection.stepLabels.enumerated()), id: \.offset) { index, label in
                    StepRow(label: label, index: index, current: server.connectStep, accent: accent)
                }
            }
            .padding(.top, 40)

            if server.connectStep >= ServerConnection.stepLabels.count {
                successBanner
                    .padding(.top, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer(minLength: 0)
        }
        .padding(.init(top: 56, leading: 48, bottom: 52, trailing: 48))
        .frame(minHeight: 560, alignment: .top)
        .animation(.easeOut(duration: 0.35), value: server.connectStep)
    }

    private var successBanner: some View {
        HStack(spacing: 18) {
            Image(systemName: "checkmark")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(Color(hex: "#052012"))
                .frame(width: 46, height: 46)
                .background(Color(hex: "#58D399"), in: Circle())
                .shadow(color: Color(hex: "#58D399").opacity(0.6), radius: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text("Connection succeeded")
                    .font(Typography.font(26, .heavy))
                    .foregroundStyle(Color(hex: "#8CF0BE"))
                Text("Loading your home…")
                    .font(Mono.font(15))
                    .foregroundStyle(Color(hex: "#8CF0BE").opacity(0.7))
            }
            Spacer(minLength: 0)
        }
        .padding(.init(top: 22, leading: 26, bottom: 22, trailing: 26))
        .background(Color(hex: "#58D399").opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(hex: "#58D399").opacity(0.45), lineWidth: 1))
    }

    // MARK: - Shared field chrome

    private func field(placeholder: String, text: Binding<String>, field: Field, secure: Bool = false, mono: Bool = false) -> some View {
        AppTextField(placeholder: placeholder, text: text, secure: secure, mono: mono,
                     accent: accent, field: field, focus: $focusedField,
                     onSubmit: { advance(from: field) })
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text)
            .font(Mono.font(14))
            .tracking(3.4)
            .foregroundStyle(accent)
    }

    private func advance(from field: Field) {
        switch field {
        case .host: focusedField = .port
        case .port: focusedField = .username
        case .username: focusedField = .password
        case .password: focusedField = .apiKey
        case .apiKey, .connect:
            if canConnect { Task { await server.connect() } }
        case .server:
            break
        }
    }

    // MARK: - Derived state (mirrors the design's renderVals)

    private var hasKey: Bool { !server.apiKey.trimmingCharacters(in: .whitespaces).isEmpty }
    private var hasCred: Bool {
        !(server.username.trimmingCharacters(in: .whitespaces).isEmpty &&
          server.password.trimmingCharacters(in: .whitespaces).isEmpty)
    }
    private var credDim: Bool { hasKey && !hasCred }
    private var keyDim: Bool { hasCred && !hasKey }

    private var credTag: String { credDim ? "NOT REQUIRED" : (hasCred ? "IN USE" : "OPTIONAL") }
    private var keyTag: String { keyDim ? "NOT REQUIRED" : (hasKey ? "IN USE" : "OPTIONAL") }
    private var credTagColor: Color { credDim ? Palette.text(0.35) : (hasCred ? accent : Palette.text(0.4)) }
    private var keyTagColor: Color { keyDim ? Palette.text(0.35) : (hasKey ? accent : Palette.text(0.4)) }

    private var canConnect: Bool {
        !server.host.trimmingCharacters(in: .whitespaces).isEmpty &&
        (hasKey || (hasCred &&
                    !server.username.trimmingCharacters(in: .whitespaces).isEmpty &&
                    !server.password.trimmingCharacters(in: .whitespaces).isEmpty))
    }

    private var hintText: String {
        if canConnect { return "Ready to connect." }
        if server.host.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Enter your server host to continue."
        }
        return "Enter a username & password, or an API key."
    }
}

// MARK: - Sub-components

/// A titled credential group (Sign in / API key) that dims when the other auth
/// method is in use, exactly like the design's exclusivity treatment.
private struct AuthBox<Content: View>: View {
    let title: String
    let tag: String
    let tagColor: Color
    let active: Bool
    let dim: Bool
    let accent: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(Mono.font(14))
                    .tracking(2)
                    .foregroundStyle(Palette.text(0.62))
                Spacer(minLength: 0)
                Text(tag)
                    .font(Mono.font(12))
                    .tracking(1.2)
                    .foregroundStyle(tagColor)
            }
            content
        }
        .padding(22)
        .background(active ? accent.opacity(0.07) : .white.opacity(0.03),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(active ? accent.opacity(0.35) : .white.opacity(0.1), lineWidth: 1.5))
        .opacity(dim ? 0.4 : 1)
        .animation(.easeOut(duration: 0.25), value: dim)
        .animation(.easeOut(duration: 0.25), value: active)
    }
}

/// One line in the connecting log: a marker (check / spinner / dot) + label.
private struct StepRow: View {
    let label: String
    let index: Int
    let current: Int
    let accent: Color

    private var isDone: Bool { index < current }
    private var isActive: Bool { index == current && current < ServerConnection.stepLabels.count }

    var body: some View {
        HStack(spacing: 18) {
            marker
                .frame(width: 34, height: 34)
            Text(isActive ? "\(label)…" : label)
                .font(Typography.font(23, .semibold))
                .foregroundStyle(isDone ? Palette.text(0.85) : (isActive ? Palette.textPrimary : Palette.text(0.35)))
        }
        .opacity(isDone || isActive ? 1 : 0.55)
    }

    @ViewBuilder private var marker: some View {
        if isDone {
            Image(systemName: "checkmark")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Color(hex: "#58D399"))
        } else if isActive {
            ProgressView()
                .controlSize(.regular)
                .tint(accent)
        } else {
            Circle()
                .fill(.white.opacity(0.25))
                .frame(width: 9, height: 9)
        }
    }
}

/// The layered radial + gradient backdrop shared by the connect screen.
private struct SetupBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#080B12"), Color(hex: "#060810")],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(OKLCH(l: 0.34, c: 0.10, h: 235)).opacity(0.5), .clear],
                           center: UnitPoint(x: 0.82, y: 0.06), startRadius: 0, endRadius: 1100)
            RadialGradient(colors: [Color(OKLCH(l: 0.30, c: 0.09, h: 250)).opacity(0.34), .clear],
                           center: UnitPoint(x: -0.06, y: 1.08), startRadius: 0, endRadius: 900)
        }
        .ignoresSafeArea()
    }
}

/// The top-right concentric-ring sonar motif with a pulsing accent ring.
private struct SonarMotif: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle().stroke(Color(hex: "#78B4DC").opacity(0.1), lineWidth: 1)
                .frame(width: 720, height: 720)
            Circle().stroke(Color(hex: "#78B4DC").opacity(0.14), lineWidth: 1)
                .frame(width: 520, height: 520)
            Circle().stroke(SetupView.setupAccent.opacity(0.18), lineWidth: 1.5)
                .frame(width: 300, height: 300)
            Circle().stroke(SetupView.setupAccent, lineWidth: 2)
                .frame(width: 300, height: 300)
                .scaleEffect(pulse ? 1.9 : 0.7)
                .opacity(pulse ? 0 : 0.7)
        }
        .position(x: 1740, y: 120)
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 4).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}
