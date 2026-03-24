import SwiftUI

// MARK: - Browser Tab Model
struct BrowserTab: Identifiable {
    let id: UUID
    var url: URL
    var title: String
    var pageTitle: String
    var isSecure: Bool
    var snapshot: UIImage?
    var blockedAdsCount: Int
    var scrollPosition: CGPoint
    var isLoading: Bool
    
    init(
        id: UUID = UUID(),
        url: URL = URL(string: "https://www.google.com")!,
        title: String = "Yeni Sekme",
        pageTitle: String = "Yeni Sekme",
        isSecure: Bool = true,
        snapshot: UIImage? = nil,
        blockedAdsCount: Int = 0,
        scrollPosition: CGPoint = .zero,
        isLoading: Bool = false
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.pageTitle = pageTitle
        self.isSecure = isSecure
        self.snapshot = snapshot
        self.blockedAdsCount = blockedAdsCount
        self.scrollPosition = scrollPosition
        self.isLoading = isLoading
    }
}
