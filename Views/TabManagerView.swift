import SwiftUI

// MARK: - Tab Manager View
struct TabManagerView: View {
    @EnvironmentObject var tabManager: TabManager
    @Environment(\.dismiss) var dismiss

    var onTabSelected: ((URL) -> Void)?
    var onNewTab: ((URL) -> Void)?

    @State private var searchText: String = ""

    private var filteredTabs: [BrowserTab] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return tabManager.tabs }
        return tabManager.tabs.filter { tab in
            tab.title.lowercased().contains(query) || tab.url.absoluteString.lowercased().contains(query)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let safeTop = max(proxy.safeAreaInsets.top, 14)

            ZStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.9), Color.cyberBlack.opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 12) {
                    HStack {
                        Text("Sekmeler")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.cyberWhite)

                        Spacer()

                        Button("Tamam") { dismiss() }
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.cyberYellow)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, safeTop)

                    HStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.cyberMuted)
                            TextField("Sekmelerde ara...", text: $searchText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundColor(.cyberWhite)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(
                            Capsule().stroke(Color.cyberYellow.opacity(0.2), lineWidth: 0.8)
                        )

                        Button {
                            let newTabURL = URL(string: "https://www.google.com")!
                            tabManager.addTab(url: newTabURL)
                            onNewTab?(newTabURL)
                            dismiss()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                Text("Yeni")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.cyberYellow, in: Capsule())
                        }
                    }
                    .padding(.horizontal, 20)

                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredTabs) { tab in
                                TabRow(
                                    tab: tab,
                                    isActive: tab.id == tabManager.activeTab.id,
                                    canClose: tabManager.tabs.count > 1,
                                    onTap: {
                                        tabManager.switchTab(id: tab.id)
                                        onTabSelected?(tab.url)
                                        dismiss()
                                    },
                                    onClose: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            tabManager.closeTab(id: tab.id)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
}

struct TabRow: View {
    let tab: BrowserTab
    let isActive: Bool
    let canClose: Bool
    let onTap: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Group {
                        if let snapshot = tab.snapshot {
                            Image(uiImage: snapshot)
                                .resizable()
                                .scaledToFill()
                        } else {
                            LinearGradient(
                                colors: [Color.cyberSurface.opacity(0.8), Color.cyberBlack.opacity(0.9)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .overlay(
                                Image(systemName: "globe")
                                    .foregroundColor(.cyberMuted)
                            )
                        }
                    }
                    .frame(width: 58, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.isSecure ? "lock.shield.fill" : "lock.open.fill")
                                .font(.system(size: 10))
                                .foregroundColor(tab.isSecure ? .cyberGreen : .cyberRed)

                            Text(tab.title)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(.cyberWhite)
                                .lineLimit(1)
                        }

                        Text(tab.url.host ?? tab.url.absoluteString)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.cyberMuted)
                            .lineLimit(1)

                        if tab.blockedAdsCount > 0 {
                            Text("\(tab.blockedAdsCount) reklam engellendi")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.cyberYellow)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.cyberMuted)
                }
            }
            .buttonStyle(.plain)

            if canClose {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.cyberMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            .thinMaterial,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isActive ? Color.cyberYellow.opacity(0.85) : Color.cyberYellow.opacity(0.2), lineWidth: isActive ? 1.2 : 0.8)
        )
        .shadow(color: isActive ? Color.cyberYellow.opacity(0.15) : .clear, radius: 10, x: 0, y: 4)
    }
}
