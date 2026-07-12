import SwiftUI
import JellyTVKit

/// Focusable fields on the Show view.
private enum ShowField: Hashable {
    case back, resume, shuffle, audio, subtitle, add
    case season(Int)
    case episode(String)
}

/// The Show view (design 2a): a full-screen "editorial dossier" for a
/// collection — its own left spine (not the main nav rail), a title block with
/// a spec sheet, a framed key-art panel with a floating resume card, an episode
/// strip for the selected season, and a season selector + control bar.
struct ShowView: View {
    let show: Show
    let onDismiss: () -> Void

    @EnvironmentObject private var theme: Theme
    @FocusState private var focus: ShowField?
    @State private var selectedSeason: Int
    @State private var sonarPulse = false

    init(show: Show, onDismiss: @escaping () -> Void) {
        self.show = show
        self.onDismiss = onDismiss
        _selectedSeason = State(initialValue: show.currentSeasonIndex)
    }

    private var season: Season { show.seasons[min(selectedSeason, show.seasons.count - 1)] }
    private var currentEpisode: Episode? { show.seasons.flatMap(\.episodes).first(where: \.isCurrent) }

    var body: some View {
        ZStack {
            background
            sonarRings
            HStack(spacing: 0) {
                spine
                content
            }
            .ignoresSafeArea()
        }
        .background(Color(hex: "#070A10").ignoresSafeArea())
        .defaultFocus($focus, .resume)
        .onExitCommand(perform: onDismiss)
        .onAppear {
            withAnimation(.easeOut(duration: 4).repeatForever(autoreverses: false)) { sonarPulse = true }
        }
    }

    // MARK: Background

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#080B12"), Color(hex: "#060810")],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(
                colors: [Color(OKLCH(l: 0.34, c: 0.10, h: 235)).opacity(0.55), .clear],
                center: .init(x: 1.0, y: -0.1), startRadius: 0, endRadius: 1200
            )
            RadialGradient(
                colors: [Color(OKLCH(l: 0.30, c: 0.09, h: 250)).opacity(0.35), .clear],
                center: .init(x: -0.05, y: 1.1), startRadius: 0, endRadius: 900
            )
        }
        .ignoresSafeArea()
    }

    private var sonarRings: some View {
        ZStack {
            ForEach(0..<4) { i in
                Circle()
                    .stroke(Color(hex: "#78B4DC").opacity(0.14 - Double(i) * 0.02), lineWidth: 1)
                    .frame(width: 720 - CGFloat(i) * 180, height: 720 - CGFloat(i) * 180)
            }
            Circle()
                .stroke(theme.accent, lineWidth: 2)
                .frame(width: 180, height: 180)
                .scaleEffect(sonarPulse ? 2.2 : 0.7)
                .opacity(sonarPulse ? 0 : 0.7)
        }
        .frame(width: 720, height: 720)
        .position(x: 1720, y: 120)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: Spine

    private var spine: some View {
        VStack(spacing: 0) {
            Image(systemName: "drop.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(theme.accent)
                .frame(width: 54, height: 54)
                .background(.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 20, y: 6)

            Spacer()

            Text(show.genreLabel.uppercased())
                .font(Typography.font(15, .semibold))
                .tracking(6)
                .foregroundStyle(Palette.text(0.32))
                .fixedSize()
                .rotationEffect(.degrees(90))
                .frame(height: 320)

            Spacer()

            VStack(spacing: 22) {
                Button(action: onDismiss) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Palette.text(0.85))
                        .frame(width: 54, height: 54)
                        .background(Palette.text(0.06), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Palette.text(0.12), lineWidth: 1))
                }
                .buttonStyle(FocusScaleStyle(scale: 1.12, cornerRadius: 15))
                .focused($focus, equals: .back)

                if let ep = currentEpisode {
                    Text("EP\n\(ep.numberLabel)")
                        .font(Typography.font(13, .heavy))
                        .tracking(2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .foregroundStyle(theme.accent)
                }
            }
        }
        .padding(.vertical, 40)
        .frame(width: 118)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .trailing) { Rectangle().fill(Palette.text(0.08)).frame(width: 1) }
    }

    // MARK: Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Spacer(); techReadout }

            HStack(alignment: .top, spacing: 40) {
                titleBlock
                Spacer(minLength: 0)
                keyArtPanel
            }
            .padding(.top, 8)

            Spacer(minLength: 24)

            episodeStrip

            Spacer(minLength: 20)

            bottomBar
        }
        .padding(.init(top: 46, leading: 64, bottom: 40, trailing: 64))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var techReadout: some View {
        HStack(spacing: 18) {
            HStack(spacing: 8) {
                Circle().fill(Palette.connected).frame(width: 8, height: 8)
                    .shadow(color: Palette.connected, radius: 6)
                Text("SIGNAL ●●●●○")
            }
            Text("|").foregroundStyle(Palette.text(0.3))
            Text(show.techLine)
        }
        .font(Typography.font(15, .medium))
        .tracking(1)
        .foregroundStyle(Palette.text(0.6))
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(show.studioLine.uppercased())
                .font(Typography.font(16, .heavy))
                .tracking(4)
                .foregroundStyle(theme.accent)
                .padding(.bottom, 18)

            Text(show.title)
                .font(Typography.font(76, .black))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .lineSpacing(-6)

            specSheet.padding(.top, 34)
        }
        .frame(maxWidth: 600, alignment: .leading)
    }

    private var specSheet: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.text(0.12)).frame(height: 1)
            HStack(spacing: 0) {
                specCell("Rating") {
                    HStack(spacing: 8) {
                        Text("★").foregroundStyle(theme.accent)
                        Text(show.rating)
                        Text(show.certification)
                            .font(Typography.font(16, .semibold))
                            .foregroundStyle(Palette.text(0.4))
                    }
                    .font(Typography.font(24, .heavy))
                    .foregroundStyle(Palette.textPrimary)
                }
                divider
                specCell("Run") { specValue(show.runSummary) }
            }
            Rectangle().fill(Palette.text(0.08)).frame(height: 1)
            HStack(spacing: 0) {
                specCell("Created by") { specValue(show.createdBy) }
                divider
                specCell("Years") { specValue(show.years) }
            }
        }
    }

    private var divider: some View { Rectangle().fill(Palette.text(0.08)).frame(width: 1) }

    private func specCell<V: View>(_ label: String, @ViewBuilder value: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(Typography.font(13, .semibold))
                .tracking(2)
                .foregroundStyle(Palette.text(0.4))
            value()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
    }

    private func specValue(_ text: String) -> some View {
        Text(text).font(Typography.font(22, .bold)).foregroundStyle(Palette.textPrimary)
    }

    // MARK: Key art + resume

    private var keyArtPanel: some View {
        ZStack(alignment: .bottomLeading) {
            keyArtImage
                .frame(width: 780, height: 460)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Palette.text(0.1), lineWidth: 1))
                .overlay(alignment: .topLeading) { cornerTick(topLeading: true) }
                .overlay(alignment: .bottomTrailing) { cornerTick(topLeading: false) }
                .shadow(color: .black.opacity(0.6), radius: 40, y: 24)

            resumeCard
                .offset(x: -32, y: 40)
        }
        .padding(.trailing, 4)
    }

    @ViewBuilder private var keyArtImage: some View {
        if let name = show.keyArt {
            Image(name).resizable().scaledToFill()
        } else {
            show.artwork.gradient
        }
    }

    private func cornerTick(topLeading: Bool) -> some View {
        Path { p in
            if topLeading {
                p.move(to: CGPoint(x: 0, y: 24)); p.addLine(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 24, y: 0))
            } else {
                p.move(to: CGPoint(x: 0, y: 24)); p.addLine(to: CGPoint(x: 24, y: 24)); p.addLine(to: CGPoint(x: 24, y: 0))
            }
        }
        .stroke(theme.accent, lineWidth: 2)
        .frame(width: 24, height: 24)
        .offset(x: topLeading ? -8 : 8, y: topLeading ? -8 : 8)
    }

    private var resumeCard: some View {
        Button {} label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Palette.text(0.14), lineWidth: 6)
                    Circle().trim(from: 0, to: show.resumeProgress)
                        .stroke(theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Circle().fill(theme.accent).frame(width: 52, height: 52)
                        .overlay(Image(systemName: "play.fill").font(.system(size: 20)).foregroundStyle(.white))
                }
                .frame(width: 92, height: 92)

                VStack(alignment: .leading, spacing: 4) {
                    Text("RESUME").font(Typography.font(12, .heavy)).tracking(2).foregroundStyle(theme.accent)
                    Text(show.resumeEpisodeLabel).font(Typography.font(22, .heavy)).foregroundStyle(Palette.textPrimary)
                    Text(show.resumeRemaining).font(Typography.font(15, .medium)).foregroundStyle(Palette.text(0.55))
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(width: 430)
            .background(Color(hex: "#0E1218").opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.text(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 30, y: 18)
        }
        .buttonStyle(FocusScaleStyle(scale: 1.05, cornerRadius: 16))
        .focused($focus, equals: .resume)
    }

    // MARK: Episode strip

    private var episodeStrip: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(season.name.uppercased()) — \(season.episodes.count) EPISODES")
                    .font(Typography.font(15, .heavy)).tracking(2).foregroundStyle(Palette.text(0.5))
                Spacer()
                Text("SWIPE ▸").font(Typography.font(14, .semibold)).tracking(1).foregroundStyle(Palette.text(0.32))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(season.episodes) { ep in
                        EpisodeCard(episode: ep)
                            .focused($focus, equals: .episode(ep.id))
                    }
                }
                .padding(.vertical, 12)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 24) {
            seasonSelector
            Spacer()
            controls
        }
        .padding(.top, 24)
        .overlay(alignment: .top) { Rectangle().fill(Palette.text(0.1)).frame(height: 1) }
    }

    private var seasonSelector: some View {
        HStack(spacing: 5) {
            ForEach(Array(show.seasons.enumerated()), id: \.element.id) { index, s in
                let active = index == selectedSeason
                Button { selectedSeason = index } label: {
                    Text(s.shortLabel)
                        .font(Typography.font(16, .bold)).tracking(1)
                        .foregroundStyle(active ? Palette.screen : Palette.text(0.6))
                        .padding(.horizontal, 20).padding(.vertical, 11)
                        .background(active ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 8))
                .focused($focus, equals: .season(index))
            }
        }
        .padding(5)
        .background(Palette.text(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.text(0.1), lineWidth: 1))
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {} label: {
                HStack(spacing: 11) {
                    Image(systemName: "shuffle").font(.system(size: 20, weight: .bold))
                    Text("Shuffle Play")
                }
                .font(Typography.font(20, .heavy)).foregroundStyle(.white)
                .padding(.horizontal, 30).padding(.vertical, 15)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 13))
            .focused($focus, equals: .shuffle)

            pill(icon: "speaker.wave.2.fill", label: "EN·5.1", field: .audio)
            pill(icon: "captions.bubble", label: "CC·OFF", field: .subtitle)

            Button {} label: {
                Image(systemName: "plus").font(.system(size: 24, weight: .regular))
                    .foregroundStyle(Palette.text(0.85))
                    .frame(width: 52, height: 52)
                    .background(Palette.text(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Palette.text(0.14), lineWidth: 1))
            }
            .buttonStyle(FocusScaleStyle(scale: 1.08, cornerRadius: 13))
            .focused($focus, equals: .add)
        }
    }

    private func pill(icon: String, label: String, field: ShowField) -> some View {
        Button {} label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                Text(label)
            }
            .font(Typography.font(18, .semibold)).foregroundStyle(Palette.text(0.85))
            .padding(.horizontal, 22).padding(.vertical, 15)
            .background(Palette.text(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Palette.text(0.14), lineWidth: 1))
        }
        .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 13))
        .focused($focus, equals: field)
    }
}
