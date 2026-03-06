import SwiftUI

// MARK: - Address Bar
struct AddressBar: View {
    @Binding var urlString: String
    @Binding var isSecure: Bool
    @Binding var isLoading: Bool
    var proxyConnected: Bool = false
    let onCommit: (String) -> Void

    @State private var isEditing: Bool = false
    @State private var editText: String = ""
    @FocusState private var isFocused: Bool
    @Namespace private var morphNamespace

    private var displayText: String {
        if isEditing { return editText }
        if let url = URL(string: urlString), let host = url.host { return host }
        return urlString
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: isSecure ? "lock.shield.fill" : "lock.open.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isSecure ? .cyberGreen : .cyberRed)
                    .frame(width: 20)

                Group {
                    if isEditing {
                        TextField("Ara veya URL gir...", text: $editText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.cyberWhite)
                            .accentColor(.cyberYellow)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .keyboardType(.webSearch)
                            .textContentType(.URL)
                            .focused($isFocused)
                            .onSubmit {
                                onCommit(editText)
                                isEditing = false
                                isFocused = false
                            }
                    } else {
                        Text(displayText)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.cyberWhite)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                focusAddressBar()
                            }
                    }
                }

                if isEditing {
                    Button {
                        editText = ""
                        isFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.cyberMuted)
                            .font(.system(size: 16))
                    }
                } else if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .cyberYellow))
                        .scaleEffect(0.7)
                }

                Image(systemName: proxyConnected ? "globe" : "bolt.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(proxyConnected ? .cyberYellow : .cyberMuted)
                    .frame(width: 20)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                .ultraThinMaterial,
                in: Capsule(style: .continuous)
            )
            .matchedGeometryEffect(id: "addressBarMorph", in: morphNamespace)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isFocused ? Color.cyberYellow.opacity(0.7) : Color.white.opacity(0.15), lineWidth: 1)
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isEditing)
            .overlay(alignment: .bottom) {
                if isLoading {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.cyberYellow.opacity(0.3),
                                    Color.cyberYellow,
                                    Color.cyberYellow.opacity(0.3)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 2)
                        .padding(.horizontal, 24)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .onChange(of: isFocused) { _, focused in
            if !focused {
                isEditing = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusAddressBar)) { _ in
            focusAddressBar()
        }
        .onAppear {
            editText = urlString
        }
        .onChange(of: urlString) { _, newValue in
            if !isEditing {
                editText = newValue
            }
        }
    }

    private func focusAddressBar() {
        editText = urlString
        isEditing = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            isFocused = true
        }
    }
}

extension Notification.Name {
    static let focusAddressBar = Notification.Name("focusAddressBar")
}
