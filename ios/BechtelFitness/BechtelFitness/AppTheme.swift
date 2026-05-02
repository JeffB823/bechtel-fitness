import SwiftUI

enum AppTheme {
    static let navy = Color(red: 0.035, green: 0.075, blue: 0.16)
    static let blue = Color(red: 0.06, green: 0.32, blue: 0.72)
    static let electricBlue = Color(red: 0.12, green: 0.50, blue: 0.95)
    static let gold = Color(red: 0.93, green: 0.69, blue: 0.22)
    static let softGold = Color(red: 1.0, green: 0.86, blue: 0.48)
    static let chrome = Color(red: 0.05, green: 0.09, blue: 0.17)
    static let surface = Color(.secondarySystemGroupedBackground)
    static let card = Color(.systemBackground)
    static let groupedBackground = Color(.systemGroupedBackground)
    static let border = Color.black.opacity(0.05)
    static let glassBorder = Color.white.opacity(0.08)
    static let heroGradient = LinearGradient(
        colors: [navy, blue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let pageGradient = LinearGradient(
        colors: [navy.opacity(0.08), groupedBackground],
        startPoint: .top,
        endPoint: .center
    )
    static let dashboardGradient = LinearGradient(
        colors: [navy.opacity(0.98), Color(red: 0.05, green: 0.11, blue: 0.21)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let workoutCanvas = LinearGradient(
        colors: [chrome, navy, Color(red: 0.02, green: 0.05, blue: 0.11)],
        startPoint: .top,
        endPoint: .bottom
    )
}
