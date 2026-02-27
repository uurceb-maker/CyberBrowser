import SwiftUI

// MARK: - Ad Block Banner
struct AdBlockBanner: View {
    @EnvironmentObject var adBlockEngine: AdBlockEngine
    
    @State private var displayCount: Int = 0
    @State private var shieldScale: CGFloat = 1.0
    
    var body: some View {
        if adBlockEngine.isEnabled || adBlockEngine.blockedAdsCount > 0 {
            HStack(spacing: 10) {
                // Shield Icon with pulse animation
                ZStack {
                    // Glow background
                    Circle()
                        .fill(Color.cyberYellow.opacity(0.2))
                        .frame(width: 36, height: 36)
                        .blur(radius: 6)
                    
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.cyberYellow)
                        .scaleEffect(shieldScale)
                }
                .frame(width: 36, height: 36)
                
                VStack(alignment: .leading, spacing: 2) {
                    // Animated counter
                    HStack(spacing: 4) {
                        Text("\(displayCount)")
                            .font(.system(size: 16, weight: .black, design: .monospaced))
                            .foregroundColor(.cyberYellow)
                            .contentTransition(.numericText())
                        
                        Text("reklam engellendi")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.cyberWhite.opacity(0.8))
                    }
                    
                    if !adBlockEngine.lastBlockedDomain.isEmpty {
                        Text(adBlockEngine.lastBlockedDomain)
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundColor(.cyberMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                
                Spacer()
                
                // Active indicator
                if adBlockEngine.isEnabled {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.cyberGreen)
                            .frame(width: 6, height: 6)
                        
                        Text("AKTİF")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyberGreen)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: CyberTheme.smallCornerRadius)
                    .fill(Color.cyberSurface.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: CyberTheme.smallCornerRadius)
                            .stroke(Color.cyberYellow.opacity(0.3), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, CyberTheme.padding)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: adBlockEngine.isEnabled)
            .onChange(of: adBlockEngine.blockedAdsCount) { _, newValue in
                // Animate count change
                withAnimation(.easeOut(duration: 0.3)) {
                    displayCount = newValue
                }
                
                // Shield pulse animation
                withAnimation(.spring(response: 0.2, dampingFraction: 0.3)) {
                    shieldScale = 1.3
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                        shieldScale = 1.0
                    }
                }
            }
            .onAppear {
                displayCount = adBlockEngine.blockedAdsCount
            }
        }
    }
}
