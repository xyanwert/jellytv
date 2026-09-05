import SwiftUI
import JellyTVKit

#if os(tvOS)
/// One chip of the movie-night facts row.
struct MovieNightFact: Identifiable, Equatable {
    enum Style: Equatable {
        /// A fact about *this* film in *this* house — tinted, the row's voice.
        case solid
        /// A "vibe" keyword from TMDB — quieter, outlined, so it reads as a
        /// tag rather than a claim.
        case outline
    }

    let id: String
    let icon: String?
    let text: String
    var style: Style = .solid
}

/// The row of answers to "is this the one tonight?" — when it ends, how it
/// ranks among the films you own, what it won, what language it is in, who
/// made it and what else of theirs is here, where it sits in its series. Each
/// chip is computed from something real (`MovieNightFacts`) or is simply not
/// there; the row never pads itself.
///
/// `ViewThatFits` walks the list down until a whole row fits the column, so a
/// long director name costs a lower-priority chip, never a truncated one —
/// the same rule the player's tag row follows.
struct MovieNightFactsRow: View {
    let facts: [MovieNightFact]
    let tint: Color

    var body: some View {
        if !facts.isEmpty {
            ViewThatFits(in: .horizontal) {
                ForEach(Array(stride(from: min(facts.count, 7), through: 1, by: -1)), id: \.self) { count in
                    HStack(spacing: 10) {
                        ForEach(facts.prefix(count)) { fact in chip(fact) }
                    }
                }
            }
        }
    }

    private func chip(_ fact: MovieNightFact) -> some View {
        HStack(spacing: 7) {
            if let icon = fact.icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(fact.style == .solid ? tint : Palette.text(0.5))
            }
            Text(fact.text)
                .font(Mono.font(13, .bold))
                .tracking(1.2)
                .foregroundStyle(fact.style == .solid ? Palette.text(0.9) : Palette.text(0.62))
                .lineLimit(1)
        }
        .fixedSize()
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(fact.style == .solid ? tint.opacity(0.14) : Palette.text(0.05), in: Capsule())
        .overlay(Capsule().stroke(fact.style == .solid ? tint.opacity(0.4) : Palette.text(0.14), lineWidth: 1))
    }
}
#endif
