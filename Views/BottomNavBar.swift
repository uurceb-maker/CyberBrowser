import SwiftUI

// MARK: - Bottom Navigation Bar
struct BottomNavBar: View {
    let canGoBack: Bool
    let canGoForward: Bool
    let tabCount: Int
    
    let onBack: () -> Void
    let onForward: () -> Void
    let onSearch: () -> Void
    let onTabs: () -> Void
    let onMenu: () -> Void
    
    var body: some View {
        HStack {
            // Back Button
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
            
            // Search Button (Yellow circle)
            Button(action: onSearch) {
                ZStack {
                    // Glow effect
                    Circle()
                        .fill(Color.cyberYellow.opacity(0.2))
                        .frame(width: 52, height: 52)
                        .blur(radius: 8)
                    
                    Circle()
                        .fill(Color.cyberYellow)
                        .frame(width: 44, height: 44)
                        .shadow(color: .cyberYellow.opacity(0.5), radius: 10, x: 0, y: 0)
                    
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.black)
                }
            }
            .buttonStyle(CyberButtonStyle())
            
            Spacer()
            
            // Tabs Button
            Button(action: onTabs) {
                ZStack {
                    Image(systemName: "square.on.square")
                        .font(.system(size: CyberTheme.iconSize, weight: .medium))
                        .foregroundColor(.cyberWhite)
                    
                    // Tab count badge
                    if tabCount > 1 {
                        Text("\(tabCount)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(3)
                            .background(Color.cyberYellow)
                            .clipShape(Circle())
                            .offset(x: 10, y: -10)
                    }
                }
            }
            .buttonStyle(CyberButtonStyle())
            
            Spacer()
            
            // Menu Button
            NavButton(
                icon: "line.3.horizontal",
                isEnabled: true,
                action: onMenu
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .padding(.bottom, 8)
        .background(
            Rectangle()
                .fill(Color.cyberBlack)
                .shadow(color: .cyberYellow.opacity(0.1), radius: 10, y: -5)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color.cyberYellow.opacity(0.2)),
                    alignment: .top
                )
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
                .font(.system(size: CyberTheme.iconSize, weight: .medium))
                .foregroundColor(isEnabled ? .cyberWhite : .cyberMuted)
        }
        .disabled(!isEnabled)
        .buttonStyle(CyberButtonStyle())
    }
}
