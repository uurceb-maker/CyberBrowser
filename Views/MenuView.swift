import SwiftUI

// MARK: - Menu View
struct MenuView: View {
    @EnvironmentObject var adBlockEngine: AdBlockEngine
    @EnvironmentObject var extensionManager: ExtensionManager
    @EnvironmentObject var tabManager: TabManager
    @Environment(\.dismiss) var dismiss
    
    @State private var showExtensions: Bool = false
    @State private var showClearConfirm: Bool = false
    
    var body: some View {
        ZStack {
            Color.cyberBlack.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Drag handle
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.cyberMuted)
                    .frame(width: 40, height: 5)
                    .padding(.top, 10)
                
                // Header
                HStack {
                    Text("Menü")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.cyberWhite)
                    
                    Spacer()
                }
                .padding(.horizontal, CyberTheme.padding)
                .padding(.top, 16)
                .padding(.bottom, 8)
                
                ScrollView {
                    VStack(spacing: 12) {
                        // Ad Block Section
                        VStack(spacing: 0) {
                            SectionHeader(title: "GÜVENLİK")
                            
                            MenuToggleRow(
                                icon: "shield.checkered",
                                iconColor: .cyberYellow,
                                title: "Reklam Engelleme",
                                subtitle: "\(adBlockEngine.totalBlockedAds) reklam engellendi",
                                isOn: $adBlockEngine.isEnabled
                            )
                            
                            Divider().background(Color.cyberDivider)
                            
                            // Extensions button
                            MenuActionRow(
                                icon: "puzzlepiece.extension",
                                iconColor: .cyberYellow,
                                title: "Uzantılar",
                                subtitle: "\(extensionManager.extensions.filter { $0.isEnabled }.count) aktif uzantı",
                                badge: "\(extensionManager.extensions.count)"
                            ) {
                                showExtensions = true
                            }
                        }
                        .cyberCard()
                        
                        // Privacy Section
                        VStack(spacing: 0) {
                            SectionHeader(title: "GİZLİLİK")
                            
                            MenuActionRow(
                                icon: "trash",
                                iconColor: .cyberRed,
                                title: "Geçmişi Temizle",
                                subtitle: "Tüm tarayıcı verilerini sil"
                            ) {
                                showClearConfirm = true
                            }
                            
                            Divider().background(Color.cyberDivider)
                            
                            MenuInfoRow(
                                icon: "lock.shield",
                                iconColor: .cyberGreen,
                                title: "Gizlilik Kalkanı",
                                subtitle: "Canvas & WebGL fingerprinting koruması",
                                status: extensionManager.extensions.first(where: { $0.name == "Gizlilik Kalkanı" })?.isEnabled == true ? "AKTİF" : "KAPALI",
                                statusColor: extensionManager.extensions.first(where: { $0.name == "Gizlilik Kalkanı" })?.isEnabled == true ? .cyberGreen : .cyberRed
                            )
                        }
                        .cyberCard()
                        
                        // Performance Section
                        VStack(spacing: 0) {
                            SectionHeader(title: "PERFORMANS")
                            
                            MenuInfoRow(
                                icon: "gauge.high",
                                iconColor: .cyberYellow,
                                title: "Tracker Engelleme",
                                subtitle: "Sayfa yükleme performansını artırır",
                                status: "AKTİF",
                                statusColor: .cyberGreen
                            )
                            
                            Divider().background(Color.cyberDivider)
                            
                            MenuInfoRow(
                                icon: "speaker.wave.2",
                                iconColor: .cyberYellow,
                                title: "Arka Plan Ses",
                                subtitle: "Video/ses arka planda çalmaya devam eder",
                                status: "AKTİF",
                                statusColor: .cyberGreen
                            )
                        }
                        .cyberCard()
                        
                        // About Section
                        VStack(spacing: 0) {
                            SectionHeader(title: "HAKKINDA")
                            
                            MenuInfoRow(
                                icon: "info.circle",
                                iconColor: .cyberMuted,
                                title: "CyberBrowser",
                                subtitle: "Versiyon 1.0 — Cyberpunk Editon",
                                status: "",
                                statusColor: .clear
                            )
                            
                            Divider().background(Color.cyberDivider)
                            
                            HStack(spacing: 8) {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(.cyberRed)
                                    .font(.system(size: 12))
                                
                                Text("Gizlilik odaklı, reklamsız gezinti")
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
        .confirmationDialog(
            "Tüm tarayıcı verileri silinecek",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Tümünü Temizle", role: .destructive) {
                clearBrowsingData()
            }
            Button("İptal", role: .cancel) {}
        } message: {
            Text("Geçmiş, çerezler ve önbellek silinecektir. Bu işlem geri alınamaz.")
        }
    }
    
    private func clearBrowsingData() {
        // Clear WKWebView data
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let dateFrom = Date(timeIntervalSince1970: 0)
        
        dataStore.removeData(ofTypes: dataTypes, modifiedSince: dateFrom) {
            print("[CyberBrowser] All browsing data cleared")
        }
        
        adBlockEngine.resetCount()
    }
}

import WebKit

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
                
                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.cyberYellow)
                        .cornerRadius(10)
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.cyberMuted)
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
