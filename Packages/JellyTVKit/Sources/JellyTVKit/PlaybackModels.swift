import Foundation

extension JellyfinAPI {

    // MARK: - PlaybackInfo request/response

    /// Body of `POST /Items/{itemId}/PlaybackInfo`. AVPlayer is strict about
    /// codecs — without an explicit `DeviceProfile` declaring what we can
    /// direct-play, Jellyfin re-encodes everything to a low-bitrate H.264
    /// variant regardless of what the source actually needs.
    public struct PlaybackInfoRequest: Encodable, Sendable {
        public let userId: String
        public let deviceProfile: DeviceProfile
        public let enableDirectPlay = true
        public let enableDirectStream = true
        public let enableTranscoding = true
        public let allowVideoStreamCopy = true
        public let allowAudioStreamCopy = true

        public init(userId: String, deviceProfile: DeviceProfile = .tvOS) {
            self.userId = userId
            self.deviceProfile = deviceProfile
        }

        enum CodingKeys: String, CodingKey {
            case userId = "UserId"
            case deviceProfile = "DeviceProfile"
            case enableDirectPlay = "EnableDirectPlay"
            case enableDirectStream = "EnableDirectStream"
            case enableTranscoding = "EnableTranscoding"
            case allowVideoStreamCopy = "AllowVideoStreamCopy"
            case allowAudioStreamCopy = "AllowAudioStreamCopy"
        }
    }

    public struct PlaybackInfoResponse: Decodable, Sendable {
        /// Optional — Jellyfin omits it on error responses.
        public let playSessionId: String?
        public let mediaSources: [MediaSource]
        /// Server-side reason when there's nothing playable; nil for healthy items.
        public let errorCode: String?

        enum CodingKeys: String, CodingKey {
            case playSessionId = "PlaySessionId"
            case mediaSources = "MediaSources"
            case errorCode = "ErrorCode"
        }

        public init(playSessionId: String? = nil, mediaSources: [MediaSource] = [], errorCode: String? = nil) {
            self.playSessionId = playSessionId
            self.mediaSources = mediaSources
            self.errorCode = errorCode
        }
    }

    // MARK: - Device profile

    /// What this device can decode natively + which transcoded fallbacks it
    /// accepts.
    public struct DeviceProfile: Encodable, Sendable {
        public let maxStreamingBitrate: Int
        public let maxStaticBitrate: Int
        public let musicStreamingTranscodingBitrate: Int
        public let directPlayProfiles: [DirectPlayProfile]
        public let transcodingProfiles: [TranscodingProfile]
        public let codecProfiles: [CodecProfile]
        /// How subtitles may reach this client — see `SubtitleProfile`.
        public let subtitleProfiles: [SubtitleProfile]

        enum CodingKeys: String, CodingKey {
            case maxStreamingBitrate = "MaxStreamingBitrate"
            case maxStaticBitrate = "MaxStaticBitrate"
            case musicStreamingTranscodingBitrate = "MusicStreamingTranscodingBitrate"
            case directPlayProfiles = "DirectPlayProfiles"
            case transcodingProfiles = "TranscodingProfiles"
            case codecProfiles = "CodecProfiles"
            case subtitleProfiles = "SubtitleProfiles"
        }

        /// Apple TV profile: modern Apple TV hardware decodes H.264 high@5.2
        /// and HEVC main10 natively across mp4/m4v/mov/mkv containers.
        public static let tvOS = DeviceProfile(
            maxStreamingBitrate: 60_000_000,
            maxStaticBitrate: 100_000_000,
            musicStreamingTranscodingBitrate: 384_000,
            directPlayProfiles: [
                DirectPlayProfile(container: "mp4,m4v,mov", videoCodec: "h264,hevc,h265,mpeg4",
                                   audioCodec: "aac,mp3,ac3,eac3,flac,alac,opus"),
                DirectPlayProfile(container: "mkv", videoCodec: "h264,hevc,h265,vp9,av1",
                                   audioCodec: "aac,mp3,ac3,eac3,flac,alac,opus,vorbis"),
            ],
            transcodingProfiles: [
                // Force MPEG-TS segments (not fmp4) — fmp4 has a remux bug
                // with MKV timestamps that produces unplayable segments.
                TranscodingProfile(container: "ts", type: "Video", videoCodec: "h264", audioCodec: "aac,mp3",
                                    context: "Streaming", protocol: "hls", maxAudioChannels: "6",
                                    minSegments: 1, breakOnNonKeyFrames: true, segmentContainer: "ts"),
            ],
            codecProfiles: [
                CodecProfile(type: "Video", codec: "h264", conditions: [
                    .lessThanEqual(property: "VideoLevel", value: "52"),
                    .equalsAny(property: "VideoProfile", value: "high|main|baseline|constrained baseline"),
                ]),
            ],
            subtitleProfiles: SubtitleProfile.avPlayer
        )

        public init(maxStreamingBitrate: Int, maxStaticBitrate: Int, musicStreamingTranscodingBitrate: Int,
                    directPlayProfiles: [DirectPlayProfile], transcodingProfiles: [TranscodingProfile],
                    codecProfiles: [CodecProfile], subtitleProfiles: [SubtitleProfile] = SubtitleProfile.avPlayer) {
            self.maxStreamingBitrate = maxStreamingBitrate
            self.maxStaticBitrate = maxStaticBitrate
            self.musicStreamingTranscodingBitrate = musicStreamingTranscodingBitrate
            self.directPlayProfiles = directPlayProfiles
            self.transcodingProfiles = transcodingProfiles
            self.codecProfiles = codecProfiles
            self.subtitleProfiles = subtitleProfiles
        }
    }

    /// One way a subtitle format may be delivered: `External` (fetched on
    /// its own as WebVTT — the app draws it), `Hls` (a rendition in the
    /// transcode's master playlist), `Encode` (burned into the picture, the
    /// only route for bitmap tracks: PGS, VobSub). Verified against Jellyfin
    /// 12: text tracks resolve `Hls` on a transcode and `External` for a
    /// sidecar, and PGS burns in whether declared or not — declared anyway,
    /// as every mainstream client does.
    public struct SubtitleProfile: Encodable, Sendable {
        public let format: String
        public let method: String

        enum CodingKeys: String, CodingKey {
            case format = "Format"
            case method = "Method"
        }

        public init(format: String, method: String) {
            self.format = format
            self.method = method
        }

        public static let avPlayer: [SubtitleProfile] = [
            SubtitleProfile(format: "vtt", method: "Hls"),
            SubtitleProfile(format: "vtt", method: "External"),
            SubtitleProfile(format: "srt", method: "External"),
            SubtitleProfile(format: "pgssub", method: "Encode"),
            SubtitleProfile(format: "dvdsub", method: "Encode"),
        ]
    }

    public struct DirectPlayProfile: Encodable, Sendable {
        public let container: String
        public let type = "Video"
        public let videoCodec: String
        public let audioCodec: String

        enum CodingKeys: String, CodingKey {
            case container = "Container"
            case type = "Type"
            case videoCodec = "VideoCodec"
            case audioCodec = "AudioCodec"
        }

        public init(container: String, videoCodec: String, audioCodec: String) {
            self.container = container
            self.videoCodec = videoCodec
            self.audioCodec = audioCodec
        }
    }

    public struct TranscodingProfile: Encodable, Sendable {
        public let container: String
        public let type: String
        public let videoCodec: String
        public let audioCodec: String
        public let context: String
        public let `protocol`: String
        public let maxAudioChannels: String
        public let minSegments: Int
        public let breakOnNonKeyFrames: Bool
        public let segmentContainer: String

        enum CodingKeys: String, CodingKey {
            case container = "Container"
            case type = "Type"
            case videoCodec = "VideoCodec"
            case audioCodec = "AudioCodec"
            case context = "Context"
            case `protocol` = "Protocol"
            case maxAudioChannels = "MaxAudioChannels"
            case minSegments = "MinSegments"
            case breakOnNonKeyFrames = "BreakOnNonKeyFrames"
            case segmentContainer = "SegmentContainer"
        }

        public init(container: String, type: String, videoCodec: String, audioCodec: String, context: String,
                    protocol: String, maxAudioChannels: String, minSegments: Int, breakOnNonKeyFrames: Bool,
                    segmentContainer: String) {
            self.container = container
            self.type = type
            self.videoCodec = videoCodec
            self.audioCodec = audioCodec
            self.context = context
            self.protocol = `protocol`
            self.maxAudioChannels = maxAudioChannels
            self.minSegments = minSegments
            self.breakOnNonKeyFrames = breakOnNonKeyFrames
            self.segmentContainer = segmentContainer
        }
    }

    public struct CodecProfile: Encodable, Sendable {
        public let type: String
        public let codec: String
        public let conditions: [ProfileCondition]

        enum CodingKeys: String, CodingKey {
            case type = "Type"
            case codec = "Codec"
            case conditions = "Conditions"
        }

        public init(type: String, codec: String, conditions: [ProfileCondition]) {
            self.type = type
            self.codec = codec
            self.conditions = conditions
        }
    }

    public struct ProfileCondition: Encodable, Sendable {
        public let condition: String
        public let property: String
        public let value: String
        public let isRequired: Bool

        enum CodingKeys: String, CodingKey {
            case condition = "Condition"
            case property = "Property"
            case value = "Value"
            case isRequired = "IsRequired"
        }

        public static func lessThanEqual(property: String, value: String) -> ProfileCondition {
            ProfileCondition(condition: "LessThanEqual", property: property, value: value, isRequired: false)
        }

        public static func equalsAny(property: String, value: String) -> ProfileCondition {
            ProfileCondition(condition: "EqualsAny", property: property, value: value, isRequired: false)
        }
    }

    // MARK: - Media source (a playable variant returned by PlaybackInfo)

    public struct MediaSource: Decodable, Equatable, Sendable {
        public let id: String
        public let container: String?
        public let supportsDirectPlay: Bool?
        public let supportsDirectStream: Bool?
        public let mediaStreams: [MediaStream]?

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case container = "Container"
            case supportsDirectPlay = "SupportsDirectPlay"
            case supportsDirectStream = "SupportsDirectStream"
            case mediaStreams = "MediaStreams"
        }

        public init(id: String, container: String? = nil, supportsDirectPlay: Bool? = nil,
                    supportsDirectStream: Bool? = nil, mediaStreams: [MediaStream]? = nil) {
            self.id = id
            self.container = container
            self.supportsDirectPlay = supportsDirectPlay
            self.supportsDirectStream = supportsDirectStream
            self.mediaStreams = mediaStreams
        }

        /// Whether AVPlayer should attempt direct-play instead of HLS. Trusts
        /// Jellyfin's own flag — we've told it exactly which containers/codecs
        /// we handle via `DeviceProfile`, so second-guessing it client-side
        /// with a hardcoded allowlist is how you route a perfectly
        /// direct-playable file through an unnecessary transcode.
        public var canDirectPlayNatively: Bool { supportsDirectPlay == true }

        public var videoStream: MediaStream? { mediaStreams?.first { $0.type == "Video" } }
    }

    public struct MediaStream: Decodable, Equatable, Sendable {
        public let type: String?
        public let codec: String?
        public let width: Int?
        public let height: Int?
        /// Jellyfin's stream index — what `AudioStreamIndex` /
        /// `SubtitleStreamIndex` on the streaming URL name.
        public let index: Int?
        /// ISO 639-2 as the file tagged it ("eng", "spa", also "deu"/"ger",
        /// "und"); `LanguageTable.canonical` before comparing.
        public let language: String?
        /// Jellyfin's own label — "English - AC3 - 5.1 - Default".
        public let displayTitle: String?
        /// The track's own title, where the file has one ("Commentary").
        public let title: String?
        public let isDefault: Bool?
        public let isForced: Bool?
        /// A sidecar file (.srt beside the video) rather than an embedded track.
        public let isExternal: Bool?
        /// Text (subrip, ass, mov_text, vtt) as opposed to a bitmap (PGS, VobSub).
        public let isTextSubtitleStream: Bool?
        public let channels: Int?
        /// Only on a `PlaybackInfo` response, never on `/Items?fields=MediaStreams`.
        public let deliveryMethod: String?
        public let deliveryUrl: String?
        /// Codec profile — "High", "Main 10", "High 10", … The distinction
        /// AVFoundation cares about: "High 10" (Hi10P) and "Main 10" are not
        /// decodable by Apple hardware in every container/segment combination.
        public let profile: String?
        /// 8 or 10. 10-bit content is the usual reason a file that "should"
        /// direct-play comes back audio-only.
        public let bitDepth: Int?
        /// "SDR", "HDR10", "DOVI", "HLG" — Dolby Vision profile 5 renders as
        /// audio-only/garbled on clients that don't negotiate it explicitly.
        public let videoRangeType: String?

        enum CodingKeys: String, CodingKey {
            case type = "Type"
            case codec = "Codec"
            case width = "Width"
            case height = "Height"
            case index = "Index"
            case language = "Language"
            case displayTitle = "DisplayTitle"
            case title = "Title"
            case isDefault = "IsDefault"
            case isForced = "IsForced"
            case isExternal = "IsExternal"
            case isTextSubtitleStream = "IsTextSubtitleStream"
            case channels = "Channels"
            case deliveryMethod = "DeliveryMethod"
            case deliveryUrl = "DeliveryUrl"
            case profile = "Profile"
            case bitDepth = "BitDepth"
            case videoRangeType = "VideoRangeType"
        }

        public init(type: String? = nil, codec: String? = nil, width: Int? = nil, height: Int? = nil,
                    profile: String? = nil, bitDepth: Int? = nil, videoRangeType: String? = nil,
                    index: Int? = nil, language: String? = nil, displayTitle: String? = nil, title: String? = nil,
                    isDefault: Bool? = nil, isForced: Bool? = nil, isExternal: Bool? = nil,
                    isTextSubtitleStream: Bool? = nil, channels: Int? = nil,
                    deliveryMethod: String? = nil, deliveryUrl: String? = nil) {
            self.type = type
            self.codec = codec
            self.width = width
            self.height = height
            self.profile = profile
            self.bitDepth = bitDepth
            self.videoRangeType = videoRangeType
            self.index = index
            self.language = language
            self.displayTitle = displayTitle
            self.title = title
            self.isDefault = isDefault
            self.isForced = isForced
            self.isExternal = isExternal
            self.isTextSubtitleStream = isTextSubtitleStream
            self.channels = channels
            self.deliveryMethod = deliveryMethod
            self.deliveryUrl = deliveryUrl
        }

        /// The language by its own name, or the track's title / codec when
        /// it has no language tag — never a bare "und".
        public var languageLabel: String {
            if LanguageTable.canonical(language) != nil { return LanguageTable.endonym(for: language) }
            if let title, !title.isEmpty { return title }
            return "Unknown"
        }
    }

    /// One line of a text subtitle track, from `…/Subtitles/{index}/0/Stream.js`.
    public struct SubtitleCue: Decodable, Equatable, Sendable {
        public let text: String
        public let startTicks: Int64
        public let endTicks: Int64

        enum CodingKeys: String, CodingKey {
            case text = "Text"
            case startTicks = "StartPositionTicks"
            case endTicks = "EndPositionTicks"
        }

        public init(text: String, startTicks: Int64, endTicks: Int64) {
            self.text = text
            self.startTicks = startTicks
            self.endTicks = endTicks
        }

        public var start: Double { Double(startTicks) / 10_000_000 }
        public var end: Double { Double(endTicks) / 10_000_000 }
    }

    public struct SubtitleTrackResponse: Decodable, Sendable {
        public let trackEvents: [SubtitleCue]
        enum CodingKeys: String, CodingKey { case trackEvents = "TrackEvents" }
    }

    /// An entry of `/Items/{id}/Ancestors` — the chain up to the library.
    public struct Ancestor: Decodable, Sendable {
        public let id: String
        public let name: String?
        public let type: String?
        public let collectionType: String?
        enum CodingKeys: String, CodingKey {
            case id = "Id", name = "Name", type = "Type", collectionType = "CollectionType"
        }
    }

    // MARK: - Session reporting bodies

    /// Body for `POST /Sessions/Playing` — call once when playback starts.
    public struct PlaybackStartReport: Encodable, Sendable {
        public let itemId: String
        public let mediaSourceId: String?
        public let playSessionId: String?
        public let positionTicks: Int64?
        public let canSeek = true

        enum CodingKeys: String, CodingKey {
            case itemId = "ItemId"
            case mediaSourceId = "MediaSourceId"
            case playSessionId = "PlaySessionId"
            case positionTicks = "PositionTicks"
            case canSeek = "CanSeek"
        }

        public init(itemId: String, mediaSourceId: String?, playSessionId: String?, positionTicks: Int64?) {
            self.itemId = itemId
            self.mediaSourceId = mediaSourceId
            self.playSessionId = playSessionId
            self.positionTicks = positionTicks
        }
    }

    /// Body for `POST /Sessions/Playing/Progress` — call every ~10s.
    public struct PlaybackProgressReport: Encodable, Sendable {
        public let itemId: String
        public let mediaSourceId: String?
        public let playSessionId: String?
        public let positionTicks: Int64?
        public let isPaused: Bool?
        public let canSeek = true

        enum CodingKeys: String, CodingKey {
            case itemId = "ItemId"
            case mediaSourceId = "MediaSourceId"
            case playSessionId = "PlaySessionId"
            case positionTicks = "PositionTicks"
            case isPaused = "IsPaused"
            case canSeek = "CanSeek"
        }

        public init(itemId: String, mediaSourceId: String?, playSessionId: String?, positionTicks: Int64?, isPaused: Bool?) {
            self.itemId = itemId
            self.mediaSourceId = mediaSourceId
            self.playSessionId = playSessionId
            self.positionTicks = positionTicks
            self.isPaused = isPaused
        }
    }

    /// Body for `POST /Sessions/Playing/Stopped` — call on teardown.
    public struct PlaybackStopReport: Encodable, Sendable {
        public let itemId: String
        public let mediaSourceId: String?
        public let playSessionId: String?
        public let positionTicks: Int64?

        enum CodingKeys: String, CodingKey {
            case itemId = "ItemId"
            case mediaSourceId = "MediaSourceId"
            case playSessionId = "PlaySessionId"
            case positionTicks = "PositionTicks"
        }

        public init(itemId: String, mediaSourceId: String?, playSessionId: String?, positionTicks: Int64?) {
            self.itemId = itemId
            self.mediaSourceId = mediaSourceId
            self.playSessionId = playSessionId
            self.positionTicks = positionTicks
        }
    }
}
