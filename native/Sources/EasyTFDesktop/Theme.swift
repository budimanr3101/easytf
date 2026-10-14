import SwiftUI

enum Theme {
    static let accent = Color(red: 0.20, green: 0.57, blue: 0.93)
    static let ec2 = Color(red: 0.96, green: 0.56, blue: 0.18)
    static let securityGroup = Color(red: 0.23, green: 0.71, blue: 0.48)
    static let loadBalancer = Color(red: 0.65, green: 0.48, blue: 0.89)
    static func environment(_ name: String) -> Color {
        switch name.lowercased() {
        case "prod", "production": return Color(red: 0.91, green: 0.37, blue: 0.39)
        case "staging", "stage": return Color(red: 0.91, green: 0.67, blue: 0.22)
        default: return accent
        }
    }
}
struct ResourceLabel: View {
    let title: String
    let symbol: String
    let color: Color
    var body: some View { HStack(spacing: 9) { Image(systemName: symbol).foregroundStyle(color).frame(width: 18); Text(title) } }
}
struct EnvironmentBadge: View {
    let name: String
    var body: some View {
        HStack(spacing: 6) { Circle().fill(Theme.environment(name)).frame(width: 6, height: 6); Text(name.uppercased()).font(.caption).fontWeight(.semibold) }
            .padding(.horizontal, 10).padding(.vertical, 6).background(Theme.environment(name).opacity(0.12), in: Capsule()).foregroundStyle(Theme.environment(name))
    }
}
