import SwiftUI
import JellyTVKit

/// A circular cast headshot with a monogram fallback and a lead-actor accent
/// ring — adapted from the v1 app's `ItemDetailView.castCell`/`castMonogram`/
/// `headshotRing`. Used across the Movies dossier and the detail screens.
struct CastAvatar: View {
    let member: CastMember
    var size: CGFloat = 96

    @EnvironmentObject private var theme: Theme

    var body: some View {
        VStack(spacing: 8) {
            headshot
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(ring)
                .shadow(color: .black.opacity(0.4), radius: 8, y: 4)

            Text(member.name)
                .font(Typography.font(16, .bold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            if let role = member.role, !role.isEmpty {
                Text(role)
                    .font(Typography.font(14, .medium))
                    .foregroundStyle(Palette.text(0.5))
                    .lineLimit(1)
            }
        }
        .frame(width: size + 40)
    }

    @ViewBuilder private var headshot: some View {
        if let string = member.imageURL, let url = URL(string: string) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                case .empty, .failure: monogram
                @unknown default: monogram
                }
            }
        } else {
            monogram
        }
    }

    private var monogram: some View {
        ZStack {
            Circle().fill(Palette.text(0.08))
            Text(member.initials)
                .font(Typography.font(size * 0.3, .heavy))
                .foregroundStyle(Palette.text(0.55))
        }
    }

    @ViewBuilder private var ring: some View {
        if member.isLead {
            Circle().stroke(
                LinearGradient(colors: [theme.accent, theme.accent.opacity(0.35)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 2.5)
        } else {
            Circle().stroke(Palette.text(0.14), lineWidth: 1)
        }
    }
}

/// A compact strip of rating chips — IMDb (0–10), Rotten Tomatoes (%, tinted by
/// freshness) and Metacritic (0–100). Each chip renders only when its value is
/// present, so absent sources leave no gap. Adapted from v1's `ratingsStrip`.
struct RatingChips: View {
    var imdb: Double?
    var rottenTomatoes: Int?
    var metacritic: Int?

    var body: some View {
        HStack(spacing: 10) {
            if let imdb {
                chip(icon: "star.fill", tint: Color(hex: "#E8B44A"),
                     value: String(format: "%.1f", imdb), label: "IMDb")
            }
            if let rt = rottenTomatoes {
                chip(icon: "circle.fill", tint: freshness(rt),
                     value: "\(rt)%", label: "RT")
            }
            if let mc = metacritic {
                chip(icon: "square.fill", tint: freshness(mc),
                     value: "\(mc)", label: "META")
            }
        }
    }

    /// Green (fresh) ≥ 75, amber ≥ 60, else red — the usual critic-score tiers.
    private func freshness(_ score: Int) -> Color {
        if score >= 75 { return Color(hex: "#3FBF8F") }
        if score >= 60 { return Color(hex: "#E8B44A") }
        return Color(hex: "#E8544A")
    }

    private func chip(icon: String, tint: Color, value: String, label: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 17, weight: .bold)).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(Typography.font(19, .black)).foregroundStyle(Palette.textPrimary)
                Text(label).font(Mono.font(11, .bold)).tracking(1).foregroundStyle(Palette.text(0.45))
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 9)
        .background(Palette.text(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.text(0.1), lineWidth: 1))
    }
}

/// A gold awards badge (e.g. "★ 2 OSCARS" / "★ OSCAR NOMINEE" / "12 WINS").
/// Renders nothing when there's no notable awards data.
struct AwardsBadge: View {
    let awards: MovieAwards?

    private static let gold = Color(hex: "#E8B44A")

    var body: some View {
        if let badge = awards?.badge {
            Text(badge)
                .font(Mono.font(13, .bold))
                .tracking(1.5)
                .foregroundStyle(Self.gold)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Self.gold.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(Self.gold.opacity(0.4), lineWidth: 1))
        }
    }
}
