import SwiftUI

// MARK: - Cyberpunk Color Palette
extension Color {
    /// Pure black background — #000000
    static let cyberBlack = Color(red: 0, green: 0, blue: 0)
    
    /// Accent yellow — #FACC15
    static let cyberYellow = Color(red: 250/255, green: 204/255, blue: 21/255)
    
    /// Pure white for text
    static let cyberWhite = Color.white
    
    /// Dark surface for cards, panels — #111111
    static let cyberSurface = Color(red: 17/255, green: 17/255, blue: 17/255)
    
    /// Darker surface for separators — #1A1A1A
    static let cyberDivider = Color(red: 26/255, green: 26/255, blue: 26/255)
    
    /// Muted text — #888888
    static let cyberMuted = Color(red: 136/255, green: 136/255, blue: 136/255)
    
    /// Danger red for close/delete actions — #EF4444
    static let cyberRed = Color(red: 239/255, green: 68/255, blue: 68/255)
    
    /// Secure green for HTTPS — #22C55E
    static let cyberGreen = Color(red: 34/255, green: 197/255, blue: 94/255)
    
    /// Yellow with glow opacity
    static let cyberYellowGlow = Color(red: 250/255, green: 204/255, blue: 21/255).opacity(0.3)
}

// MARK: - UIColor Extension for Hex
extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}

// MARK: - Design Constants
enum CyberTheme {
    static let cornerRadius: CGFloat = 12
    static let smallCornerRadius: CGFloat = 8
    static let padding: CGFloat = 16
    static let smallPadding: CGFloat = 8
    static let iconSize: CGFloat = 22
    static let navBarHeight: CGFloat = 56
    static let addressBarHeight: CGFloat = 44
    
    // Glow effect
    static func yellowGlow(radius: CGFloat = 10) -> some View {
        Color.cyberYellow.opacity(0.4).blur(radius: radius)
    }
}

// MARK: - Custom Button Styles
struct CyberButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct CyberPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.cyberYellow)
            .foregroundColor(.black)
            .cornerRadius(CyberTheme.smallCornerRadius)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3), value: configuration.isPressed)
    }
}

// MARK: - View Modifiers
struct CyberCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.cyberSurface)
            .cornerRadius(CyberTheme.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: CyberTheme.cornerRadius)
                    .stroke(Color.cyberYellow.opacity(0.2), lineWidth: 1)
            )
    }
}

extension View {
    func cyberCard() -> some View {
        modifier(CyberCardModifier())
    }
}
