import SwiftUI

// MARK: - Tab Manager View
@MainActor
struct TabManagerView: View {
    @EnvironmentObject var tabManager: TabManager
    @Environment(\.dismiss) private var dismiss

    var onTabSelected: ((URL) -> Void)?
    var onNewTab: ((URL) -> Void)?

    @State private var searchText = ""

    private var filteredRegularTabs: [BrowserTab] {
        filterTabs(tabManager.regularTabs)
    }

    private var filteredPrivateTabs: [BrowserTab] {
        filterTabs(tabManager.privateTabs)
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

                        Button("Tamam") {
                            dismiss()
                        }
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

                        Button {
                            let newTabURL = URL(string: "https://www.google.com")!
                            tabManager.openPrivateTab(url: newTabURL)
                            onNewTab?(newTabURL)
                            dismiss()
                        } label: {
                            Image(systemName: "moon.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.12), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 20)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            if !filteredRegularTabs.isEmpty {
                                TabSectionHeader(title: "Sekmeler", systemImage: "square.stack.3d.up")

                                ForEach(filteredRegularTabs) { tab in
                                    tabRow(for: tab)
                                }
                            }

                            if !filteredPrivateTabs.isEmpty {
                                TabSectionHeader(title: "Gizli Sekmeler", systemImage: "lock.fill")

                                ForEach(filteredPrivateTabs) { tab in
                                    tabRow(for: tab)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func filterTabs(_ tabs: [BrowserTab]) -> [BrowserTab] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return tabs }
        return tabs.filter { tab in
            tab.title.lowercased().contains(query) || tab.url.absoluteString.lowercased().contains(query)
        }
    }

    @ViewBuilder
    private func tabRow(for tab: BrowserTab) -> some View {
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

struct TabSectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.cyberYellow)

            Text(title)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.cyberYellow)
                .tracking(1.2)
        }
        .padding(.horizontal, 4)
    }
}

struct TabRow: View {
    let tab: BrowserTab
    let isActive: Bool
    let canClose: Bool
    let onTap: () -> Void
    let onClose: () -> Void

    private let privateTint = Color(red: 0.52, green: 0.48, blue: 0.92)

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
                                colors: tab.isPrivate
                                    ? [privateTint.opacity(0.45), Color.cyberBlack.opacity(0.95)]
                                    : [Color.cyberSurface.opacity(0.8), Color.cyberBlack.opacity(0.9)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .overlay(
                                Image(systemName: tab.isPrivate ? "lock.fill" : "globe")
                                    .foregroundColor(tab.isPrivate ? privateTint : .cyberMuted)
                            )
                        }
                    }
                    .frame(width: 58, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.isPrivate ? "lock.fill" : (tab.isSecure ? "lock.shield.fill" : "lock.open.fill"))
                                .font(.system(size: 10))
                                .foregroundColor(tab.isPrivate ? privateTint : (tab.isSecure ? .cyberGreen : .cyberRed))

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
                        } else if tab.isPrivate {
                            Text("Gizli oturum")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(privateTint)
                        }
                    }

                    Spacer()

                    Image(systemName: tab.isPrivate ? "lock.circle.fill" : "chevron.right")
                        .font(.system(size: tab.isPrivate ? 18 : 12, weight: .semibold))
                        .foregroundColor(tab.isPrivate ? privateTint : .cyberMuted)
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
                .stroke(
                    isActive
                        ? (tab.isPrivate ? privateTint.opacity(0.9) : Color.cyberYellow.opacity(0.85))
                        : (tab.isPrivate ? privateTint.opacity(0.35) : Color.cyberYellow.opacity(0.2)),
                    lineWidth: isActive ? 1.2 : 0.8
                )
        )
        .shadow(color: isActive ? (tab.isPrivate ? privateTint.opacity(0.18) : Color.cyberYellow.opacity(0.15)) : .clear, radius: 10, x: 0, y: 4)
    }
}
