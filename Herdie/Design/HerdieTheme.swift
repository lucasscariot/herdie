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
