import SwiftUI
import JellyTVKit

/// Branded placeholder for the remote-control companion. The actual remote
/// (server discovery + playback control of the Apple TV app) lands in a later change.
struct RootView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.10, blue: 0.29),
                    Color(red: 0.43, green: 0.23, blue: 0.82),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "appletvremote.gen4")
                    .font(.system(size: 64))
                    .foregroundStyle(.white)
                Text(JellyTVKit.displayName)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Remote for your Apple TV — v\(JellyTVKit.version)")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

#Preview {
    RootView()
}
