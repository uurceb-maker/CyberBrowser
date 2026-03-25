import SwiftUI

// MARK: - Bottom Navigation Bar
struct BottomNavBar: View {
    let canGoBack: Bool
    let canGoForward: Bool
    let isLoading: Bool
    let tabCount: Int
    let isPrivateTab: Bool

    let onBack: () -> Void
    let onForward: () -> Void
    let onHome: () -> Void
    let onReloadOrStop: () -> Void
    let onAddressFocus: () -> Void
    let onTabs: () -> Void
    let onMenu: () -> Void
    let onPrivateTab: () -> Void
    let onConvertToPrivate: () -> Void

    @State private var privateLongPressTriggered = false

    var body: some View {
        GeometryReader { geometry in
            let barHeight: CGFloat = 56
            let totalHeight = barHeight + geometry.safeAreaInsets.bottom

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    NavButton(icon: "arrow.left", isEnabled: canGoBack, action: onBack)
                    NavButton(icon: "arrow.right", isEnabled: canGoForward, action: onForward)
                    NavButton(icon: "house", isEnabled: true, action: onHome)
                    NavButton(icon: isLoading ? "xmark" : "arrow.clockwise", isEnabled: true, action: onReloadOrStop)

                    Button(action: onAddressFocus) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(.cyberWhite)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(CyberButtonStyle())

                    Button(action: onTabs) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "plus.square")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundColor(.cyberWhite)
                                .frame(width: 44, height: 44)

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
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(CyberButtonStyle())

                    Button {
                        if privateLongPressTriggered {
                            privateLongPressTriggered = false
                            return
                        }
                        onPrivateTab()
                    } label: {
                        Image(systemName: isPrivateTab ? "eyeglasses" : "moon.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(isPrivateTab ? .cyberYellow : .cyberWhite)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(CyberButtonStyle())
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.55)
                            .onEnded { _ in
                                privateLongPressTriggered = true
                                onConvertToPrivate()
                            }
                    )

                    NavButton(icon: "line.3.horizontal", isEnabled: true, action: onMenu)
                }
                .frame(height: barHeight)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)

                Spacer(minLength: geometry.safeAreaInsets.bottom)
            }
            .frame(height: totalHeight, alignment: .top)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: CyberTheme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CyberTheme.cornerRadius, style: .continuous)
                    .stroke(Color.cyberYellow.opacity(0.22), lineWidth: 0.8)
            )
            .shadow(color: Color.cyberYellow.opacity(0.14), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 20)
        }
        .frame(height: 90)
    }
}

// MARK: - Navigation Button Component
struct NavButton: View {
    let icon: String
    let isEnabled: Bool
    let action: () -> Void
    @State private var tapCount = 0

    var body: some View {
        Button {
            tapCount += 1
            action()
        } label: {
            Image(systemName: icon)
                .symbolVariant(isEnabled ? .none : .slash)
                .symbolEffect(.bounce, value: tapCount)
                .font(.system(size: 26, weight: .medium))
                .foregroundColor(isEnabled ? .cyberWhite : .cyberMuted)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(!isEnabled)
        .buttonStyle(CyberButtonStyle())
    }
}
