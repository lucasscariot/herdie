import SwiftUI

enum HerdieTheme {
    static let accent = Color(red: 0.15, green: 1.0, blue: 0.27)
    static let background = Color(red: 0.008, green: 0.012, blue: 0.01)
    static let surface = Color(red: 0.075, green: 0.082, blue: 0.09)
    static let raisedSurface = Color(red: 0.105, green: 0.11, blue: 0.12)
    static let secondary = Color(red: 0.57, green: 0.59, blue: 0.65)
    static let danger = Color(red: 1.0, green: 0.28, blue: 0.3)
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
                colors: [HerdieTheme.accent.opacity(0.08), .clear],
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
    var tint: Color = .white
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 52, height: 52)
                .background(.thinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.09)))
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
    func herdieCard(cornerRadius: CGFloat = 22) -> some View {
        background(HerdieTheme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.045))
            }
    }
}
