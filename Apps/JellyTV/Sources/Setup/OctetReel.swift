import SwiftUI
import JellyTVKit

/// A four-octet IPv4 "reel" for entering a server address with the remote —
/// no on-screen keyboard needed. The first two octets seed to 192 / 168 (the
/// near-universal home-network prefix) but every octet is adjustable.
///
/// tvOS interaction (**select-to-edit**, so focus is never trapped):
/// navigate between octets normally with ◀/▶; press **Select** on an octet to
/// enter edit mode; then ▲/▼ spins its value 0–255 and ◀/▶ slides to the
/// neighbour still spinning; **Select** or **Menu** locks it and restores normal
/// navigation so you can move on to the rest of the form.
struct OctetReel: View {
    @Binding var address: String
    let accent: Color

    @State private var octets: [Int] = [192, 168, 1, 100]
    @State private var editing: Int?
    @FocusState private var focused: Int?

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { i in
                cell(i)
                if i < 3 {
                    Text(".")
                        .font(Mono.font(28, .bold))
                        .foregroundStyle(Palette.text(0.35))
                        .padding(.bottom, 6)
                }
            }
        }
        .onAppear(perform: seed)
        .onChange(of: octets) { pushAddress() }
    }

    private func cell(_ i: Int) -> some View {
        let isEditing = editing == i
        let isFocused = focused == i
        let active = isEditing || isFocused
        return VStack(spacing: 2) {
            chevron("chevron.up", lit: isEditing)
            Text(String(format: "%3d", octets[i]))
                .font(Mono.font(34, .heavy))
                .monospacedDigit()
                .foregroundStyle(active ? Palette.textPrimary : Palette.text(0.7))
                .contentTransition(.numericText())
            chevron("chevron.down", lit: isEditing)
        }
        .frame(width: 104, height: 108)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(isEditing ? 0.10 : (isFocused ? 0.07 : 0.04)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isEditing ? accent : (isFocused ? accent.opacity(0.5) : .white.opacity(0.12)),
                        lineWidth: isEditing ? 2.5 : 1.5)
        )
        .shadow(color: isEditing ? accent.opacity(0.4) : .clear, radius: 16)
        .scaleEffect(isEditing ? 1.06 : 1)
        .animation(.snappy(duration: 0.16), value: editing)
        .animation(.snappy(duration: 0.12), value: octets[i])
        .focusable()
        .focused($focused, equals: i)
        .onTapGesture { toggleEdit(i) }        // Select press
        // Steering is attached ONLY while this octet is being edited: onMoveCommand
        // consumes every directional press, so leaving it on at rest would trap
        // focus inside the reel. At rest, ◀/▶/▲/▼ navigate normally.
        .modifier(EditSteering(
            active: isEditing,
            onMove: { direction in
                switch direction {
                case .up:    octets[i] = IPv4.clamp(octets[i] + 1)
                case .down:  octets[i] = IPv4.clamp(octets[i] - 1)
                case .left:  if i > 0 { editing = i - 1; focused = i - 1 }
                case .right: if i < 3 { editing = i + 1; focused = i + 1 }
                @unknown default: break
                }
            },
            onExit: { editing = nil }          // Menu exits edit mode
        ))
    }

    private func chevron(_ name: String, lit: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 18, weight: .heavy))
            .foregroundStyle(lit ? accent : Palette.text(0.22))
    }

    private func toggleEdit(_ i: Int) {
        editing = (editing == i) ? nil : i
        focused = i
    }

    private func seed() {
        if let parsed = IPv4.octets(from: address) {
            octets = parsed
        } else {
            pushAddress()  // publish the default so Connect can enable
        }
    }

    private func pushAddress() {
        address = IPv4.string(from: octets)
    }
}

/// Attaches directional steering (and Menu-to-exit) only while `active`. Keeping
/// `onMoveCommand` off at rest lets the focus engine move focus out of the reel
/// normally; it's a directional-input sink whenever it's present.
private struct EditSteering: ViewModifier {
    let active: Bool
    let onMove: (MoveCommandDirection) -> Void
    let onExit: () -> Void

    func body(content: Content) -> some View {
        if active {
            content
                .onMoveCommand(perform: onMove)
                .onExitCommand(perform: onExit)
        } else {
            content
        }
    }
}
