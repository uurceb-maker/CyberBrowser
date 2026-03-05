import SwiftUI

@main
struct CyberBrowserApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    @AppStorage("ageGateConfirmed") private var ageGateConfirmed = false

    @StateObject private var tabManager = TabManager()
    @StateObject private var adBlockEngine = AdBlockEngine()
    @StateObject private var extensionManager = ExtensionManager()
    @StateObject private var proxyManager = ProxyManager()
    
    init() {
        // Configure background audio session
        AudioSessionManager.shared.configureBackgroundAudio()
        
        // Apply global appearance
        UINavigationBar.appearance().barTintColor = UIColor.black
        UINavigationBar.appearance().tintColor = UIColor(hex: "#22D3EE")
        UINavigationBar.appearance().titleTextAttributes = [
            .foregroundColor: UIColor.white
        ]
        UITabBar.appearance().barTintColor = UIColor.black
        UITabBar.appearance().tintColor = UIColor(hex: "#22D3EE")
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if onboardingCompleted && ageGateConfirmed {
                    ContentView()
                        .environmentObject(tabManager)
                        .environmentObject(adBlockEngine)
                        .environmentObject(extensionManager)
                        .environmentObject(proxyManager)
                } else {
                    OnboardingView()
                }
            }
            .preferredColorScheme(.dark)
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    proxyManager.handleAppDidBecomeActive()
                case .inactive, .background:
                    proxyManager.handleAppWillResignActive()
                @unknown default:
                    break
                }
            }
        }
    }
}
