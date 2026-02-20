import SwiftUI

// MARK: - Tab Manager View
struct TabManagerView: View {
    @EnvironmentObject var tabManager: TabManager
    @Environment(\.dismiss) var dismiss
    
    // Callbacks for tab selection and new tab
    var onTabSelected: ((URL) -> Void)?
    var onNewTab: ((URL) -> Void)?
    
    let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        ZStack {
            // Background
            Color.cyberBlack.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Sekmeler")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.cyberWhite)
                    
                    Spacer()
                    
                    // Tab count
                    Text("\(tabManager.tabs.count)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.cyberYellow)
                        .cornerRadius(12)
                    
                    Spacer().frame(width: 12)
                    
                    // Done button
                    Button("Tamam") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.cyberYellow)
                }
                .padding(.horizontal, CyberTheme.padding)
                .padding(.top, 20)
                .padding(.bottom, 16)
                
                // Tab Grid
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(tabManager.tabs) { tab in
                            TabCard(
                                tab: tab,
                                isActive: tab.id == tabManager.activeTab.id,
                                onTap: {
                                    tabManager.switchTab(id: tab.id)
                                    onTabSelected?(tab.url)
                                    dismiss()
                                },
                                onClose: {
                                    withAnimation(.spring(response: 0.3)) {
                                        tabManager.closeTab(id: tab.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, CyberTheme.padding)
                    .padding(.bottom, 100)
                }
                
                Spacer()
            }
            
            // New Tab FAB
            VStack {
                Spacer()
                
                Button(action: {
                    let newTabURL = URL(string: "https://www.google.com")!
                    tabManager.addTab(url: newTabURL)
                    onNewTab?(newTabURL)
                    dismiss()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                        Text("Yeni Sekme")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(Color.cyberYellow)
                            .shadow(color: .cyberYellow.opacity(0.4), radius: 15, y: 5)
                    )
                }
                .padding(.bottom, 30)
            }
        }
    }
}

// MARK: - Tab Card
struct TabCard: View {
    let tab: BrowserTab
    let isActive: Bool
    let onTap: () -> Void
    let onClose: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Snapshot preview
                ZStack {
                    if let snapshot = tab.snapshot {
                        Image(uiImage: snapshot)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 140)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.cyberSurface, Color.cyberBlack],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: 140)
                            .overlay(
                                Image(systemName: "globe")
                                    .font(.system(size: 30))
                                    .foregroundColor(.cyberMuted)
                            )
                    }
                    
                    // Close button overlay
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: onClose) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.cyberWhite)
                                    .padding(6)
                                    .background(
                                        Circle()
                                            .fill(Color.black.opacity(0.7))
                                    )
                            }
                            .padding(6)
                        }
                        Spacer()
                    }
                    
                    // Ad blocked badge
                    if tab.blockedAdsCount > 0 {
                        VStack {
                            Spacer()
                            HStack {
                                HStack(spacing: 3) {
                                    Image(systemName: "shield.checkered")
                                        .font(.system(size: 9))
                                    Text("\(tab.blockedAdsCount)")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                }
                                .foregroundColor(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.cyberYellow)
                                .cornerRadius(4)
                                .padding(6)
                                
                                Spacer()
                            }
                        }
                    }
                }
                .frame(height: 140)
                
                // Title bar
                HStack(spacing: 6) {
                    // Security indicator
                    Image(systemName: tab.isSecure ? "lock.fill" : "lock.open.fill")
                        .font(.system(size: 10))
                        .foregroundColor(tab.isSecure ? .cyberGreen : .cyberRed)
                    
                    Text(tab.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.cyberWhite)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.cyberSurface)
            }
            .cornerRadius(CyberTheme.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: CyberTheme.cornerRadius)
                    .stroke(
                        isActive ? Color.cyberYellow : Color.cyberYellow.opacity(0.15),
                        lineWidth: isActive ? 2 : 0.5
                    )
            )
            .shadow(
                color: isActive ? .cyberYellow.opacity(0.2) : .clear,
                radius: 8
            )
        }
        .buttonStyle(.plain)
    }
}
