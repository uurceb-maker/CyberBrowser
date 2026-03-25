import SwiftUI
import WebKit

// MARK: - Menu View
struct MenuView: View {
    enum AITool: String, Identifiable {
        case summary
        case translation

        var id: String { rawValue }

        var title: String {
            switch self {
            case .summary:
                return "Sayfayi Ozetle"
            case .translation:
                return "Metni Cevir"
            }
        }
    }

    enum TranslationLanguage: String, CaseIterable, Identifiable {
        case tr, en, de, fr, es

        var id: String { rawValue }

        var title: String {
            rawValue.uppercased()
        }
    }

    @EnvironmentObject var adBlockEngine: AdBlockEngine
    @EnvironmentObject var extensionManager: ExtensionManager
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var proxyManager: ProxyManager
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var aiAssistant: AIAssistant
    let webView: WKWebView?

    @State private var showExtensions = false
    @State private var showInlineProxySettings = false
    @State private var showProxySettingsSheet = false
    @State private var showClearConfirm = false
    @State private var activeAITool: AITool?
    @State private var aiResultText = ""
    @State private var translationLanguage: TranslationLanguage = .tr

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.9), Color.cyberBlack.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.cyberMuted)
                    .frame(width: 40, height: 5)
                    .padding(.top, 10)

                HStack {
                    Text("Menu")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.cyberWhite)

                    Spacer()

                    Button("Kapat") {
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.cyberYellow)
                }
                .padding(.horizontal, CyberTheme.padding)
                .padding(.top, 16)
                .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 12) {
                        VStack(spacing: 0) {
                            SectionHeader(title: "ARACLAR")

                            MenuActionRow(
                                icon: "doc.text",
                                iconColor: .cyberYellow,
                                title: "Sayfayi Ozetle",
                                subtitle: "Aktif sayfanin icerigini kisa ozetler",
                                isLoading: aiAssistant.isProcessing && activeAITool == .summary
                            ) {
                                activeAITool = .summary
                                aiResultText = ""
                                Task { @MainActor in
                                    await summarizePage()
                                }
                            }

                            Divider().background(Color.cyberDivider)

                            MenuActionRow(
                                icon: "character.book.closed",
                                iconColor: .cyberYellow,
                                title: "Metni Cevir",
                                subtitle: "Secili metni istedigin dile cevirir",
                                isLoading: aiAssistant.isProcessing && activeAITool == .translation
                            ) {
                                activeAITool = .translation
                                aiResultText = ""
                            }
                        }
                        .cyberCard()

                        VStack(spacing: 0) {
                            SectionHeader(title: "GUVENLIK")

                            MenuToggleRow(
                                icon: "shield.checkered",
                                iconColor: .cyberYellow,
                                title: "Reklam Engelleme",
                                subtitle: adBlockEngine.isEnabled ? "\(adBlockEngine.filterInfo) - \(adBlockEngine.blockedAdsCount) engellendi" : "Devre disi",
                                isOn: $adBlockEngine.isEnabled
                            )

                            Divider().background(Color.cyberDivider)

                            MenuActionRow(
                                icon: "puzzlepiece.extension",
                                iconColor: .cyberYellow,
                                title: "Uzantilar",
                                subtitle: "\(extensionManager.extensions.filter { $0.isEnabled }.count) aktif uzanti",
                                badge: "\(extensionManager.extensions.count)"
                            ) {
                                showExtensions = true
                            }

                            Divider().background(Color.cyberDivider)

                            MenuActionRow(
                                icon: "network",
                                iconColor: .cyberYellow,
                                title: "Proxy Ayarlari",
                                subtitle: proxyManager.connectionStatus
                            ) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                    showInlineProxySettings.toggle()
                                }
                            }

                            if showInlineProxySettings {
                                Divider().background(Color.cyberDivider)

                                InlineProxyPanel()
                                    .environmentObject(proxyManager)
                                    .transition(
                                        .asymmetric(
                                            insertion: .push(from: .bottom).combined(with: .opacity),
                                            removal: .push(from: .top).combined(with: .opacity)
                                        )
                                    )

                                Divider().background(Color.cyberDivider)

                                MenuActionRow(
                                    icon: "slider.horizontal.3",
                                    iconColor: .cyberYellow,
                                    title: "Gelismis Proxy",
                                    subtitle: "Sunucu ayarlari ve link import"
                                ) {
                                    showProxySettingsSheet = true
                                }
                            }
                        }
                        .cyberCard()

                        VStack(spacing: 0) {
                            SectionHeader(title: "GIZLILIK")

                            MenuActionRow(
                                icon: "trash",
                                iconColor: .cyberRed,
                                title: "Gecmisi Temizle",
                                subtitle: "Tum tarayici verilerini sil"
                            ) {
                                showClearConfirm = true
                            }

                            Divider().background(Color.cyberDivider)

                            MenuInfoRow(
                                icon: "lock.shield",
                                iconColor: .cyberGreen,
                                title: "Gizlilik Kalkani",
                                subtitle: "Canvas ve WebGL fingerprinting korumasi",
                                status: extensionManager.extensions.first(where: { $0.name == "Gizlilik Kalkani" })?.isEnabled == true ? "AKTIF" : "KAPALI",
                                statusColor: extensionManager.extensions.first(where: { $0.name == "Gizlilik Kalkani" })?.isEnabled == true ? .cyberGreen : .cyberRed
                            )
                        }
                        .cyberCard()

                        VStack(spacing: 0) {
                            SectionHeader(title: "PERFORMANS")

                            MenuInfoRow(
                                icon: "gauge.high",
                                iconColor: .cyberYellow,
                                title: "Tracker Engelleme",
                                subtitle: "Sayfa yukleme performansini artirir",
                                status: "AKTIF",
                                statusColor: .cyberGreen
                            )

                            Divider().background(Color.cyberDivider)

                            MenuInfoRow(
                                icon: "speaker.wave.2",
                                iconColor: .cyberYellow,
                                title: "Arka Plan Ses",
                                subtitle: "Video ve ses arka planda calmaya devam eder",
                                status: "AKTIF",
                                statusColor: .cyberGreen
                            )
                        }
                        .cyberCard()

                        VStack(spacing: 0) {
                            SectionHeader(title: "HAKKINDA")

                            MenuInfoRow(
                                icon: "info.circle",
                                iconColor: .cyberMuted,
                                title: "CyberBrowser",
                                subtitle: "Versiyon 3.0 - Native AdBlock Engine",
                                status: "",
                                statusColor: .clear
                            )

                            Divider().background(Color.cyberDivider)

                            HStack(spacing: 8) {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(.cyberRed)
                                    .font(.system(size: 12))

                                Text("Gizlilik odakli, reklamsiz gezinti")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.cyberMuted)

                                Spacer()
                            }
                            .padding(12)
                        }
                        .cyberCard()
                    }
                    .padding(.horizontal, CyberTheme.padding)
                    .padding(.bottom, 30)
                }
            }
        }
        .sheet(isPresented: $showExtensions) {
            ExtensionsView()
                .environmentObject(extensionManager)
        }
        .sheet(isPresented: $showProxySettingsSheet) {
            NavigationStack {
                ProxySettingsView()
                    .environmentObject(proxyManager)
            }
        }
        .sheet(item: $activeAITool) { tool in
            NavigationStack {
                aiToolSheet(for: tool)
                    .presentationDetents(tool == .summary ? [.medium, .large] : [.medium])
            }
        }
        .confirmationDialog(
            "Tum tarayici verileri silinecek",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Tumunu Temizle", role: .destructive) {
                clearBrowsingData()
            }
            Button("Iptal", role: .cancel) {}
        } message: {
            Text("Gecmis, cerezler ve onbellek silinecektir. Bu islem geri alinamaz.")
        }
    }

    @ViewBuilder
    private func aiToolSheet(for tool: AITool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            switch tool {
            case .summary:
                Text("Sayfa Ozeti")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.cyberWhite)

                if aiAssistant.isProcessing {
                    HStack(spacing: 12) {
                        ProgressView()
                            .tint(.cyberYellow)
                        Text("Sayfa icerigi isleniyor...")
                            .foregroundColor(.cyberMuted)
                    }
                } else {
                    ScrollView {
                        Text(aiResultText.isEmpty ? "Ozet hazir degil." : aiResultText)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.cyberWhite)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

            case .translation:
                Text("Metin Ceviri")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.cyberWhite)

                Picker("Dil", selection: $translationLanguage) {
                    ForEach(TranslationLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .tint(.cyberYellow)

                Button {
                    Task { @MainActor in
                        await translateSelection()
                    }
                } label: {
                    HStack {
                        if aiAssistant.isProcessing {
                            ProgressView()
                                .tint(.black)
                        }
                        Text(aiAssistant.isProcessing ? "Ceviriliyor..." : "Secili Metni Cevir")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.cyberYellow, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(aiAssistant.isProcessing)

                ScrollView {
                    Text(aiResultText.isEmpty ? "Sayfada secili metin bulundugunda ceviri burada gorunecek." : aiResultText)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.cyberWhite)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.cyberBlack.ignoresSafeArea())
    }

    private func summarizePage() async {
        guard let webView else {
            aiResultText = "WebView hazir degil."
            return
        }

        let result = await aiAssistant.summarizePage(webView: webView)
        aiResultText = result
        aiAssistant.lastResult = result
    }

    private func translateSelection() async {
        guard let webView else {
            aiResultText = "WebView hazir degil."
            return
        }

        aiAssistant.isProcessing = true
        defer { aiAssistant.isProcessing = false }

        let selectedText = await aiAssistant.selectedText(from: webView)
        let result = await aiAssistant.translateSelection(selectedText, to: translationLanguage.rawValue)
        aiResultText = result
        aiAssistant.lastResult = result
    }

    private func clearBrowsingData() {
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let dateFrom = Date(timeIntervalSince1970: 0)

        dataStore.removeData(ofTypes: dataTypes, modifiedSince: dateFrom) {
            print("[CyberBrowser] All browsing data cleared")
        }

        adBlockEngine.blockedAdsCount = 0
        adBlockEngine.lastBlockedDomain = ""
    }
}

// MARK: - Menu Components
struct SectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.cyberYellow)
                .tracking(1.5)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }
}

struct MenuToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.cyberWhite)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.cyberMuted)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: .cyberYellow))
                .labelsHidden()
        }
        .padding(12)
    }
}

struct MenuActionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    var badge: String? = nil
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(iconColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.cyberWhite)

                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.cyberMuted)
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .tint(.cyberYellow)
                } else if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.cyberYellow)
                        .cornerRadius(10)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.cyberMuted)
                }
            }
            .padding(12)
        }
    }
}

struct MenuInfoRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let status: String
    let statusColor: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.cyberWhite)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.cyberMuted)
            }

            Spacer()

            if !status.isEmpty {
                Text(status)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(statusColor)
            }
        }
        .padding(12)
    }
}

struct InlineProxyPanel: View {
    @EnvironmentObject var proxyManager: ProxyManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Proxy", systemImage: "globe")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.cyberWhite)

                Spacer()

                Text(proxyManager.isConnected ? "Aktif" : "Kapali")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(proxyManager.isConnected ? .cyberGreen : .cyberMuted)
            }

            Picker("Protokol", selection: $proxyManager.selectedProtocol) {
                ForEach(ProxyManager.ProxyProtocol.allCases, id: \.self) { proto in
                    Text(proto.rawValue).tag(proto)
                }
            }
            .pickerStyle(.menu)
            .tint(.cyberYellow)

            Text(proxyManager.connectionStatus)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.cyberMuted)
                .lineLimit(2)

            Button(proxyManager.isConnected ? "Baglantiyi Kes" : "Baglan") {
                if proxyManager.isConnected {
                    proxyManager.stopProxy()
                } else {
                    proxyManager.startProxy()
                }
            }
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundColor(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.cyberYellow, in: Capsule())
        }
        .padding(12)
    }
}
