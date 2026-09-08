import UIKit

/// What this device calls itself — in Jellyfin's session list (`DeviceName`) and in a
/// pairing ("*Living Room* is looking for a remote", "*iPhone* is now a remote").
///
/// Both apps used to register as `Device="JellyTV"`, which was fine while nothing ever
/// listed them side by side. A pairing prompt naming the TV "JellyTV" would not tell a
/// house with two of them which one it meant.
enum DeviceIdentity {
    static var name: String {
        #if os(tvOS)
        // tvOS still answers with the name set in Settings → General ("Living Room");
        // an unnamed box says "Apple TV", which is also what we say.
        let name = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Apple TV" : name
        #else
        // iOS 16+ answers `UIDevice.name` with the generic "iPhone" unless the app carries
        // an entitlement for the user-assigned name, so the class of device is what we
        // can honestly say.
        return DeviceClass.current == .pad ? "iPad" : "iPhone"
        #endif
    }
}
