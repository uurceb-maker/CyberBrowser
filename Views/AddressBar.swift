import SwiftUI

// MARK: - Address Bar
struct AddressBar: View {
    @Binding var urlString: String
    @Binding var isSecure: Bool
    @Binding var isLoading: Bool
    let onCommit: (String) -> Void
    
    @State private var isEditing: Bool = false
    @State private var editText: String = ""
    @FocusState private var isFocused: Bool
    
    // Display hostname when not editing, full URL when editing
    private var displayText: String {
        if isEditing {
            return editText
        }
        if let url = URL(string: urlString), let host = url.host {
            return host
        }
        return urlString
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Security Icon
            Image(systemName: isSecure ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isSecure ? .cyberGreen : .cyberRed)
                .frame(width: 20)
            
            // URL/Search TextField
            if isEditing {
                TextField("Ara veya URL gir...", text: $editText)
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
                        onCommit(editText)
                        isEditing = false
                        isFocused = false
                    }
            } else {
                Text(displayText)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.cyberWhite)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editText = urlString
                        isEditing = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isFocused = true
                        }
                    }
            }
            
            // Loading / Clear / Reload indicator
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .cyberYellow))
                    .scaleEffect(0.7)
            } else if isEditing {
                Button(action: {
                    editText = ""
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
            if !focused {
                isEditing = false
            }
        }
    }
}
