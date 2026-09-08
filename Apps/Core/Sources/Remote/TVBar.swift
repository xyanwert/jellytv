import SwiftUI
import JellyTVKit

#if os(iOS)
/// The paired TV, always in view while it is paired: what it is doing and where plays
/// will go. Tap for the remote sheet.
///
/// On the phone it is a full-width bar stacked directly above the tab bar — YouTube's
/// "Playing on Living Room TV" strip, the one the owner named. On the iPad it is a card
/// floating bottom-trailing, because the iPad has no tab bar to stack on and a
/// full-width strip across a 1180pt canvas would be mostly empty.
struct TVBar: View {
    let onOpen: () -> Void

    @EnvironmentObject private var link: TVLink
    @EnvironmentObject private var theme: Theme

    static let phoneHeight: CGFloat = 62

    private var isPhone: Bool { DeviceClass.current == .phone }

    var body: some View {
        // Two siblings, not a button inside a button: SwiftUI does not say which of two
        // nested buttons a tap belongs to, and the pause circle is the one control on the
        // bar people press most.
        HStack(spacing: 14) {
            Button(action: onOpen) {
                HStack(spacing: 14) {
                    glyph
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(title)
                                .font(Typography.font(isPhone ? 15 : 16, .bold))
                                .foregroundStyle(Palette.textPrimary)
                                .lineLimit(1)
                            if link.canSwitch {
                                // Two TVs up: this one is a choice, and the sheet has the other.
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(theme.accent)
                            }
                        }
                        Text(subtitle)
                            .font(Typography.font(isPhone ? 12 : 13, .medium))
                            .foregroundStyle(Palette.text(0.55))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if link.nowPlaying == nil {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.text(0.4))
                    }
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title). \(subtitle)")
            .accessibilityHint("Opens the remote")

            if link.nowPlaying != nil {
                Button {
                    link.togglePlayPause()
                } label: {
                    Image(systemName: link.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(theme.accent))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(link.isPaused ? "Play on TV" : "Pause TV")
            }
        }
        .padding(.horizontal, isPhone ? 18 : 20)
        .frame(maxWidth: .infinity)
        .frame(height: isPhone ? Self.phoneHeight : 68)
        .background(chrome)
    }

    // MARK: - Words

    private var title: String {
        switch link.presence {
        case .online:
            return link.nowPlaying != nil ? "Playing on \(link.tvName)" : link.tvName
        case .checking, .offline, .none:
            return link.tvName
        }
    }

    private var subtitle: String {
        switch link.presence {
        case .online:
            if let item = link.nowPlaying {
                return [item.seriesName, item.episodeLine].compactMap { $0 }.joined(separator: " · ")
            }
            return link.sendToTV ? "Ready · plays from here go to the TV"
                                 : "Ready · plays stay on this \(DeviceIdentity.name)"
        case .checking:
            return "Checking…"
        case .offline:
            return "Not open — open Why.So.Jelly? on it"
        case .none:
            return ""
        }
    }

    // MARK: - Looks

    private var glyph: some View {
        ZStack {
            Circle()
                .fill(link.isOnline ? theme.accent.opacity(0.16) : Palette.text(0.06))
                .frame(width: 38, height: 38)
            Image(systemName: link.isOnline ? "tv.fill" : "tv")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(link.isOnline ? theme.accent : Palette.text(0.45))
            if link.isOnline {
                Circle()
                    .fill(Palette.connected)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Palette.chromeInk, lineWidth: 2))
                    .offset(x: 13, y: -13)
            }
        }
    }

    @ViewBuilder
    private var chrome: some View {
        if isPhone {
            // The tab bar's own material, so the two read as one piece of chrome.
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Palette.chromeInk.opacity(0.55))
            }
            .overlay(alignment: .top) {
                Rectangle().fill(Palette.text(0.1)).frame(height: 1)
            }
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Palette.sheet.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Palette.text(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
        }
    }
}

/// A transient line under the bar: what a press just did.
struct TVNotice: View {
    let text: String
    @EnvironmentObject private var theme: Theme

    var body: some View {
        Text(text)
            .font(Typography.font(14, .semibold))
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(2)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Palette.sheet.opacity(0.96)))
            .overlay(Capsule().stroke(theme.accent.opacity(0.5), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
#endif
