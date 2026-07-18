import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A single-line text input, styled to match the app's dark chrome (used by
/// the connect-to-server form and any other in-app search/entry field).
///
/// A focused tvOS `TextField` always paints a large white system "pill" that
/// can't be turned off (`focusEffectDisabled()` doesn't touch it), and it
/// fights our dark chrome. And SwiftUI's `.focused()` doesn't reliably raise the
/// full-screen keyboard for an off-screen field. So the visible/focusable
/// element is a plain-styled `Button` that draws our own dark fill + accent
/// border, and text entry happens in a real UIKit `UITextField` (via
/// `TVTextField`) layered invisibly behind it. Selecting the button flips
/// `editing`, which drives that field's `becomeFirstResponder()` — the native
/// call that actually presents the tvOS keyboard. The field only exists while
/// this input is focused/editing, keeping it out of the focus-navigation path.
struct AppTextField<F: Hashable>: View {
    let placeholder: String
    @Binding var text: String
    var secure: Bool = false
    var mono: Bool = false
    var prefix: String? = nil
    /// Leading SF Symbol, e.g. "magnifyingglass" for a search field.
    var systemImage: String? = nil
    /// Trailing accessory text, e.g. a live result count.
    var trailing: String? = nil
    var width: CGFloat? = nil
    let accent: Color
    let field: F
    var focus: FocusState<F?>.Binding
    var onSubmit: () -> Void = {}

    @State private var editing = false

    private var isFocused: Bool { focus.wrappedValue == field }
    private var isEmpty: Bool { text.isEmpty }

    var body: some View {
        ZStack {
            // Real UIKit input target, layered invisibly behind the button. It
            // only exists while this field is focused/editing, so it stays out of
            // the focus-navigation path and can't steal focus from a neighbour.
            if isFocused || editing {
                TVTextField(text: $text, isSecure: secure, isEditing: $editing, onSubmit: onSubmit)
                    .frame(maxWidth: width ?? .infinity)
                    .frame(height: 60)
                    .opacity(0.02)
            }

            Button { editing = true } label: {
                HStack(spacing: 10) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .foregroundStyle(Palette.text(0.45))
                    }
                    if let prefix {
                        Text(prefix)
                            .font(Mono.font(16))
                            .foregroundStyle(Palette.text(0.4))
                    }
                    Text(displayText)
                        .font(mono ? Mono.font(20, .semibold) : Typography.font(20, .semibold))
                        .foregroundStyle(isEmpty ? Palette.text(0.32) : Palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    if let trailing {
                        Text(trailing)
                            .font(Mono.font(16, .bold))
                            .foregroundStyle(Palette.text(0.4))
                    }
                }
                .padding(.horizontal, 18)
                .frame(height: 60)
                .frame(maxWidth: width ?? .infinity, alignment: .leading)
                .background(fill, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(stroke, lineWidth: 1.5))
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .animation(.easeOut(duration: 0.18), value: isFocused)
            }
            .buttonStyle(AppTextFieldButtonStyle())
            .focused(focus, equals: field)
        }
        // When the keyboard dismisses, land focus back on this field's button
        // rather than dropping to nowhere.
        .onChange(of: editing) {
            if !editing { focus.wrappedValue = field }
        }
        // Without this, a vertical ScrollView ancestor proposes unbounded
        // height to this view, and the focusable Button inside expands to
        // fill it — harmless in SetupView (never inside a ScrollView) but a
        // full-height invisible field when reused somewhere that is.
        .frame(height: 60)
    }

    private var displayText: String {
        if isEmpty { return placeholder }
        return secure ? String(repeating: "•", count: min(text.count, 32)) : text
    }
    private var fill: Color { .white.opacity(isFocused ? 0.08 : 0.05) }
    private var stroke: Color { isFocused ? accent : .white.opacity(0.14) }
}

/// Renders a field button's label with no tvOS system chrome (no white focus
/// pill) — the field draws its own focus treatment via `isFocused`.
struct AppTextFieldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

#if canImport(UIKit)
/// A UIKit `UITextField` bridged into SwiftUI purely as an invisible keyboard
/// target. `isEditing` is the command channel: flipping it true calls
/// `becomeFirstResponder()` — the native call that reliably presents tvOS's
/// full-screen keyboard (SwiftUI's `.focused()` does not, for an off-screen
/// field). The field renders nothing (clear text + tint); the visible value is
/// drawn by the styled button in front of it.
struct TVTextField: UIViewRepresentable {
    @Binding var text: String
    var isSecure: Bool
    @Binding var isEditing: Bool
    var onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.delegate = context.coordinator
        tf.isSecureTextEntry = isSecure
        tf.autocorrectionType = .no
        tf.autocapitalizationType = .none
        tf.spellCheckingType = .no
        tf.borderStyle = .none
        tf.backgroundColor = .clear
        tf.textColor = .clear   // the styled button draws the visible value
        tf.tintColor = .clear
        tf.addTarget(context.coordinator,
                     action: #selector(Coordinator.editingChanged(_:)),
                     for: .editingChanged)
        return tf
    }

    func updateUIView(_ tf: UITextField, context: Context) {
        if tf.text != text { tf.text = text }
        tf.isSecureTextEntry = isSecure
        // Drive first-responder off `isEditing`. Defer so we never mutate
        // responder state in the middle of a SwiftUI view update.
        if isEditing, !tf.isFirstResponder {
            DispatchQueue.main.async { _ = tf.becomeFirstResponder() }
        } else if !isEditing, tf.isFirstResponder {
            DispatchQueue.main.async { tf.resignFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        let parent: TVTextField
        init(_ parent: TVTextField) { self.parent = parent }

        @objc func editingChanged(_ tf: UITextField) {
            parent.text = tf.text ?? ""
        }

        func textFieldShouldReturn(_ tf: UITextField) -> Bool {
            tf.resignFirstResponder()
            parent.onSubmit()
            return true
        }

        func textFieldDidEndEditing(_ tf: UITextField) {
            // Keyboard dismissed (Return, Menu, or elsewhere) — release the
            // command flag so the field goes away and focus returns to the button.
            if parent.isEditing {
                DispatchQueue.main.async { self.parent.isEditing = false }
            }
        }
    }
}
#else
/// Non-UIKit fallback (keeps the file compiling on platforms without UIKit).
struct TVTextField: View {
    @Binding var text: String
    var isSecure: Bool
    @Binding var isEditing: Bool
    var onSubmit: () -> Void
    var body: some View {
        Group {
            if isSecure { SecureField("", text: $text) } else { TextField("", text: $text) }
        }
        .onSubmit { isEditing = false; onSubmit() }
    }
}
#endif
