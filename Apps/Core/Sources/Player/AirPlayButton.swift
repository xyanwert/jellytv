import SwiftUI
import AVFoundation
#if os(iOS)
import AVKit
#endif

/// The AirPlay control, in this chrome's clothes rather than the system's.
///
/// It is a *labelled* button that says which device it is playing to, not a
/// bare glyph — the whole point of surfacing it here is that "am I on the TV
/// or on this iPad?" should be answerable without tapping anything.
///
/// On iOS the visible part is ours and a real `AVRoutePickerView` sits
/// invisibly on top of it, so the tap opens Apple's own route chooser (which
/// is the only supported way to switch routes — there is no API to enumerate
/// and select them ourselves). It is held at 2% alpha rather than zero
/// because a fully transparent `UIView` stops hit-testing.
///
/// tvOS has no `AVRoutePickerView` — the TV owns routing at the system level
/// — so there it stays an inert readout of where the audio is going.
struct AirPlayButton: View {
    let accent: Color

    @State private var routeName: String = AirPlayButton.currentRouteName()
    @State private var isExternal: Bool = AirPlayButton.currentRouteIsExternal()

    private var shape: some Shape { RoundedRectangle(cornerRadius: 18, style: .continuous) }

    var body: some View {
        label
            .overlay {
                #if os(iOS)
                RoutePickerOverlay()
                    .opacity(0.02)
                #endif
            }
            .onReceive(NotificationCenter.default.publisher(
                for: AVAudioSession.routeChangeNotification)) { _ in
                routeName = Self.currentRouteName()
                isExternal = Self.currentRouteIsExternal()
            }
            .accessibilityLabel("AirPlay — currently \(routeName)")
    }

    private var label: some View {
        HStack(spacing: 12) {
            Image(systemName: "airplayvideo")
                .font(.system(size: 24, weight: .semibold))
            Text(routeName.uppercased())
                .font(Mono.font(15, .bold))
                .tracking(0.8)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 200, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
        }
        // Lit when the picture is somewhere other than this device: that is
        // the state worth spotting from across the room.
        .foregroundStyle(isExternal ? .white : Palette.text(0.9))
        .padding(.horizontal, 22)
        .frame(height: 62)
        .background(isExternal ? accent : Color.black.opacity(0.4), in: shape)
        .overlay(shape.stroke(isExternal ? Color.clear : Palette.text(0.14), lineWidth: 1))
    }

    /// The audio route's own name — "iPad", "Living Room TV", a speaker's
    /// name. Not a guess: this is what the system reports it is playing to.
    static func currentRouteName() -> String {
        AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "This iPad"
    }

    /// True when output has left the device — AirPlay, or an external display
    /// carrying the audio.
    static func currentRouteIsExternal() -> Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { output in
            switch output.portType {
            case .airPlay, .HDMI, .bluetoothA2DP: return true
            default: return false
            }
        }
    }
}

#if os(iOS)
/// Apple's route chooser, stripped of its own drawing. Held invisible over
/// our own button so the tap raises the system picker while the chrome keeps
/// its own look — the supported way to do this, since route *selection* has
/// no public API of its own.
private struct RoutePickerOverlay: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = true
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif
