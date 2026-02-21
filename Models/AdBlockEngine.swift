import SwiftUI
import WebKit

// MARK: - Ad Block Engine (Native WKContentRuleList)
// Uses Apple's native content blocking API for blazing-fast ad blocking
// instead of JavaScript-based blocking. Rules compile to bytecode and
// run inside WebKit's rendering engine — zero JS overhead.

class AdBlockEngine: ObservableObject {
    @Published var totalBlockedAds: Int = 0
    @Published var isEnabled: Bool = true {
        didSet {
            if isEnabled != oldValue {
                // Re-compile rules when toggled
                needsRecompile = true
            }
        }
    }
    @Published var showBanner: Bool = false
    @Published var lastBlockedDomain: String = ""
    @Published var isCompiled: Bool = false
    @Published var filterInfo: String = "Derleniyor..."
    
    // Compiled rule lists — cached after first compile
    private(set) var compiledRuleLists: [WKContentRuleList] = []
    var needsRecompile: Bool = true
    
    // Banner auto-hide timer
    private var bannerHideWorkItem: DispatchWorkItem?
    
    // MARK: - Compile Content Rules
    // Compiles JSON rules into native bytecode — called once, cached
    func compileRules(completion: @escaping () -> Void) {
        guard isEnabled else {
            compiledRuleLists = []
            isCompiled = true
            needsRecompile = false
            DispatchQueue.main.async {
                self.filterInfo = "Devre dışı"
            }
            completion()
            return
        }
        
        let store = WKContentRuleListStore.default()
        let ruleChunks = AdBlockRules.generateChunkedRules()
        var compiled: [WKContentRuleList] = []
        let group = DispatchGroup()
        
        for (index, chunk) in ruleChunks.enumerated() {
            group.enter()
            store?.compileContentRuleList(
                forIdentifier: "CyberBrowser_AdBlock_\(index)",
                encodedContentRuleList: chunk
            ) { ruleList, error in
                if let ruleList = ruleList {
                    compiled.append(ruleList)
                } else if let error = error {
                    print("[AdBlock] Chunk \(index) compile error: \(error.localizedDescription)")
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.compiledRuleLists = compiled
            self.isCompiled = true
            self.needsRecompile = false
            let totalRules = AdBlockRules.totalRuleCount
            self.filterInfo = "\(totalRules) kural aktif"
            print("[AdBlock] Compiled \(compiled.count) rule lists (\(totalRules) rules)")
            completion()
        }
    }
    
    // MARK: - Apply Rules to WebView Configuration
    func applyRules(to contentController: WKUserContentController) {
        // Remove existing rules
        contentController.removeAllContentRuleLists()
        
        guard isEnabled else { return }
        
        // Add compiled native rules
        for ruleList in compiledRuleLists {
            contentController.add(ruleList)
        }
    }
    
    // MARK: - Supplementary YouTube Ad Skip (minimal JS)
    // Only this small script remains — for skipping unskippable video ads
    // that cannot be caught by URL-based blocking
    static let youtubeAdSkipScript: String = """
    (function() {
        'use strict';
        if (!window.location.hostname.includes('youtube.com')) return;
        
        let lastCheck = 0;
        function skipAds() {
            const now = Date.now();
            if (now - lastCheck < 400) return;
            lastCheck = now;
            
            // Click skip button if available
            const skipBtn = document.querySelector(
                '.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button'
            );
            if (skipBtn) {
                skipBtn.click();
                try { window.webkit.messageHandlers.adBlocked.postMessage({count:1,total:0,url:window.location.href}); } catch(e) {}
            }
            
            // Speed through unskippable ads
            const video = document.querySelector('video');
            if (video && document.querySelector('.ad-showing')) {
                video.currentTime = video.duration || 0;
            }
        }
        
        // Use requestAnimationFrame instead of setInterval for efficiency
        function checkLoop() {
            skipAds();
            requestAnimationFrame(checkLoop);
        }
        requestAnimationFrame(checkLoop);
    })();
    """
    
    // MARK: - Create Supplementary Scripts
    func createUserScripts() -> [WKUserScript] {
        guard isEnabled else { return [] }
        
        return [
            WKUserScript(
                source: Self.youtubeAdSkipScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true // Only main frame — not iframes
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
            
            // Cancel previous timer
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

// MARK: - Native Content Blocking Rules
// Apple's Content Blocker JSON format — compiled to bytecode by WebKit
struct AdBlockRules {
    
    // Total rule count for UI display
    static var totalRuleCount: Int {
        let adguardRules = AdGuardFilterConverter.generateBuiltInFilterRules().count
        return blockDomainRules.count + cssHideRules.count + trackingRules.count + cookieBannerRules.count + adguardRules
    }
    
    // MARK: - Generate Chunked JSON Rules
    // WKContentRuleList has a per-list limit; chunk into manageable pieces
    static func generateChunkedRules() -> [String] {
        // Combine all rules
        var allRules: [[String: Any]] = []
        
        // 1. Domain blocking rules (ads, trackers)
        allRules.append(contentsOf: blockDomainRules.map { domain -> [String: Any] in
            [
                "trigger": [
                    "url-filter": escapeForRegex(domain),
                    "load-type": ["third-party"]
                ] as [String: Any],
                "action": ["type": "block"]
            ]
        })
        
        // 2. Full URL block rules (ad networks, tracking endpoints)
        allRules.append(contentsOf: trackingRules.map { pattern -> [String: Any] in
            [
                "trigger": [
                    "url-filter": pattern
                ] as [String: Any],
                "action": ["type": "block"]
            ]
        })
        
        // 3. CSS hide rules (cosmetic filtering)
        allRules.append(contentsOf: cssHideRules.map { selector -> [String: Any] in
            [
                "trigger": ["url-filter": ".*"] as [String: Any],
                "action": [
                    "type": "css-display-none",
                    "selector": selector
                ] as [String: Any]
            ]
        })
        
        // 4. Cookie banner blocking
        allRules.append(contentsOf: cookieBannerRules.map { selector -> [String: Any] in
            [
                "trigger": ["url-filter": ".*"] as [String: Any],
                "action": [
                    "type": "css-display-none",
                    "selector": selector
                ] as [String: Any]
            ]
        })
        
        // 5. AdGuard filter converter rules (Turkish + Base)
        allRules.append(contentsOf: AdGuardFilterConverter.generateBuiltInFilterRules())
        
        let chunkSize = 500
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
    
    // MARK: - Regex Escaper
    private static func escapeForRegex(_ domain: String) -> String {
        return domain
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "-", with: "\\-")
    }
    
    // MARK: - Domain Block Rules (AdGuard Base + EasyList equivalent)
    // 200+ ad/tracker domains — processed natively by WebKit
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
        "cm.g.doubleclick.net",
        "securepubads.g.doubleclick.net",
        "ade.googlesyndication.com",
        "s0.2mdn.net",
        "pagead2.googleadservices.com",
        "afs.googlesyndication.com",
        
        // === Facebook / Meta ===
        "connect.facebook.net",
        "pixel.facebook.com",
        "an.facebook.com",
        "staticxx.facebook.com",
        "www.facebook.com/tr",
        
        // === Amazon Ads ===
        "aax-us-east.amazon-adsystem.com",
        "z-na.amazon-adsystem.com",
        "fls-na.amazon-adsystem.com",
        "aax-us-iad.amazon-adsystem.com",
        "c.amazon-adsystem.com",
        "s.amazon-adsystem.com",
        
        // === Ad Networks ===
        "ads.pubmatic.com",
        "hbopenbid.pubmatic.com",
        "t.pubmatic.com",
        "image6.pubmatic.com",
        "ads.yahoo.com",
        "advertising.yahoo.com",
        "adtech.yahooinc.com",
        "ad.turn.com",
        "cdn.taboola.com",
        "trc.taboola.com",
        "api.taboola.com",
        "nr.taboola.com",
        "cdn.outbrain.com",
        "amplify.outbrain.com",
        "widgets.outbrain.com",
        "log.outbrain.com",
        "ads.twitter.com",
        "analytics.twitter.com",
        "static.ads-twitter.com",
        
        // === Tracking & Analytics ===
        "www.google-analytics.com",
        "google-analytics.com",
        "ssl.google-analytics.com",
        "analytics.google.com",
        "bat.bing.com",
        "c.bing.com",
        "clarity.ms",
        "www.clarity.ms",
        "static.hotjar.com",
        "script.hotjar.com",
        "vars.hotjar.com",
        "in.hotjar.com",
        "www.googletagmanager.com",
        "googletagmanager.com",
        
        // === Media Ads ===
        "imasdk.googleapis.com",
        "ad.youtube.com",
        
        // === Pop-up / Push Networks ===
        "cdn.popin.cc",
        "app.popin.cc",
        "cdn.moengage.com",
        "sdk.moengage.com",
        "cdn.onesignal.com",
        "onesignal.com",
        "cdn.pushwoosh.com",
        "cp.pushwoosh.com",
        "pushnews.io",
        
        // === Ad Exchanges ===
        "ib.adnxs.com",
        "secure.adnxs.com",
        "acdn.adnxs.com",
        "prebid.adnxs.com",
        "ads.rubiconproject.com",
        "fastlane.rubiconproject.com",
        "pixel.rubiconproject.com",
        "ads.openx.net",
        "u.openx.net",
        "rtb.openx.net",
        
        // === Mobile Ad Networks ===
        "ads.mopub.com",
        "app.adjust.com",
        "s2s.adjust.com",
        "view.adjust.com",
        "app.appsflyer.com",
        "sdk.appsflyer.com",
        "t.appsflyer.com",
        "conversions.appsflyer.com",
        "cdn.branch.io",
        "api.branch.io",
        
        // === Other Trackers ===
        "cdn.krxd.net",
        "beacon.krxd.net",
        "usermatch.krxd.net",
        "cdn.segment.com",
        "api.segment.io",
        "cdn.mxpnl.com",
        "decide.mixpanel.com",
        "api-js.mixpanel.com",
        "cr.frontend.weborama.fr",
        "cdn.cookielaw.org",
        "geolocation.onetrust.com",
        "cdn.tt.omtrdc.net",
        "dpm.demdex.net",
        
        // === Criteo ===
        "dis.eu.criteo.com",
        "static.criteo.net",
        "sslwidget.criteo.com",
        "gum.criteo.com",
        
        // === Misc Ad/Tracking ===
        "adserver.adtechus.com",
        "cdn.districtm.io",
        "match.adsrvr.org",
        "insight.adsrvr.org",
        "platform.linkedin.com",
        "snap.licdn.com",
        "px.ads.linkedin.com",
        "tr.snapchat.com",
        "sc-static.net",
        
        // === AdGuard Additions ===
        "mc.yandex.ru",
        "an.yandex.ru",
        "ads.yandex.ru",
        "counter.yadro.ru",
        "top-fwz1.mail.ru",
        "ad.mail.ru",
        "rs.mail.ru",
        "r.mradx.net",
        "ssp.rambler.ru",
        "www.tns-counter.ru",
        "pixel.onaudience.com",
        "adx.adform.net",
        "track.adform.net",
        "serving.adform.net",
        "banners.adform.net",
        "a.adform.net",
        "ad.atdmt.com",
        "ssum.casalemedia.com",
        "js.dmtry.com",
        "e.serverbid.com",
        "eus.rubiconproject.com",
        "optimized-by.rubiconproject.com",
        "sync.outbrain.com",
        "tr.outbrain.com",
        "widgets.pinterest.com",
        "log.pinterest.com",
        "trk.pinterest.com",
        
        // === Turkish Ad Networks ===
        "ads.sahibinden.com",
        "i.hizliresim.com",
        "ad.mncdn.com",
        "reklam.hurriyet.com.tr",
        "ads.sozcu.com.tr",
        "reklam.mynet.com",
        "ads.milliyet.com.tr",
        
        // === Fingerprinting / Privacy ===
        "cdn.amplitude.com",
        "api.amplitude.com",
        "cdn.fullstory.com",
        "edge.fullstory.com",
        "cdn.mouseflow.com",
        "o2.mouseflow.com",
        "d.agkn.com",
        "js.hs-scripts.com",
        "js.hs-analytics.net",
        "js.hsforms.net",
        "track.hubspot.com",
        "forms.hubspot.com",
        "api.hubspot.com",
        "bat.bing.com",
        "bat.r.msn.com",
        "a.scorecardresearch.com",
        "sb.scorecardresearch.com",
        "b.scorecardresearch.com",
        "pixel.quantserve.com",
        "secure.quantserve.com",
        "pixel.wp.com",
        "stats.wp.com",
        "s.pinimg.com",
        "ct.pinterest.com",
        "js-agent.newrelic.com",
        "bam.nr-data.net",
        
        // === More Ad Networks (AdGuard Extended) ===
        "adclick.g.doublecklick.net",
        "www.outbrain.com",
        "www.taboola.com",
        "cdn.vox-cdn.com",
        "sb.voicefive.com",
        "cdn.permutive.com",
        "cdn.lotame.com",
        "bcp.crwdcntrl.net",
        "tags.crwdcntrl.net",
        "cdn.tynt.com",
        "p.typekit.net",
        "use.typekit.net",
        "fast.wistia.com",
        "pippio.com",
        "scdn.cxense.com",
        "cdn.cxense.com",
        "api.cxense.com",
        "id5-sync.com",
        "lcdn.livingads.io",
        "cdn.sharethrough.com",
        "bttrack.com",
        "trk.helios-cloud.com"
    ]
    
    // MARK: - CSS Hide Rules (Cosmetic Filtering)
    // Equivalent to AdGuard's ## (element hiding) rules
    static let cssHideRules: [String] = [
        // Generic ad containers
        "[id*=\"ad-container\"]",
        "[id*=\"ad_container\"]",
        "[class*=\"ad-container\"]",
        "[class*=\"ad_container\"]",
        "[class*=\"ad-wrapper\"]",
        "[class*=\"ad_wrapper\"]",
        "[class*=\"ad-slot\"]",
        "[class*=\"ad-banner\"]",
        "[class*=\"ad_banner\"]",
        "[class*=\"advertisement\"]",
        "[class*=\"sponsored-content\"]",
        
        // Google Ads
        "ins.adsbygoogle",
        ".adsbygoogle",
        
        // Video ads
        ".ytp-ad-module",
        ".ytp-ad-overlay-container",
        ".ytp-ad-text-overlay",
        ".video-ads",
        ".ad-showing",
        ".ytp-ad-image-overlay",
        "#masthead-ad",
        "#player-ads",
        "ytd-promoted-sparkles-web-renderer",
        "ytd-display-ad-renderer",
        "ytd-companion-slot-renderer",
        "ytd-action-companion-ad-renderer",
        "ytd-promoted-video-renderer",
        "ytd-ad-slot-renderer",
        ".ytd-banner-promo-renderer",
        
        // Popup overlays
        "[class*=\"popup-ad\"]",
        "[class*=\"interstitial\"]",
        "[class*=\"modal-ad\"]",
        "[class*=\"overlay-ad\"]",
        
        // Social tracking widgets
        ".fb-like",
        ".twitter-share-button",
        "[class*=\"social-share\"]"
    ]
    
    // MARK: - URL Pattern Tracking Rules
    // Regex patterns for tracking endpoints
    static let trackingRules: [String] = [
        ".*\\.doubleclick\\.net",
        ".*googlesyndication\\.com",
        ".*google-analytics\\.com.*collect",
        ".*googletagmanager\\.com/gtm",
        ".*facebook\\.com/tr",
        ".*facebook\\.net/en_US/fbevents",
        ".*hotjar\\.com.*hotjar",
        ".*clarity\\.ms.*collect",
        ".*amazon-adsystem\\.com.*ad",
        ".*taboola\\.com.*loaders",
        ".*outbrain\\.com.*widget"
    ]
    
    // MARK: - Cookie Banner CSS Rules
    static let cookieBannerRules: [String] = [
        "#onetrust-consent-sdk",
        "#onetrust-banner-sdk",
        "#CybotCookiebotDialog",
        "#CybotCookiebotDialogOverlay",
        ".cookie-consent",
        ".cookie-banner",
        ".cookie-notice",
        "#cookie-notice",
        "#cookie-law-info-bar",
        ".cc-banner",
        ".cc-window",
        ".js-cookie-consent",
        "#gdpr-cookie-notice",
        ".cookie-popup",
        "#cookie-popup",
        ".cookie-modal",
        "[class*=\"cookie-consent\"]",
        "[class*=\"cookie-banner\"]",
        "[id*=\"cookie-consent\"]",
        "[id*=\"cookie-banner\"]",
        ".consent-banner",
        "#consent-banner",
        ".gdpr-banner",
        "#gdpr-banner",
        ".privacy-banner",
        "#privacy-notice",
        ".cookie-overlay",
        ".consent-overlay",
        ".gdpr-overlay",
        "#cookiescript_injected",
        ".cookieinfo",
        "#cookie-bar"
    ]
}
