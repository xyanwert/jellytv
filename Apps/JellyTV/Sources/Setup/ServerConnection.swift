import SwiftUI
import JellyTVKit

/// Manages the Jellyfin server connection lifecycle: input validation,
/// authentication, and connection state. Persists credentials to UserDefaults.
@MainActor
final class ServerConnection: ObservableObject {
    enum Status: Equatable {
        case disconnected
        case connecting(String)      // status message
        case connected(ServerInfo)
    }

    struct ServerInfo: Equatable {
        let name: String
        let version: String
        let userId: String
        let apiKey: String
        let baseURL: URL
    }

    @Published var status: Status = .disconnected

    /// Number of completed steps in the connecting sequence (0...4). The active
    /// step is at index `connectStep`; when it reaches `Self.stepLabels.count`
    /// every step is done and the success banner shows. Drives the progress log.
    @Published var connectStep: Int = 0
    /// A human-readable failure message shown on the setup form after a failed
    /// attempt (nil while idle or mid-connect).
    @Published var errorMessage: String?

    /// The staged log shown while connecting. Each real milestone advances one.
    static let stepLabels = [
        "Reaching server",
        "Handshake established",
        "Authenticating",
        "Synchronizing libraries",
    ]

    // Input fields
    @Published var host: String = ""
    @Published var port: String = "8096"
    @Published var username: String = ""
    @Published var password: String = ""
    @Published var apiKey: String = ""

    // Persisted state
    private let userDefaults = UserDefaults.standard
    private let hostKey = "jelly:server.host"
    private let portKey = "jelly:server.port"
    private let apiKeyKey = "jelly:auth.apiKey"
    private let userIdKey = "jelly:auth.userId"
    private let deviceName = "JellyTV"

    /// Whether we have valid stored credentials.
    var isConnected: Bool {
        if case .connected = status { return true }
        return false
    }

    /// The server info when connected.
    var serverInfo: ServerInfo? {
        if case .connected(let info) = status { return info }
        return nil
    }

    var deviceId: String {
        if let existing = userDefaults.string(forKey: "jelly:device.id"), !existing.isEmpty { return existing }
        let id = UUID().uuidString
        userDefaults.set(id, forKey: "jelly:device.id")
        return id
    }

    /// `host:port` for progress/error readouts, falling back to placeholders.
    var hostReadout: String {
        let h = host.trimmingCharacters(in: .whitespaces)
        let p = port.trimmingCharacters(in: .whitespaces)
        return "\(h.isEmpty ? "server" : h):\(p.isEmpty ? "8096" : p)"
    }

    init() {
        // Hydrate from UserDefaults
        host = userDefaults.string(forKey: hostKey) ?? ""
        port = userDefaults.string(forKey: portKey) ?? "8096"
        apiKey = userDefaults.string(forKey: apiKeyKey) ?? ""

        // Screenshot/testing hook: force a specific setup state (see below).
        if applyDemoHook() { return }

        // If we have stored credentials, try to reconnect
        if let storedHost = userDefaults.string(forKey: hostKey),
           !storedHost.isEmpty,
           let storedApiKey = userDefaults.string(forKey: apiKeyKey),
           !storedApiKey.isEmpty {
            host = storedHost
            if let storedPort = userDefaults.string(forKey: portKey) {
                port = storedPort
            }
            apiKey = storedApiKey
            // Enter the connecting state synchronously so the very first frame is
            // the progress screen, not a flash of the empty form.
            status = .connecting("Reconnecting…")
            Task { await reconnect() }
        }
    }

    /// Screenshot/testing hook: `JT_SETUP_DEMO` forces a specific setup state so
    /// the form/exclusivity/progress/success/error screens can be captured
    /// without live typing. Returns true if a state was applied (skips
    /// auto-reconnect). No effect in normal launches.
    private func applyDemoHook() -> Bool {
        guard let demo = ProcessInfo.processInfo.environment["JT_SETUP_DEMO"] else { return false }
        host = "media.local"
        port = "8096"
        switch demo {
        case "filled":                       // valid via API key → key IN USE, sign-in dimmed
            apiKey = "b3f1a9d47c2e4f80a1c6"
        case "creds":                        // valid via username/password → API key dimmed
            username = "alex"
            password = "seahorse"
            apiKey = ""
        case "connecting":                   // mid-progress log
            apiKey = "b3f1a9d47c2e4f80a1c6"
            connectStep = Int(ProcessInfo.processInfo.environment["JT_STEP"] ?? "2") ?? 2
            status = .connecting("Connecting…")
        case "success":                      // final success banner
            apiKey = "b3f1a9d47c2e4f80a1c6"
            connectStep = Self.stepLabels.count
            status = .connecting("Connecting…")
        case "error":                        // failed attempt back on the form
            apiKey = "b3f1a9d47c2e4f80a1c6"
            errorMessage = "Username or password is incorrect."
        default:
            return false
        }
        return true
    }

    /// Validate inputs and attempt a connection, driving `connectStep` through
    /// the staged log as each real milestone completes. On failure, sets
    /// `errorMessage` and returns to the form; on success, holds the "All set"
    /// banner briefly before flipping to `.connected` (which routes to Home).
    func connect() async {
        errorMessage = nil
        guard let baseURL = buildURL() else {
            fail("Enter a valid server host to continue.")
            return
        }
        guard hasAnyCredentials else {
            fail("Enter a username & password, or an API key.")
            return
        }

        status = .connecting("Connecting…")
        connectStep = 0
        await dwell()   // let "Reaching server…" register

        // Steps 1 & 2 — reach + handshake, verified with the unauthenticated
        // public info endpoint (also gives us the server name for both modes).
        guard let publicInfo = await fetchPublicSystemInfo(baseURL: baseURL) else {
            fail("Couldn't reach a Jellyfin server at \(hostReadout). Check the host and port.")
            return
        }
        connectStep = 2
        await dwell()

        // Step 3 — authenticate (API key or username/password).
        var finalApiKey = apiKey
        let userId: String

        if !apiKey.isEmpty {
            let resolved = username.isEmpty
                ? await fetchFirstUserId(baseURL: baseURL, apiKey: apiKey)
                : await resolveUser(baseURL: baseURL, apiKey: apiKey, username: username)
            guard let resolved else {
                fail("The server is reachable, but that API key was rejected.")
                return
            }
            userId = resolved
        } else {
            switch await authenticateByName(baseURL: baseURL, username: username, password: password) {
            case .success(let auth):
                finalApiKey = auth.accessToken
                userId = auth.userId
            case .failure(let reason):
                fail(reason)
                return
            }
        }
        connectStep = 3
        await dwell()

        // Step 4 — synchronize + persist.
        saveCredentials(host: host, port: port, apiKey: finalApiKey, userId: userId)
        await dwell()
        connectStep = 4   // shows the "All set" success banner

        let info = ServerInfo(
            name: publicInfo.name,
            version: publicInfo.version,
            userId: userId,
            apiKey: finalApiKey,
            baseURL: baseURL
        )
        // Hold the success banner (status stays .connecting so RootView keeps
        // showing this screen), then flip to Home.
        try? await Task.sleep(for: .milliseconds(1100))
        status = .connected(info)
    }

    /// Reconnect with stored credentials, driving the same visible steps.
    /// Retries up to 3 times with increasing backoff if the server is unreachable,
    /// so a slow network or server restart doesn't dump the user on the form.
    private func reconnect() async {
        guard let baseURL = buildURL(), !apiKey.isEmpty else {
            status = .disconnected
            return
        }

        for attempt in 1...3 {
            status = .connecting("Reconnecting…")
            connectStep = 0

            guard let publicInfo = await fetchPublicSystemInfo(baseURL: baseURL) else {
                if attempt < 3 {
                    connectStep = 0
                    errorMessage = "Server unreachable. Retrying (\(attempt)/3)…"
                    try? await Task.sleep(for: .seconds(TimeInterval(attempt * 2)))
                    continue
                }
                fail("Couldn't reach \(hostReadout). Sign in again.")
                return
            }
            connectStep = 2

            guard await fetchFirstUserId(baseURL: baseURL, apiKey: apiKey) != nil else {
                fail("Your saved session has expired. Sign in again.")
                return
            }
            connectStep = 4

            let userId = userDefaults.string(forKey: userIdKey) ?? ""
            status = .connected(ServerInfo(
                name: publicInfo.name,
                version: publicInfo.version,
                userId: userId,
                apiKey: apiKey,
                baseURL: baseURL
            ))
            return
        }
    }

    /// True when the user has supplied at least one usable credential.
    private var hasAnyCredentials: Bool {
        let hasKey = !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
        let hasUserPass = !username.trimmingCharacters(in: .whitespaces).isEmpty &&
                          !password.trimmingCharacters(in: .whitespaces).isEmpty
        return hasKey || hasUserPass
    }

    /// Report a failed attempt: surface the message and return to the form.
    private func fail(_ message: String) {
        errorMessage = message
        connectStep = 0
        status = .disconnected
    }

    /// Minimum dwell between steps so the staged log stays legible even against
    /// a fast local server.
    private func dwell() async {
        try? await Task.sleep(for: .milliseconds(430))
    }

    /// Sign out: clear credentials and reset state.
    func signOut() {
        userDefaults.removeObject(forKey: hostKey)
        userDefaults.removeObject(forKey: portKey)
        userDefaults.removeObject(forKey: apiKeyKey)
        userDefaults.removeObject(forKey: userIdKey)
        apiKey = ""
        username = ""
        password = ""
        connectStep = 0
        errorMessage = nil
        status = .disconnected
    }

    // MARK: - Private

    private func buildURL() -> URL? {
        let hostTrimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let portTrimmed = port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hostTrimmed.isEmpty else { return nil }
        let urlString = "http://\(hostTrimmed):\(portTrimmed)"
        return URL(string: urlString)
    }

    private func saveCredentials(host: String, port: String, apiKey: String, userId: String) {
        userDefaults.set(host, forKey: hostKey)
        userDefaults.set(port, forKey: portKey)
        userDefaults.set(apiKey, forKey: apiKeyKey)
        userDefaults.set(userId, forKey: userIdKey)
    }

    // MARK: - API Calls

    /// Unauthenticated reachability + identity check via `/System/Info/Public`.
    /// Confirms the host is actually a Jellyfin server before we try to auth.
    private func fetchPublicSystemInfo(baseURL: URL) async -> (name: String, version: String)? {
        guard let url = URL(string: "System/Info/Public", relativeTo: baseURL) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            let info = try JSONDecoder().decode(JellyfinAPI.PublicSystemInfo.self, from: data)
            return (info.serverName ?? "Jellyfin", info.version ?? "Unknown")
        } catch {
            return nil
        }
    }

    /// Attempts `AuthenticateByName`. On failure, the reason string surfaces the
    /// server's actual HTTP status (and message body, if any) instead of always
    /// assuming a bad password — a 401 lockout, a malformed request, or a
    /// network hiccup all look identical to the user otherwise.
    enum AuthOutcome {
        case success(JellyfinAPI.AuthenticationResult)
        case failure(String)
    }

    private func authenticateByName(baseURL: URL, username: String, password: String) async -> AuthOutcome {
        guard let url = URL(string: "Users/AuthenticateByName", relativeTo: baseURL) else {
            return .failure("Couldn't build the sign-in request URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // No Token attribute here (unlike the normal authorized-request header) —
        // some Jellyfin server versions try to resolve an explicit `Token=""` on
        // this pre-auth call and reject the whole request with a 400 before ever
        // looking at the body.
        request.setValue(preAuthHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let body = ["Username": username, "Pw": password]
        request.httpBody = try? JSONEncoder().encode(body)

        #if DEBUG
        print("[Auth] POST \(url.absoluteString)")
        print("[Auth] Authorization: \(preAuthHeader())")
        print("[Auth] body bytes: \(request.httpBody?.count ?? 0), username length: \(username.count)")
        #endif

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure("No response from the server.")
            }
            #if DEBUG
            print("[Auth] status: \(httpResponse.statusCode)")
            print("[Auth] response headers: \(httpResponse.allHeaderFields)")
            print("[Auth] response body: \(String(data: data, encoding: .utf8) ?? "<\(data.count) non-UTF8 bytes>")")
            #endif
            guard httpResponse.statusCode == 200 else {
                let serverMessage = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let detail = (serverMessage?.isEmpty == false) ? " — \(serverMessage!)" : ""
                return .failure("Sign-in rejected (HTTP \(httpResponse.statusCode))\(detail)")
            }
            return .success(try JSONDecoder().decode(JellyfinAPI.AuthenticationResult.self, from: data))
        } catch {
            #if DEBUG
            print("[Auth] request error: \(error)")
            #endif
            return .failure("Sign-in request failed: \(error.localizedDescription)")
        }
    }

    private func resolveUser(baseURL: URL, apiKey: String, username: String) async -> String? {
        guard let url = URL(string: "Users", relativeTo: baseURL) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(mediaBrowserHeader(apiKey: apiKey), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            let users = try JSONDecoder().decode([JellyfinAPI.User].self, from: data)
            // Match by name (case-insensitive)
            return users.first { $0.name.lowercased() == username.lowercased() }?.id
        } catch {
            return nil
        }
    }

    private func fetchFirstUserId(baseURL: URL, apiKey: String) async -> String? {
        guard let url = URL(string: "Users", relativeTo: baseURL) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(mediaBrowserHeader(apiKey: apiKey), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            let users = try JSONDecoder().decode([JellyfinAPI.User].self, from: data)
            return users.first?.id
        } catch {
            return nil
        }
    }

    private func mediaBrowserHeader(apiKey: String) -> String {
        JellyfinAPI.authorizationHeader(token: apiKey,
                                        client: deviceName,
                                        device: deviceName,
                                        deviceId: deviceId,
                                        version: "1.0.0")
    }

    /// Header for calls made before we have a token (`AuthenticateByName`) —
    /// no `Token` attribute at all, rather than an empty one.
    private func preAuthHeader() -> String {
        "MediaBrowser Client=\"\(deviceName)\", Device=\"\(deviceName)\", DeviceId=\"\(deviceId)\", Version=\"1.0.0\""
    }
}
