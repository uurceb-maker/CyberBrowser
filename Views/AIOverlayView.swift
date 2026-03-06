import SwiftUI
import WebKit

@MainActor
struct AIOverlayView: View {
    @ObservedObject var assistant: AIAssistant
    let webView: WKWebView?

    @State private var isExpanded = false

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()

                VStack(alignment: .trailing, spacing: 10) {
                    if isExpanded {
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                runSummarize()
                            } label: {
                                Label("Sayfayi Ozetle", systemImage: "text.alignleft")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            }

                            Button {
                                runTranslateSelection()
                            } label: {
                                Label("Secili Metni Cevir", systemImage: "globe")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            }

                            if assistant.isProcessing {
                                ProgressView()
                                    .tint(.cyberYellow)
                            }

                            if !assistant.lastResult.isEmpty {
                                ScrollView {
                                    Text(assistant.lastResult)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(.cyberWhite)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 180)
                            }
                        }
                        .padding(12)
                        .frame(width: 280)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.cyberYellow.opacity(0.22), lineWidth: 0.8)
                        )
                        .transition(.scale.combined(with: .opacity))
                    }

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.black)
                            .frame(width: 48, height: 48)
                            .background(Color.cyberYellow, in: Circle())
                    }
                    .shadow(color: Color.cyberYellow.opacity(0.35), radius: 16, x: 0, y: 8)
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: isExpanded)
    }

    private func runSummarize() {
        guard let webView else {
            assistant.lastResult = "WebView hazir degil."
            return
        }

        Task { @MainActor in
            let result = await assistant.summarizePage(webView: webView)
            assistant.lastResult = result
        }
    }

    private func runTranslateSelection() {
        guard let webView else {
            assistant.lastResult = "WebView hazir degil."
            return
        }

        Task { @MainActor in
            let selection = await extractSelectionText(from: webView)
            let result = await assistant.translateSelection(selection, to: "en")
            assistant.lastResult = result
        }
    }

    private func extractSelectionText(from webView: WKWebView) async -> String {
        await withCheckedContinuation { continuation in
            let script = "window.getSelection ? window.getSelection().toString() : ''"
            webView.evaluateJavaScript(script) { result, _ in
                continuation.resume(returning: result as? String ?? "")
            }
        }
    }
}
