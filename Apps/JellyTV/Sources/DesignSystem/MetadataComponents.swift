import SwiftUI
import JellyTVKit

/// The cast headshot itself: a soft rounded square (deliberately *not* a
/// circle), with a per-person gradient monogram fallback, a lead/Oscar accent
/// border, and a gold Academy-Award medal tucked into the lower-left corner for
/// Oscar-winning actors. Shared by the vertical `CastAvatar` (detail rows) and
/// the horizontal `CastListItem` (Movies dossier).
struct CastPortrait: View {
    let member: CastMember
    var size: CGFloat = 72

    @EnvironmentObject private var theme: Theme

    private static let gold = Color(hex: "#E8B44A")
    private var corner: CGFloat { size * 0.3 }

    var body: some View {
        headshot
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(border)
            .overlay(alignment: .bottomLeading) { medal }
            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
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

    /// A deterministic two-tone gradient (hue seeded from the id) behind the
    /// initials, so each fallback tile gets its own colour rather than flat grey.
    private var monogram: some View {
        let hue = Double(abs(member.id.hashValue) % 360)
        return ZStack {
            LinearGradient(
                colors: [Color(OKLCH(l: 0.56, c: 0.13, h: hue)),
                         Color(OKLCH(l: 0.38, c: 0.11, h: hue + 26))],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(member.initials)
                .font(Typography.font(size * 0.32, .heavy))
                .foregroundStyle(.white.opacity(0.92))
        }
    }

    @ViewBuilder private var border: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        if member.wonOscar {
            shape.stroke(
                LinearGradient(colors: [Self.gold, Self.gold.opacity(0.45)],
                               startPoint: .top, endPoint: .bottom), lineWidth: 2.5)
        } else if member.isLead {
            shape.stroke(
                LinearGradient(colors: [theme.accent, theme.accent.opacity(0.3)],
                               startPoint: .top, endPoint: .bottom), lineWidth: 2)
        } else {
            shape.stroke(Palette.text(0.14), lineWidth: 1)
        }
    }

    /// The Oscar medal — a gold star on a dark disc, overlapping the lower-left
    /// corner (matching the design). Only for Academy-Award winners.
    @ViewBuilder private var medal: some View {
        if member.wonOscar {
            let d = size * 0.4
            ZStack {
                Circle().fill(Color(hex: "#0E121A"))
                Circle().stroke(Self.gold, lineWidth: 1.5)
                Image(systemName: "star.fill")
                    .font(.system(size: d * 0.48, weight: .bold))
                    .foregroundStyle(Self.gold)
            }
            .frame(width: d, height: d)
            .offset(x: -d * 0.32, y: d * 0.32)
        }
    }
}

/// A vertical cast cell (portrait above, name/character below) — the horizontal
/// cast strip on the Movie and Show detail screens.
struct CastAvatar: View {
    let member: CastMember
    var size: CGFloat = 96

    var body: some View {
        VStack(spacing: 8) {
            CastPortrait(member: member, size: size)

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
}

/// A horizontal cast entry (portrait beside name/character) for the Movies
/// dossier's two-column cast grid.
struct CastListItem: View {
    let member: CastMember
    var portrait: CGFloat = 42

    var body: some View {
        HStack(spacing: 10) {
            CastPortrait(member: member, size: portrait)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .font(Typography.font(15, .bold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                if let role = member.role, !role.isEmpty {
                    Text(role)
                        .font(Mono.font(12, .medium))
                        .foregroundStyle(Palette.text(0.45))
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
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

/// A compact gold "★ Won N Academy Awards" capsule for the detail screens.
/// Renders only for actual Oscar wins (nothing for nominations / other awards).
struct AwardsBadge: View {
    let awards: MovieAwards?

    private static let gold = Color(hex: "#E8B44A")

    var body: some View {
        if let label = awards?.academyAwardsLabel {
            HStack(spacing: 7) {
                Image(systemName: "star.fill").font(.system(size: 12, weight: .bold))
                Text(label).font(Typography.font(15, .bold))
            }
            .foregroundStyle(Self.gold)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Self.gold.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(Self.gold.opacity(0.4), lineWidth: 1))
        }
    }
}
