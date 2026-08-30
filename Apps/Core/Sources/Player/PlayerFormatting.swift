import Foundation

/// The chrome's position readout — `27:14` under an hour, `1:04:22` over.
///
/// **Both halves are formatted against `duration`, not against themselves.**
/// That is what stops a two-hour film reading `8:03 / 2:11:00`: the pair
/// stays the same shape and the same width for the whole film, so the
/// numbers don't jump sideways as the minutes roll over.
///
/// An earlier version of this followed the design mockup literally and
/// rendered hours:minutes (`00:27/01:17`). That was wrong twice over: it only
/// changed once a minute, so at a 4Hz tick it looked frozen, and `00:27` reads
/// as twenty-seven *seconds* to anyone who has used any other player. Seconds
/// are back.
func formatPlayerClock(_ seconds: Double, matching duration: Double) -> String {
    let showHours = duration >= 3600
    guard seconds.isFinite, seconds >= 0 else { return showHours ? "0:00:00" : "0:00" }
    let total = Int(seconds)
    let s = total % 60
    if showHours {
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, s)
    }
    return String(format: "%d:%02d", total / 60, s)
}
