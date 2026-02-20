import SwiftUI

// MARK: - Extensions View
struct ExtensionsView: View {
    @EnvironmentObject var extensionManager: ExtensionManager
    @Environment(\.dismiss) var dismiss
    
    @State private var showAddScript: Bool = false
    @State private var newScriptName: String = ""
    @State private var newScriptCode: String = ""
    @State private var selectedInjectionTime: ScriptInjectionTime = .atDocumentEnd
    
    var body: some View {
        ZStack {
            Color.cyberBlack.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.cyberWhite)
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 2) {
                        Text("Uzantılar")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.cyberWhite)
                        
                        Text("\(extensionManager.extensions.filter { $0.isEnabled }.count) aktif")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.cyberYellow)
                    }
                    
                    Spacer()
                    
                    Button(action: { showAddScript = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.cyberYellow)
                    }
                }
                .padding(.horizontal, CyberTheme.padding)
                .padding(.top, 16)
                .padding(.bottom, 12)
                
                // Info Banner
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.cyberYellow)
                    
                    Text("Uzantıları açıp kapatabilir veya kendi scriptlerinizi ekleyebilirsiniz.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.cyberMuted)
                }
                .padding(12)
                .background(Color.cyberSurface)
                .cornerRadius(CyberTheme.smallCornerRadius)
                .padding(.horizontal, CyberTheme.padding)
                .padding(.bottom, 12)
                
                // Extension List
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(extensionManager.extensions) { ext in
                            ExtensionCard(extension: ext) {
                                extensionManager.toggleExtension(id: ext.id)
                            } onDelete: {
                                withAnimation(.spring(response: 0.3)) {
                                    extensionManager.removeExtension(id: ext.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, CyberTheme.padding)
                    .padding(.bottom, 30)
                }
                
                // iOS 18.4+ Web Extension Info
                VStack(spacing: 6) {
                    Divider()
                        .background(Color.cyberYellow.opacity(0.2))
                    
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12))
                            .foregroundColor(.cyberYellow)
                        
                        Text("iOS 18.4+ — WKWebExtensionController ile tam uzantı desteği")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.cyberMuted)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .sheet(isPresented: $showAddScript) {
            AddScriptSheet(
                name: $newScriptName,
                code: $newScriptCode,
                injectionTime: $selectedInjectionTime
            ) {
                if !newScriptName.isEmpty && !newScriptCode.isEmpty {
                    extensionManager.addUserScript(
                        name: newScriptName,
                        code: newScriptCode,
                        injectionTime: selectedInjectionTime
                    )
                    newScriptName = ""
                    newScriptCode = ""
                    showAddScript = false
                }
            }
        }
    }
}

// MARK: - Extension Card
struct ExtensionCard: View {
    let `extension`: BrowserExtension
    let onToggle: () -> Void
    let onDelete: () -> Void
    
    @State private var showDeleteConfirm = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(`extension`.isEnabled ? Color.cyberYellow.opacity(0.15) : Color.cyberSurface)
                    .frame(width: 44, height: 44)
                
                Image(systemName: `extension`.iconName)
                    .font(.system(size: 20))
                    .foregroundColor(`extension`.isEnabled ? .cyberYellow : .cyberMuted)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(`extension`.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.cyberWhite)
                
                Text(`extension`.description)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.cyberMuted)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    Text("v\(`extension`.version)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.cyberMuted)
                    
                    Text("•")
                        .foregroundColor(.cyberMuted)
                    
                    Text(`extension`.author)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.cyberMuted)
                }
            }
            
            Spacer()
            
            // Actions
            VStack(spacing: 8) {
                // Toggle
                Toggle("", isOn: Binding(
                    get: { `extension`.isEnabled },
                    set: { _ in onToggle() }
                ))
                .toggleStyle(SwitchToggleStyle(tint: .cyberYellow))
                .labelsHidden()
                .scaleEffect(0.8)
                
                // Delete (only for user-added)
                if `extension`.author == "Kullanıcı" {
                    Button(action: { showDeleteConfirm = true }) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.cyberRed.opacity(0.7))
                    }
                }
            }
        }
        .padding(12)
        .cyberCard()
        .confirmationDialog("Bu uzantıyı silmek istediğinize emin misiniz?", isPresented: $showDeleteConfirm) {
            Button("Sil", role: .destructive) { onDelete() }
            Button("İptal", role: .cancel) {}
        }
    }
}

// MARK: - Add Script Sheet
struct AddScriptSheet: View {
    @Binding var name: String
    @Binding var code: String
    @Binding var injectionTime: ScriptInjectionTime
    let onSave: () -> Void
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Color.cyberBlack.ignoresSafeArea()
            
            VStack(spacing: 16) {
                // Header
                HStack {
                    Button("İptal") { dismiss() }
                        .foregroundColor(.cyberMuted)
                    
                    Spacer()
                    
                    Text("Yeni Script")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.cyberWhite)
                    
                    Spacer()
                    
                    Button("Ekle") { onSave() }
                        .foregroundColor(.cyberYellow)
                        .fontWeight(.bold)
                        .disabled(name.isEmpty || code.isEmpty)
                }
                .padding(.horizontal)
                .padding(.top, 16)
                
                // Name Field
                VStack(alignment: .leading, spacing: 6) {
                    Text("SCRIPT ADI")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyberYellow)
                    
                    TextField("Örn: Karanlık Mod", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.cyberWhite)
                        .padding(12)
                        .background(Color.cyberSurface)
                        .cornerRadius(CyberTheme.smallCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: CyberTheme.smallCornerRadius)
                                .stroke(Color.cyberYellow.opacity(0.3), lineWidth: 0.5)
                        )
                }
                .padding(.horizontal)
                
                // Injection Time Picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("ÇALIŞTIRMA ZAMANI")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyberYellow)
                    
                    Picker("", selection: $injectionTime) {
                        Text("Sayfa Başı").tag(ScriptInjectionTime.atDocumentStart)
                        Text("Sayfa Sonu").tag(ScriptInjectionTime.atDocumentEnd)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
                
                // Code Editor
                VStack(alignment: .leading, spacing: 6) {
                    Text("JAVASCRIPT KODU")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyberYellow)
                    
                    TextEditor(text: $code)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundColor(.cyberGreen)
                        .scrollContentBackground(.hidden)
                        .background(Color.cyberSurface)
                        .cornerRadius(CyberTheme.smallCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: CyberTheme.smallCornerRadius)
                                .stroke(Color.cyberYellow.opacity(0.3), lineWidth: 0.5)
                        )
                        .frame(minHeight: 200)
                }
                .padding(.horizontal)
                
                // Help text
                Text("JavaScript kodunu yapıştırın. Kod her sayfada otomatik çalıştırılacaktır.")
                    .font(.system(size: 11))
                    .foregroundColor(.cyberMuted)
                    .padding(.horizontal)
                
                Spacer()
            }
        }
    }
}
