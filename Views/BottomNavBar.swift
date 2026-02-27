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
        HStack {
            NavButton(
                icon: "chevron.left",
                isEnabled: canGoBack,
                action: onBack
            )
            
            Spacer()
            
            // Forward Button
            NavButton(
                icon: "chevron.right",
                isEnabled: canGoForward,
                action: onForward
            )
            
            Spacer()
            
            NavButton(
                icon: "house",
                isEnabled: true,
                action: onHome
            )
            
            Spacer()
            
            NavButton(
                icon: isLoading ? "xmark" : "arrow.clockwise",
                isEnabled: true,
                action: onReloadOrStop
            )
            
            Spacer()
            
            Button(action: onAddressFocus) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.cyberWhite)
            }
            .buttonStyle(CyberButtonStyle())
            
            Spacer()
            
            Button(action: onTabs) {
                ZStack {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.cyberWhite)
                    
                    if tabCount > 1 {
                        Text("\(tabCount)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyberWhite)
                            .padding(2)
                            .background(Color.cyberSurface)
                            .clipShape(Circle())
                            .offset(x: 9, y: -8)
                    }
                }
            }
            .buttonStyle(CyberButtonStyle())
            
            Spacer()
            
            NavButton(
                icon: "line.3.horizontal",
                isEnabled: true,
                action: onMenu
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .padding(.bottom, 6)
        .background(
            Color.cyberBlack.opacity(0.92)
        )
    }
}

// MARK: - Navigation Button Component
struct NavButton: View {
    let icon: String
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(isEnabled ? .cyberWhite : .cyberMuted)
        }
        .disabled(!isEnabled)
        .buttonStyle(CyberButtonStyle())
    }
}
