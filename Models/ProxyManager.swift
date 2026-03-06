import Combine
import Foundation
import Network
import WebKit

final class ProxyManager: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var connectionStatus: String = "Baglanti Yok"
    @Published var selectedProtocol: ProxyProtocol = .direct {
        didSet { defaults.set(selectedProtocol.rawValue, forKey: StorageKey.selectedProtocol) }
    }

    @Published var serverAddress: String {
        didSet { defaults.set(serverAddress, forKey: StorageKey.serverAddress) }
    }

    @Published var serverPort: Int {
        didSet { defaults.set(serverPort, forKey: StorageKey.serverPort) }
    }

    @Published var serverUUID: String {
        didSet { defaults.set(serverUUID, forKey: StorageKey.serverUUID) }
    }

    @Published var serverPassword: String {
        didSet { defaults.set(serverPassword, forKey: StorageKey.serverPassword) }
    }

    enum ProxyProtocol: String, CaseIterable {
        case direct = "Direct"
        case socks5 = "SOCKS5"
        case shadowsocks = "Shadowsocks"
        case trojan = "Trojan"
        case vless = "VLESS"
    }

    private enum StorageKey {
        static let selectedProtocol = "proxy.selectedProtocol"
        static let serverAddress = "proxy.serverAddress"
        static let serverPort = "proxy.serverPort"
        static let serverUUID = "proxy.serverUUID"
        static let serverPassword = "proxy.serverPassword"
    }

    private let defaults = UserDefaults.standard
    private let localPort: UInt16 = 9090
    private var localServer: NWListener?
    private let xray = XrayWrapper()

    init() {
        let savedProtocol = defaults.string(forKey: StorageKey.selectedProtocol) ?? ProxyProtocol.direct.rawValue
        selectedProtocol = ProxyProtocol(rawValue: savedProtocol) ?? .direct
        serverAddress = defaults.string(forKey: StorageKey.serverAddress) ?? "127.0.0.1"

        let savedPort = defaults.integer(forKey: StorageKey.serverPort)
        serverPort = savedPort == 0 ? 443 : savedPort

        serverUUID = defaults.string(forKey: StorageKey.serverUUID) ?? ""
        serverPassword = defaults.string(forKey: StorageKey.serverPassword) ?? ""

        if selectedProtocol == .direct {
            connectionStatus = "Dogrudan baglanti"
        }
    }

    // MARK: - DataStore with Proxy
    func createProxyDataStore() -> WKWebsiteDataStore {
        let dataStore = WKWebsiteDataStore.nonPersistent()
        if selectedProtocol != .direct {
            let endpoint = NWEndpoint.hostPort(
                host: .ipv4(.loopback),
                port: NWEndpoint.Port(rawValue: localPort)!
            )
            let proxyConfig = ProxyConfiguration(socksv5Proxy: endpoint)
            dataStore.proxyConfigurations = [proxyConfig]
        }
        return dataStore
    }

    // MARK: - Connect / Disconnect
    func startProxy() {
        guard selectedProtocol != .direct else {
            isConnected = false
            connectionStatus = "Dogrudan baglanti"
            return
        }

        connectionStatus = "Baglaniyor..."

        let protocolName = protocolNameForXray(selectedProtocol)
        let config = xray.generateConfig(
            protocolName: protocolName,
            serverAddress: serverAddress,
            serverPort: serverPort,
            uuid: serverUUID,
            password: serverPassword,
            localPort: Int(localPort)
        )

        guard let configURL = xray.writeConfig(config) else {
            isConnected = false
            connectionStatus = "Konfigurasyon yazilamadi"
            return
        }

        let started = xray.start(configPath: configURL.path)
        isConnected = started
        connectionStatus = started
            ? "\(selectedProtocol.rawValue) aktif (port \(localPort))"
            : "\(selectedProtocol.rawValue) baslatilamadi"
    }

    func stopProxy() {
        localServer?.cancel()
        xray.stop()
        isConnected = false
        connectionStatus = "Baglanti kesildi"
    }

    // MARK: - App Lifecycle
    func handleAppWillResignActive() {
        // Keep state, no-op for now.
    }

    func handleAppDidBecomeActive() {
        if selectedProtocol != .direct {
            startProxy()
        }
    }

    private func protocolNameForXray(_ protocolType: ProxyProtocol) -> String {
        switch protocolType {
        case .direct:
            return "direct"
        case .socks5:
            return "socks"
        case .shadowsocks:
            return "shadowsocks"
        case .trojan:
            return "trojan"
        case .vless:
            return "vless"
        }
    }
}
