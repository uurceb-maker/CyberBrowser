import Foundation
import Network
import WebKit

extension ProxyConfiguration {
    /// Shadowsocks proxy endpoint mapped to local SOCKS5 tunnel.
    static func shadowsocks(port: UInt16) -> ProxyConfiguration {
        let endpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: port)!
        )
        return ProxyConfiguration(socksv5Proxy: endpoint)
    }
}
