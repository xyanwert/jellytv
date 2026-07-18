import SwiftUI
import JellyTVKit

struct HomeDetail: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(title: "Home")

            DetailRow(label: "Hide NSFW", description: "Exclude adult content from Home") {
                ToggleSwitch(isOn: $appState.hideNSFW)
            }
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
}
