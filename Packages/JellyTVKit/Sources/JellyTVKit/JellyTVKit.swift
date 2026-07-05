import Foundation

/// Shared surface for the JellyTV apps. Both the tvOS client and the iOS
/// companion link this package; future shared code (Jellyfin API client,
/// domain models, the remote-control protocol) will live here.
public enum JellyTVKit {
    /// Marketing version, kept in sync with `MARKETING_VERSION` in project.yml.
    public static let version = "0.1.0"

    /// User-facing app name (App Store product name), shared by both shells.
    public static let displayName = "Why.So.Jelly?"
}
