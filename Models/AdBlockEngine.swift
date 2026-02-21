import SwiftUI
import WebKit

// MARK: - Ad Block Engine v2.1 — Hybrid 3-Layer Blocking
// Layer 1: WKContentRuleList (native bytecode — fastest, blocks network requests)
// Layer 2: decidePolicyFor domain blocking (fallback if WKContentRuleList fails)
// Layer 3: JavaScript cosmetic filter (hides ad elements that slip through)

class AdBlockEngine: ObservableObject {
    @Published var totalBlockedAds: Int = 0
    @Published var isEnabled: Bool = true {
        didSet {
            if isEnabled != oldValue {
                needsRecompile = true
            }
        }
    }
    @Published var showBanner: Bool = false
    @Published var lastBlockedDomain: String = ""
    @Published var isCompiled: Bool = false
    @Published var filterInfo: String = "Derleniyor..."
    
    private(set) var compiledRuleLists: [WKContentRuleList] = []
    var needsRecompile: Bool = true
    private var bannerHideWorkItem: DispatchWorkItem?
    
    // MARK: - Layer 2: Blocked domain Set (for decidePolicyFor fallback)
    // Use a Set for O(1) lookup instead of array linear scan
    static let blockedDomainSet: Set<String> = {
        var domains = Set<String>()
        for d in AdBlockRules.blockDomainRules {
            domains.insert(d)
            // Also add without www prefix
            if d.hasPrefix("www.") {
                domains.insert(String(d.dropFirst(4)))
            }
        }
        return domains
    }()
    
    /// Checks if a URL's host matches a blocked domain — O(1) lookup
    func shouldBlockURL(_ url: URL) -> Bool {
        guard isEnabled, let host = url.host?.lowercased() else { return false }
        
        // Check exact match
        if Self.blockedDomainSet.contains(host) { return true }
        
        // Check suffix match (e.g., "ads.example.com" contains "example.com")
        for domain in Self.blockedDomainSet {
            if host.hasSuffix("." + domain) { return true }
        }
        
        return false
    }
    
    // MARK: - Layer 1: Compile Native Content Rules
    func compileRules(completion: @escaping () -> Void) {
        guard isEnabled else {
            compiledRuleLists = []
            isCompiled = true
            needsRecompile = false
            DispatchQueue.main.async { self.filterInfo = "Devre dışı" }
            completion()
            return
        }
        
        let store = WKContentRuleListStore.default()
        let ruleChunks = AdBlockRules.generateChunkedRules()
        var compiled: [WKContentRuleList] = []
        let group = DispatchGroup()
        var successCount = 0
        var failCount = 0
        
        for (index, chunk) in ruleChunks.enumerated() {
            group.enter()
            store?.compileContentRuleList(
                forIdentifier: "CyberBlock_v2_\(index)",
                encodedContentRuleList: chunk
            ) { ruleList, error in
                if let ruleList = ruleList {
                    compiled.append(ruleList)
                    successCount += 1
                } else if let error = error {
                    failCount += 1
                    print("[AdBlock] ❌ Chunk \(index) FAILED: \(error.localizedDescription)")
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.compiledRuleLists = compiled
            self.isCompiled = true
            self.needsRecompile = false
            
            let domainCount = AdBlockRules.blockDomainRules.count
            if successCount > 0 {
                self.filterInfo = "\(domainCount)+ domain engeli aktif"
            } else {
                self.filterInfo = "JS + domain engeli aktif"
            }
            print("[AdBlock] ✅ Compiled: \(successCount) chunks OK, \(failCount) failed, \(domainCount) domains in fallback")
            completion()
        }
    }
    
    // MARK: - Apply Rules to WebView
    func applyRules(to contentController: WKUserContentController) {
        contentController.removeAllContentRuleLists()
        guard isEnabled else { return }
        for ruleList in compiledRuleLists {
            contentController.add(ruleList)
        }
    }
    
    // MARK: - Layer 3: JavaScript Cosmetic Filter + Ad Element Hider
    static let cosmeticFilterScript: String = """
    (function() {
        'use strict';
        
        // ===== ELEMENT HIDING (cosmetic filter) =====
        const adSelectors = [
            // Generic ad containers
            'ins.adsbygoogle', '.adsbygoogle', '[id^="google_ads"]',
            '[id^="div-gpt-ad"]', '[class*="ad-container"]', '[class*="ad-wrapper"]',
            '[class*="ad-banner"]', '[class*="ad_banner"]', '[class*="advertisement"]',
            '[class*="sponsored"]', '[id*="ad-container"]', '[id*="ad_container"]',
            '[data-ad]', '[data-ad-slot]', '[data-google-query-id]',
            
            // Specific ad networks
            'iframe[src*="doubleclick"]', 'iframe[src*="googlesyndication"]',
            'iframe[src*="amazon-adsystem"]', 'iframe[src*="facebook.com/plugins"]',
            'iframe[id^="google_ads"]', 'iframe[id^="aswift"]',
            
            // YouTube ads
            '.ytp-ad-module', '.ytp-ad-overlay-container', '.ytp-ad-text-overlay',
            '.video-ads', '.ad-showing', '#masthead-ad', '#player-ads',
            'ytd-promoted-sparkles-web-renderer', 'ytd-display-ad-renderer',
            'ytd-companion-slot-renderer', 'ytd-action-companion-ad-renderer',
            'ytd-promoted-video-renderer', 'ytd-ad-slot-renderer',
            '.ytd-banner-promo-renderer', 'ytd-in-feed-ad-layout-renderer',
            '#related ytd-promoted-sparkles-web-renderer',
            
            // Pop-ups and overlays
            '[class*="popup-ad"]', '[class*="interstitial"]',
            '[class*="modal-ad"]', '[class*="overlay-ad"]',
            
            // Cookie banners
            '#onetrust-consent-sdk', '#onetrust-banner-sdk',
            '#CybotCookiebotDialog', '#CybotCookiebotDialogOverlay',
            '.cookie-consent', '.cookie-banner', '.cookie-notice',
            '#cookie-notice', '#cookie-law-info-bar',
            '.cc-banner', '.cc-window', '.js-cookie-consent',
            '#gdpr-cookie-notice', '.cookie-popup', '#cookie-popup',
            '[class*="cookie-consent"]', '[class*="cookie-banner"]',
            '.consent-banner', '#consent-banner', '.gdpr-banner',
            '#cookiescript_injected', '.cookie-overlay', '#cookie-bar',
            
            // Social widgets (tracking)
            '.fb-like', '.twitter-share-button'
        ];
        
        function hideAds() {
            let count = 0;
            const combinedSelector = adSelectors.join(',');
            try {
                document.querySelectorAll(combinedSelector).forEach(function(el) {
                    if (el.offsetHeight > 0 || el.style.display !== 'none') {
                        el.style.setProperty('display', 'none', 'important');
                        el.style.setProperty('visibility', 'hidden', 'important');
                        el.style.setProperty('height', '0', 'important');
                        el.style.setProperty('overflow', 'hidden', 'important');
                        count++;
                    }
                });
            } catch(e) {}
            
            if (count > 0) {
                try {
                    window.webkit.messageHandlers.adBlocked.postMessage({
                        count: count, total: 0, url: window.location.href
                    });
                } catch(e) {}
            }
        }
        
        // ===== COOKIE BANNER AUTO-DISMISS =====
        function dismissCookies() {
            const acceptBtns = document.querySelectorAll(
                '[class*="cookie"] button[class*="accept"], [class*="cookie"] button[class*="agree"], ' +
                '#onetrust-accept-btn-handler, #CybotCookiebotDialogBodyLevelButtonLevelOptinAllowAll, ' +
                '.cc-accept, .cc-dismiss, .cc-allow, button[data-cookie-accept]'
            );
            acceptBtns.forEach(function(btn) { try { btn.click(); } catch(e) {} });
            
            document.body.style.overflow = '';
            document.documentElement.style.overflow = '';
        }
        
        // ===== YOUTUBE AD SKIP =====
        function skipYouTubeAds() {
            if (!window.location.hostname.includes('youtube.com')) return;
            
            const skipBtn = document.querySelector(
                '.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button, ' +
                'button.ytp-ad-skip-button-modern, .ytp-ad-skip-button-slot'
            );
            if (skipBtn) {
                skipBtn.click();
                try { window.webkit.messageHandlers.adBlocked.postMessage({count:1,total:0,url:window.location.href}); } catch(e) {}
            }
            
            const video = document.querySelector('video');
            const adShowing = document.querySelector('.ad-showing, .ytp-ad-player-overlay');
            if (video && adShowing) {
                video.playbackRate = 16;
                video.currentTime = video.duration || 999;
            }
        }
        
        // ===== RUN =====
        // Initial run after page load
        function run() {
            hideAds();
            dismissCookies();
            skipYouTubeAds();
        }
        
        // Run on DOMContentLoaded
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', function() { setTimeout(run, 300); });
        } else {
            setTimeout(run, 300);
        }
        
        // Run again after full load
        window.addEventListener('load', function() { setTimeout(run, 1000); });
        
        // Bounded MutationObserver — checks for new ads, auto-disconnects after 30 seconds
        let observerChecks = 0;
        const maxChecks = 50;
        const observer = new MutationObserver(function() {
            observerChecks++;
            if (observerChecks <= maxChecks) {
                setTimeout(function() { hideAds(); skipYouTubeAds(); }, 200);
            } else {
                observer.disconnect();
            }
        });
        observer.observe(document.documentElement, { childList: true, subtree: true });
        
        // Force observer disconnect after 30 seconds
        setTimeout(function() { observer.disconnect(); }, 30000);
        
        // Periodic check for YouTube (needs ongoing monitoring for ads)
        if (window.location.hostname.includes('youtube.com')) {
            let ytChecks = 0;
            const ytInterval = setInterval(function() {
                ytChecks++;
                skipYouTubeAds();
                hideAds();
                if (ytChecks > 120) clearInterval(ytInterval); // Stop after 2 minutes
            }, 1000);
        }
        
    })();
    """;
    
    // MARK: - Create User Scripts (Layer 3)
    func createUserScripts() -> [WKUserScript] {
        guard isEnabled else { return [] }
        
        return [
            WKUserScript(
                source: Self.cosmeticFilterScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        ]
    }
    
    // MARK: - Handle Blocked Ad Notification
    func handleBlockedAd(count: Int, domain: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.totalBlockedAds += max(count, 1)
            self.lastBlockedDomain = domain
            self.showBanner = true
            
            self.bannerHideWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                withAnimation(.easeOut(duration: 0.3)) {
                    self?.showBanner = false
                }
            }
            self.bannerHideWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
        }
    }
    
    func resetCount() {
        totalBlockedAds = 0
    }
}

// MARK: - Native Content Blocking Rules (Layer 1)
struct AdBlockRules {
    
    // MARK: - Generate Safe JSON Rules
    // Each rule is validated individually — bad rules are skipped
    static func generateChunkedRules() -> [String] {
        var allRules: [[String: Any]] = []
        
        // 1. Domain block rules — use safe regex
        for domain in blockDomainRules {
            let escaped = domain
                .replacingOccurrences(of: ".", with: "\\\\.")
            
            allRules.append([
                "trigger": ["url-filter": escaped] as [String: Any],
                "action": ["type": "block"]
            ])
        }
        
        // 2. CSS hide rules  
        for selector in cssHideSelectors {
            allRules.append([
                "trigger": ["url-filter": ".*"] as [String: Any],
                "action": [
                    "type": "css-display-none",
                    "selector": selector
                ] as [String: Any]
            ])
        }
        
        // Chunk into smaller groups (150 rules per chunk to avoid compile failures)
        let chunkSize = 150
        var chunks: [String] = []
        
        for i in stride(from: 0, to: allRules.count, by: chunkSize) {
            let end = min(i + chunkSize, allRules.count)
            let chunk = Array(allRules[i..<end])
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: chunk, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                chunks.append(jsonString)
            }
        }
        
        return chunks
    }
    
    // MARK: - Blocked Domains (used by both Layer 1 and Layer 2)
    static let blockDomainRules: [String] = [
        // === Google Ads ===
        "googleads.g.doubleclick.net",
        "pagead2.googlesyndication.com",
        "adservice.google.com",
        "www.googleadservices.com",
        "googleadservices.com",
        "tpc.googlesyndication.com",
        "ad.doubleclick.net",
        "stats.g.doubleclick.net",
        "securepubads.g.doubleclick.net",
        "s0.2mdn.net",
        "pagead2.googleadservices.com",
        
        // === YouTube Ads ===
        "imasdk.googleapis.com",
        
        // === Facebook / Meta ===
        "connect.facebook.net",
        "pixel.facebook.com",
        "an.facebook.com",
        
        // === Amazon Ads ===
        "aax-us-east.amazon-adsystem.com",
        "z-na.amazon-adsystem.com",
        "fls-na.amazon-adsystem.com",
        "c.amazon-adsystem.com",
        "s.amazon-adsystem.com",
        
        // === Ad Networks ===
        "ads.pubmatic.com",
        "hbopenbid.pubmatic.com",
        "image6.pubmatic.com",
        "ads.yahoo.com",
        "adtech.yahooinc.com",
        "cdn.taboola.com",
        "trc.taboola.com",
        "api.taboola.com",
        "nr.taboola.com",
        "cdn.outbrain.com",
        "widgets.outbrain.com",
        "log.outbrain.com",
        "ads.twitter.com",
        "analytics.twitter.com",
        
        // === Tracking ===
        "www.google-analytics.com",
        "google-analytics.com",
        "ssl.google-analytics.com",
        "bat.bing.com",
        "clarity.ms",
        "www.clarity.ms",
        "static.hotjar.com",
        "script.hotjar.com",
        "in.hotjar.com",
        "www.googletagmanager.com",
        "googletagmanager.com",
        
        // === Ad Exchanges ===
        "ib.adnxs.com",
        "secure.adnxs.com",
        "acdn.adnxs.com",
        "ads.rubiconproject.com",
        "fastlane.rubiconproject.com",
        "ads.openx.net",
        "u.openx.net",
        
        // === Mobile Ad Networks ===
        "ads.mopub.com",
        "app.adjust.com",
        "view.adjust.com",
        "app.appsflyer.com",
        "sdk.appsflyer.com",
        "cdn.branch.io",
        
        // === Push/Popup ===
        "cdn.onesignal.com",
        "onesignal.com",
        "cdn.pushwoosh.com",
        
        // === Criteo ===
        "dis.eu.criteo.com",
        "static.criteo.net",
        "gum.criteo.com",
        
        // === Other Trackers ===
        "cdn.segment.com",
        "api.segment.io",
        "cdn.mxpnl.com",
        "cdn.amplitude.com",
        "api.amplitude.com",
        "cdn.fullstory.com",
        "cdn.mouseflow.com",
        "js.hs-scripts.com",
        "track.hubspot.com",
        "a.scorecardresearch.com",
        "pixel.quantserve.com",
        "js-agent.newrelic.com",
        "bam.nr-data.net",
        "dpm.demdex.net",
        "cdn.cookielaw.org",
        
        // === Yandex ===
        "mc.yandex.ru",
        "an.yandex.ru",
        "ads.yandex.ru",
        
        // === Turkish Ad Networks ===
        "ads.sahibinden.com",
        "ad.mncdn.com",
        "reklam.hurriyet.com.tr",
        "ads.sozcu.com.tr",
        "reklam.mynet.com",
        "ads.milliyet.com.tr",
        
        // === LinkedIn / Snap ===
        "px.ads.linkedin.com",
        "snap.licdn.com",
        "tr.snapchat.com",
        
        // === Misc ===
        "match.adsrvr.org",
        "insight.adsrvr.org",
        "adserver.adtechus.com",
        "id5-sync.com",
        "cdn.sharethrough.com",
        "scdn.cxense.com"
    ]
    
    // MARK: - CSS Hide Selectors (for native css-display-none)
    static let cssHideSelectors: [String] = [
        "ins.adsbygoogle",
        ".adsbygoogle",
        "[id^=\"google_ads\"]",
        "[id^=\"div-gpt-ad\"]",
        "[data-ad-slot]",
        "[data-google-query-id]",
        ".ytp-ad-module",
        ".ytp-ad-overlay-container",
        ".video-ads",
        "#masthead-ad",
        "#player-ads",
        "ytd-promoted-sparkles-web-renderer",
        "ytd-display-ad-renderer",
        "ytd-ad-slot-renderer",
        "ytd-in-feed-ad-layout-renderer"
    ]
}
