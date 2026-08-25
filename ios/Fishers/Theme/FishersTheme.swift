import SwiftUI

enum FishersTheme {
    static let accent = Color(red: 0.05, green: 0.35, blue: 0.28)
    static let pitch = Color(red: 0.12, green: 0.48, blue: 0.32)
    static let available = Color(red: 0.18, green: 0.62, blue: 0.38)
    static let maybe = Color(red: 0.92, green: 0.68, blue: 0.18)
    static let unavailable = Color(red: 0.72, green: 0.28, blue: 0.28)
    static let ink = Color(red: 0.08, green: 0.12, blue: 0.14)
    static let mist = Color(red: 0.94, green: 0.96, blue: 0.95)
    static let cream = Color(red: 0.98, green: 0.97, blue: 0.94)

    static let display = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let title = Font.system(.title2, design: .rounded).weight(.semibold)
    static let body = Font.system(.body, design: .default)
}
