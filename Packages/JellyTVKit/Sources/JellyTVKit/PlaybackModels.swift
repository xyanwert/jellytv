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

        enum CodingKeys: String, CodingKey {
            case maxStreamingBitrate = "MaxStreamingBitrate"
            case maxStaticBitrate = "MaxStaticBitrate"
            case musicStreamingTranscodingBitrate = "MusicStreamingTranscodingBitrate"
            case directPlayProfiles = "DirectPlayProfiles"
            case transcodingProfiles = "TranscodingProfiles"
            case codecProfiles = "CodecProfiles"
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
            ]
        )

        public init(maxStreamingBitrate: Int, maxStaticBitrate: Int, musicStreamingTranscodingBitrate: Int,
                    directPlayProfiles: [DirectPlayProfile], transcodingProfiles: [TranscodingProfile],
                    codecProfiles: [CodecProfile]) {
            self.maxStreamingBitrate = maxStreamingBitrate
            self.maxStaticBitrate = maxStaticBitrate
            self.musicStreamingTranscodingBitrate = musicStreamingTranscodingBitrate
            self.directPlayProfiles = directPlayProfiles
            self.transcodingProfiles = transcodingProfiles
            self.codecProfiles = codecProfiles
        }
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

        enum CodingKeys: String, CodingKey {
            case type = "Type"
            case codec = "Codec"
            case width = "Width"
            case height = "Height"
        }

        public init(type: String? = nil, codec: String? = nil, width: Int? = nil, height: Int? = nil) {
            self.type = type
            self.codec = codec
            self.width = width
            self.height = height
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
