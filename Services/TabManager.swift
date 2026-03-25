import SwiftUI
import WebKit

// MARK: - Tab Manager Service
@MainActor
final class TabManager: ObservableObject {
    @Published var tabs: [BrowserTab] = []
    @Published var activeTabIndex: Int = 0
    @Published var showTabManager: Bool = false

    init() {
        tabs = [BrowserTab()]
    }

    // MARK: - Active Tab
    var activeTab: BrowserTab {
        get {
            guard !tabs.isEmpty, activeTabIndex < tabs.count else {
                return BrowserTab()
            }
            return tabs[activeTabIndex]
        }
        set {
            guard activeTabIndex < tabs.count else { return }
            tabs[activeTabIndex] = newValue
        }
    }

    var activeTabURL: URL {
        get { activeTab.url }
        set {
            guard activeTabIndex < tabs.count else { return }
            tabs[activeTabIndex].url = newValue
        }
    }

    var regularTabs: [BrowserTab] {
        tabs.filter { !$0.isPrivate }
    }

    var privateTabs: [BrowserTab] {
        tabs.filter(\.isPrivate)
    }

    // MARK: - Tab Operations
    func addTab(url: URL = URL(string: "https://www.google.com")!, isPrivate: Bool = false) {
        let newTab = BrowserTab(
            url: url,
            title: isPrivate ? "Gizli Sekme" : "Yeni Sekme",
            pageTitle: isPrivate ? "Gizli Sekme" : "Yeni Sekme",
            isPrivate: isPrivate
        )
        tabs.append(newTab)
        activeTabIndex = tabs.count - 1
        showTabManager = false
        AudioSessionManager.shared.configureForBrowserPlayback()
    }

    func openPrivateTab(url: URL? = nil) {
        addTab(url: url ?? URL(string: "https://www.google.com")!, isPrivate: true)
    }

    func convertActiveTabToPrivate() {
        guard activeTabIndex < tabs.count else { return }
        let current = tabs[activeTabIndex]
        tabs[activeTabIndex] = BrowserTab(
            id: current.id,
            url: current.url,
            title: current.title.isEmpty ? "Gizli Sekme" : current.title,
            pageTitle: current.pageTitle.isEmpty ? "Gizli Sekme" : current.pageTitle,
            isSecure: current.isSecure,
            snapshot: current.snapshot,
            blockedAdsCount: current.blockedAdsCount,
            scrollPosition: current.scrollPosition,
            isLoading: current.isLoading,
            isPrivate: true
        )
    }

    func closeTab(id: UUID) {
        guard tabs.count > 1 else { return }

        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closingTab = tabs[index]

        if closingTab.isPrivate {
            clearPrivateDataStore()
        }

        tabs.remove(at: index)

        if activeTabIndex >= tabs.count {
            activeTabIndex = max(tabs.count - 1, 0)
        } else if index < activeTabIndex {
            activeTabIndex -= 1
        }
    }

    func switchTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        let previousTab = activeTab
        withAnimation(.easeInOut(duration: 0.2)) {
            activeTabIndex = index
        }
        showTabManager = false

        trimMemoryCache(for: previousTab)
        AudioSessionManager.shared.configureForBrowserPlayback()
    }

    // Save current page state (URL, title) before switching away
    func saveCurrentTabState(
        url: URL?,
        title: String?,
        isSecure: Bool?,
        scrollPosition: CGPoint? = nil,
        isLoading: Bool? = nil
    ) {
        guard activeTabIndex < tabs.count else { return }
        if let url {
            tabs[activeTabIndex].url = url
        }
        if let title {
            tabs[activeTabIndex].title = title
            tabs[activeTabIndex].pageTitle = title
        }
        if let isSecure {
            tabs[activeTabIndex].isSecure = isSecure
        }
        if let scrollPosition {
            tabs[activeTabIndex].scrollPosition = scrollPosition
        }
        if let isLoading {
            tabs[activeTabIndex].isLoading = isLoading
        }
    }

    func updateActiveTab(
        title: String? = nil,
        url: URL? = nil,
        isSecure: Bool? = nil,
        snapshot: UIImage? = nil,
        scrollPosition: CGPoint? = nil,
        isLoading: Bool? = nil
    ) {
        updateTab(
            at: activeTabIndex,
            title: title,
            url: url,
            isSecure: isSecure,
            snapshot: snapshot,
            scrollPosition: scrollPosition,
            isLoading: isLoading
        )
    }

    func updateTab(
        at index: Int,
        title: String? = nil,
        url: URL? = nil,
        isSecure: Bool? = nil,
        snapshot: UIImage? = nil,
        scrollPosition: CGPoint? = nil,
        isLoading: Bool? = nil
    ) {
        guard index >= 0, index < tabs.count else { return }

        if let title {
            tabs[index].title = title
            tabs[index].pageTitle = title
        }
        if let url {
            tabs[index].url = url
        }
        if let isSecure {
            tabs[index].isSecure = isSecure
        }
        if let snapshot {
            tabs[index].snapshot = snapshot
        }
        if let scrollPosition {
            tabs[index].scrollPosition = scrollPosition
        }
        if let isLoading {
            tabs[index].isLoading = isLoading
        }
    }

    func incrementBlockedAds() {
        guard activeTabIndex < tabs.count else { return }
        tabs[activeTabIndex].blockedAdsCount += 1
    }

    private func clearPrivateDataStore() {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.nonPersistent().removeData(ofTypes: types, modifiedSince: .distantPast) {}
    }

    private func trimMemoryCache(for tab: BrowserTab) {
        let dataStore: WKWebsiteDataStore = tab.isPrivate ? .nonPersistent() : .default()
        dataStore.removeData(
            ofTypes: [WKWebsiteDataTypeMemoryCache],
            modifiedSince: Date(timeIntervalSinceNow: -300)
        ) {}
    }
}
