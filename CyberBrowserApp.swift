import SwiftUI

@main
struct CyberBrowserApp: App {
    @StateObject private var tabManager = TabManager()
    @StateObject private var adBlockEngine = AdBlockEngine()
    @StateObject private var extensionManager = ExtensionManager()
    
    init() {
        // Configure background audio session
        AudioSessionManager.shared.configureBackgroundAudio()
        
        // Apply global appearance
        UINavigationBar.appearance().barTintColor = UIColor.black
        UINavigationBar.appearance().tintColor = UIColor(hex: "#FACC15")
        UINavigationBar.appearance().titleTextAttributes = [
            .foregroundColor: UIColor.white
        ]
        UITabBar.appearance().barTintColor = UIColor.black
        UITabBar.appearance().tintColor = UIColor(hex: "#FACC15")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tabManager)
                .environmentObject(adBlockEngine)
                .environmentObject(extensionManager)
                .preferredColorScheme(.dark)
        }
    }
}
