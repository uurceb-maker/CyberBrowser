import Foundation
import WebKit
import Combine

// MARK: - Ad Block Engine v3.0 — Real EasyList Integration
class AdBlockEngine: ObservableObject {
    
    // MARK: - Published State
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "adBlockEnabled")
            needsRecompile = (isEnabled != oldValue)
        }
    }
    @Published var blockedAdsCount: Int = 0
    @Published var lastBlockedDomain: String = ""
    @Published var filterInfo: String = "Yükleniyor..."
    
    var needsRecompile: Bool = false
    
    // MARK: - Compiled Rules Storage
    private var compiledRuleLists: [WKContentRuleList] = []
    private var isCompiling = false
    
    // MARK: - Domain Set for decidePolicyFor fallback (Layer 2)
    private let blockedDomainKeywords: Set<String> = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com",
        "google-analytics.com", "googletagmanager.com", "googletagservices.com",
        "adnxs.com", "adsrvr.org", "advertising.com", "adform.net",
        "taboola.com", "outbrain.com", "criteo.com", "criteo.net",
        "moatads.com", "amazon-adsystem.com", "facebook.net", "fbcdn.net",
        "rubiconproject.com", "pubmatic.com", "openx.net", "casalemedia.com",
        "indexwwi.com", "bidswitch.net", "smartadserver.com", "adcolony.com",
        "unity3d.com", "applovin.com", "mopub.com", "vungle.com",
        "admob.com", "chartboost.com", "inmobi.com", "ironsrc.com",
        "smaato.net", "tapjoy.com", "fyber.com", "digitalturbine.com",
        "ad.doubleclick.net", "pagead2.googlesyndication.com",
        "securepubads.g.doubleclick.net", "tpc.googlesyndication.com",
        "stats.g.doubleclick.net", "cm.g.doubleclick.net",
        "ade.googlesyndication.com", "s0.2mdn.net",
        "cdn.taboola.com", "trc.taboola.com", "nr-data.net",
        "widgets.outbrain.com", "log.outbrain.com",
        "static.ads-twitter.com", "analytics.twitter.com",
        "pixel.facebook.com", "an.facebook.com",
        "bid.g.doubleclick.net", "ad.atdmt.com",
        "adserver.yahoo.com", "ads.yahoo.com",
        "yieldmanager.com", "overture.com", "gemini.yahoo.com",
        "ads.pubmatic.com", "image2.pubmatic.com",
        "gads.pubmatic.com", "hbopenbid.pubmatic.com",
        "track.adform.net", "serving.adform.net",
        "creative.adform.net", "a.adform.net"
    ]
    
    // MARK: - EasyList URLs
    private let easyListURL = "https://easylist-downloads.adblockplus.org/easylist_content_blocker.json"
    private let cacheFileName = "easylist_content_blocker.json"
    private let cacheMaxAgeDays: Double = 7
    private let maxRulesPerChunk = 50000 // Safari supports up to 150K per list
    
    // MARK: - init
    init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "adBlockEnabled") as? Bool ?? true
    }
    
    // MARK: - Compile Rules (Main Entry Point)
    func compileRules(completion: @escaping () -> Void) {
        guard isEnabled else {
            filterInfo = "Devre dışı"
            compiledRuleLists = []
            completion()
            return
        }
        
        guard !isCompiling else {
            completion()
            return
        }
        isCompiling = true
        filterInfo = "Kurallar yükleniyor..."
        
        // Try to load from cache first, download if needed
        loadEasyListJSON { [weak self] jsonString in
            guard let self = self, let jsonString = jsonString else {
                print("[AdBlock] ❌ Failed to load EasyList — using embedded fallback")
                self?.compileEmbeddedFallback(completion: completion)
                return
            }
            
            self.compileJSONRules(jsonString, completion: completion)
        }
    }
    
    // MARK: - Load EasyList JSON (Cache or Download)
    private func loadEasyListJSON(completion: @escaping (String?) -> Void) {
        let cacheURL = getCacheFileURL()
        
        // Check if cache exists and is fresh
        if let cacheURL = cacheURL,
           FileManager.default.fileExists(atPath: cacheURL.path) {
            
            if let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
               let modDate = attrs[.modificationDate] as? Date {
                let age = Date().timeIntervalSince(modDate)
                let maxAge = cacheMaxAgeDays * 24 * 60 * 60
                
                if age < maxAge {
                    // Cache is fresh — use it
                    print("[AdBlock] 📦 Loading EasyList from cache (age: \(Int(age/3600))h)")
                    if let data = try? Data(contentsOf: cacheURL),
                       let json = String(data: data, encoding: .utf8) {
                        completion(json)
                        return
                    }
                }
            }
        }
        
        // Download fresh copy
        downloadEasyList(completion: completion)
    }
    
    // MARK: - Download EasyList
    private func downloadEasyList(completion: @escaping (String?) -> Void) {
        guard let url = URL(string: easyListURL) else {
            completion(nil)
            return
        }
        
        print("[AdBlock] ⬇️ Downloading EasyList from server...")
        DispatchQueue.main.async {
            self.filterInfo = "EasyList indiriliyor..."
        }
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("[AdBlock] ❌ Download failed: \(error.localizedDescription)")
                // Try to use stale cache
                if let cacheURL = self.getCacheFileURL(),
                   let data = try? Data(contentsOf: cacheURL),
                   let json = String(data: data, encoding: .utf8) {
                    print("[AdBlock] 📦 Using stale cache as fallback")
                    completion(json)
                } else {
                    completion(nil)
                }
                return
            }
            
            guard let data = data,
                  let json = String(data: data, encoding: .utf8) else {
                print("[AdBlock] ❌ Invalid response data")
                completion(nil)
                return
            }
            
            // Save to cache
            if let cacheURL = self.getCacheFileURL() {
                try? data.write(to: cacheURL)
                print("[AdBlock] 💾 Saved EasyList to cache (\(data.count / 1024)KB)")
            }
            
            completion(json)
        }
        task.resume()
    }
    
    // MARK: - Compile JSON Rules
    private func compileJSONRules(_ jsonString: String, completion: @escaping () -> Void) {
        // Parse to count rules
        guard let data = jsonString.data(using: .utf8),
              let allRules = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            print("[AdBlock] ❌ Failed to parse EasyList JSON")
            compileEmbeddedFallback(completion: completion)
            return
        }
        
        let totalRules = allRules.count
        print("[AdBlock] 📋 EasyList loaded: \(totalRules) rules total")
        
        // Chunk the rules
        let chunks = stride(from: 0, to: totalRules, by: maxRulesPerChunk).map { start in
            Array(allRules[start..<min(start + maxRulesPerChunk, totalRules)])
        }
        
        print("[AdBlock] 📦 Split into \(chunks.count) chunks of max \(maxRulesPerChunk) rules")
        
        // Compile each chunk
        let store = WKContentRuleListStore.default()
        var compiled: [WKContentRuleList] = []
        let group = DispatchGroup()
        
        for (index, chunk) in chunks.enumerated() {
            group.enter()
            
            guard let chunkData = try? JSONSerialization.data(withJSONObject: chunk),
                  let chunkJSON = String(data: chunkData, encoding: .utf8) else {
                print("[AdBlock] ❌ Failed to serialize chunk \(index)")
                group.leave()
                continue
            }
            
            let identifier = "easylist_chunk_\(index)"
            store?.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: chunkJSON) { ruleList, error in
                if let ruleList = ruleList {
                    compiled.append(ruleList)
                    print("[AdBlock] ✅ Compiled chunk \(index): \(chunk.count) rules")
                } else if let error = error {
                    print("[AdBlock] ❌ Chunk \(index) compilation failed: \(error.localizedDescription)")
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.compiledRuleLists = compiled
            self.isCompiling = false
            self.needsRecompile = false
            
            let totalCompiled = compiled.count
            self.filterInfo = "\(totalRules) kural — \(totalCompiled)/\(chunks.count) grup aktif"
            
            print("[AdBlock] 🎯 Compilation complete: \(compiled.count)/\(chunks.count) chunks compiled successfully")
            completion()
        }
    }
    
    // MARK: - Embedded Fallback (if download fails)
    private func compileEmbeddedFallback(completion: @escaping () -> Void) {
        let fallbackRules = Self.embeddedFallbackRules
        
        let store = WKContentRuleListStore.default()
        store?.compileContentRuleList(forIdentifier: "embedded_fallback", encodedContentRuleList: fallbackRules) { [weak self] ruleList, error in
            DispatchQueue.main.async {
                if let ruleList = ruleList {
                    self?.compiledRuleLists = [ruleList]
                    self?.filterInfo = "Yedek kurallar aktif"
                    print("[AdBlock] ✅ Embedded fallback compiled")
                } else {
                    self?.compiledRuleLists = []
                    self?.filterInfo = "Kurallar derlenemedi"
                    print("[AdBlock] ❌ Even fallback failed: \(error?.localizedDescription ?? "unknown")")
                }
                self?.isCompiling = false
                self?.needsRecompile = false
                completion()
            }
        }
    }
    
    // MARK: - Apply Rules to WKUserContentController
    func applyRules(to controller: WKUserContentController) {
        // Remove old rules
        controller.removeAllContentRuleLists()
        
        guard isEnabled else { return }
        
        // Add all compiled rule lists
        for ruleList in compiledRuleLists {
            controller.add(ruleList)
        }
        
        print("[AdBlock] 📎 Applied \(compiledRuleLists.count) rule list(s) to WebView")
        
        // Layer 3: Add cosmetic filter JS
        let cosmeticScript = WKUserScript(
            source: Self.cosmeticFilterScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false // Run in all frames to catch iframe ads
        )
        controller.addUserScript(cosmeticScript)
        
        // YouTube ad skip
        let ytScript = WKUserScript(
            source: Self.youtubeAdSkipScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        controller.addUserScript(ytScript)
    }
    
    // MARK: - Layer 2: URL Blocking (decidePolicyFor fallback)
    func shouldBlockURL(_ url: URL) -> Bool {
        guard isEnabled else { return false }
        guard let host = url.host?.lowercased() else { return false }
        
        for keyword in blockedDomainKeywords {
            if host.contains(keyword) {
                return true
            }
        }
        return false
    }
    
    // MARK: - Handle Blocked Ad
    func handleBlockedAd(count: Int, domain: String) {
        DispatchQueue.main.async {
            self.blockedAdsCount += count
            if !domain.isEmpty {
                self.lastBlockedDomain = domain
            }
        }
    }
    
    // MARK: - Cache Path
    private func getCacheFileURL() -> URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return docs.appendingPathComponent(cacheFileName)
    }
    
    // MARK: - Embedded Fallback Rules (minimal, pre-validated)
    // These are real Safari Content Blocker JSON — tested and known to compile
    static let embeddedFallbackRules: String = """
    [
        {"trigger":{"url-filter":"^https?://.*doubleclick\\\\.net"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*googlesyndication\\\\.com"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*googleadservices\\\\.com"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*google-analytics\\\\.com"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*googletagmanager\\\\.com"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*adnxs\\\\.com"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*adsrvr\\\\.org"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*taboola\\\\.com"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*outbrain\\\\.com"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*criteo\\\\.(com|net)"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*moatads\\\\.com"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*amazon-adsystem\\\\.com"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*rubiconproject\\\\.com"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*pubmatic\\\\.com"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*openx\\\\.net"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*casalemedia\\\\.com"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*smartadserver\\\\.com"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*bidswitch\\\\.net"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*admob\\\\.com"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*2mdn\\\\.net"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*advertising\\\\.com"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*adform\\\\.net"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*nr-data\\\\.net"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*yieldmanager\\\\.com"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*adcolony\\\\.com"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*applovin\\\\.com"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*vungle\\\\.com"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*chartboost\\\\.com"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*inmobi\\\\.com"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://.*smaato\\\\.net"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":".adsbygoogle"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"[id^=\\"google_ads\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"[id^=\\"div-gpt-ad\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"[class*=\\"ad-container\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"[class*=\\"ad-wrapper\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"[class*=\\"ad-banner\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"[class*=\\"sponsored\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"ins.adsbygoogle"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"amp-ad"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"AMP-AD"}}
    ]
    """
    
    // MARK: - Layer 3: Cosmetic Filter Script
    static let cosmeticFilterScript: String = """
    (function() {
        'use strict';
        const selectors = [
            '.adsbygoogle', 'ins.adsbygoogle', '[id^="google_ads"]', '[id^="div-gpt-ad"]',
            '[class*="ad-container"]', '[class*="ad-wrapper"]', '[class*="ad-banner"]',
            '[class*="adunit"]', '[class*="ad-slot"]', '[class*="ad_unit"]',
            '[class*="sponsored"]', '[class*="ad-placement"]',
            'iframe[src*="doubleclick"]', 'iframe[src*="googlesyndication"]',
            'iframe[src*="adnxs"]', 'iframe[src*="taboola"]',
            '[id*="taboola"]', '[class*="taboola"]',
            '[id*="outbrain"]', '[class*="outbrain"]',
            '.trc_related_container', '#taboola-below-article',
            '#cookie-banner', '#cookie-notice', '[class*="cookie-consent"]',
            '[class*="cookie-banner"]', '[class*="cookie-notice"]',
            '[id*="cookie-popup"]', '[class*="gdpr"]',
            '[id*="consent-banner"]', '[class*="consent-banner"]'
        ];
        
        let hiddenCount = 0;
        
        function hideElements() {
            const joined = selectors.join(',');
            document.querySelectorAll(joined).forEach(el => {
                if (el.style.display !== 'none') {
                    el.style.setProperty('display', 'none', 'important');
                    hiddenCount++;
                }
            });
            if (hiddenCount > 0 && window.webkit && window.webkit.messageHandlers.adBlocked) {
                window.webkit.messageHandlers.adBlocked.postMessage({count: hiddenCount, url: location.hostname});
                hiddenCount = 0;
            }
        }
        
        // Run immediately
        hideElements();
        
        // Run on DOMContentLoaded
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', hideElements);
        }
        
        // Bounded MutationObserver — max 30 seconds
        let checkCount = 0;
        const maxChecks = 100;
        const observer = new MutationObserver(() => {
            checkCount++;
            if (checkCount >= maxChecks) {
                observer.disconnect();
                return;
            }
            hideElements();
        });
        
        observer.observe(document.documentElement, {
            childList: true,
            subtree: true
        });
        
        setTimeout(() => observer.disconnect(), 30000);
    })();
    """
    
    // MARK: - YouTube Ad Skip Script
    static let youtubeAdSkipScript: String = """
    (function() {
        'use strict';
        if (!location.hostname.includes('youtube.com')) return;
        
        const skipInterval = setInterval(() => {
            // Click skip button
            const skipBtn = document.querySelector('.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern, [class*="skip-button"]');
            if (skipBtn) { skipBtn.click(); return; }
            
            // Speed through unskippable ads
            const video = document.querySelector('video');
            const adOverlay = document.querySelector('.ad-showing, .ytp-ad-player-overlay');
            if (video && adOverlay) {
                video.currentTime = video.duration || 999;
                video.playbackRate = 16;
            }
            
            // Remove ad overlays
            document.querySelectorAll('.ytp-ad-overlay-container, .ytp-ad-text-overlay, #player-ads').forEach(el => {
                el.remove();
            });
        }, 500);
        
        // Stop after 2 minutes
        setTimeout(() => clearInterval(skipInterval), 120000);
    })();
    """
}
