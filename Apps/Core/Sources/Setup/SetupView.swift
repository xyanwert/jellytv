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
    /// Phone only: whether the API KEY box is expanded below its disclosure
    /// row. See `phoneApiKeyDisclosure` — declared here (not `#if os(iOS)`)
    /// just to keep every `@State` declaration in one place.
    @State private var apiKeyExpanded = false

    /// The connect/login screen uses its own neon-purple accent, independent
    /// of the in-app theme color picked in Settings — that color still governs
    /// everything past sign-in.
    private var accent: Color { Self.setupAccent }
    fileprivate static let setupAccent = Color(hex: "#B14EFF")

    var body: some View {
        Group {
            #if os(iOS)
            if DeviceClass.current == .phone {
                phoneBody
            } else {
                padTVBody
            }
            #else
            padTVBody
            #endif
        }
        .preferredColorScheme(.dark)
        .defaultFocus($focusedField, .host)
        // Clear a stale error as soon as the user edits anything.
        .onChange(of: fieldsSignature) { server.errorMessage = nil }
        #if os(tvOS)
        .onExitCommand { /* only screen while disconnected — no-op */ }
        #endif
        .onAppear {
            // Auto-scan the LAN as soon as the connect screen shows.
            if case .disconnected = server.status { scanner.start() }
            #if os(iOS)
            // A pre-existing key (a demo hook, or a value left over from a
            // previous session) should show its box open, not hide it behind
            // the disclosure row on top of it.
            if hasKey { apiKeyExpanded = true }
            #endif
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

    /// iPad/tvOS: the existing split layout — a brand column beside a glass
    /// panel, both sized for a wide landscape canvas.
    private var padTVBody: some View {
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
    }

    private var fieldsSignature: String {
        [server.host, server.port, server.username, server.password, server.apiKey].joined(separator: "\u{1F}")
    }

    // MARK: - Brand column

    #if os(iOS)
    private static let brandColumnWidth: CGFloat = 440
    private static let brandLeadingPadding: CGFloat = 56
    private static let titleFontSize: CGFloat = 46
    private static let bodyFontSize: CGFloat = 18
    private static let bodyMaxWidth: CGFloat = 340
    #else
    private static let brandColumnWidth: CGFloat = 720
    private static let brandLeadingPadding: CGFloat = 110
    private static let titleFontSize: CGFloat = 72
    private static let bodyFontSize: CGFloat = 22
    private static let bodyMaxWidth: CGFloat = 480
    #endif

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
                    wordmark()
                    Text("JELLYFIN CLIENT")
                        .font(Mono.font(15))
                        .tracking(3.6)
                        .foregroundStyle(Palette.text(0.42))
                }
            }

            Text("Connect\nyour server")
                .font(Typography.font(Self.titleFontSize, .black))
                .tracking(-2)
                .lineSpacing(-4)
                .foregroundStyle(Palette.textPrimary)

            Text("Point Why.So.Jelly? at your Jellyfin server to stream your library. Sign in with a username and password, or paste an API key.")
                .font(Typography.font(Self.bodyFontSize, .medium))
                .lineSpacing(6)
                .foregroundStyle(Palette.text(0.6))
                .frame(maxWidth: Self.bodyMaxWidth, alignment: .leading)

            statusLine
                .padding(.top, 6)
        }
        .padding(.init(top: 96, leading: Self.brandLeadingPadding, bottom: 96, trailing: 0))
        .frame(width: Self.brandColumnWidth, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func wordmark(fontSize: CGFloat = 40) -> some View {
        (
            Text("Why").foregroundColor(Palette.textPrimary)
            + Text(".").foregroundColor(accent)
            + Text("So").foregroundColor(Palette.textPrimary)
            + Text(".").foregroundColor(accent)
            + Text("Jelly?").foregroundColor(Palette.textPrimary)
        )
        .font(Typography.font(fontSize, .black))
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

    #if os(iOS)
    private static let panelWidth: CGFloat = 480
    private static let panelTrailingPadding: CGFloat = 48
    #else
    private static let panelWidth: CGFloat = 760
    private static let panelTrailingPadding: CGFloat = 110
    #endif

    private var panelColumn: some View {
        panelCard
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.init(top: 70, leading: 40, bottom: 70, trailing: Self.panelTrailingPadding))
    }

    private var panelCard: some View {
        Group {
            if case .connecting = server.status {
                connectingPanel
            } else {
                formPanel
            }
        }
        .frame(width: Self.panelWidth)
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

            #if os(tvOS)
            if hostMode == .reel {
                reelEntry
            } else if hostMode == .manual {
                manualEntry
            }
            #else
            if hostMode == .manual {
                manualEntry
            }
            #endif
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
            #if os(tvOS)
            // The octet-reel entry only exists as a tvOS workaround for typing
            // an IP without a real keyboard — iOS just has "Manual".
            modeChip(title: "Enter IP", systemImage: "number", mode: .reel)
            #endif
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

    #if os(tvOS)
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
    #endif

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
            server.beginConnect()
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
            if canConnect { server.beginConnect() }
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

    // MARK: - Phone layout (`Connect.dc.html` / `Connecting.dc.html`)
    //
    // The iPad/tvOS layout is a ~920pt-wide `HStack` (a 440pt brand column
    // beside a 480pt panel) — on a 402pt-wide phone that rendered as the
    // brand column alone, with the whole form clipped off the trailing edge
    // entirely. This is a real second layout, not a resize: one scrolling
    // column, a compact brand row instead of the brand column's big vertical
    // block, discovery-first HOST section, SIGN IN open by default, and API
    // KEY collapsed behind a disclosure row (see `phoneApiKeyDisclosure`) so
    // the Connect button isn't pushed below the fold by a second open box
    // most people never need. Reuses every existing piece that isn't
    // iPad/tvOS-width-specific — `serverSection`, `AuthBox`, `field`,
    // `connectButton`, `errorBanner`, `StepRow`, `successBanner` — rather
    // than forking parallel copies of them.
    #if os(iOS)

    @ViewBuilder
    private var phoneBody: some View {
        ZStack {
            PhoneSetupBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    phoneBrandRow
                    if case .connecting = server.status {
                        phoneConnectingPanel
                    } else {
                        phoneFormPanel
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 58)
                .padding(.bottom, 48)
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .ignoresSafeArea()
    }

    private var phoneBrandRow: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image("AppMark")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
                    .shadow(color: .black.opacity(0.55), radius: 12, y: 8)
                VStack(alignment: .leading, spacing: 4) {
                    wordmark(fontSize: 24)
                    Text("JELLYFIN CLIENT")
                        .font(Mono.font(10))
                        .tracking(3)
                        .foregroundStyle(Palette.text(0.42))
                }
            }
            if case .connecting = server.status {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Connect your server")
                        .font(Typography.font(26, .black))
                        .tracking(-0.9)
                        .foregroundStyle(Palette.textPrimary)
                    statusLine
                }
            }
        }
    }

    private var phoneFormPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            serverSection

            AuthBox(
                title: "SIGN IN",
                tag: credTag, tagColor: credTagColor,
                active: hasCred, dim: credDim, accent: accent
            ) {
                field(placeholder: "Username", text: $server.username, field: .username)
                field(placeholder: "Password", text: $server.password, field: .password, secure: false)
            }

            phoneApiKeyDisclosure

            if let error = server.errorMessage {
                errorBanner(error)
            }

            VStack(spacing: 14) {
                connectButton
                Text(hintText)
                    .font(Typography.font(15, .medium))
                    .foregroundStyle(Palette.text(0.35))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.top, 4)
        }
    }

    /// **New behaviour, not just layout.** The API KEY box is the minority
    /// path (most people sign in with a username/password), and on iPad/tvOS
    /// it can afford to sit open beside SIGN IN because there's a whole
    /// second column of width to spend on it. Stacked into one phone column
    /// that box pushes the Connect button below the fold — so here it starts
    /// collapsed behind this disclosure row and only becomes the full
    /// `AuthBox` (with the same `keyDim`/`credDim` exclusivity dimming) once
    /// tapped open. `apiKeyExpanded` is sticky once set — collapsing it again
    /// after typing a key doesn't clear the field, only hides the box.
    private var phoneApiKeyDisclosure: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                apiKeyExpanded.toggle()
                if apiKeyExpanded { focusedField = .apiKey }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.text(0.5))
                    Text("Use an API key instead")
                        .font(Typography.font(15, .bold))
                        .foregroundStyle(Palette.text(0.68))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.text(0.35))
                        .rotationEffect(.degrees(apiKeyExpanded ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(Palette.text(0.04), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Palette.text(0.1), lineWidth: 1))
            }
            .buttonStyle(.plain)

            if apiKeyExpanded {
                AuthBox(
                    title: "API KEY",
                    tag: keyTag, tagColor: keyTagColor,
                    active: hasKey, dim: keyDim, accent: accent
                ) {
                    field(placeholder: "Paste API key", text: $server.apiKey, field: .apiKey, mono: true)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: apiKeyExpanded)
    }

    private var phoneConnectingPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow("SETUP // CONNECTING")
                .padding(.bottom, 8)
            Text(server.connectStep >= ServerConnection.stepLabels.count ? "All set" : "Connecting…")
                .font(Typography.font(32, .black))
                .foregroundStyle(Palette.textPrimary)
            Text(server.hostReadout)
                .font(Mono.font(13))
                .foregroundStyle(Palette.text(0.45))
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 22) {
                ForEach(Array(ServerConnection.stepLabels.enumerated()), id: \.offset) { index, label in
                    StepRow(label: label, index: index, current: server.connectStep, accent: accent)
                }
            }
            .padding(.top, 34)

            if server.connectStep >= ServerConnection.stepLabels.count {
                successBanner
                    .padding(.top, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                // The escape hatch the iPad/tvOS panel doesn't have — see
                // `ServerConnection.cancelConnect()`. Hidden once the success
                // banner shows: by then the connection has already succeeded
                // and credentials are saved, so there's nothing left to cancel.
                phoneCancelButton
                    .padding(.top, 36)
            }
        }
        .animation(.easeOut(duration: 0.35), value: server.connectStep)
    }

    private var phoneCancelButton: some View {
        Button {
            server.cancelConnect()
        } label: {
            Text("Cancel")
                .font(Typography.font(16, .heavy))
                .foregroundStyle(Palette.text(0.6))
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Palette.text(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.text(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
    #endif
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

#if os(iOS)
/// The phone connect screen's backdrop — the same violet radial glow and
/// concentric sonar rings as `SetupBackground`/`SonarMotif`, repositioned for
/// a phone's actual top-right corner instead of those two components' fixed
/// pixel offsets (tuned for the iPad/tvOS landscape canvas — `SonarMotif`
/// alone sits at x=1740, which is off the right edge of a ~400pt-wide phone
/// entirely). Matches `Connect.dc.html`'s own radial-gradient + ring corner
/// treatment rather than `SetupBackground`'s blue-toned glow — the design
/// ties this screen's background tint to its own neon-purple accent.
private struct PhoneSetupBackdrop: View {
    @State private var pulse = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: "#07080C")
                RadialGradient(
                    stops: [
                        .init(color: Color(hex: "#241338"), location: 0),
                        .init(color: Color(hex: "#150b22"), location: 0.38),
                        .init(color: Color(hex: "#0a0710"), location: 0.72),
                        .init(color: Color(hex: "#07080C"), location: 1),
                    ],
                    center: UnitPoint(x: 0.82, y: 0.04),
                    startRadius: 0, endRadius: geo.size.height * 0.62
                )
                ringMotif
                    .position(x: geo.size.width * 0.85, y: 66)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 4).repeatForever(autoreverses: false)) { pulse = true }
        }
    }

    private var ringMotif: some View {
        ZStack {
            Circle().stroke(SetupView.setupAccent.opacity(0.06), lineWidth: 1).frame(width: 412, height: 412)
            Circle().stroke(SetupView.setupAccent.opacity(0.12), lineWidth: 1).frame(width: 252, height: 252)
            Circle().stroke(SetupView.setupAccent.opacity(0.2), lineWidth: 1).frame(width: 116, height: 116)
            Circle().stroke(SetupView.setupAccent, lineWidth: 1.5)
                .frame(width: 116, height: 116)
                .scaleEffect(pulse ? 1.9 : 0.7)
                .opacity(pulse ? 0 : 0.7)
        }
        .allowsHitTesting(false)
    }
}
#endif
