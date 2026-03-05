import SwiftUI

// MARK: - Main Content View
struct ContentView: View {
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var adBlockEngine: AdBlockEngine
    @EnvironmentObject var extensionManager: ExtensionManager
    @EnvironmentObject var proxyManager: ProxyManager
    
    @StateObject private var webViewStore = WebViewStore()
    @StateObject private var aiAssistant = AIAssistant()
    
    @State private var showMenu: Bool = false
    @State private var showTabManager: Bool = false
    @State private var displayURL: String = "https://www.google.com"
    @State private var isInitialized: Bool = false
    
    var body: some View {
        ZStack {
            WebViewContainer(store: webViewStore)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(0.28), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 88)
                .allowsHitTesting(false)

                Spacer()

                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.35)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 128)
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                AddressBar(
                    urlString: $displayURL,
                    isSecure: $webViewStore.isSecure,
                    isLoading: $webViewStore.isLoading,
                    proxyConnected: proxyManager.isConnected && proxyManager.selectedProtocol != .direct,
                    onCommit: { input in
                        webViewStore.loadURLString(input)
                    }
                )

                Spacer(minLength: 0)

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

            AIOverlayView(assistant: aiAssistant, webView: webViewStore.webView)
                .padding(.trailing, 18)
                .padding(.bottom, 104)
        }
        .background(.clear)
        .statusBarHidden(false)
        .onAppear {
            guard !isInitialized else { return }
            isInitialized = true
            
            webViewStore.adBlockEngine = adBlockEngine
            webViewStore.tabManager = tabManager
            webViewStore.extensionManager = extensionManager
            webViewStore.proxyManager = proxyManager
            
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
        .onChange(of: proxyManager.selectedProtocol) { _, _ in
            guard isInitialized else { return }
            webViewStore.reconnectWithProxy()
        }
        .onChange(of: proxyManager.isConnected) { _, _ in
            guard isInitialized else { return }
            webViewStore.reconnectWithProxy()
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
                .environmentObject(proxyManager)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .environmentObject(TabManager())
        .environmentObject(AdBlockEngine())
        .environmentObject(ExtensionManager())
        .environmentObject(ProxyManager())
}
