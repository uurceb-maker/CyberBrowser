import SwiftUI

// MARK: - Tab Manager Service
class TabManager: ObservableObject {
    @Published var tabs: [BrowserTab] = []
    @Published var activeTabIndex: Int = 0
    @Published var showTabManager: Bool = false
    
    init() {
        // Start with one default tab
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
    
    // MARK: - Tab Operations
    func addTab(url: URL = URL(string: "https://www.google.com")!) {
        let newTab = BrowserTab(url: url, title: "Yeni Sekme")
        tabs.append(newTab)
        activeTabIndex = tabs.count - 1
        showTabManager = false
    }
    
    func closeTab(id: UUID) {
        guard tabs.count > 1 else { return } // Keep at least one tab
        
        if let index = tabs.firstIndex(where: { $0.id == id }) {
            tabs.remove(at: index)
            
            // Adjust active index
            if activeTabIndex >= tabs.count {
                activeTabIndex = tabs.count - 1
            }
        }
    }
    
    func switchTab(id: UUID) {
        if let index = tabs.firstIndex(where: { $0.id == id }) {
            activeTabIndex = index
            showTabManager = false
        }
    }
    
    // Save current page state (URL, title) before switching away
    func saveCurrentTabState(url: URL?, title: String?, isSecure: Bool?) {
        guard activeTabIndex < tabs.count else { return }
        if let url = url {
            tabs[activeTabIndex].url = url
        }
        if let title = title {
            tabs[activeTabIndex].title = title
        }
        if let isSecure = isSecure {
            tabs[activeTabIndex].isSecure = isSecure
        }
    }
    
    func updateActiveTab(title: String? = nil, url: URL? = nil, isSecure: Bool? = nil, snapshot: UIImage? = nil) {
        guard activeTabIndex < tabs.count else { return }
        
        if let title = title {
            tabs[activeTabIndex].title = title
        }
        if let url = url {
            tabs[activeTabIndex].url = url
        }
        if let isSecure = isSecure {
            tabs[activeTabIndex].isSecure = isSecure
        }
        if let snapshot = snapshot {
            tabs[activeTabIndex].snapshot = snapshot
        }
    }
    
    func incrementBlockedAds() {
        guard activeTabIndex < tabs.count else { return }
        tabs[activeTabIndex].blockedAdsCount += 1
    }
}
