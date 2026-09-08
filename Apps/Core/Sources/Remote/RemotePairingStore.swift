import Foundation
import JellyTVKit

/// The local mirror of this device's pairings — what lets the TV bar draw, and the TV
/// list its remotes, before the server has answered. One codec for both sides: the phone
/// keeps the pairings it is the remote in, the TV the ones it is the TV in, under the
/// same key, and each filters by its own role on load.
enum RemotePairingStore {
    static let key = "jelly:remote.pairings"

    static func load() -> [YsojAPI.RemotePairing] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONDecoder().decode([YsojAPI.RemotePairing].self, from: data)
        else { return [] }
        return stored
    }

    static func save(_ pairings: [YsojAPI.RemotePairing]) {
        guard let data = try? JSONEncoder().encode(pairings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

/// The sentences both sides of a pairing say, spelled once.
enum RemoteCopy {
    static let needsYsoj = "Pairing needs a YSOJ server. Jellyfin apps can still cast here with remote control on."
    static let needsYsojShort = "Needs a YSOJ server"
}
