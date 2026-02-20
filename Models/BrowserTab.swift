import SwiftUI

// MARK: - Browser Tab Model
struct BrowserTab: Identifiable {
    let id: UUID
    var url: URL
    var title: String
    var isSecure: Bool
    var snapshot: UIImage?
    var blockedAdsCount: Int
    
    init(
        id: UUID = UUID(),
        url: URL = URL(string: "https://www.google.com")!,
        title: String = "Yeni Sekme",
        isSecure: Bool = true,
        snapshot: UIImage? = nil,
        blockedAdsCount: Int = 0
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.isSecure = isSecure
        self.snapshot = snapshot
        self.blockedAdsCount = blockedAdsCount
    }
}
