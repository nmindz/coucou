import SwiftUI

/// Coucou's text input: a soft rounded well with a hairline border that lights up in the
/// window's tint (Coucou orange in the Coucou window) while the field has focus.
/// Works on `TextField` and `SecureField`, in dark and light windows.
private struct CoucouFieldChrome: ViewModifier {
    var icon: String?
    var monospaced: Bool
    var height: CGFloat

    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled

    private var fill: Color {
        scheme == .dark ? Color(hex: "#1F2024") : Color(nsColor: .textBackgroundColor)
    }
    /// 3:1 against the field and its surroundings, so the field can be told apart (WCAG 1.4.11).
    private var border: Color {
        scheme == .dark ? Color.white.opacity(0.34) : Color.black.opacity(0.46)
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        HStack(spacing: 7) {
            if let icon {
                Image(systemName: icon)
                    .coucouFont(size: 12, weight: .medium)
                    .foregroundStyle(focused ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 14)
            }
            content
                .textFieldStyle(.plain)
                .coucouText(monospaced ? .mono : .body)
                .focused($focused)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .frame(minHeight: height)
        .background(shape.fill(fill))
        .overlay(shape.strokeBorder(focused ? AnyShapeStyle(.tint) : AnyShapeStyle(border),
                                    lineWidth: focused ? 1.5 : 1))
        // Soft halo around the focused field, in place of the system focus ring.
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.tint.opacity(0.22), lineWidth: 3)
                .padding(-3)
                .opacity(focused ? 1 : 0)
                .allowsHitTesting(false)
        )
        .focusEffectDisabled()
        .opacity(isEnabled ? 1 : 0.55)
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

extension View {
    /// Draws a `TextField` or `SecureField` in Coucou's style; use in place of `.roundedBorder`.
    func coucouField(icon: String? = nil, monospaced: Bool = false, height: CGFloat = 32) -> some View {
        modifier(CoucouFieldChrome(icon: icon, monospaced: monospaced, height: height))
    }
}
