import Foundation
import WebKit

@MainActor
final class AIAssistant: ObservableObject {
    @Published var isProcessing = false
    @Published var lastResult: String = ""

    /// Pull page text and summarize it.
    func summarizePage(webView: WKWebView) async -> String {
        isProcessing = true
        defer { isProcessing = false }

        let script = "document.body ? document.body.innerText.substring(0, 10000) : ''"
        do {
            let text = try await evaluateText(script: script, webView: webView)
            guard !text.isEmpty else { return "Sayfa icerigi okunamadi." }
            return extractiveSummary(text)
        } catch {
            return "Sayfa icerigi okunamadi."
        }
    }

    /// Translate selected text (placeholder behavior for now).
    func translateSelection(_ text: String, to lang: String) async -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Secili metin bulunamadi."
        }
        return "[\(lang.uppercased())] \(text)"
    }

    private func evaluateText(script: String, webView: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = result as? String ?? ""
                continuation.resume(returning: value)
            }
        }
    }

    /// Lightweight on-device fallback summary.
    private func extractiveSummary(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(of: "\n", with: " ")
        let sentences = cleaned.components(separatedBy: ". ")
        let summary = sentences.prefix(5).joined(separator: ". ")
        if summary.isEmpty { return "Ozet olusturulamadi." }
        return summary.hasSuffix(".") ? summary : summary + "."
    }
}
