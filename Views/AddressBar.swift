import SwiftUI

// MARK: - Address Bar
struct AddressBar: View {
    @Binding var urlString: String
    @Binding var isSecure: Bool
    @Binding var isLoading: Bool
    let onCommit: (String) -> Void
    
    @State private var isEditing: Bool = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // Security Icon
            Image(systemName: isSecure ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isSecure ? .cyberGreen : .cyberRed)
                .frame(width: 20)
            
            // URL/Search TextField
            TextField("Ara veya URL gir...", text: $urlString)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(.cyberWhite)
                .accentColor(.cyberYellow)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .keyboardType(.webSearch)
                .textContentType(.URL)
                .focused($isFocused)
                .onSubmit {
                    onCommit(urlString)
                    isFocused = false
                }
                .onTapGesture {
                    isEditing = true
                    // Select all text on tap
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isFocused = true
                    }
                }
            
            // Loading / Reload indicator
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .cyberYellow))
                    .scaleEffect(0.7)
            } else if isEditing {
                Button(action: {
                    urlString = ""
                    isFocused = true
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.cyberMuted)
                        .font(.system(size: 16))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: CyberTheme.smallCornerRadius)
                .fill(Color.cyberSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: CyberTheme.smallCornerRadius)
                        .stroke(
                            isFocused ? Color.cyberYellow : Color.cyberYellow.opacity(0.3),
                            lineWidth: isFocused ? 1.5 : 0.5
                        )
                )
        )
        .padding(.horizontal, CyberTheme.padding)
        .padding(.vertical, 6)
        .onChange(of: isFocused) { focused in
            isEditing = focused
        }
    }
}
