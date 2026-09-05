import SwiftUI
import JellyTVKit

/// Settings → Server: the connected Jellyfin server's name, version, and
/// connection status.
struct ServerDetail: View {
    @EnvironmentObject private var server: ServerConnection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(title: "Server")

            if let info = server.serverInfo {
                DetailRow(label: info.name, description: "Version \(info.version)") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Palette.connected)
                            .frame(width: 10, height: 10)
                        Text("Connected")
                            .font(Typography.font(18, .semibold))
                            .foregroundStyle(Palette.connected)
                    }
                }
                DetailDivider()

                Button {
                    server.signOut()
                } label: {
                    HStack {
                        Text("Disconnect")
                            .font(Typography.font(20, .bold))
                            .foregroundStyle(.red)
                        Spacer(minLength: 0)
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                    .padding(.vertical, 20)
                    // 20, not 8: the focus style's accent bar sits in the
                    // first 8pt, so less than this and it touches the D.
                    .padding(.horizontal, 20)
                    .contentShape(Rectangle())
                }
                // Full-column row: at 1.03 the trailing glyph landed outside
                // the (unscaled) tint. Tint + bar + glow carry focus alone.
                .buttonStyle(RowFocusStyle(scale: 1))
            } else {
                DetailRow(label: "Not connected", description: "") {
                    Circle()
                        .fill(Palette.text(0.35))
                        .frame(width: 10, height: 10)
                }
            }

            Spacer(minLength: 0)
        }
    }
}
