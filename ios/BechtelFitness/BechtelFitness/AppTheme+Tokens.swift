import SwiftUI

extension AppTheme {
    enum Spacing {
        static let xs: CGFloat = 6
        static let s: CGFloat = 10
        static let m: CGFloat = 14
        static let l: CGFloat = 18
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let chip: CGFloat = 12
        static let row: CGFloat = 18
        static let card: CGFloat = 24
        static let hero: CGFloat = 32
    }

    enum Size {
        static let minTouch: CGFloat = 44
        static let restRing: CGFloat = 220
        static let restRingLine: CGFloat = 14
        static let restPill: CGFloat = 74
        static let icon: CGFloat = 64
        static let compactIcon: CGFloat = 44
        static let secondaryActionWidth: CGFloat = 112
    }

    enum TextOnDark {
        static let primary = Color.white
        static let secondary = Color.white.opacity(0.78)
        static let tertiary = Color.white.opacity(0.62)
        static let small = Color.white.opacity(0.74)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(AppTheme.navy)
            .frame(minHeight: AppTheme.Size.minTouch)
            .padding(.horizontal, AppTheme.Spacing.l)
            .background(AppTheme.gold.opacity(configuration.isPressed ? 0.82 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(minHeight: AppTheme.Size.minTouch)
            .padding(.horizontal, AppTheme.Spacing.l)
            .background(Color.white.opacity(configuration.isPressed ? 0.16 : 0.10), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(AppTheme.navy)
            .frame(minHeight: AppTheme.Size.minTouch)
            .padding(.horizontal, AppTheme.Spacing.l)
            .background(Color.clear, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(AppTheme.navy.opacity(configuration.isPressed ? 0.45 : 0.25), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
