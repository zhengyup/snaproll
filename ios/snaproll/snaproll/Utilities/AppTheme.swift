import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.06, green: 0.05, blue: 0.04)
    static let backgroundGlow = Color(red: 0.22, green: 0.17, blue: 0.07)
    static let surface = Color(red: 0.11, green: 0.10, blue: 0.08)
    static let surfaceRaised = Color(red: 0.15, green: 0.13, blue: 0.10)
    static let card = Color(red: 0.14, green: 0.12, blue: 0.09)
    static let border = Color.white.opacity(0.08)
    static let primaryAction = Color(red: 0.90, green: 0.69, blue: 0.04)
    static let accent = Color(red: 0.95, green: 0.75, blue: 0.09)
    static let softText = Color(red: 0.66, green: 0.63, blue: 0.57)
    static let creamText = Color(red: 0.97, green: 0.94, blue: 0.90)
    static let mutedText = Color(red: 0.82, green: 0.78, blue: 0.71)
    static let shadow = Color.black.opacity(0.28)

    static func color(from hex: String) -> Color {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt64()
        Scanner(string: sanitized).scanHexInt64(&int)

        let red = Double((int >> 16) & 0xFF) / 255.0
        let green = Double((int >> 8) & 0xFF) / 255.0
        let blue = Double(int & 0xFF) / 255.0

        return Color(red: red, green: green, blue: blue)
    }
}
