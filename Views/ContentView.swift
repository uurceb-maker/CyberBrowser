import SwiftUI

// MARK: - Main Content View
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var adBlockEngine: AdBlockEngine
    @EnvironmentObject var extensionManager: ExtensionManager
    @EnvironmentObject var proxyManager: ProxyManager

    @StateObject private var webViewStore = WebViewStore()
    @StateObject private var aiAssistant = AIAssistant()

    @State private var showMenu = false
    @State private var showTabManager = false
    @State private var displayURL = "https://www.google.com"
    @State private var isInitialized = false
    @State private var isAddressBarFocused = false
    @State private var keyboardHeight: CGFloat = 0

    private let privateBackground = Color(red: 0.10, green: 0.10, blue: 0.18)

    var body: some View {
        GeometryReader { proxy in
            let safeTop = max(proxy.safeAreaInsets.top, 8)
            let topBarVisible = webViewStore.isTopBarVisible || isAddressBarFocused

            ZStack {
                (tabManager.activeTab.isPrivate ? privateBackground : Color.black)
                    .ignoresSafeArea()

                WebViewContainer(store: webViewStore)
                    .id(webViewStore.webViewID)
                    .ignoresSafeArea()
                    .padding(.bottom, keyboardHeight > 0 ? max(keyboardHeight - proxy.safeAreaInsets.bottom, 0) : 0)
                    .background(tabManager.activeTab.isPrivate ? privateBackground : Color.clear)

                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color.black.opacity(0.28), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 88 + safeTop)
                    .allowsHitTesting(false)

                    Spacer()

                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.35)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 128 + max(proxy.safeAreaInsets.bottom, 10))
                    .allowsHitTesting(false)
                }
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    AddressBar(
                        urlString: $displayURL,
                        isSecure: $webViewStore.isSecure,
                        isLoading: $webViewStore.isLoading,
                        loadingProgress: $webViewStore.estimatedProgress,
                        proxyConnected: proxyManager.isConnected && proxyManager.selectedProtocol != .direct,
                        isPrivateMode: tabManager.activeTab.isPrivate,
                        onFocusChange: { focused in
                            isAddressBarFocused = focused
                            webViewStore.setAddressBarFocused(focused)
                        },
                        onCommit: { input in
                            webViewStore.loadURLString(input)
                        }
                    )
                    .padding(.top, safeTop)
                    .offset(y: topBarVisible ? 0 : -(safeTop + 96))
                    .opacity(topBarVisible ? 1 : 0.01)
                    .allowsHitTesting(topBarVisible)

                    Spacer(minLength: 0)

                    BottomNavBar(
                        canGoBack: webViewStore.canGoBack,
                        canGoForward: webViewStore.canGoForward,
                        isLoading: webViewStore.isLoading,
                        tabCount: tabManager.tabs.count,
                        isPrivateTab: tabManager.activeTab.isPrivate,
                        onBack: { webViewStore.goBack() },
                        onForward: { webViewStore.goForward() },
                        onHome: { webViewStore.goHome() },
                        onReloadOrStop: {
                            webViewStore.isLoading ? webViewStore.stopLoading() : webViewStore.reload()
                        },
                        onAddressFocus: {
                            isAddressBarFocused = true
                            webViewStore.setAddressBarFocused(true)
                            webViewStore.showTopBar()
                            NotificationCenter.default.post(name: .focusAddressBar, object: nil)
                        },
                        onTabs: {
                            if let url = webViewStore.webView.url {
                                tabManager.updateActiveTab(
                                    title: webViewStore.pageTitle,
                                    url: url,
                                    isSecure: webViewStore.isSecure,
                                    scrollPosition: webViewStore.currentScrollPosition,
                                    isLoading: webViewStore.isLoading
                                )
                            }
                            showTabManager = true
                        },
                        onMenu: { showMenu = true },
                        onPrivateTab: {
                            tabManager.openPrivateTab()
                            webViewStore.activate(tab: tabManager.activeTab)
                            displayURL = tabManager.activeTab.url.absoluteString
                        },
                        onConvertToPrivate: {
                            if let currentURL = webViewStore.webView.url {
                                tabManager.updateActiveTab(
                                    title: webViewStore.pageTitle,
                                    url: currentURL,
                                    isSecure: webViewStore.isSecure,
                                    scrollPosition: webViewStore.currentScrollPosition,
                                    isLoading: webViewStore.isLoading
                                )
                            }
                            tabManager.convertActiveTabToPrivate()
                            webViewStore.activate(tab: tabManager.activeTab)
                        }
                    )
                    .opacity(isAddressBarFocused ? 0 : 1)
                    .offset(y: isAddressBarFocused ? 60 : 0)
                    .allowsHitTesting(!isAddressBarFocused)
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .animation(.spring(response: 0.28, dampingFraction: 0.88), value: topBarVisible)
                .animation(.easeOut(duration: 0.25), value: isAddressBarFocused)

                if let message = webViewStore.transientMessage {
                    VStack {
                        Spacer()

                        Text(message)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.82), in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                            )
                            .padding(.bottom, 108 + max(proxy.safeAreaInsets.bottom, 10))
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
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

            if proxyManager.selectedProtocol != .direct && !proxyManager.isConnected {
                proxyManager.startProxy()
            }

            webViewStore.compileAdBlockRules {
                webViewStore.injectScripts()
                webViewStore.activate(tab: tabManager.activeTab)
                displayURL = tabManager.activeTab.url.absoluteString
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            guard
                let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            else {
                return
            }

            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = frame.height
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = 0
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            webViewStore.handleScenePhase(newPhase)
        }
        .onChange(of: webViewStore.currentURLString) { _, newURL in
            displayURL = newURL
        }
        .onChange(of: tabManager.activeTabIndex) { oldIndex, _ in
            tabManager.updateTab(
                at: oldIndex,
                title: webViewStore.pageTitle,
                url: webViewStore.webView.url,
                isSecure: webViewStore.isSecure,
                scrollPosition: webViewStore.currentScrollPosition,
                isLoading: webViewStore.isLoading
            )
            let tab = tabManager.activeTab
            webViewStore.activate(tab: tab)
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
            webViewStore.applyProxyConfiguration(reload: true)
        }
        .onChange(of: proxyManager.isConnected) { _, _ in
            guard isInitialized else { return }
            webViewStore.applyProxyConfiguration(reload: true)
        }
        .fullScreenCover(isPresented: $showTabManager) {
            TabManagerView(
                onTabSelected: { url in
                    displayURL = url.absoluteString
                },
                onNewTab: { url in
                    displayURL = url.absoluteString
                }
            )
            .environmentObject(tabManager)
        }
        .sheet(isPresented: $showMenu) {
            MenuView(aiAssistant: aiAssistant, webView: webViewStore.webView)
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
