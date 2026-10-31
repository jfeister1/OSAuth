import SwiftUI

enum AppTheme {
    static let backgroundTop = Color(red: 0.07, green: 0.09, blue: 0.11)
    static let backgroundBottom = Color(red: 0.04, green: 0.05, blue: 0.07)
    static let panel = Color(red: 0.11, green: 0.14, blue: 0.17).opacity(0.92)
    static let panelStroke = Color.white.opacity(0.08)
    static let accent = Color(red: 0.18, green: 0.82, blue: 0.72)
    static let accentMuted = Color(red: 0.18, green: 0.82, blue: 0.72).opacity(0.18)
    static let warning = Color(red: 0.96, green: 0.72, blue: 0.28)
    static let danger = Color(red: 0.93, green: 0.35, blue: 0.32)
    static let textPrimary = Color(red: 0.93, green: 0.95, blue: 0.96)
    static let textSecondary = Color(red: 0.62, green: 0.68, blue: 0.72)
    static let mono = Font.system(.body, design: .monospaced)
    static let display = Font.system(size: 28, weight: .semibold, design: .rounded)
    static let title = Font.system(size: 15, weight: .semibold, design: .rounded)
}

struct AtmosphereBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.backgroundTop, AppTheme.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [AppTheme.accent.opacity(0.16), .clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 420
            )

            Canvas { context, size in
                let spacing: CGFloat = 28
                for x in stride(from: 0, through: size.width, by: spacing) {
                    for y in stride(from: 0, through: size.height, by: spacing) {
                        let rect = CGRect(x: x, y: y, width: 1.2, height: 1.2)
                        context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.035)))
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}
