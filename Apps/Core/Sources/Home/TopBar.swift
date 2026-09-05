import SwiftUI
import JellyTVKit

/// The Home content area's readout row: a breadcrumb-style eyebrow on the
/// left, the remote-control switch and a clock on the right, and the hero
/// rotation dots truly centered in the middle (independent of the two sides'
/// widths, hence the `ZStack` rather than a 3-way `HStack`). The wordmark/logo
/// and primary navigation live in the rail (`NavRail`), not here.
///
/// **The profile avatar is gone.** It was a focusable "M" in a ring that
/// opened Settings — a job the rail's gear already does one row down, and
/// nobody read a monogram as "settings". Home's rule is that anything that
/// looks pressable does something you can't already do from the rail.
struct TopBar: View {
    let heroCount: Int
    let heroIndex: Int
    let slideStartTime: Date
    let rotationSeconds: Double

    var body: some View {
        ZStack {
            HStack(alignment: .center) {
                Text("HOME // FEATURED")
                    .font(Typography.font(15, .heavy))
                    .tracking(2.6)
                    .foregroundStyle(Palette.text(0.5))

                Spacer()

                HStack(alignment: .center, spacing: 26) {
                    #if os(tvOS)
                    RemoteControlButton()
                    #endif
                    // A clock reads as intentional set dressing on tvOS (no
                    // visible system clock there) and has room to spare in
                    // iPad's landscape canvas; on a phone it sits a few points
                    // below the *real* status-bar clock and just reads as a
                    // second, wrong time. Phone drops it rather than showing
                    // two clocks.
                    if DeviceClass.current != .phone {
                        TopBarClock()
                    }
                }
            }

            // Centered irrespective of the two sides' widths — fine on
            // iPad's wide landscape row, where the eyebrow text on the left
            // stays well clear of screen-center. On a narrow phone width the
            // eyebrow ("HOME // FEATURED") runs close enough to center that
            // it collided with these dots outright. The genre's phone apps
            // don't show a hero-carousel page indicator here either — the
            // title text itself is what tells you which slide you're on.
            if DeviceClass.current != .phone {
                HeroDotsRow(count: heroCount, activeIndex: heroIndex,
                            slideStartTime: slideStartTime, interval: rotationSeconds)
            }
        }
        .padding(.horizontal, DeviceClass.current == .phone ? 20 : 56)
        #if os(iOS)
        .padding(.top, 8)
        #else
        .padding(.top, 20)
        // The remote-control switch is the only focusable thing up here and
        // it sits at the far right; the hero's buttons sit at the far left.
        // tvOS's focus engine wants horizontal overlap for an Up move, so
        // without this Up from Resume went nowhere and the switch could
        // only be reached by luck. As a focus section the bar's whole
        // full-width frame stands in for the switch — the same fix
        // `ShowView`'s shelf header uses.
        .focusSection()
        #endif
    }
}

/// The real time, set the way a good screensaver sets it: large light digits,
/// the meridiem small and in the accent, the day under it in the readout
/// voice, and a colon that breathes once a second so it is unmistakably
/// *live*. It replaced a `Text("9:41 PM")` — a screenshot clock, frozen at
/// Apple's keynote time, on a screen people leave on for hours.
///
/// Locale decides 12- or 24-hour (the meridiem simply isn't drawn in a 24-hour
/// locale), and the date line is the locale's own abbreviated weekday/month
/// order, upper-cased — never a hand-built "THU · SEP 4" that is wrong in
/// half the world.
struct TopBarClock: View {
    @EnvironmentObject private var theme: Theme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let parts = Self.parts(for: context.date)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(parts.hour)
                    Text(":")
                        .opacity(parts.colonLit ? 1 : 0.3)
                        .animation(.easeInOut(duration: 0.45), value: parts.colonLit)
                    Text(parts.minute)
                    if let meridiem = parts.meridiem {
                        Text(meridiem)
                            .font(Mono.font(13, .bold))
                            .tracking(1.4)
                            .foregroundStyle(theme.accent)
                            .padding(.leading, 7)
                    }
                }
                .font(Typography.font(34, .semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.text(0.92))

                Text(parts.date)
                    .font(Mono.font(12, .bold))
                    .tracking(2.2)
                    .foregroundStyle(Palette.text(0.42))
            }
        }
        .focusable(false)
        .accessibilityElement(children: .combine)
    }

    private struct Parts {
        var hour: String
        var minute: String
        var meridiem: String?
        var colonLit: Bool
        var date: String
    }

    private static let uses12Hour: Bool = {
        DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? true
    }()

    private static func parts(for date: Date) -> Parts {
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let hour24 = components.hour ?? 0
        let hour = uses12Hour ? (hour24 % 12 == 0 ? 12 : hour24 % 12) : hour24
        let minute = components.minute ?? 0
        return Parts(
            hour: uses12Hour ? String(hour) : String(format: "%02d", hour),
            minute: String(format: "%02d", minute),
            meridiem: uses12Hour ? (hour24 < 12 ? "AM" : "PM") : nil,
            colonLit: (components.second ?? 0) % 2 == 0,
            date: date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased()
        )
    }
}

#if os(tvOS)
/// The "connect remote" switch — icon only, as asked, with its state carried
/// by the glyph and the fill: a phone with radio waves in the accent while
/// this TV is controllable, a crossed-out phone when it isn't, a spinner in
/// between. The words appear only for a beat after a press (and for any
/// message a controlling phone sends), beside the icon, then go away — a
/// caption that stayed would be one more label on a screen that has enough.
struct RemoteControlButton: View {
    @EnvironmentObject private var remote: RemoteControl
    @EnvironmentObject private var theme: Theme

    private var isOn: Bool { remote.status == .on }

    var body: some View {
        HStack(spacing: 16) {
            if let notice = remote.notice {
                Text(notice)
                    .font(Typography.font(17, .semibold))
                    .foregroundStyle(Palette.text(0.7))
                    .lineLimit(1)
                    .transition(.opacity)
            }
            Button(action: remote.toggle) {
                ZStack {
                    if remote.status == .connecting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Palette.text(0.8))
                    } else {
                        Image(systemName: glyph)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(isOn ? .white : Palette.text(0.72))
                    }
                }
                .frame(width: 54, height: 54)
                .background(isOn ? theme.accent : Palette.text(0.08), in: Circle())
                .overlay(Circle().stroke(isOn ? .clear : Palette.text(0.16), lineWidth: 1))
                .shadow(color: isOn ? theme.accent.opacity(0.45) : .clear, radius: 14, y: 4)
            }
            .buttonStyle(FocusScaleStyle(scale: 1.1, cornerRadius: 999))
            .accessibilityLabel(isOn ? "Remote control on" : "Remote control off")
            .accessibilityHint("Lets Jellyfin apps on other devices play to this TV")
        }
        .animation(.easeOut(duration: 0.25), value: remote.notice)
        .animation(.easeOut(duration: 0.25), value: remote.status)
    }

    private var glyph: String {
        switch remote.status {
        case .on: return "iphone.radiowaves.left.and.right"
        case .off, .failed, .connecting: return "iphone.slash"
        }
    }
}
#endif
