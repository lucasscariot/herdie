import SwiftUI

enum HerdieTheme {
    static let accent = adaptive(light: 0x5140C8, dark: 0xA49CFF)
    static let onAccent = adaptive(light: 0xFFFFFF, dark: 0x15102E)
    static let blue = adaptive(light: 0x155BB5, dark: 0x70B4FF)
    static let border = adaptive(light: 0xD1D1E0, dark: 0x393947)
    static let background = adaptive(light: 0xF8F8FD, dark: 0x06060E)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x131517)
    static let raisedSurface = adaptive(light: 0xEEEEF8, dark: 0x1B1C1F)
    static let secondary = Color.secondary
    static let danger = Color(red: 1.0, green: 0.28, blue: 0.3)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}

struct HerdieBackground: View {
    var body: some View {
        ZStack {
            HerdieTheme.background
            RadialGradient(
                colors: [HerdieTheme.accent.opacity(0.11), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 440
            )
            RadialGradient(
                colors: [HerdieTheme.blue.opacity(0.12), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 320
            )
        }
        .ignoresSafeArea()
    }
}

struct RoundIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var tint: Color = .primary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 52, height: 52)
                .background(.thinMaterial, in: Circle())
                .overlay(Circle().stroke(HerdieTheme.border))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct SectionLabel: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.caption.weight(.medium))
                .tracking(1.2)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption)
            }
        }
        .foregroundStyle(HerdieTheme.secondary)
    }
}

extension View {
    @ViewBuilder
    func herdieGlass() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    func herdieCard(cornerRadius: CGFloat = 22) -> some View {
        background(HerdieTheme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(HerdieTheme.border)
            }
    }
}

/// Local rendering only. Remote terminal cells and cursor coordinates stay intact.
enum TerminalTheme: String, Codable, CaseIterable, Identifiable {
    case herdie, remote
    var id: Self { self }
    var title: String { self == .herdie ? "Herdie" : "Remote colours" }
    var background: UIColor { UIColor { self.background(for: $0.userInterfaceStyle) } }
    var foreground: UIColor { UIColor { self.foreground(for: $0.userInterfaceStyle) } }

    func background(for style: UIUserInterfaceStyle) -> UIColor {
        Self.rgb(style == .light ? 0xFAFAFD : (self == .herdie ? 0x101016 : 0x06060E))
    }

    func foreground(for style: UIUserInterfaceStyle) -> UIColor {
        style == .light ? Self.rgb(0x242430) : (self == .herdie ? Self.rgb(0xE5E4EC) : .white)
    }

    func resolve(_ color: TerminalColor, isBackground: Bool = false, style: UIUserInterfaceStyle = .dark) -> UIColor {
        switch color {
        case .default:
            return isBackground ? background(for: style) : foreground(for: style)
        case let .rgb(red, green, blue):
            let original = UIColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
            return surface(original, red: red, green: green, blue: blue, isBackground: isBackground, style: style)
        case let .indexed(index):
            if index < 16 {
                if self == .herdie {
                    let dark: [UInt32] = [
                        0x15151D, 0xF08089, 0xA3CCAC, 0xE5C890,
                        0x9EBAF0, 0xB8A7EF, 0x8BCBCD, 0xD6D5DE,
                        0x797887, 0xFF9AA2, 0xBBE5C4, 0xF5DFA4,
                        0xB9CEF8, 0xD1BFF8, 0xB1E5E6, 0xF1F0F5
                    ]
                    let light: [UInt32] = [
                        0x242430, 0xA32D41, 0x28613C, 0x785714,
                        0x315DA8, 0x7051AA, 0x24676D, 0x555563,
                        0x747480, 0xB52F43, 0x317048, 0x826119,
                        0x3C65AE, 0x7950B0, 0x287278, 0x242430
                    ]
                    if isBackground && (index == 0 || index == 8) {
                        return index == 0 ? background(for: style) : Self.rgb(style == .light ? 0xE9E9F2 : 0x24242F)
                    }
                    return Self.rgb((style == .light && !isBackground ? light : dark)[Int(index)])
                }
                let palette: [UIColor] = [
                    .black, .systemRed, .systemGreen, .systemYellow,
                    .systemBlue, .systemPurple, .systemTeal, .lightGray,
                    .darkGray, .red, .green, .yellow, .blue, .magenta, .cyan, .white
                ]
                return palette[Int(index)]
            }
            let red: UInt8
            let green: UInt8
            let blue: UInt8
            if index >= 232 {
                red = UInt8(8 + 10 * (Int(index) - 232))
                green = red
                blue = red
            } else {
                let cube = Int(index) - 16
                func channel(_ value: Int) -> UInt8 { UInt8(value == 0 ? 0 : 55 + value * 40) }
                red = channel(cube / 36)
                green = channel((cube % 36) / 6)
                blue = channel(cube % 6)
            }
            let original = UIColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
            return surface(original, red: red, green: green, blue: blue, isBackground: isBackground, style: style)
        }
    }

    private func surface(_ original: UIColor, red: UInt8, green: UInt8, blue: UInt8, isBackground: Bool, style: UIUserInterfaceStyle) -> UIColor {
        let brightest = max(red, green, blue)
        let darkest = min(red, green, blue)
        // Unify dark neutral panel fills; preserve coloured highlights, syntax and selection colours.
        guard self == .herdie, isBackground, brightest <= 100, brightest - darkest <= 24 else { return original }
        return brightest < 64 ? background(for: style) : Self.rgb(style == .light ? 0xE9E9F2 : 0x24242F)
    }

    func legibleForeground(_ foreground: UIColor, on background: UIColor, style: UIUserInterfaceStyle) -> UIColor {
        guard self == .herdie, style == .light, Self.contrast(foreground, background) < 4.5 else { return foreground }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard foreground.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return foreground }
        let ink = self.foreground(for: .light)
        if min(red, green, blue) > 0.7, max(red, green, blue) - min(red, green, blue) < 0.12,
           Self.contrast(ink, background) >= 4.5 { return ink }
        let target: CGFloat = Self.contrast(.black, background) >= Self.contrast(.white, background) ? 0 : 1
        func blend(_ amount: CGFloat) -> UIColor {
            UIColor(red: red + (target - red) * amount, green: green + (target - green) * amount,
                    blue: blue + (target - blue) * amount, alpha: alpha)
        }
        var low: CGFloat = 0, high: CGFloat = 1
        for _ in 0..<12 {
            let middle = (low + high) / 2
            if Self.contrast(blend(middle), background) >= 4.5 { high = middle } else { low = middle }
        }
        return blend(high)
    }

    static func contrast(_ first: UIColor, _ second: UIColor) -> CGFloat {
        func luminance(_ color: UIColor) -> CGFloat {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            func linear(_ value: CGFloat) -> CGFloat { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}
