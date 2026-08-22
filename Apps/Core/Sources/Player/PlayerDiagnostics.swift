import Foundation
import AVFoundation
import JellyTVKit
import os

/// Playback tracing, off unless `JT_PLAYER_LOG=1` is set in the environment
/// (same inert-unless-set convention as `JT_SHOW_MOVIES` and friends).
///
/// Exists because the two failure modes that matter most here are invisible
/// from the UI: a file that plays **audio with a black frame**, and a queue
/// that silently stops advancing. Neither surfaces as an `AVPlayerItem`
/// error — `status` stays `.readyToPlay` throughout — so the only way to
/// tell them apart from "working" is to print what the server negotiated
/// and what tracks AVFoundation actually ended up with.
///
/// Lines go to both `os_log` (visible in Console.app / `xcrun simctl spawn
/// … log stream`) and stdout, so a simulator run's captured runtime log
/// shows them without extra tooling.
enum PlayerDiagnostics {
    static let isEnabled = ProcessInfo.processInfo.environment["JT_PLAYER_LOG"] == "1"

    private static let logger = Logger(subsystem: "net.graficx.jellytv", category: "player")

    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let line = message()
        logger.info("\(line, privacy: .public)")
        print("[player] \(line)")
    }

    /// What the server negotiated for this item, and which URL we picked.
    static func logResolved(_ resolved: ResolvedPlayback, item: PlayableItem) {
        guard isEnabled else { return }
        let source = resolved.mediaSource
        let video = source.videoStream
        let audio = source.mediaStreams?.first { $0.type == "Audio" }
        log("""
        resolve "\(item.title)" [\(item.id)]
          container=\(source.container ?? "?") \
        directPlay=\(source.supportsDirectPlay.map(String.init) ?? "?") \
        directStream=\(source.supportsDirectStream.map(String.init) ?? "?")
          video=\(video?.codec ?? "?") profile=\(video?.profile ?? "?") \
        bitDepth=\(video?.bitDepth.map(String.init) ?? "?") \
        range=\(video?.videoRangeType ?? "?") \
        \(video?.width ?? 0)x\(video?.height ?? 0)
          audio=\(audio?.codec ?? "?")
          route=\(resolved.directURL != nil ? "DIRECT" : "HLS")
          url=\(redact(resolved.directURL ?? resolved.hlsURL))
        """)
    }

    /// The decisive check for "sound but no picture": once an item is
    /// `.readyToPlay`, ask AVFoundation what it actually loaded. A video
    /// track that is absent, `isPlayable == false`, or paired with a
    /// `presentationSize` of zero means the container/codec got through
    /// negotiation but not through the decoder.
    @MainActor
    static func logTracks(of item: AVPlayerItem, label: String) {
        guard isEnabled else { return }
        // `AVPlayerItem.tracks`, not `asset.loadTracks` — an HLS asset has no
        // statically-known tracks, so asking the *asset* always answers zero
        // and tells you nothing about whether video actually arrived.
        let video = item.tracks.filter { $0.assetTrack?.mediaType == .video }
        let audio = item.tracks.filter { $0.assetTrack?.mediaType == .audio }
        let descriptions = video.map { track -> String in
            let codes = (track.assetTrack?.formatDescriptions as? [CMFormatDescription] ?? [])
                .map { fourCC($0) }.joined(separator: ",")
            return "enabled=\(track.isEnabled) codec=\(codes.isEmpty ? "?" : codes)"
        }
        let size = item.presentationSize
        log("""
        tracks [\(label)] videoTracks=\(video.count) audioTracks=\(audio.count) \
        presentationSize=\(Int(size.width))x\(Int(size.height))
          \(descriptions.isEmpty ? "(no video track)" : descriptions.joined(separator: "\n  "))
          verdict=\(verdict(videoTrackCount: video.count, audioTrackCount: audio.count, size: size))
        """)
    }

    /// Dumps the master playlist (and its first variant) that Jellyfin
    /// generated. The `#EXT-X-STREAM-INF` line is where a `BANDWIDTH` that
    /// under-declares what the segments actually contain shows up — the
    /// cause of `CoreMediaErrorDomain -12318`, which AVPlayer reports by
    /// dropping the video and leaving audio running.
    static func dumpPlaylists(masterURL: URL, authHeader: String) async {
        guard isEnabled else { return }
        guard let master = await fetchText(masterURL, authHeader: authHeader) else {
            log("playlist FETCH FAILED \(redact(masterURL))")
            return
        }
        log("master.m3u8:\n\(master)")

        let variantLine = master
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") }
        guard let variantLine,
              let variantURL = URL(string: variantLine, relativeTo: masterURL)?.absoluteURL,
              let variant = await fetchText(variantURL, authHeader: authHeader) else { return }
        log("variant playlist (first 1500 chars):\n\(String(variant.prefix(1500)))")
    }

    private static func fetchText(_ url: URL, authHeader: String) async -> String? {
        var request = URLRequest(url: url)
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func verdict(videoTrackCount: Int, audioTrackCount: Int, size: CGSize) -> String {
        if videoTrackCount == 0 && audioTrackCount > 0 { return "AUDIO-ONLY — no video track reached the player" }
        if videoTrackCount > 0 && size == .zero { return "AUDIO-ONLY — video track present but never decoded" }
        if videoTrackCount == 0 && audioTrackCount == 0 { return "EMPTY — nothing loaded" }
        return "OK"
    }

    private static func fourCC(_ format: CMFormatDescription) -> String {
        let code = CMFormatDescriptionGetMediaSubType(format)
        let bytes = [
            UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "\(code)"
    }

    /// Keeps `api_key` out of the log — the URL is otherwise the single most
    /// useful line here, so log it with just that one param masked.
    private static func redact(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return url.absoluteString }
        components.queryItems = items.map {
            $0.name == "api_key" ? URLQueryItem(name: $0.name, value: "***") : $0
        }
        return components.url?.absoluteString ?? url.absoluteString
    }
}
