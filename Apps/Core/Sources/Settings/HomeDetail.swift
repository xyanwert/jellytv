import SwiftUI
import JellyTVKit

struct HomeDetail: View {
    /// tvOS only: opens the keypad. `SettingsView` owns the presentation so
    /// the panel covers the rail and the category list too, not just this pane.
    var onRequestAdultUnlock: () -> Void = {}

    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(title: "Home")

            // **The TV has no standing "show adult content" switch.** A
            // switch left on is the state a television spends most of its
            // life in, and the next person to pick the remote up inherits
            // it — so on tvOS this is a door that shuts itself twelve hours
            // later (`AdultLock`). A phone is one person's, so iOS keeps the
            // preference it always had.
            #if os(tvOS)
            adultRow
            #else
            DetailRow(label: "Hide NSFW", description: "Exclude adult content from Home") {
                ToggleSwitch(isOn: $appState.hideNSFW)
            }
            #endif
            DetailDivider()

            DetailRow(label: "Rotation", description: "Hero auto-advance interval") {
                SegmentedControl(
                    options: HeroRotation.allCases.map(\.label),
                    selection: Binding(
                        get: { theme.rotationInterval.label },
                        set: { label in
                            if let match = HeroRotation.allCases.first(where: { $0.label == label }) {
                                theme.rotationInterval = match
                            }
                        }
                    )
                )
            }
            DetailDivider()

            DetailRow(label: "Transition", description: "Hero backdrop animation") {
                SegmentedControl(
                    options: HeroTransitionStyle.allCases.map(\.label),
                    selection: Binding(
                        get: { theme.transitionStyle.label },
                        set: { label in
                            if let match = HeroTransitionStyle.allCases.first(where: { $0.label == label }) {
                                theme.transitionStyle = match
                            }
                        }
                    )
                )
            }
            DetailDivider()

            Spacer(minLength: 0)
        }
    }

    #if os(tvOS)
    /// The countdown is inside a `TimelineView` ticking once a minute: the
    /// remaining time is computed against `.now`, and nothing else on this
    /// screen changes for twelve hours, so without it the row would read
    /// "11h 42m" for the rest of the evening.
    private var adultRow: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let remaining = appState.adultUnlockRemainingLabel
            DetailRow(
                label: "Adult content",
                description: remaining.map { "Showing for another \($0)." }
                    ?? "Hidden everywhere. The code shows it for 12 hours."
            ) {
                if remaining == nil {
                    DetailActionButton(title: "Unlock", action: onRequestAdultUnlock)
                } else {
                    DetailActionButton(title: "Hide now", action: appState.lockAdultContent)
                }
            }
        }
    }
    #endif
}
