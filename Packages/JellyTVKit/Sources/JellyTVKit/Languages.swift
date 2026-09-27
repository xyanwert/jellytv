import Foundation

// MARK: - Languages

/// A language as the app names it: by its own spelling, never an English
/// exonym — Español, 日本語, Français. Jellyfin tags streams with ISO 639-2
/// codes, mostly the bibliographic set ("ger", "fre", "chi") but files carry
/// the terminological set ("deu", "fra", "zho") and two-letter 639-1 tags
/// too, so every code here is canonicalised before it is compared.
public struct Language: Hashable, Sendable, Identifiable {
    /// The canonical code — ISO 639-2/B ("spa", "jpn", "ger").
    public let code: String
    /// Other spellings the same language arrives under.
    public let aliases: [String]
    /// The name in the language itself.
    public let endonym: String

    public var id: String { code }
}

public enum LanguageTable {
    /// The languages offered when a preference is picked — the ten that
    /// cover what a home library holds, most common first. (A longer list
    /// was cut on request: thirty rows to scroll is not a picker.)
    public static let all: [Language] = [
        Language(code: "eng", aliases: ["en"], endonym: "English"),
        Language(code: "spa", aliases: ["es"], endonym: "Español"),
        Language(code: "jpn", aliases: ["ja"], endonym: "日本語"),
        Language(code: "chi", aliases: ["zho", "zh", "cmn", "yue"], endonym: "中文"),
        Language(code: "fre", aliases: ["fra", "fr"], endonym: "Français"),
        Language(code: "ger", aliases: ["deu", "de"], endonym: "Deutsch"),
        Language(code: "por", aliases: ["pt"], endonym: "Português"),
        Language(code: "ita", aliases: ["it"], endonym: "Italiano"),
        Language(code: "kor", aliases: ["ko"], endonym: "한국어"),
        Language(code: "rus", aliases: ["ru"], endonym: "Русский"),
    ]

    /// Languages a file may carry that the picker doesn't offer: still
    /// named properly when they turn up on a track.
    static let recognised: [Language] = [
        Language(code: "ara", aliases: ["ar"], endonym: "العربية"),
        Language(code: "hin", aliases: ["hi"], endonym: "हिन्दी"),
        Language(code: "dut", aliases: ["nld", "nl"], endonym: "Nederlands"),
        Language(code: "swe", aliases: ["sv"], endonym: "Svenska"),
        Language(code: "nor", aliases: ["no", "nob", "nno"], endonym: "Norsk"),
        Language(code: "dan", aliases: ["da"], endonym: "Dansk"),
        Language(code: "fin", aliases: ["fi"], endonym: "Suomi"),
        Language(code: "pol", aliases: ["pl"], endonym: "Polski"),
        Language(code: "tur", aliases: ["tr"], endonym: "Türkçe"),
        Language(code: "gre", aliases: ["ell", "el"], endonym: "Ελληνικά"),
        Language(code: "heb", aliases: ["he", "iw"], endonym: "עברית"),
        Language(code: "tha", aliases: ["th"], endonym: "ไทย"),
        Language(code: "vie", aliases: ["vi"], endonym: "Tiếng Việt"),
        Language(code: "ind", aliases: ["id"], endonym: "Bahasa Indonesia"),
        Language(code: "cat", aliases: ["ca"], endonym: "Català"),
        Language(code: "ukr", aliases: ["uk"], endonym: "Українська"),
        Language(code: "cze", aliases: ["ces", "cs"], endonym: "Čeština"),
        Language(code: "hun", aliases: ["hu"], endonym: "Magyar"),
        Language(code: "rum", aliases: ["ron", "ro"], endonym: "Română"),
    ]

    private static let byAnyCode: [String: Language] = {
        var map: [String: Language] = [:]
        for language in all + recognised {
            map[language.code] = language
            for alias in language.aliases { map[alias] = language }
        }
        return map
    }()

    /// The canonical (639-2/B) code for any spelling Jellyfin or a file might
    /// use — "es", "spa", "SPA", "es-MX" all give "spa". Unknown codes come
    /// back lower-cased and trimmed of a region, so two unknowns still match
    /// each other.
    public static func canonical(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let lowered = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !lowered.isEmpty, lowered != "und" else { return nil }
        let base = lowered.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? lowered
        return byAnyCode[base]?.code ?? base
    }

    /// "EN", "ES", "JA" — the two-letter tag where there is one, for a pill
    /// with no room for a name; the code itself otherwise.
    public static func shortCode(for raw: String?) -> String? {
        guard let code = canonical(raw) else { return nil }
        if let language = byAnyCode[code], let two = language.aliases.first(where: { $0.count == 2 }) {
            return two.uppercased()
        }
        return code.uppercased()
    }

    public static func language(for raw: String?) -> Language? {
        guard let code = canonical(raw) else { return nil }
        return byAnyCode[code]
    }

    /// How a code is shown: its own name, or the code itself in capitals
    /// when it is one this table doesn't know.
    public static func endonym(for raw: String?) -> String {
        guard let code = canonical(raw) else { return "Unknown" }
        return byAnyCode[code]?.endonym ?? code.uppercased()
    }
}

// MARK: - Preferences

/// When subtitles come on by themselves.
public enum SubtitleMode: String, Codable, CaseIterable, Sendable {
    /// Always, in the first preferred language the item has.
    case on
    /// Never — except a *forced* track in the sound's own language, which is
    /// the film's own choice (the alien speaking, the sign on the wall).
    case off
    /// Only when the sound isn't one of the preferred languages — the anime
    /// rule: Japanese audio gets the Spanish subtitles, a Spanish dub doesn't.
    case smart
}

/// What one library wants: up to three languages for the sound, up to three
/// for the subtitles, each in order of preference, and whether subtitles
/// start on. Empty lists mean "whatever the file's default is".
public struct LibraryLanguagePreference: Codable, Equatable, Sendable {
    public var audio: [String]
    public var subtitles: [String]
    public var subtitleMode: SubtitleMode

    public static let slots = 3

    public init(audio: [String] = [], subtitles: [String] = [], subtitleMode: SubtitleMode = .off) {
        self.audio = Array(audio.prefix(Self.slots))
        self.subtitles = Array(subtitles.prefix(Self.slots))
        self.subtitleMode = subtitleMode
    }

    public static let none = LibraryLanguagePreference()

    /// Whether anything at all has been chosen — the settings row's readout.
    public var isEmpty: Bool { audio.isEmpty && subtitles.isEmpty && subtitleMode == .off }
}

// MARK: - The pick

/// Which tracks a video starts with, from its streams and a library's
/// preference. Pure, so the rules are testable without a server.
public enum TrackPicker {
    public struct Choice: Equatable, Sendable {
        /// The audio stream's Jellyfin `Index`; nil when the item has none.
        public var audioIndex: Int?
        /// The subtitle stream's `Index`; nil means subtitles off.
        public var subtitleIndex: Int?
        /// True when the chosen subtitle is a bitmap track (PGS, VobSub) and
        /// has to be burned in by the server.
        public var subtitleIsBurnIn: Bool
        /// True when subtitles came on only because the sound isn't a
        /// preferred language (`SubtitleMode.smart`), or a forced track was
        /// picked under `.off` — the language check says so.
        public var subtitleIsAutomatic: Bool

        public init(audioIndex: Int? = nil, subtitleIndex: Int? = nil,
                    subtitleIsBurnIn: Bool = false, subtitleIsAutomatic: Bool = false) {
            self.audioIndex = audioIndex
            self.subtitleIndex = subtitleIndex
            self.subtitleIsBurnIn = subtitleIsBurnIn
            self.subtitleIsAutomatic = subtitleIsAutomatic
        }
    }

    public static func choose(streams: [JellyfinAPI.MediaStream],
                              preference: LibraryLanguagePreference?) -> Choice {
        let pref = preference ?? .none
        let audio = streams.filter { $0.type == "Audio" }.sorted { ($0.index ?? 0) < ($1.index ?? 0) }
        let subs = streams.filter { $0.type == "Subtitle" }.sorted { ($0.index ?? 0) < ($1.index ?? 0) }

        // Sound: the first preferred language the file has (its default track
        // among several, a commentary only if nothing else), else the file's
        // default, else its first.
        var chosenAudio: JellyfinAPI.MediaStream?
        for code in pref.audio.compactMap(LanguageTable.canonical) {
            let matches = audio.filter { LanguageTable.canonical($0.language) == code }
            guard !matches.isEmpty else { continue }
            let plain = matches.filter { !isCommentary($0) }
            let pool = plain.isEmpty ? matches : plain
            chosenAudio = pool.first { $0.isDefault == true } ?? pool.first
            break
        }
        if chosenAudio == nil {
            let plain = audio.filter { !isCommentary($0) }
            let pool = plain.isEmpty ? audio : plain
            chosenAudio = pool.first { $0.isDefault == true } ?? pool.first
        }
        let audioCode = LanguageTable.canonical(chosenAudio?.language)
        let preferredAudio = pref.audio.compactMap(LanguageTable.canonical)
        let audioIsPreferred = preferredAudio.isEmpty || (audioCode.map { preferredAudio.contains($0) } ?? false)

        var choice = Choice(audioIndex: chosenAudio?.index)
        guard !subs.isEmpty else { return choice }

        let wanted: Bool
        switch pref.subtitleMode {
        case .on: wanted = true
        case .off: wanted = false
        case .smart: wanted = !audioIsPreferred
        }

        if wanted {
            // A full track (never forced — those are partial) in the first
            // preferred language the file has; text before bitmap, since a
            // bitmap track costs a transcode.
            for code in pref.subtitles.compactMap(LanguageTable.canonical) {
                let matches = subs.filter { LanguageTable.canonical($0.language) == code && $0.isForced != true }
                guard !matches.isEmpty else { continue }
                let pick = matches.first { $0.isTextSubtitleStream != false } ?? matches[0]
                choice.subtitleIndex = pick.index
                choice.subtitleIsBurnIn = pick.isTextSubtitleStream == false
                choice.subtitleIsAutomatic = pref.subtitleMode == .smart
                return choice
            }
            return choice
        }

        // Off: only a forced track in the sound's own language — the film's
        // own call, not ours.
        if let audioCode,
           let forced = subs.first(where: { $0.isForced == true && LanguageTable.canonical($0.language) == audioCode }) {
            choice.subtitleIndex = forced.index
            choice.subtitleIsBurnIn = forced.isTextSubtitleStream == false
            choice.subtitleIsAutomatic = true
        }
        return choice
    }

    private static func isCommentary(_ stream: JellyfinAPI.MediaStream) -> Bool {
        let text = ((stream.title ?? "") + " " + (stream.displayTitle ?? "")).lowercased()
        return text.contains("commentary") || text.contains("comentario")
    }
}
