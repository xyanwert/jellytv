import SwiftUI
import JellyTVKit

/// Settings → Server: the connected Jellyfin server's name, version, and
/// connection status.
struct ServerDetail: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(title: "Server")

            DetailRow(label: SampleCatalog.server.name, description: "Version \(SampleCatalog.server.version)") {
                HStack(spacing: 8) {
                    Circle()
                        .fill(SampleCatalog.server.isConnected ? Palette.connected : Palette.text(0.35))
                        .frame(width: 10, height: 10)
                    Text(SampleCatalog.server.isConnected ? "Connected" : "Offline")
                        .font(Typography.font(18, .semibold))
                        .foregroundStyle(SampleCatalog.server.isConnected ? Palette.connected : Palette.text(0.5))
                }
            }
            DetailDivider()

            Spacer(minLength: 0)
        }
    }
}
