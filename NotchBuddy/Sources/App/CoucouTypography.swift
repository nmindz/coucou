import SwiftUI

/// Text size for the Coucou window's pages (Settings → General → Text size), so text can grow
/// without assistive technology (WCAG 1.4.4).
enum TextSize {
    static let key = "textScale"
    static let options: [(scale: Double, label: LocalizedStringResource)] = [
        (1.0, "text-size.default"), (1.15, "text-size.large"), (1.3, "text-size.larger"), (1.5, "text-size.largest"),
    ]
}

private struct TextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var coucouTextScale: CGFloat {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

/// The roles text plays on a page; one size and colour each, the same on every page.
enum CoucouTextRole {
    case sectionLabel   // "NOTETAKER": small capitals above a card
    case rowTitle       // a setting's name
    case body           // running text, control labels
    case detail         // the explanation under a setting
    case caption        // status lines, hints
    case mono           // paths, commands

    var size: CGFloat {
        switch self {
        case .sectionLabel: 13.5
        case .rowTitle:     15.5
        case .body:         15
        case .detail:       14
        case .caption:      13
        case .mono:         13
        }
    }

    var weight: Font.Weight {
        switch self {
        case .sectionLabel: .bold
        case .rowTitle:     .medium
        default:            .regular
        }
    }
}

/// Palette for text on the window's dark surfaces; every pair passes WCAG AA (4.5:1) on the
/// panel, card and field backgrounds.
enum CoucouTextColor {
    static let primary   = Color(hex: "#F5F6F8")   // 15:1 and up
    static let secondary = Color(hex: "#8E939C")   // 5.3:1 and up
    static let muted     = Color(hex: "#8A8F98")   // 5.0:1 and up
}

private struct ScaledFont: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    @Environment(\.coucouTextScale) private var scale

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight, design: design))
    }
}

extension View {
    /// A fixed point size that follows the user's text size.
    func coucouFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design))
    }

    /// The size and weight of a text role, following the user's text size.
    func coucouText(_ role: CoucouTextRole) -> some View {
        coucouFont(size: role.size, weight: role.weight, design: role == .mono ? .monospaced : .default)
    }
}

extension View {
    /// Coucou's button: the Coucou window's own style, the system's in the App Store build (its
    /// own Settings window follows the system appearance).
    @ViewBuilder func coucouButton(primary: Bool = false) -> some View {
        #if APPSTORE
        if primary { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        #else
        buttonStyle(HubButtonStyle(primary: primary))
        #endif
    }
}
