import SwiftUI
import JellyTVKit

#if os(tvOS)
/// The keypad that opens the twelve-hour door (`AdultLock`).
///
/// **A keypad, not a text field.** tvOS's own keyboard for six digits is a
/// linear strip of every character on the remote's D-pad — a dozen presses
/// per digit, and the field has to be on screen for it to raise at all
/// (`AppTextField` exists because of exactly that). A 3×4 grid is one press
/// per digit from wherever focus already is, which is what a remote is for.
///
/// It submits itself on the last digit: an OK button would have to be
/// arrowed down to past the pad, and there is nothing to confirm — six digits
/// are either the code or they aren't. A wrong code clears the slots and says
/// so rather than silently emptying them, because an empty pad after a press
/// reads as a dropped button.
struct AdultUnlockPanel: View {
    let onFinished: () -> Void

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: Theme
    @FocusState private var focus: Key?
    @State private var entered = ""
    @State private var wrong = false

    private enum Key: Hashable {
        case digit(Int)
        case delete
        case cancel
    }

    private static let rows: [[Int]] = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]

    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()

            VStack(spacing: 30) {
                header
                slots
                message
                keypad
            }
            .padding(52)
            .frame(width: 720)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Palette.sheet)
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Palette.text(0.12), lineWidth: 1))
            )
        }
        .onAppear { focus = .digit(1) }
        .onExitCommand(perform: onFinished)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 8) {
            Text("ADULT CONTENT")
                .font(Mono.font(14, .bold))
                .tracking(2.6)
                .foregroundStyle(theme.accent)
            Text("Enter the code")
                .font(Typography.font(40, .black))
                .foregroundStyle(Palette.textPrimary)
            Text("Unlocks for 12 hours, then hides itself again.")
                .font(Typography.font(19, .medium))
                .foregroundStyle(Palette.text(0.45))
        }
    }

    /// One slot per digit, filled as they land. Dots rather than the numbers:
    /// the code is typed on a screen the whole room is looking at.
    private var slots: some View {
        HStack(spacing: 14) {
            ForEach(0..<AdultLock.digits, id: \.self) { index in
                let filled = index < entered.count
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Palette.text(filled ? 0.1 : 0.04))
                    .frame(width: 58, height: 72)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(wrong ? theme.accent : Palette.text(filled ? 0.28 : 0.1), lineWidth: 1.5)
                    )
                    .overlay {
                        if filled {
                            Circle().fill(Palette.textPrimary).frame(width: 16, height: 16)
                        }
                    }
            }
        }
        .animation(.easeOut(duration: 0.15), value: entered)
        .animation(.easeOut(duration: 0.2), value: wrong)
    }

    /// Holds its line whether or not there is anything to say — a message
    /// that appears re-lays the keypad out under the remote mid-press.
    private var message: some View {
        Text(wrong ? "That's not the code." : " ")
            .font(Typography.font(19, .semibold))
            .foregroundStyle(theme.accent)
            .frame(height: 24)
    }

    private var keypad: some View {
        VStack(spacing: 14) {
            ForEach(Self.rows, id: \.self) { row in
                HStack(spacing: 14) {
                    ForEach(row, id: \.self) { digit in
                        key(label: "\(digit)", focusKey: .digit(digit)) { append(digit) }
                    }
                }
            }
            HStack(spacing: 14) {
                key(label: nil, systemImage: "delete.left", focusKey: .delete, action: backspace)
                key(label: "0", focusKey: .digit(0)) { append(0) }
                key(label: nil, systemImage: "xmark", focusKey: .cancel, action: onFinished)
            }
        }
        // The pad is one block of siblings: without this, Left from the "1"
        // key hunts the whole screen for the geometrically nearest focusable
        // view and lands back in the Settings category list behind the scrim.
        .focusSection()
    }

    @ViewBuilder
    private func key(label: String?, systemImage: String? = nil,
                     focusKey: Key, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let label {
                    Text(label).font(Typography.font(34, .bold))
                } else if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 26, weight: .semibold))
                }
            }
            .foregroundStyle(Palette.textPrimary)
            .frame(width: 128, height: 88)
            .background(Palette.text(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Palette.text(0.1), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(FocusScaleStyle(scale: 1.08, cornerRadius: 14))
        .focused($focus, equals: focusKey)
    }

    // MARK: - Entry

    private func append(_ digit: Int) {
        // A press that lands on a full pad is the last one's echo, not a
        // seventh digit — swallow it rather than shifting the slots along.
        guard entered.count < AdultLock.digits else { return }
        wrong = false
        entered.append(String(digit))
        guard entered.count == AdultLock.digits else { return }
        if appState.unlockAdultContent(code: entered) {
            onFinished()
        } else {
            wrong = true
            entered = ""
        }
    }

    private func backspace() {
        wrong = false
        guard !entered.isEmpty else { return }
        entered.removeLast()
    }
}
#endif
