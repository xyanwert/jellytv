import SwiftUI
import JellyTVKit

/// App shell: hosts the Home screen and presents the Settings panel over a
/// dimmed, blurred Home. Owns and injects the shared `Theme`.
struct RootView: View {
    @StateObject private var theme = Theme()
    // Opens Settings at launch only when JT_SHOW_SETTINGS=1 (screenshot/testing hook).
    @State private var showSettings = ProcessInfo.processInfo.environment["JT_SHOW_SETTINGS"] == "1"

    var body: some View {
        ZStack {
            HomeView(onOpenSettings: { withAnimation(.easeOut(duration: 0.2)) { showSettings = true } })
                .disabled(showSettings)
                .blur(radius: showSettings ? 8 : 0)

            if showSettings {
                SettingsPanel(onDismiss: { withAnimation(.easeOut(duration: 0.2)) { showSettings = false } })
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: showSettings)
        .environmentObject(theme)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    RootView()
}
