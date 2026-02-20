import SwiftUI
import WebKit

// MARK: - Extension System
// Custom browser extension model that allows loading user scripts
// and web extensions compatible with the manifest.json format

// MARK: - Browser Extension Model
struct BrowserExtension: Identifiable, Codable {
    let id: UUID
    var name: String
    var description: String
    var version: String
    var isEnabled: Bool
    var contentScripts: [ExtensionScript]
    var permissions: [String]
    var iconName: String
    var author: String
    
    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        version: String = "1.0",
        isEnabled: Bool = true,
        contentScripts: [ExtensionScript] = [],
        permissions: [String] = [],
        iconName: String = "puzzlepiece.extension",
        author: String = "Unknown"
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.version = version
        self.isEnabled = isEnabled
        self.contentScripts = contentScripts
        self.permissions = permissions
        self.iconName = iconName
        self.author = author
    }
}

// MARK: - Extension Script
struct ExtensionScript: Identifiable, Codable {
    let id: UUID
    var code: String
    var injectionTime: ScriptInjectionTime
    var matchPatterns: [String] // URL patterns like "*://*.youtube.com/*"
    var mainFrameOnly: Bool
    
    init(
        id: UUID = UUID(),
        code: String,
        injectionTime: ScriptInjectionTime = .atDocumentEnd,
        matchPatterns: [String] = ["*"],
        mainFrameOnly: Bool = false
    ) {
        self.id = id
        self.code = code
        self.injectionTime = injectionTime
        self.matchPatterns = matchPatterns
        self.mainFrameOnly = mainFrameOnly
    }
}

enum ScriptInjectionTime: String, Codable {
    case atDocumentStart
    case atDocumentEnd
}

// MARK: - Extension Manager
class ExtensionManager: ObservableObject {
    @Published var extensions: [BrowserExtension] = []
    @Published var showExtensionStore: Bool = false
    
    private let storageKey = "cyber_browser_extensions"
    
    init() {
        loadExtensions()
        if extensions.isEmpty {
            loadBuiltInExtensions()
        }
    }
    
    // MARK: - Built-in Extensions
    func loadBuiltInExtensions() {
        let builtIns: [BrowserExtension] = [
            // Dark Mode Extension
            BrowserExtension(
                name: "Karanlık Mod Zorlama",
                description: "Tüm web sitelerini karanlık temaya çevirir",
                version: "1.0",
                isEnabled: false,
                contentScripts: [
                    ExtensionScript(
                        code: """
                        (function() {
                            const style = document.createElement('style');
                            style.textContent = `
                                html {
                                    filter: invert(1) hue-rotate(180deg) !important;
                                    background: #000 !important;
                                }
                                img, video, canvas, svg, [style*="background-image"] {
                                    filter: invert(1) hue-rotate(180deg) !important;
                                }
                            `;
                            document.documentElement.appendChild(style);
                        })();
                        """,
                        injectionTime: .atDocumentStart,
                        matchPatterns: ["*"]
                    )
                ],
                permissions: ["all_urls"],
                iconName: "moon.fill",
                author: "CyberBrowser"
            ),
            
            // Reader Mode Extension
            BrowserExtension(
                name: "Okuyucu Modu",
                description: "Sayfaları temiz, okunabilir bir formata dönüştürür",
                version: "1.0",
                isEnabled: false,
                contentScripts: [
                    ExtensionScript(
                        code: """
                        (function() {
                            window.cyberReaderMode = function() {
                                const article = document.querySelector('article') || document.querySelector('main') || document.querySelector('.content') || document.body;
                                const title = document.title;
                                const content = article.innerHTML;
                                
                                document.body.innerHTML = `
                                    <div style="max-width:700px; margin:40px auto; padding:20px; font-family: Georgia, serif; line-height:1.8; color:#e0e0e0; background:#111;">
                                        <h1 style="color:#FACC15; font-size:28px; border-bottom:2px solid #FACC15; padding-bottom:10px;">${title}</h1>
                                        <div style="font-size:18px;">${content}</div>
                                    </div>
                                `;
                                
                                // Clean up non-text elements
                                document.querySelectorAll('script, style, iframe, nav, footer, header, aside, .ad, .ads, .sidebar').forEach(el => el.remove());
                                
                                window.webkit.messageHandlers.extensionAction.postMessage({
                                    action: 'readerMode',
                                    status: 'activated'
                                });
                            };
                        })();
                        """,
                        injectionTime: .atDocumentEnd
                    )
                ],
                permissions: ["all_urls"],
                iconName: "book.fill",
                author: "CyberBrowser"
            ),
            
            // Privacy Shield Extension
            BrowserExtension(
                name: "Gizlilik Kalkanı",
                description: "Parmak izi takibini ve canvas fingerprinting'i engeller",
                version: "1.0",
                isEnabled: true,
                contentScripts: [
                    ExtensionScript(
                        code: """
                        (function() {
                            'use strict';
                            
                            // Block canvas fingerprinting
                            const origToDataURL = HTMLCanvasElement.prototype.toDataURL;
                            HTMLCanvasElement.prototype.toDataURL = function(type) {
                                if (this.width > 16 && this.height > 16) {
                                    const ctx = this.getContext('2d');
                                    if (ctx) {
                                        const imageData = ctx.getImageData(0, 0, this.width, this.height);
                                        for (let i = 0; i < imageData.data.length; i += 4) {
                                            imageData.data[i] ^= 1; // Tiny noise
                                        }
                                        ctx.putImageData(imageData, 0, 0);
                                    }
                                }
                                return origToDataURL.apply(this, arguments);
                            };
                            
                            // Block WebGL fingerprinting
                            const getParameterOrig = WebGLRenderingContext.prototype.getParameter;
                            WebGLRenderingContext.prototype.getParameter = function(param) {
                                // RENDERER, VENDOR
                                if (param === 0x1F01 || param === 0x1F00) {
                                    return 'CyberBrowser WebGL';
                                }
                                return getParameterOrig.apply(this, arguments);
                            };
                            
                            // Block navigator enumeration
                            Object.defineProperty(navigator, 'plugins', { get: () => [] });
                            Object.defineProperty(navigator, 'languages', { get: () => ['tr-TR', 'tr', 'en-US', 'en'] });
                            
                            // Block battery API
                            if (navigator.getBattery) {
                                navigator.getBattery = () => Promise.reject('Blocked by CyberBrowser');
                            }
                            
                            console.log('[CyberBrowser] Privacy Shield active');
                        })();
                        """,
                        injectionTime: .atDocumentStart,
                        matchPatterns: ["*"]
                    )
                ],
                permissions: ["all_urls"],
                iconName: "shield.lefthalf.filled",
                author: "CyberBrowser"
            ),
            
            // Auto-Cookie Dismiss
            BrowserExtension(
                name: "Çerez Uyarısı Engelleyici",
                description: "Çerez onay pop-up'larını otomatik kapatır",
                version: "1.0",
                isEnabled: true,
                contentScripts: [
                    ExtensionScript(
                        code: """
                        (function() {
                            'use strict';
                            
                            const cookieSelectors = [
                                '#onetrust-consent-sdk', '#onetrust-banner-sdk',
                                '.cookie-consent', '.cookie-banner', '.cookie-notice',
                                '#cookie-notice', '#cookie-law-info-bar',
                                '.cc-banner', '.cc-window', '#CybotCookiebotDialog',
                                '.js-cookie-consent', '#gdpr-cookie-notice',
                                '.cookie-popup', '#cookie-popup', '.cookie-modal',
                                '[class*="cookie-consent"]', '[class*="cookie-banner"]',
                                '[id*="cookie-consent"]', '[id*="cookie-banner"]',
                                '.consent-banner', '#consent-banner',
                                '.gdpr-banner', '#gdpr-banner',
                                '.privacy-banner', '#privacy-notice'
                            ];
                            
                            function dismissCookies() {
                                cookieSelectors.forEach(selector => {
                                    document.querySelectorAll(selector).forEach(el => {
                                        el.style.display = 'none';
                                        el.remove();
                                    });
                                });
                                
                                // Click accept/dismiss buttons
                                const acceptBtns = document.querySelectorAll(
                                    '[class*="cookie"] button, [id*="cookie"] button, ' +
                                    '.cc-accept, .cc-dismiss, .cc-allow, ' +
                                    '#onetrust-accept-btn-handler, ' +
                                    '#CybotCookiebotDialogBodyLevelButtonLevelOptinAllowAll, ' +
                                    'button[data-cookie-accept], button[data-gdpr-accept]'
                                );
                                acceptBtns.forEach(btn => btn.click());
                                
                                // Remove overlay
                                document.querySelectorAll('.cookie-overlay, .consent-overlay, .gdpr-overlay').forEach(el => el.remove());
                                
                                // Restore scroll
                                document.body.style.overflow = '';
                                document.documentElement.style.overflow = '';
                            }
                            
                            // Run on load and observe
                            if (document.readyState === 'loading') {
                                document.addEventListener('DOMContentLoaded', () => setTimeout(dismissCookies, 500));
                            } else {
                                setTimeout(dismissCookies, 500);
                            }
                            
                            // Watch for late-loading consent dialogs
                            const observer = new MutationObserver(() => setTimeout(dismissCookies, 300));
                            observer.observe(document.documentElement, { childList: true, subtree: true });
                            
                            // Stop observing after 10 seconds
                            setTimeout(() => observer.disconnect(), 10000);
                            
                            console.log('[CyberBrowser] Cookie dismiss active');
                        })();
                        """,
                        injectionTime: .atDocumentEnd,
                        matchPatterns: ["*"]
                    )
                ],
                permissions: ["all_urls"],
                iconName: "xmark.shield.fill",
                author: "CyberBrowser"
            ),
            
            // YouTube Enhancer
            BrowserExtension(
                name: "YouTube Geliştirici",
                description: "YouTube'da reklam atlama, otomatik HD kalite ve mini oynatıcı",
                version: "1.0",
                isEnabled: true,
                contentScripts: [
                    ExtensionScript(
                        code: """
                        (function() {
                            'use strict';
                            
                            if (!window.location.hostname.includes('youtube.com')) return;
                            
                            // Auto HD Quality
                            function setHDQuality() {
                                const player = document.querySelector('#movie_player');
                                if (player && player.setPlaybackQualityRange) {
                                    player.setPlaybackQualityRange('hd1080');
                                }
                            }
                            
                            // Auto-skip ads
                            function skipAds() {
                                const skipBtn = document.querySelector(
                                    '.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button'
                                );
                                if (skipBtn) skipBtn.click();
                                
                                // Remove overlay ads
                                document.querySelectorAll(
                                    '.ytp-ad-overlay-container, .ytp-ad-text-overlay'
                                ).forEach(el => el.remove());
                                
                                // Speed through unskippable ads
                                const video = document.querySelector('video');
                                if (video && document.querySelector('.ad-showing')) {
                                    video.currentTime = video.duration || 0;
                                }
                            }
                            
                            // Remove suggestions overlay
                            function cleanUI() {
                                document.querySelectorAll(
                                    '#masthead-ad, #player-ads, .ytd-promoted-sparkles-web-renderer, ' +
                                    '.ytd-display-ad-renderer, .ytd-companion-slot-renderer, ' +
                                    '#related ytd-promoted-sparkles-web-renderer'
                                ).forEach(el => el.remove());
                            }
                            
                            setInterval(skipAds, 500);
                            setInterval(cleanUI, 2000);
                            setTimeout(setHDQuality, 3000);
                            
                            console.log('[CyberBrowser] YouTube Enhancer active');
                        })();
                        """,
                        injectionTime: .atDocumentEnd,
                        matchPatterns: ["*://*.youtube.com/*"]
                    )
                ],
                permissions: ["*://*.youtube.com/*"],
                iconName: "play.rectangle.fill",
                author: "CyberBrowser"
            )
        ]
        
        extensions = builtIns
        saveExtensions()
    }
    
    // MARK: - Extension Management
    func toggleExtension(id: UUID) {
        if let index = extensions.firstIndex(where: { $0.id == id }) {
            extensions[index].isEnabled.toggle()
            saveExtensions()
        }
    }
    
    func addExtension(_ ext: BrowserExtension) {
        extensions.append(ext)
        saveExtensions()
    }
    
    func removeExtension(id: UUID) {
        extensions.removeAll(where: { $0.id == id })
        saveExtensions()
    }
    
    // MARK: - Add Extension from User Script (Paste Code)
    func addUserScript(name: String, code: String, injectionTime: ScriptInjectionTime = .atDocumentEnd) {
        let ext = BrowserExtension(
            name: name,
            description: "Kullanıcı tarafından eklenen script",
            version: "1.0",
            isEnabled: true,
            contentScripts: [
                ExtensionScript(
                    code: code,
                    injectionTime: injectionTime,
                    matchPatterns: ["*"]
                )
            ],
            permissions: ["all_urls"],
            iconName: "doc.text",
            author: "Kullanıcı"
        )
        addExtension(ext)
    }
    
    // MARK: - Import Extension from manifest.json (WebExtension format)
    func importFromManifest(jsonData: Data) -> Bool {
        guard let manifest = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return false
        }
        
        let name = manifest["name"] as? String ?? "İsimsiz Uzantı"
        let description = manifest["description"] as? String ?? ""
        let version = manifest["version"] as? String ?? "1.0"
        
        var scripts: [ExtensionScript] = []
        
        // Parse content_scripts from manifest
        if let contentScripts = manifest["content_scripts"] as? [[String: Any]] {
            for cs in contentScripts {
                let matches = cs["matches"] as? [String] ?? ["*"]
                let jsFiles = cs["js"] as? [String] ?? []
                let runAt = cs["run_at"] as? String ?? "document_end"
                
                let injTime: ScriptInjectionTime = runAt == "document_start" ? .atDocumentStart : .atDocumentEnd
                
                // Note: In a full implementation, JS file contents would be read from
                // a bundled directory. Here we note the file paths.
                for jsFile in jsFiles {
                    scripts.append(ExtensionScript(
                        code: "// Loaded from: \(jsFile)\n// Content would be loaded from extension bundle",
                        injectionTime: injTime,
                        matchPatterns: matches
                    ))
                }
            }
        }
        
        // Parse background scripts
        if let background = manifest["background"] as? [String: Any] {
            if let bgScripts = background["scripts"] as? [String] {
                for script in bgScripts {
                    scripts.append(ExtensionScript(
                        code: "// Background script: \(script)",
                        injectionTime: .atDocumentStart,
                        matchPatterns: ["*"]
                    ))
                }
            }
        }
        
        let ext = BrowserExtension(
            name: name,
            description: description,
            version: version,
            isEnabled: true,
            contentScripts: scripts,
            permissions: manifest["permissions"] as? [String] ?? [],
            iconName: "puzzlepiece.extension.fill",
            author: manifest["author"] as? String ?? "Bilinmeyen"
        )
        
        addExtension(ext)
        return true
    }
    
    // MARK: - Generate WKUserScripts for active extensions
    func activeUserScripts(for url: URL? = nil) -> [WKUserScript] {
        var scripts: [WKUserScript] = []
        
        for ext in extensions where ext.isEnabled {
            for cs in ext.contentScripts {
                // Check if URL matches the pattern
                if let url = url, !matchesPattern(url: url, patterns: cs.matchPatterns) {
                    continue
                }
                
                let injTime: WKUserScriptInjectionTime = cs.injectionTime == .atDocumentStart
                    ? .atDocumentStart
                    : .atDocumentEnd
                
                scripts.append(WKUserScript(
                    source: cs.code,
                    injectionTime: injTime,
                    forMainFrameOnly: cs.mainFrameOnly
                ))
            }
        }
        
        return scripts
    }
    
    // MARK: - URL Pattern Matching
    private func matchesPattern(url: URL, patterns: [String]) -> Bool {
        let urlString = url.absoluteString.lowercased()
        
        for pattern in patterns {
            if pattern == "*" || pattern == "<all_urls>" {
                return true
            }
            
            // Convert glob pattern to regex-ish matching
            let cleanedPattern = pattern
                .replacingOccurrences(of: "*://", with: "")
                .replacingOccurrences(of: "*.", with: "")
                .replacingOccurrences(of: "/*", with: "")
                .replacingOccurrences(of: "*", with: "")
                .lowercased()
            
            if !cleanedPattern.isEmpty && urlString.contains(cleanedPattern) {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Persistence
    func saveExtensions() {
        if let data = try? JSONEncoder().encode(extensions) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    func loadExtensions() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([BrowserExtension].self, from: data) else {
            return
        }
        extensions = decoded
    }
}
