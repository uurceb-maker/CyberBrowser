import SwiftUI

// MARK: - Main Content View
struct ContentView: View {
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var adBlockEngine: AdBlockEngine
    @EnvironmentObject var extensionManager: ExtensionManager
    
    // WebView state
    @State private var currentURL: URL = URL(string: "https://www.google.com")!
    @State private var urlString: String = "https://www.google.com"
    @State private var canGoBack: Bool = false
    @State private var canGoForward: Bool = false
    @State private var isLoading: Bool = false
    @State private var pageTitle: String = "Yeni Sekme"
    @State private var isSecure: Bool = true
    
    // Navigation triggers
    @State private var triggerGoBack: Bool = false
    @State private var triggerGoForward: Bool = false
    @State private var triggerReload: Bool = false
    
    // UI state
    @State private var showMenu: Bool = false
    @State private var showTabManager: Bool = false
    @State private var addressBarFocused: Bool = false
    
    var body: some View {
        ZStack {
            // Full black background
            Color.cyberBlack.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // MARK: - Ad Block Banner (Top)
                AdBlockBanner()
                    .zIndex(1)
                
                // MARK: - Address Bar
                AddressBar(
                    urlString: $urlString,
                    isSecure: $isSecure,
                    isLoading: $isLoading,
                    onCommit: { input in
                        navigateTo(input)
                    }
                )
                
                // Loading progress bar
                if isLoading {
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.cyberYellow.opacity(0.3),
                                        Color.cyberYellow,
                                        Color.cyberYellow.opacity(0.3)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 2)
                            .frame(width: geometry.size.width * 0.6)
                            .offset(x: isLoading ? geometry.size.width * 0.4 : -geometry.size.width * 0.6)
                            .animation(
                                .linear(duration: 1.5).repeatForever(autoreverses: false),
                                value: isLoading
                            )
                    }
                    .frame(height: 2)
                }
                
                // MARK: - Web View
                WebView(
                    url: $currentURL,
                    canGoBack: $canGoBack,
                    canGoForward: $canGoForward,
                    isLoading: $isLoading,
                    pageTitle: $pageTitle,
                    isSecure: $isSecure,
                    goBack: triggerGoBack,
                    goForward: triggerGoForward,
                    reload: triggerReload
                )
                .environmentObject(adBlockEngine)
                .environmentObject(tabManager)
                .environmentObject(extensionManager)
                
                // MARK: - Bottom Navigation Bar
                BottomNavBar(
                    canGoBack: canGoBack,
                    canGoForward: canGoForward,
                    tabCount: tabManager.tabs.count,
                    onBack: {
                        triggerGoBack = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            triggerGoBack = false
                        }
                    },
                    onForward: {
                        triggerGoForward = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            triggerGoForward = false
                        }
                    },
                    onSearch: {
                        addressBarFocused = true
                    },
                    onTabs: {
                        showTabManager = true
                    },
                    onMenu: {
                        showMenu = true
                    }
                )
            }
        }
        .statusBarHidden(false)
        .onChange(of: currentURL) { newURL in
            urlString = newURL.absoluteString
        }
        .fullScreenCover(isPresented: $showTabManager) {
            TabManagerView()
                .environmentObject(tabManager)
        }
        .sheet(isPresented: $showMenu) {
            MenuView()
                .environmentObject(adBlockEngine)
                .environmentObject(extensionManager)
                .environmentObject(tabManager)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
        }
    }
    
    // MARK: - Navigation Logic
    private func navigateTo(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else { return }
        
        // Check if it's a URL
        if trimmed.contains(".") && !trimmed.contains(" ") {
            // Looks like a URL
            var urlStr = trimmed
            if !urlStr.hasPrefix("http://") && !urlStr.hasPrefix("https://") {
                urlStr = "https://" + urlStr
            }
            if let url = URL(string: urlStr) {
                currentURL = url
                urlString = url.absoluteString
                return
            }
        }
        
        // Treat as search query
        let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        if let searchURL = URL(string: "https://www.google.com/search?q=\(query)") {
            currentURL = searchURL
            urlString = searchURL.absoluteString
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .environmentObject(TabManager())
        .environmentObject(AdBlockEngine())
        .environmentObject(ExtensionManager())
}
