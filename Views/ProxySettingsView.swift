import SwiftUI

struct ProxySettingsView: View {
    @EnvironmentObject var proxyManager: ProxyManager

    @State private var serverAddress: String = ""
    @State private var portText: String = ""
    @State private var uuidPasswordText: String = ""

    var body: some View {
        Form {
            Section("Proxy Protocol") {
                Picker("Protocol", selection: $proxyManager.selectedProtocol) {
                    ForEach(ProxyManager.ProxyProtocol.allCases, id: \.self) { proto in
                        Text(proto.rawValue).tag(proto)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Server") {
                TextField("Server address", text: $serverAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("Port", text: $portText)
                    .keyboardType(.numberPad)

                SecureField("UUID / Password", text: $uuidPasswordText)

                NavigationLink {
                    ServerConfigView()
                        .environmentObject(proxyManager)
                } label: {
                    Label("Advanced Server Config", systemImage: "server.rack")
                }
            }

            Section("Connection") {
                HStack {
                    Circle()
                        .fill(proxyManager.isConnected ? Color.green : Color.red)
                        .frame(width: 10, height: 10)

                    Text(proxyManager.connectionStatus)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Button(proxyManager.isConnected ? "Disconnect" : "Connect") {
                    saveInputs()
                    if proxyManager.isConnected {
                        proxyManager.stopProxy()
                    } else {
                        proxyManager.startProxy()
                    }
                }
            }
        }
        .navigationTitle("Proxy Settings")
        .onAppear {
            serverAddress = proxyManager.serverAddress
            portText = "\(proxyManager.serverPort)"
            uuidPasswordText = proxyManager.serverUUID.isEmpty ? proxyManager.serverPassword : proxyManager.serverUUID
        }
    }

    private func saveInputs() {
        proxyManager.serverAddress = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if let p = Int(portText), p > 0 {
            proxyManager.serverPort = p
        }

        switch proxyManager.selectedProtocol {
        case .vless:
            proxyManager.serverUUID = uuidPasswordText
            proxyManager.serverPassword = ""
        case .trojan, .shadowsocks, .socks5:
            proxyManager.serverPassword = uuidPasswordText
        case .direct:
            break
        }
    }
}

#Preview {
    NavigationStack {
        ProxySettingsView()
            .environmentObject(ProxyManager())
    }
}
