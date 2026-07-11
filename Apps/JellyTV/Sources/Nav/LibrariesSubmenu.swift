import SwiftUI
import JellyTVKit

/// The rail's Libraries slide-out submenu: a 392pt blurred panel listing every
/// library, opened over a dimmed (not hidden) Home.
struct LibrariesSubmenu: View {
    let libraries: [Library]

    @EnvironmentObject private var theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LIBRARIES")
                .font(Typography.font(15, .heavy))
                .tracking(3.5)
                .foregroundStyle(theme.accent)
            Text("Your Media")
                .font(Typography.font(40, .black))
                .foregroundStyle(Palette.textPrimary)
                .padding(.bottom, 18)

            ForEach(libraries) { library in
                LibraryRow(library: library)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 44)
        .frame(width: 392, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Color(hex: "#0B0E16").opacity(0.55))
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(Palette.text(0.1)).frame(width: 1)
        }
    }
}

private struct LibraryRow: View {
    let library: Library
    @EnvironmentObject private var theme: Theme

    var body: some View {
        Button {} label: {
            HStack(spacing: 16) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Palette.text(0.7))
                    .frame(width: 44, height: 44)
                    .background(Palette.text(0.06), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                HStack(spacing: 10) {
                    Text(library.name)
                        .font(Typography.font(21, .bold))
                        .foregroundStyle(library.isAdult ? Color(hex: "#FFD9DC") : Palette.textPrimary)
                    if library.isAdult {
                        HStack(spacing: 5) {
                            Image(systemName: "lock.fill").font(.system(size: 10, weight: .heavy))
                            Text("18+").font(Typography.font(12, .black))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(theme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: theme.accent.opacity(0.55), radius: 8)
                    }
                }

                Spacer(minLength: 8)
                Text(library.itemCount)
                    .font(Typography.font(15, .medium))
                    .foregroundStyle(Palette.text(0.4))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                library.isAdult ? theme.accent.opacity(0.08) : Palette.text(0.03),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(library.isAdult ? theme.accent.opacity(0.24) : Palette.text(0.07), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(FocusScaleStyle(scale: 1.02, cornerRadius: 14, outline: false))
    }
}
