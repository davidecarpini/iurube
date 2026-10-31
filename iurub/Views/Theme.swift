import SwiftUI

// Semantic system surfaces keep text readable in light mode, dark mode and increased contrast.
enum Theme {
    static let accent = Color(red: 0.91, green: 0.29, blue: 0.22)
    static let background = Color("LaunchBackground")
    static let ink = Color.primary
    static let quiet = Color.secondary
    #if os(iOS)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    #else
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    #endif
}

struct BrandMark: View {
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "play.rectangle.fill")
                .foregroundStyle(Theme.accent)
            Text("iurub")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("iurub")
    }
}

struct SettingsButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: "slider.horizontal.3").frame(width: 32, height: 32) }
            .accessibilityLabel("Impostazioni")
            .accessibilityIdentifier("settingsButton")
    }
}
