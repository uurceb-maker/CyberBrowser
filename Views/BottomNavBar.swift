import SwiftUI

// MARK: - Bottom Navigation Bar
struct BottomNavBar: View {
    let canGoBack: Bool
    let canGoForward: Bool
    let isLoading: Bool
    let tabCount: Int

    let onBack: () -> Void
    let onForward: () -> Void
    let onHome: () -> Void
    let onReloadOrStop: () -> Void
    let onAddressFocus: () -> Void
    let onTabs: () -> Void
    let onMenu: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            NavButton(icon: "arrow.left", isEnabled: canGoBack, action: onBack)
            NavButton(icon: "arrow.right", isEnabled: canGoForward, action: onForward)
            NavButton(icon: "house", isEnabled: true, action: onHome)
            NavButton(icon: isLoading ? "xmark" : "arrow.clockwise", isEnabled: true, action: onReloadOrStop)

            Button(action: onAddressFocus) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.cyberWhite)
            }
            .buttonStyle(CyberButtonStyle())

            Button(action: onTabs) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "plus.square")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.cyberWhite)

                    if tabCount > 1 {
                        Text("\(tabCount)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.cyberYellow, in: Capsule())
                            .offset(x: 7, y: -7)
                    }
                }
            }
            .buttonStyle(CyberButtonStyle())

            NavButton(icon: "line.3.horizontal", isEnabled: true, action: onMenu)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: CyberTheme.cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CyberTheme.cornerRadius, style: .continuous)
                .stroke(Color.cyberYellow.opacity(0.22), lineWidth: 0.8)
        )
        .shadow(color: Color.cyberYellow.opacity(0.14), radius: 20, x: 0, y: 10)
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }
}

// MARK: - Navigation Button Component
struct NavButton: View {
    let icon: String
    let isEnabled: Bool
    let action: () -> Void
    @State private var tapCount: Int = 0

    var body: some View {
        Button {
            tapCount += 1
            action()
        } label: {
            Image(systemName: icon)
                .symbolVariant(isEnabled ? .none : .slash)
                .symbolEffect(.bounce, value: tapCount)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(isEnabled ? .cyberWhite : .cyberMuted)
        }
        .disabled(!isEnabled)
        .buttonStyle(CyberButtonStyle())
    }
}
