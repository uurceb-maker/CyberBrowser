import SwiftUI
import UIKit

struct ServerConfigView: View {
    @EnvironmentObject var proxyManager: ProxyManager

    @State private var serverAddress: String = ""
    @State private var serverPortText: String = ""
    @State private var uuidOrPassword: String = ""
    @State private var importStatus: String = ""

    var body: some View {
        Form {
            Section("Protokol") {
                Picker("Protokol", selection: $proxyManager.selectedProtocol) {
                    Text("VLESS").tag(ProxyManager.ProxyProtocol.vless)
                    Text("Trojan").tag(ProxyManager.ProxyProtocol.trojan)
                    Text("Shadowsocks").tag(ProxyManager.ProxyProtocol.shadowsocks)
                    Text("SOCKS5").tag(ProxyManager.ProxyProtocol.socks5)
                }
                .pickerStyle(.menu)
            }

            Section("Sunucu Bilgisi") {
                TextField("Sunucu adresi", text: $serverAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("Port", text: $serverPortText)
                    .keyboardType(.numberPad)

                SecureField("UUID / Password", text: $uuidOrPassword)
            }

            Section("Eylemler") {
                Button("Baglantiyi Test Et") {
                    saveToManager()
                    Task { await proxyManager.startProxy() }
                }

                Button("Panodan Link Import Et") {
                    importFromClipboard()
                }

                if !importStatus.isEmpty {
                    Text(importStatus)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Server Config")
        .onAppear {
            serverAddress = proxyManager.serverAddress
            serverPortText = "\(proxyManager.serverPort)"
            uuidOrPassword = proxyManager.serverUUID.isEmpty ? proxyManager.serverPassword : proxyManager.serverUUID
        }
    }

    private func saveToManager() {
        proxyManager.serverAddress = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if let port = Int(serverPortText), port > 0 {
            proxyManager.serverPort = port
        }

        switch proxyManager.selectedProtocol {
        case .vless:
            proxyManager.serverUUID = uuidOrPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        case .trojan, .shadowsocks, .socks5:
            proxyManager.serverPassword = uuidOrPassword
        case .direct:
            break
        }
    }

    private func importFromClipboard() {
        guard let raw = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            importStatus = "Panoda uygun baglanti yok."
            return
        }

        if raw.hasPrefix("vless://"), let parsed = parseStandardURL(raw) {
            proxyManager.selectedProtocol = .vless
            serverAddress = parsed.host
            serverPortText = String(parsed.port)
            uuidOrPassword = parsed.user
            saveToManager()
            importStatus = "VLESS import edildi."
            return
        }

        if raw.hasPrefix("trojan://"), let parsed = parseStandardURL(raw) {
            proxyManager.selectedProtocol = .trojan
            serverAddress = parsed.host
            serverPortText = String(parsed.port)
            uuidOrPassword = parsed.user
            saveToManager()
            importStatus = "Trojan import edildi."
            return
        }

        if raw.hasPrefix("ss://"), let parsed = parseShadowsocksURL(raw) {
            proxyManager.selectedProtocol = .shadowsocks
            serverAddress = parsed.host
            serverPortText = String(parsed.port)
            uuidOrPassword = parsed.password
            saveToManager()
            importStatus = "Shadowsocks import edildi."
            return
        }

        importStatus = "Desteklenmeyen format."
    }

    private func parseStandardURL(_ raw: String) -> (host: String, port: Int, user: String)? {
        guard let components = URLComponents(string: raw),
              let host = components.host,
              let port = components.port
        else { return nil }

        let user = components.user ?? ""
        return (host, port, user)
    }

    private func parseShadowsocksURL(_ raw: String) -> (host: String, port: Int, password: String)? {
        guard let url = URL(string: raw) else { return nil }

        if let host = url.host, let port = url.port {
            let password = url.user ?? ""
            return (host, port, password)
        }

        // Supports base64 format fallback: ss://base64@host:port
        let stripped = raw.replacingOccurrences(of: "ss://", with: "")
        let pieces = stripped.split(separator: "@")
        guard pieces.count == 2 else { return nil }
        let hostPort = pieces[1].split(separator: ":")
        guard hostPort.count == 2, let port = Int(hostPort[1]) else { return nil }

        let passwordRaw = String(pieces[0])
        let decoded = Data(base64Encoded: passwordRaw).flatMap { String(data: $0, encoding: .utf8) } ?? passwordRaw
        let password = decoded.split(separator: ":").last.map(String.init) ?? decoded
        return (String(hostPort[0]), port, password)
    }
}

#Preview {
    NavigationStack {
        ServerConfigView()
            .environmentObject(ProxyManager())
    }
}
