import Foundation
import Network

/// A minimal, real TCP listener on loopback — needed only because
/// `AVPlayer`/`AVURLAsset` have their own private networking stack and don't
/// consult app-registered `URLProtocol`s (only `URLSession`-based code does).
/// Answers every connection with a canned HTTP 302 redirect to a real
/// public-domain sample video; AVPlayer follows real HTTP redirects natively,
/// so no byte-proxying or bundled video asset is needed. Everything else
/// (JSON API + images) is answered by `MockJellyfinURLProtocol` instead,
/// which intercepts before any of this real networking ever happens.
actor MockVideoRedirectServer {
    static let shared = MockVideoRedirectServer()

    // Google's old gtv-videos-bucket sample (BigBuckBunny.mp4) now 403s —
    // swapped for Apple's own bipbop HLS test stream, which exists
    // specifically for AVPlayer testing and has stayed stable for years.
    static let sampleVideoURL = "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8"

    private var listener: NWListener?
    private var boundPort: UInt16?

    /// Starts the listener on first call; returns the already-bound port on
    /// subsequent calls. Returns 0 if the listener fails to come up.
    func start() async -> UInt16 {
        if let boundPort { return boundPort }

        guard let listener = try? NWListener(using: .tcp, on: .any) else { return 0 }
        listener.newConnectionHandler = { connection in
            Task { Self.handle(connection) }
        }

        let port: UInt16 = await withCheckedContinuation { continuation in
            let resumed = ResumeGuard()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let port = listener.port, resumed.claim() else { return }
                    continuation.resume(returning: port.rawValue)
                case .failed, .cancelled:
                    guard resumed.claim() else { return }
                    continuation.resume(returning: 0)
                default:
                    break
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
        }

        self.listener = listener
        self.boundPort = port
        return port
    }

    private static func handle(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { _, _, _, _ in
            let response = "HTTP/1.1 302 Found\r\nLocation: \(sampleVideoURL)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}

/// A once-only claim guard for `NWListener.stateUpdateHandler`, which can fire
/// multiple times — resuming a `CheckedContinuation` more than once traps, so
/// only the first `.ready`/`.failed`/`.cancelled` transition may act. A plain
/// captured `var` triggers Swift 6's sendable-closure-capture diagnostic since
/// the handler runs on the listener's own queue; this class-based lock avoids it.
private final class ResumeGuard: @unchecked Sendable {
    private var claimed = false
    private let lock = NSLock()

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
