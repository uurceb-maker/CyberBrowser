import Foundation
import WebKit
import Combine

// MARK: - Ad Block Engine v3.1 — Bulletproof Edition
// Architecture:
// Layer 1: WKContentRuleList — native WebKit blocking (blocks ALL request types: img, script, css, xhr, iframe)
//   - Embedded rules compile INSTANTLY (no download needed)
//   - EasyList download runs in background as enhancement
// Layer 2: decidePolicyFor — catches navigation/iframe requests as fallback
// Layer 3: JS Cosmetic Filter — hides remaining ad elements visually

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
    
    // MARK: - Layer 2: Domain keywords for decidePolicyFor
    private let blockedDomainKeywords: Set<String> = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com",
        "google-analytics.com", "googletagmanager.com", "googletagservices.com",
        "adnxs.com", "adsrvr.org", "advertising.com", "adform.net",
        "taboola.com", "outbrain.com", "criteo.com", "criteo.net",
        "moatads.com", "amazon-adsystem.com", "rubiconproject.com",
        "pubmatic.com", "openx.net", "casalemedia.com", "bidswitch.net",
        "smartadserver.com", "adcolony.com", "applovin.com", "vungle.com",
        "admob.com", "chartboost.com", "inmobi.com", "smaato.net",
        "2mdn.net", "nr-data.net", "yieldmanager.com",
        "pagead2.googlesyndication.com", "securepubads.g.doubleclick.net",
        "tpc.googlesyndication.com", "s0.2mdn.net",
        "cdn.taboola.com", "trc.taboola.com",
        "widgets.outbrain.com", "log.outbrain.com",
        "static.ads-twitter.com", "analytics.twitter.com",
        "pixel.facebook.com", "an.facebook.com",
        "ads.yahoo.com", "gemini.yahoo.com"
    ]
    
    // MARK: - EasyList Download Config
    private let easyListURL = "https://easylist-downloads.adblockplus.org/easylist_content_blocker.json"
    private let cacheFileName = "easylist_content_blocker.json"
    private let cacheMaxAgeDays: Double = 7
    private let maxRulesPerChunk = 50000
    
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
        filterInfo = "Kurallar derleniyor..."
        
        // Step 1: Compile embedded rules FIRST (instant, guaranteed)
        compileEmbeddedRules { [weak self] in
            guard let self = self else { return }
            
            // Step 2: Try to enhance with downloaded EasyList in background
            self.downloadAndCompileEasyList()
            
            // Don't wait for download — return immediately with embedded rules
            completion()
        }
    }
    
    // MARK: - Compile Embedded Rules (instant, no download)
    private func compileEmbeddedRules(completion: @escaping () -> Void) {
        let store = WKContentRuleListStore.default()
        let group = DispatchGroup()
        var compiled: [WKContentRuleList] = []
        
        // Compile network blocking rules
        group.enter()
        store?.compileContentRuleList(forIdentifier: "embedded_network", encodedContentRuleList: Self.networkBlockRules) { ruleList, error in
            if let ruleList = ruleList {
                compiled.append(ruleList)
                print("[AdBlock] ✅ Network rules compiled")
            } else {
                print("[AdBlock] ❌ Network rules failed: \(error?.localizedDescription ?? "unknown")")
            }
            group.leave()
        }
        
        // Compile CSS hiding rules
        group.enter()
        store?.compileContentRuleList(forIdentifier: "embedded_css", encodedContentRuleList: Self.cssHideRules) { ruleList, error in
            if let ruleList = ruleList {
                compiled.append(ruleList)
                print("[AdBlock] ✅ CSS rules compiled")
            } else {
                print("[AdBlock] ❌ CSS rules failed: \(error?.localizedDescription ?? "unknown")")
            }
            group.leave()
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.compiledRuleLists = compiled
            self.isCompiling = false
            self.needsRecompile = false
            self.filterInfo = "\(compiled.count) kural grubu aktif"
            print("[AdBlock] 🎯 Embedded compilation: \(compiled.count)/2 groups compiled")
            completion()
        }
    }
    
    // MARK: - Download EasyList (background enhancement)
    private func downloadAndCompileEasyList() {
        // Check cache first
        if let cacheURL = getCacheFileURL(),
           FileManager.default.fileExists(atPath: cacheURL.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
           let modDate = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modDate) < cacheMaxAgeDays * 86400 {
            
            // Cache is fresh — compile in background
            if let data = try? Data(contentsOf: cacheURL),
               let json = String(data: data, encoding: .utf8) {
                print("[AdBlock] 📦 Loading EasyList from cache")
                compileDownloadedRules(json)
                return
            }
        }
        
        // Download
        guard let url = URL(string: easyListURL) else { return }
        print("[AdBlock] ⬇️ Downloading EasyList...")
        
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil,
                  let json = String(data: data, encoding: .utf8) else {
                print("[AdBlock] ⚠️ Download failed — embedded rules are sufficient")
                return
            }
            
            // Cache
            if let cacheURL = self.getCacheFileURL() {
                try? data.write(to: cacheURL)
                print("[AdBlock] 💾 Cached EasyList (\(data.count / 1024)KB)")
            }
            
            self.compileDownloadedRules(json)
        }.resume()
    }
    
    // MARK: - Compile Downloaded Rules
    private func compileDownloadedRules(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let allRules = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return
        }
        
        let totalRules = allRules.count
        let chunks = stride(from: 0, to: totalRules, by: maxRulesPerChunk).map { start in
            Array(allRules[start..<min(start + maxRulesPerChunk, totalRules)])
        }
        
        let store = WKContentRuleListStore.default()
        let group = DispatchGroup()
        var downloaded: [WKContentRuleList] = []
        
        for (i, chunk) in chunks.enumerated() {
            group.enter()
            guard let chunkData = try? JSONSerialization.data(withJSONObject: chunk),
                  let chunkJSON = String(data: chunkData, encoding: .utf8) else {
                group.leave()
                continue
            }
            
            store?.compileContentRuleList(forIdentifier: "easylist_\(i)", encodedContentRuleList: chunkJSON) { ruleList, error in
                if let ruleList = ruleList {
                    downloaded.append(ruleList)
                    print("[AdBlock] ✅ EasyList chunk \(i): \(chunk.count) rules")
                } else {
                    print("[AdBlock] ❌ EasyList chunk \(i) failed: \(error?.localizedDescription ?? "")")
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self, !downloaded.isEmpty else { return }
            // Add downloaded rules to existing embedded rules
            self.compiledRuleLists.append(contentsOf: downloaded)
            self.filterInfo = "\(totalRules) kural aktif (\(self.compiledRuleLists.count) grup)"
            print("[AdBlock] 🎯 EasyList added: \(downloaded.count) chunks → total \(self.compiledRuleLists.count) groups")
            
            // Post notification so WebView can re-inject
            NotificationCenter.default.post(name: .adBlockRulesUpdated, object: nil)
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
        
        print("[AdBlock] 📎 Applied \(compiledRuleLists.count) rule list(s)")
        
        // Layer 3: JS Cosmetic Filter (runs in ALL frames)
        let cosmeticScript = WKUserScript(
            source: Self.cosmeticFilterScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        controller.addUserScript(cosmeticScript)
        
        // YouTube ad skip (main frame only)
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
    
    // MARK: - Layer 1a: Network Blocking Rules (Embedded — guaranteed to compile)
    // These are REAL Safari Content Blocker JSON rules copied from EasyList format
    // They use url-filter patterns that are 100% valid ICU regex
    static let networkBlockRules: String = """
    [
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?doubleclick\\\\.net[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?googlesyndication\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?googleadservices\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?google-analytics\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?googletagmanager\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?googletagservices\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?adnxs\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?adsrvr\\\\.org[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?advertising\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?adform\\\\.net[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?taboola\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?outbrain\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?criteo\\\\.(com|net)[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?moatads\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?amazon-adsystem\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?rubiconproject\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?pubmatic\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?openx\\\\.net[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?casalemedia\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?bidswitch\\\\.net[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?smartadserver\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?adcolony\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?applovin\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?vungle\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?admob\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?chartboost\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?inmobi\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?smaato\\\\.net[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?2mdn\\\\.net[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?nr-data\\\\.net[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?yieldmanager\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?facebook\\\\.net[/:].*fbads","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?serving-sys\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?quantserve\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?scorecardresearch\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?bluekai\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?exoclick\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?popads\\\\.net[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?propellerads\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?trafficjunky\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?revcontent\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?mgid\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?zedo\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?adtechus\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?spotxchange\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?sharethrough\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?contextweb\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?lijit\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?adblade\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?medianet\\\\.com[/:]","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/pagead/","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/adserver/","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/ads\\\\.js"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/ad\\\\.js"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/adsbygoogle\\\\.js"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/show_ads"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/adview"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/ad_iframe"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/adfetch"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/adhandler"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/gpt\\\\.js"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/pubads"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/gampad/"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/sponsor"},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/_ad_","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"tracking\\\\.js","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"tracker\\\\.js","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"analytics\\\\.js","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/pixel\\\\.gif","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/pixel\\\\.png","load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/beacon\\\\.","load-type":["third-party"]},"action":{"type":"block"}}
    ]
    """
    
    // MARK: - Layer 1b: CSS Hide Rules (Embedded — guaranteed to compile)
    static let cssHideRules: String = """
    [
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":".adsbygoogle"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"ins.adsbygoogle"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"[id^=\\"google_ads\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"[id^=\\"div-gpt-ad\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"[class*=\\"ad-container\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"[class*=\\"ad-wrapper\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"[class*=\\"ad-banner\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"[class*=\\"adunit\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"[class*=\\"ad-slot\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"[class*=\\"ad_unit\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"[class*=\\"sponsored\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"[class*=\\"ad-placement\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"[id*=\\"taboola\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"[class*=\\"taboola\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"[id*=\\"outbrain\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"[class*=\\"outbrain\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":".trc_related_container"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"#taboola-below-article"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"amp-ad"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"AMP-AD"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"#cookie-banner"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"#cookie-notice"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"[class*=\\"cookie-consent\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"[class*=\\"cookie-banner\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"[class*=\\"cookie-notice\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"[id*=\\"consent-banner\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"[class*=\\"consent-banner\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"[class*=\\"gdpr\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"iframe[src*=\\"doubleclick\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"iframe[src*=\\"googlesyndication\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"iframe[src*=\\"adnxs\\"]"}},
        {"trigger":{"url-filter":"^https?://"},"action":{"type":"css-display-none","selector":"iframe[src*=\\"taboola\\"]"}}
    ]
    """
    
    // MARK: - Layer 3: Cosmetic Filter Script (JS)
    static let cosmeticFilterScript: String = """
    (function() {
        'use strict';
        if (window.__cyberAdBlockInjected) return;
        window.__cyberAdBlockInjected = true;
        
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
            '[id*="consent-banner"]', '[class*="consent-banner"]',
            '.ad-overlay', '#ad-overlay', '[class*="interstitial"]',
            '[id*="ad-popup"]', '[class*="ad-popup"]'
        ];
        
        let totalHidden = 0;
        
        function hideElements() {
            let count = 0;
            const joined = selectors.join(',');
            try {
                document.querySelectorAll(joined).forEach(function(el) {
                    if (el.style.display !== 'none') {
                        el.style.setProperty('display', 'none', 'important');
                        el.style.setProperty('visibility', 'hidden', 'important');
                        el.style.setProperty('height', '0', 'important');
                        el.style.setProperty('overflow', 'hidden', 'important');
                        count++;
                    }
                });
            } catch(e) {}
            
            if (count > 0) {
                totalHidden += count;
                try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.adBlocked) {
                        window.webkit.messageHandlers.adBlocked.postMessage({count: count, url: location.hostname});
                    }
                } catch(e) {}
            }
        }
        
        // Run immediately
        hideElements();
        
        // Run on DOMContentLoaded
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', hideElements);
        }
        
        // Run after full load
        window.addEventListener('load', function() {
            hideElements();
            // Run a few more times after load to catch late-loading ads
            setTimeout(hideElements, 500);
            setTimeout(hideElements, 1500);
            setTimeout(hideElements, 3000);
            setTimeout(hideElements, 5000);
        });
        
        // MutationObserver — watch for dynamically inserted ads
        let checkCount = 0;
        const maxChecks = 200;
        const observer = new MutationObserver(function() {
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
        
        // Stop observer after 60 seconds
        setTimeout(function() { observer.disconnect(); }, 60000);
    })();
    """
    
    // MARK: - YouTube Ad Skip Script
    static let youtubeAdSkipScript: String = """
    (function() {
        'use strict';
        if (!location.hostname.includes('youtube.com')) return;
        if (window.__cyberYTAdSkip) return;
        window.__cyberYTAdSkip = true;
        
        const skipInterval = setInterval(function() {
            // Click skip button
            var skipBtn = document.querySelector('.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern, [class*="skip-button"]');
            if (skipBtn) { skipBtn.click(); return; }
            
            // Speed through unskippable ads
            var video = document.querySelector('video');
            var adOverlay = document.querySelector('.ad-showing, .ytp-ad-player-overlay');
            if (video && adOverlay) {
                video.currentTime = video.duration || 999;
                video.playbackRate = 16;
            }
            
            // Remove ad overlays
            document.querySelectorAll('.ytp-ad-overlay-container, .ytp-ad-text-overlay, #player-ads').forEach(function(el) {
                el.remove();
            });
        }, 500);
        
        // Stop after 2 minutes
        setTimeout(function() { clearInterval(skipInterval); }, 120000);
    })();
    """
}

// MARK: - Notification
extension Notification.Name {
    static let adBlockRulesUpdated = Notification.Name("adBlockRulesUpdated")
}
