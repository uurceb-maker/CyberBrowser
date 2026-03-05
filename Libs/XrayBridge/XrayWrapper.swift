import Foundation

/// Swift wrapper around the Xray core bridge.
/// This is a runtime-safe scaffold until a real xcframework is linked.
final class XrayWrapper {
    private var isRunning = false

    /// Build an Xray JSON config with local SOCKS inbound and selected outbound.
    func generateConfig(
        protocolName: String,   // vless, trojan, shadowsocks, socks
        serverAddress: String,
        serverPort: Int,
        uuid: String,
        password: String,
        localPort: Int = 9090
    ) -> String {
        var outboundSettings: [String: Any] = [:]

        switch protocolName.lowercased() {
        case "vless", "trojan":
            outboundSettings = [
                "vnext": [[
                    "address": serverAddress,
                    "port": serverPort,
                    "users": [[
                        "id": uuid,
                        "password": password
                    ]]
                ]]
            ]
        case "shadowsocks":
            outboundSettings = [
                "servers": [[
                    "address": serverAddress,
                    "port": serverPort,
                    "password": password,
                    "method": "aes-128-gcm"
                ]]
            ]
        case "socks":
            outboundSettings = [
                "servers": [[
                    "address": serverAddress,
                    "port": serverPort
                ]]
            ]
        default:
            outboundSettings = [
                "vnext": [[
                    "address": serverAddress,
                    "port": serverPort,
                    "users": [["id": uuid]]
                ]]
            ]
        }

        let config: [String: Any] = [
            "inbounds": [[
                "port": localPort,
                "listen": "127.0.0.1",
                "protocol": "socks",
                "settings": ["auth": "noauth"]
            ]],
            "outbounds": [[
                "protocol": protocolName.lowercased(),
                "settings": outboundSettings,
                "streamSettings": [
                    "network": "ws",
                    "security": "tls",
                    "wsSettings": ["path": "/"]
                ]
            ]]
        ]

        guard
            let data = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted]),
            let json = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return json
    }

    /// Persist generated config to Documents.
    func writeConfig(_ json: String) -> URL? {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let fileURL = dir.appendingPathComponent("xray_config.json")
        do {
            try json.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }

    /// Starts Xray runtime. Currently simulated until bridge is linked.
    @discardableResult
    func start(configPath: String) -> Bool {
        print("[XrayBridge] Starting with config: \(configPath)")
        isRunning = true
        return true
    }

    func stop() {
        isRunning = false
        print("[XrayBridge] Stopped")
    }

    var running: Bool { isRunning }
}
