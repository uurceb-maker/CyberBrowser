import SwiftUI

// MARK: - Main Content View
struct ContentView: View {
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var adBlockEngine: AdBlockEngine
    @EnvironmentObject var extensionManager: ExtensionManager
    
    @StateObject private var webViewStore = WebViewStore()
    
    @State private var showMenu: Bool = false
    @State private var showTabManager: Bool = false
    @State private var showShareSheet: Bool = false
    @State private var displayURL: String = "https://www.google.com"
    @State private var isInitialized: Bool = false
    
    var body: some View {
        ZStack {
            Color.cyberBlack.ignoresSafeArea()
            
            VStack(spacing: 0) {
                AdBlockBanner()
                    .zIndex(1)
                
                AddressBar(
                    urlString: $displayURL,
                    isSecure: $webViewStore.isSecure,
                    isLoading: $webViewStore.isLoading,
                    onCommit: { input in
                        webViewStore.loadURLString(input)
                    }
                )
                
                quickAccessBar
                
                if webViewStore.isLoading {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(.cyberYellow)
                        .frame(height: 2)
                        .padding(.horizontal, CyberTheme.padding)
                }
                
                WebViewContainer(store: webViewStore)
                
                BottomNavBar(
                    canGoBack: webViewStore.canGoBack,
                    canGoForward: webViewStore.canGoForward,
                    isLoading: webViewStore.isLoading,
                    tabCount: tabManager.tabs.count,
                    onBack: { webViewStore.goBack() },
                    onForward: { webViewStore.goForward() },
                    onHome: { webViewStore.goHome() },
                    onReloadOrStop: {
                        webViewStore.isLoading ? webViewStore.stopLoading() : webViewStore.reload()
                    },
                    onAddressFocus: {
                        NotificationCenter.default.post(name: .focusAddressBar, object: nil)
                    },
                    onTabs: {
                        if let url = webViewStore.webView.url {
                            tabManager.updateActiveTab(
                                title: webViewStore.pageTitle,
                                url: url,
                                isSecure: webViewStore.isSecure
                            )
                        }
                        showTabManager = true
                    },
                    onMenu: { showMenu = true }
                )
            }
        }
        .statusBarHidden(false)
        .onAppear {
            guard !isInitialized else { return }
            isInitialized = true
            
            webViewStore.adBlockEngine = adBlockEngine
            webViewStore.tabManager = tabManager
            webViewStore.extensionManager = extensionManager
            
            webViewStore.compileAdBlockRules {
                webViewStore.injectScripts()
                webViewStore.loadURL(tabManager.activeTab.url)
            }
        }
        .onChange(of: webViewStore.currentURLString) { _, newURL in
            displayURL = newURL
        }
        .onChange(of: tabManager.activeTabIndex) { _, _ in
            let tab = tabManager.activeTab
            webViewStore.loadURL(tab.url)
            displayURL = tab.url.absoluteString
        }
        .onChange(of: adBlockEngine.isEnabled) { _, _ in
            if adBlockEngine.needsRecompile {
                webViewStore.compileAdBlockRules {
                    webViewStore.injectScripts()
                    webViewStore.reload()
                }
            }
        }
        .fullScreenCover(isPresented: $showTabManager) {
            TabManagerView(
                onTabSelected: { url in
                    webViewStore.loadURL(url)
                    displayURL = url.absoluteString
                },
                onNewTab: { url in
                    webViewStore.loadURL(url)
                    displayURL = url.absoluteString
                }
            )
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
        .sheet(isPresented: $showShareSheet) {
            if let current = URL(string: webViewStore.currentURLString) {
                ActivityView(items: [current])
            } else {
                ActivityView(items: [webViewStore.currentURLString])
            }
        }
    }
    
    private var quickAccessBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                QuickActionChip(title: "Google", icon: "magnifyingglass") {
                    webViewStore.loadURLString("https://www.google.com")
                }
                QuickActionChip(title: "YouTube", icon: "play.rectangle.fill") {
                    webViewStore.loadURLString("https://www.youtube.com")
                }
                QuickActionChip(title: "X", icon: "bubble.left.and.bubble.right.fill") {
                    webViewStore.loadURLString("https://x.com")
                }
                QuickActionChip(title: "Dizipal", icon: "tv.fill") {
                    webViewStore.loadURLString("https://dizipal1541.com/")
                }
                QuickActionChip(title: "Paylas", icon: "square.and.arrow.up.fill") {
                    showShareSheet = true
                }
            }
            .padding(.horizontal, CyberTheme.padding)
            .padding(.bottom, 6)
        }
    }
}

struct QuickActionChip: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.cyberWhite)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.cyberSurface)
            .overlay(
                Capsule()
                    .stroke(Color.cyberYellow.opacity(0.25), lineWidth: 0.8)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(CyberButtonStyle())
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview
#Preview {
    ContentView()
        .environmentObject(TabManager())
        .environmentObject(AdBlockEngine())
        .environmentObject(ExtensionManager())
}
