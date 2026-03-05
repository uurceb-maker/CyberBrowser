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
        // Google Ad Network
        "doubleclick.net", "googlesyndication.com", "googleadservices.com",
        "google-analytics.com", "googletagmanager.com", "googletagservices.com",
        "pagead2.googlesyndication.com", "securepubads.g.doubleclick.net",
        "tpc.googlesyndication.com", "s0.2mdn.net", "2mdn.net",
        // Major Ad Exchanges
        "adnxs.com", "adsrvr.org", "advertising.com", "adform.net",
        "taboola.com", "outbrain.com", "criteo.com", "criteo.net",
        "moatads.com", "amazon-adsystem.com", "rubiconproject.com",
        "pubmatic.com", "openx.net", "casalemedia.com", "bidswitch.net",
        "smartadserver.com", "yieldmanager.com",
        "cdn.taboola.com", "trc.taboola.com",
        "widgets.outbrain.com", "log.outbrain.com",
        // Mobile Ad SDKs
        "adcolony.com", "applovin.com", "vungle.com",
        "admob.com", "chartboost.com", "inmobi.com", "smaato.net",
        "unityads.unity3d.com", "mopub.com", "ironsrc.com",
        // Social Media Trackers
        "static.ads-twitter.com", "analytics.twitter.com",
        "pixel.facebook.com", "an.facebook.com", "connect.facebook.net",
        "ads.yahoo.com", "gemini.yahoo.com",
        "ads.linkedin.com", "snap.licdn.com",
        // Analytics & Tracking
        "nr-data.net", "hotjar.com", "mouseflow.com", "fullstory.com",
        "mixpanel.com", "segment.com", "amplitude.com",
        "omtrdc.net", "demdex.net", "everesttech.net",
        "quantserve.com", "scorecardresearch.com", "bluekai.com",
        // Popup / Redirect Networks
        "exoclick.com", "popads.net", "propellerads.com",
        "trafficjunky.com", "revcontent.com", "mgid.com",
        "zedo.com", "adtechus.com", "spotxchange.com",
        "sharethrough.com", "contextweb.com", "lijit.com",
        "adblade.com", "medianet.com", "serving-sys.com",
        // Fingerprinting & Surveillance
        "fingerprintjs.com", "cdn.cookielaw.org",
        "trustarc.com", "onetrust.com",
        // Additional Networks
        "adhigh.net", "adroll.com",
        "tradedoubler.com", "awin1.com", "impact.com",
        // Türk Bahis/Casino Siteleri
        "betasus.com", "grandpashabet.com", "grandpashabetgiris.com",
        "kareasbet.com", "meritbet.com", "spinco.com", "hititbet.com",
        "dedebet.com", "dedebet202.com", "dedebet203.com",
        "bahiscom.com", "betpas.com", "tipobet.com", "betboo.com",
        "bets10.com", "mobilbahis.com", "superbetin.com",
        "casinometropol.com", "tempobet.com", "youwin.com",
        "1xbet.com", "mostbet.com", "pinup.com", "melbet.com",
        "betkanyon.com", "dinamobet.com", "restbet.com",
        "hovarda.com", "jasminbet.com", "imajbet.com",
        "mariobet.com", "sahabet.com", "matbet.com",
        "pusulabet.com", "hiltonbet.com", "jojobet.com"
    ]
    private let blockedPathKeywords: Set<String> = [
        "/adserver", "/doubleclick", "/googlesyndication", "/pagead",
        "/reklam", "/sponsor", "/promo", "/banner", "/bonus", "/casino", "/bahis", "/bet",
        "/bahis-", "/casino-", "/slot-", "/canli-bahis", "/deneme-bonusu",
        "/kayip-bonusu", "/hosgeldin-bonusu", "/uye-ol"
    ]
    
    // MARK: - EasyList Download Config
    private let easyListURLs: [String] = [
        "https://easylist-downloads.adblockplus.org/easylist_content_blocker.json",
        "https://cdn.jsdelivr.net/gh/niceincode/niceincode.github.io@master/nicelist/nicelist.json",
        "https://raw.githubusercontent.com/niceincode/niceincode.github.io/master/nicelist/nicelist.json",
        "https://easylist.to/easylist/easylist.txt"
    ]
    private let cacheFileName = "easylist_content_blocker.json"
    private let cacheMaxAgeDays: Double = 7
    private let maxRulesPerChunk = 50000
    private let maxRetryAttempts = 3
    
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
        
        // Compile first-party path rules
        group.enter()
        store?.compileContentRuleList(forIdentifier: "embedded_first_party", encodedContentRuleList: Self.firstPartyPathRules) { ruleList, error in
            if let ruleList = ruleList {
                compiled.append(ruleList)
                print("[AdBlock] First-party rules compiled")
            } else {
                print("[AdBlock] First-party rules failed: \(error?.localizedDescription ?? "unknown")")
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
    
    // MARK: - Download EasyList (background enhancement with retry + fallback)
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
        
        // Try each URL with retry
        tryDownloadEasyList(urlIndex: 0, attempt: 0)
    }
    
    private func tryDownloadEasyList(urlIndex: Int, attempt: Int) {
        guard urlIndex < easyListURLs.count else {
            print("[AdBlock] ⚠️ All EasyList sources failed — embedded rules are sufficient")
            return
        }
        
        guard let url = URL(string: easyListURLs[urlIndex]) else {
            tryDownloadEasyList(urlIndex: urlIndex + 1, attempt: 0)
            return
        }
        
        print("[AdBlock] ⬇️ Downloading EasyList (source \(urlIndex + 1)/\(easyListURLs.count), attempt \(attempt + 1))...")
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        let session = URLSession(configuration: config)
        
        session.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            
            // Check for valid response
            if let data = data, error == nil,
               let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               let json = String(data: data, encoding: .utf8),
               json.contains("trigger") || json.contains("url-filter") {
                
                // Cache successfully
                if let cacheURL = self.getCacheFileURL() {
                    try? data.write(to: cacheURL)
                    print("[AdBlock] 💾 Cached EasyList (\(data.count / 1024)KB)")
                }
                
                self.compileDownloadedRules(json)
                return
            }
            
            // Retry with exponential backoff
            let nextAttempt = attempt + 1
            if nextAttempt < self.maxRetryAttempts {
                let delay = Double(nextAttempt) * 2.0
                print("[AdBlock] 🔄 Retry in \(delay)s...")
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    self.tryDownloadEasyList(urlIndex: urlIndex, attempt: nextAttempt)
                }
            } else {
                // Try next URL source
                print("[AdBlock] ❌ Source \(urlIndex + 1) failed, trying next...")
                self.tryDownloadEasyList(urlIndex: urlIndex + 1, attempt: 0)
            }
        }.resume()
    }
    
    // MARK: - Compile Downloaded Rules
    private func compileDownloadedRules(_ jsonString: String) {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[") else {
            print("[AdBlock] ⚠️ Downloaded list is not JSON rule format, skipped")
            return
        }
        
        guard let data = jsonString.data(using: .utf8),
              let allRules = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            print("[AdBlock] ⚠️ Downloaded JSON parse failed")
            return
        }
        
        let validRules = allRules.filter { rule in
            guard
                let trigger = rule["trigger"] as? [String: Any],
                let action = rule["action"] as? [String: Any],
                trigger["url-filter"] != nil,
                action["type"] != nil
            else {
                return false
            }
            return true
        }
        
        guard !validRules.isEmpty else {
            print("[AdBlock] ⚠️ Downloaded list has no valid rules")
            return
        }
        
        let totalRules = validRules.count
        let chunks = stride(from: 0, to: totalRules, by: maxRulesPerChunk).map { start in
            Array(validRules[start..<min(start + maxRulesPerChunk, totalRules)])
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
        
        // Anti-anti-adblock (runs FIRST at document start to intercept detection)
        let antiDetectScript = WKUserScript(
            source: Self.antiAdBlockScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        controller.addUserScript(antiDetectScript)

        // Fingerprint protection (document START, main frame only)
        let fpScript = WKUserScript(
            source: Self.fingerprintProtectionScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        controller.addUserScript(fpScript)
        
        // Layer 3: JS Cosmetic Filter (runs in ALL frames)
        let cosmeticScript = WKUserScript(
            source: Self.cosmeticFilterScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        controller.addUserScript(cosmeticScript)

        // Turkish streaming site ad block (runs in ALL frames at document END)
        let trScript = WKUserScript(
            source: Self.turkishStreamingAdBlockScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        controller.addUserScript(trScript)
        
        // Cookie consent auto-dismiss
        let cookieScript = WKUserScript(
            source: Self.cookieConsentScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        controller.addUserScript(cookieScript)
        
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

        // YouTube'dayken googlesyndication/doubleclick'i engelleme
        // (video player bu domain'leri kullanıyor)
        let youtubeExemptDomains: Set<String> = [
            "googlesyndication.com", "doubleclick.net",
            "googleadservices.com", "2mdn.net"
        ]
        if let mainHost = url.host?.lowercased() {
            for exemptDomain in youtubeExemptDomains {
                if mainHost == exemptDomain || mainHost.hasSuffix(".\(exemptDomain)") {
                    // Bu domain'leri Layer 1 (WKContentRuleList) zaten yönetiyor
                    // Layer 2'de tekrar engellemeye gerek yok çünkü video player'ı bozuyor
                    return false
                }
            }
        }

        guard let host = url.host?.lowercased() else { return false }
        
        for keyword in blockedDomainKeywords {
            if host == keyword || host.hasSuffix(".\(keyword)") {
                return true
            }
        }
        
        let path = url.path.lowercased()
        for keyword in blockedPathKeywords {
            if path.contains(keyword) {
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
    // Simplified ICU regex with resource-type filtering for reliable compilation
    static let networkBlockRules: String = """
    [
        {"trigger":{"url-filter":".*\\.doubleclick\\.net","resource-type":["script","image","style-sheet","raw","media","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.googlesyndication\\.com","resource-type":["script","image","style-sheet","raw","media","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.googleadservices\\.com","resource-type":["script","image","raw","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.google-analytics\\.com","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.googletagmanager\\.com","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.googletagservices\\.com","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.adnxs\\.com","resource-type":["script","image","style-sheet","raw","media","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.adsrvr\\.org","resource-type":["script","image","raw","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.advertising\\.com","resource-type":["script","image","raw","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.adform\\.net","resource-type":["script","image","raw","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.taboola\\.com","resource-type":["script","image","style-sheet","raw","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.outbrain\\.com","resource-type":["script","image","style-sheet","raw","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.criteo\\.com","resource-type":["script","image","raw","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.criteo\\.net","resource-type":["script","image","raw","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.moatads\\.com","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.amazon-adsystem\\.com","resource-type":["script","image","raw","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.rubiconproject\\.com","resource-type":["script","image","raw","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.pubmatic\\.com","resource-type":["script","image","raw","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.openx\\.net","resource-type":["script","image","raw","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.casalemedia\\.com","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.bidswitch\\.net","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.smartadserver\\.com","resource-type":["script","image","raw","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.adcolony\\.com","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.applovin\\.com","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.vungle\\.com","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.admob\\.com","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.chartboost\\.com","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.inmobi\\.com","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.smaato\\.net","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.2mdn\\.net","resource-type":["script","image","raw","media","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.nr-data\\.net","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.yieldmanager\\.com","resource-type":["script","image","raw","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.serving-sys\\.com","resource-type":["script","image","raw","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.quantserve\\.com","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.scorecardresearch\\.com","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.bluekai\\.com","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.exoclick\\.com","resource-type":["script","image","raw","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.popads\\.net","resource-type":["script","image","raw","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.propellerads\\.com","resource-type":["script","image","raw","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.trafficjunky\\.com","resource-type":["script","image","raw","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.revcontent\\.com","resource-type":["script","image","raw","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.mgid\\.com","resource-type":["script","image","raw","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.zedo\\.com","resource-type":["script","image","raw","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.adtechus\\.com","resource-type":["script","image","raw","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.sharethrough\\.com","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.hotjar\\.com","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.mouseflow\\.com","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.fullstory\\.com","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.mixpanel\\.com","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.segment\\.com","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.amplitude\\.com","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.demdex\\.net","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.omtrdc\\.net","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.adroll\\.com","resource-type":["script","image","raw","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.tradedoubler\\.com","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.ironsrc\\.com","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.mopub\\.com","resource-type":["script","image","raw"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/pagead/","resource-type":["script","image","raw"],"load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/adserver/","resource-type":["script","image","raw"],"load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/ads\\.js","resource-type":["script"],"load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/ad\\.js","resource-type":["script"],"load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/adsbygoogle\\.js","resource-type":["script"],"load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/show_ads","resource-type":["script","image","raw"],"load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/gpt\\.js","resource-type":["script"],"load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/pubads","resource-type":["script","raw"],"load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/gampad/","resource-type":["script","image","raw"],"load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/_ad_","resource-type":["script","image","raw"],"load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"tracking\\.js","resource-type":["script"],"load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"tracker\\.js","resource-type":["script"],"load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"analytics\\.js","resource-type":["script"],"load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/pixel\\.gif","resource-type":["image"],"load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/pixel\\.png","resource-type":["image"],"load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/beacon\\.","resource-type":["image","raw"],"load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/adview","resource-type":["script","image","raw"],"load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/ad_iframe","resource-type":["script","raw"],"load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/adfetch","resource-type":["script","raw"],"load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"/adhandler","resource-type":["script","raw"],"load-type":["third-party"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":".*\\.googlesyndication\\.com","if-domain":["*youtube.com","*youtu.be"]},"action":{"type":"ignore-previous-rules"}},
        {"trigger":{"url-filter":".*\\.doubleclick\\.net","if-domain":["*youtube.com","*youtu.be"]},"action":{"type":"ignore-previous-rules"}}
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
    
    static let firstPartyPathRules: String = """
    [
        {"trigger":{"url-filter":"[\\/\\-_](reklam|sponsor|sponsored|promo|promotion)[\\/\\-_]","resource-type":["image","script","style-sheet","raw","media","svg-document","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"(banner|prebid|vast|preroll|midroll|instream|outstream|doubleclick|pagead|googlesyndication)","resource-type":["image","script","raw","media","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"(casino|bahis|bet|bonus)","resource-type":["image","script","raw","media","popup"]},"action":{"type":"block"}}
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
            '[id*="ad-popup"]', '[class*="ad-popup"]',
            '[id*="reklam"]', '[class*="reklam"]',
            '[id*="sponsor"]', '[class*="sponsor"]'
        ];
        
        const adKeywords = [
            'reklam', 'sponsor', 'sponsored', 'promo',
            'casino', 'bahis', 'bonus', 'preroll', 'midroll'
        ];
        
        let totalHidden = 0;
        
        function textContainsKeyword(text) {
            if (!text) return false;
            const value = String(text).toLowerCase();
            for (const k of adKeywords) {
                if (value.includes(k)) return true;
            }
            return false;
        }
        
        function hideContainer(el) {
            if (!el) return 0;
            const container = el.closest('section, article, div, aside, li') || el;
            const rect = container.getBoundingClientRect ? container.getBoundingClientRect() : null;
            if (!rect || rect.height < 80 || rect.width < 200) return 0;
            if (container && container.style.display !== 'none') {
                container.style.setProperty('display', 'none', 'important');
                container.style.setProperty('visibility', 'hidden', 'important');
                container.style.setProperty('height', '0', 'important');
                container.style.setProperty('overflow', 'hidden', 'important');
                return 1;
            }
            return 0;
        }
        
        function hideLikelyAdBlocks() {
            let removed = 0;
            const candidates = document.querySelectorAll('iframe, img, video, a[href], [id*="reklam"], [class*="reklam"], [id*="sponsor"], [class*="sponsor"]');
            candidates.forEach(function(el) {
                const joined = [
                    el.id,
                    el.className,
                    el.getAttribute && el.getAttribute('src'),
                    el.getAttribute && el.getAttribute('href'),
                    el.getAttribute && el.getAttribute('title'),
                    el.getAttribute && el.getAttribute('aria-label'),
                    el.textContent
                ].join(' ');
                
                if (textContainsKeyword(joined)) {
                    removed += hideContainer(el);
                }
            });
            return removed;
        }
        
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
            
            count += hideLikelyAdBlocks();
            
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
    
    // MARK: - YouTube Ad Skip Script v2
    static let youtubeAdSkipScript: String = """
    (function() {
        'use strict';
        if (!location.hostname.includes('youtube.com')) return;
        if (window.__cyberYTv4) return;
        window.__cyberYTv4 = true;

        // --- Skip button clicker (non-destructive) ---
        function clickSkip() {
            var btns = document.querySelectorAll(
                '.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern, ' +
                'button.ytp-ad-skip-button-modern, .ytp-ad-skip-button-slot, ' +
                '.videoAdUiSkipButton, .ytp-ad-skip-button-container button'
            );
            for (var i = 0; i < btns.length; i++) {
                try { btns[i].click(); } catch(e) {}
            }
        }

        // --- Safe ad fast-forward (does NOT kill the video) ---
        function fastForwardAd() {
            var player = document.querySelector('.html5-video-player');
            if (!player || !player.classList.contains('ad-showing')) return;

            var video = document.querySelector('video');
            if (!video) return;

            // First try clicking skip
            clickSkip();

            // If unskippable: speed through it silently
            // Do NOT set currentTime = duration (this kills the player)
            video.muted = true;
            video.playbackRate = 16;

            // When ad video ends naturally, YouTube will load the real video
            // We just need to unmute and restore speed when ad-showing disappears
        }

        // --- Restore normal playback after ad ends ---
        function restorePlayback() {
            var player = document.querySelector('.html5-video-player');
            if (player && !player.classList.contains('ad-showing')) {
                var video = document.querySelector('video');
                if (video && video.playbackRate > 1) {
                    video.playbackRate = 1;
                    video.muted = false;
                }
            }
        }

        // --- Remove ad overlay elements (visual only, safe) ---
        function removeOverlays() {
            var selectors = [
                '.ytp-ad-overlay-container', '.ytp-ad-text-overlay',
                '.ytp-ad-image-overlay', '.ytp-ad-player-overlay-flyout-cta',
                'ytd-promoted-sparkles-web-renderer', '.ytd-display-ad-renderer',
                '.ytd-promoted-video-renderer', '#masthead-ad',
                '.ytd-banner-promo-renderer', 'ytd-in-feed-ad-layout-renderer',
                'ytd-ad-slot-renderer', '.ytd-merch-shelf-renderer',
                '#offer-module', '.ytd-statement-banner-renderer',
                '.ytp-ad-action-interstitial'
            ];
            selectors.forEach(function(sel) {
                document.querySelectorAll(sel).forEach(function(el) {
                    el.style.setProperty('display', 'none', 'important');
                });
            });
        }

        // --- MutationObserver on player class changes ---
        function observePlayer() {
            var player = document.querySelector('.html5-video-player');
            if (!player) return;

            var observer = new MutationObserver(function() {
                if (player.classList.contains('ad-showing')) {
                    fastForwardAd();
                } else {
                    restorePlayback();
                }
            });
            observer.observe(player, { attributes: true, attributeFilter: ['class'] });
        }

        // --- Main loop (lighter, 1s interval) ---
        function mainCheck() {
            var player = document.querySelector('.html5-video-player');
            if (player && player.classList.contains('ad-showing')) {
                fastForwardAd();
            } else {
                restorePlayback();
            }
            removeOverlays();
            clickSkip();
        }

        var checkInterval = setInterval(mainCheck, 1000);
        setTimeout(function() { clearInterval(checkInterval); }, 300000);

        // SPA navigation
        var lastURL = location.href;
        setInterval(function() {
            if (location.href !== lastURL) {
                lastURL = location.href;
                mainCheck();
                setTimeout(observePlayer, 2000);
            }
        }, 1000);

        // Init
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', function() {
                mainCheck();
                setTimeout(observePlayer, 2000);
            });
        } else {
            mainCheck();
            setTimeout(observePlayer, 2000);
        }
    })();
    """
    
    // MARK: - Anti-Anti-Adblock Script (prevents adblock detection)
    static let antiAdBlockScript: String = """
    (function() {
        'use strict';
        if (window.__cyberAntiDetect) return;
        window.__cyberAntiDetect = true;
        
        // Stub adsbygoogle — prevents "ad blocker detected" warnings
        Object.defineProperty(window, 'adsbygoogle', {
            get: function() {
                return { loaded: true, push: function() {}, length: 1 };
            },
            set: function() {},
            configurable: false
        });
        
        // Stub google ad objects
        window.google_ad_modifications = {};
        window.google_reactive_ads_global_state = {};
        window.__google_ad_urls = [];
        
        // Stub common ad detection variables
        window.canRunAds = true;
        window.isAdBlockActive = false;
        window.adBlockDetected = false;
        window.adblockEnabled = false;
        
        // Override createElement to prevent bait element detection
        var origCreate = document.createElement.bind(document);
        document.createElement = function(tag) {
            var el = origCreate(tag);
            if (tag.toLowerCase() === 'div') {
                var origGetComputed = window.getComputedStyle;
                // Ensure bait divs always appear "visible"
                var origOffsetHeight = Object.getOwnPropertyDescriptor(HTMLElement.prototype, 'offsetHeight');
                if (origOffsetHeight && origOffsetHeight.get) {
                    Object.defineProperty(el, 'offsetHeight', {
                        get: function() {
                            if (this.className && (
                                this.className.includes('ads') ||
                                this.className.includes('ad-') ||
                                this.className.includes('adsbox') ||
                                this.id === 'ad-test'
                            )) {
                                return 1;
                            }
                            return origOffsetHeight.get.call(this);
                        }
                    });
                }
            }
            return el;
        };
        
        // Neutralize common anti-adblock scripts
        try {
            Object.defineProperty(window, 'blockAdBlock', {
                get: function() { return { onDetected: function(){}, onNotDetected: function(fn){ if(fn) fn(); } }; },
                set: function() {},
                configurable: true
            });
        } catch(e) {}
        
        try {
            Object.defineProperty(window, 'fuckAdBlock', {
                get: function() { return { onDetected: function(){}, onNotDetected: function(fn){ if(fn) fn(); } }; },
                set: function() {},
                configurable: true
            });
        } catch(e) {}
    })();
    """
    
    // MARK: - Fingerprint Protection Script
    static let fingerprintProtectionScript: String = """
    (function() {
        'use strict';
        if (window.__cyberFPProtect) return;
        window.__cyberFPProtect = true;
        
        // Canvas fingerprint protection — add subtle noise
        var origToDataURL = HTMLCanvasElement.prototype.toDataURL;
        HTMLCanvasElement.prototype.toDataURL = function(type) {
            var ctx = this.getContext('2d');
            if (ctx) {
                var imgData = ctx.getImageData(0, 0, this.width, this.height);
                for (var i = 0; i < imgData.data.length; i += 4) {
                    imgData.data[i] = imgData.data[i] ^ 1; // Tiny noise
                }
                ctx.putImageData(imgData, 0, 0);
            }
            return origToDataURL.apply(this, arguments);
        };
        
        // WebGL fingerprint protection
        var origGetParameter = null;
        try {
            var c = document.createElement('canvas');
            var gl = c.getContext('webgl') || c.getContext('experimental-webgl');
            if (gl) {
                origGetParameter = gl.__proto__.getParameter;
                gl.__proto__.getParameter = function(param) {
                    // Mask renderer/vendor info
                    if (param === 37445) return 'Apple GPU';
                    if (param === 37446) return 'Apple GPU';
                    return origGetParameter.call(this, param);
                };
            }
        } catch(e) {}
        
        // AudioContext fingerprint protection
        try {
            var origCreateOscillator = AudioContext.prototype.createOscillator;
            AudioContext.prototype.createOscillator = function() {
                var osc = origCreateOscillator.call(this);
                // Add random detune to prevent audio fingerprinting
                osc.detune.value = Math.random() * 0.01;
                return osc;
            };
        } catch(e) {}
        
        // Navigator property spoofing
        try {
            Object.defineProperty(navigator, 'hardwareConcurrency', { get: function() { return 4; } });
            Object.defineProperty(navigator, 'deviceMemory', { get: function() { return 8; } });
        } catch(e) {}
    })();
    """

    // MARK: - Turkish Streaming Site Ad Block Script v2
    static let turkishStreamingAdBlockScript: String = """
    (function() {
        'use strict';
        if (window.__cyberTRv2) return;
        window.__cyberTRv2 = true;

        // === BLOCKED DOMAIN PATTERNS (catches image-only banners via link href) ===
        var blockedDomainPatterns = [
            'bet', 'casino', 'bahis', 'slot', 'jackpot', 'poker',
            'rulet', 'tombala', 'blackjack', 'baccarat'
        ];
        var blockedDomains = [
            'betasus', 'grandpashabet', 'kareasbet', 'meritbet', 'spinco',
            'hititbet', 'dedebet', 'bahiscom', 'betpas', 'tipobet',
            'bets10', 'mobilbahis', 'superbetin', 'casinometropol',
            'jojobet', 'sahabet', 'matbet', 'pusulabet', 'hiltonbet',
            'mariobet', 'imajbet', 'restbet', 'dinamobet', 'hovarda',
            'betkanyon', 'jasminbet', 'youwin', 'tempobet', 'betboo',
            '1xbet', 'mostbet', 'pinup', 'melbet', 'pinbahis',
            'kralbet', 'cashwin', 'ngsbahis', 'fenomenbet'
        ];
        var blockedTextWords = [
            'bonus', 'freespin', 'kayıp bonusu', 'kayip bonusu',
            'deneme bonusu', 'hoşgeldin', 'hosgeldin', 'üye ol',
            'hemen üye', 'bedava bahis', 'canlı bahis', 'canli bahis'
        ];

        function isGamblingURL(href) {
            if (!href) return false;
            var h = href.toLowerCase();
            for (var i = 0; i < blockedDomains.length; i++) {
                if (h.includes(blockedDomains[i])) return true;
            }
            for (var j = 0; j < blockedDomainPatterns.length; j++) {
                // Only match in domain part, not in path of legitimate sites
                try {
                    var u = new URL(h, location.href);
                    if (u.hostname && u.hostname !== location.hostname) {
                        if (u.hostname.includes(blockedDomainPatterns[j])) return true;
                    }
                } catch(e) {
                    if (h.includes(blockedDomainPatterns[j])) return true;
                }
            }
            return false;
        }

        function hasGamblingText(el) {
            var text = (el.textContent || '').toLowerCase();
            for (var i = 0; i < blockedTextWords.length; i++) {
                if (text.includes(blockedTextWords[i])) return true;
            }
            return false;
        }

        // === 1. INJECT CSS — instantly hide known ad patterns ===
        var style = document.createElement('style');
        style.textContent = [
            '[class*="reklam"], [id*="reklam"] { display:none!important; height:0!important; }',
            '[class*="adsBox"], [id*="adsBox"] { display:none!important; }',
            '[class*="ad-overlay"], [id*="ad-overlay"] { display:none!important; }',
            '[class*="preroll"], [id*="preroll"] { display:none!important; }',
            '[class*="video-ad"], [id*="video-ad"] { display:none!important; }',
            '[class*="adContainer"], [id*="adContainer"] { display:none!important; }',
            '.reklamAlani, #reklamAlani { display:none!important; }',
            '[class*="interstitial"] { display:none!important; }',
            '[class*="popup-ad"], [id*="popup-ad"] { display:none!important; }'
        ].join('\\n');
        (document.head || document.documentElement).appendChild(style);

        // === 2. NUKE ALL LINKS TO GAMBLING SITES (and their parent containers) ===
        function nukeGamblingLinks() {
            var allLinks = document.querySelectorAll('a[href]');
            allLinks.forEach(function(link) {
                var href = link.getAttribute('href') || '';
                if (isGamblingURL(href)) {
                    // Hide the link itself
                    link.style.setProperty('display', 'none', 'important');
                    // Also hide its parent container (the banner wrapper)
                    var container = link.closest('div, section, aside, li, article, figure, td');
                    if (container) {
                        // Don't hide if container is too large (might be the whole page)
                        var r = container.getBoundingClientRect();
                        if (r.height < 800) {
                            container.style.setProperty('display', 'none', 'important');
                            container.style.setProperty('height', '0', 'important');
                            container.style.setProperty('overflow', 'hidden', 'important');
                        }
                    }
                }
            });

            // Also hide images whose src contains gambling domains
            var allImgs = document.querySelectorAll('img[src]');
            allImgs.forEach(function(img) {
                var src = (img.getAttribute('src') || '').toLowerCase();
                if (isGamblingURL(src)) {
                    var container = img.closest('div, a, section, aside, li, article, figure') || img;
                    container.style.setProperty('display', 'none', 'important');
                }
            });

            // Hide iframes to gambling sites
            var allIframes = document.querySelectorAll('iframe[src]');
            allIframes.forEach(function(iframe) {
                var src = iframe.getAttribute('src') || '';
                if (isGamblingURL(src)) {
                    iframe.style.setProperty('display', 'none', 'important');
                    iframe.style.setProperty('height', '0', 'important');
                }
            });
        }

        // === 3. NUKE ELEMENTS WITH GAMBLING TEXT ===
        function nukeGamblingText() {
            var candidates = document.querySelectorAll('div, section, aside, span, p, a, li');
            candidates.forEach(function(el) {
                if (hasGamblingText(el)) {
                    // Only hide if it's a reasonably sized block (not the whole page)
                    var r = el.getBoundingClientRect();
                    if (r.height > 20 && r.height < 600 && r.width > 50) {
                        var container = el.closest('div, section, aside, li, article') || el;
                        var cr = container.getBoundingClientRect();
                        if (cr.height < 800) {
                            container.style.setProperty('display', 'none', 'important');
                            container.style.setProperty('height', '0', 'important');
                        }
                    }
                }
            });
        }

        // === 4. AUTO-CLICK "Reklamı Geç" / Skip buttons ===
        function clickSkipButtons() {
            // Direct text match on buttons and clickable elements
            var clickables = document.querySelectorAll('button, a, span, div');
            for (var i = 0; i < clickables.length && i < 1000; i++) {
                var el = clickables[i];
                var t = (el.textContent || '').trim().toLowerCase();
                // Match "Reklamı Geç", "Reklamı Geç (3)", "REKLAMI GEÇ", etc.
                if (/reklam[ıi]\\s*(geç|gec|kapat)/i.test(t) ||
                    /skip\\s*ad/i.test(t) ||
                    (t === 'geç' || t === 'gec' || t === 'skip' || t === 'kapat' || t === 'x')) {
                    // Only click if it's a small element (button-like)
                    var r = el.getBoundingClientRect();
                    if (r.width < 300 && r.height < 100 && r.width > 10) {
                        try { el.click(); } catch(e) {}
                    }
                }
            }
        }

        // === 5. BLOCK CLICK-JACKING ===
        document.addEventListener('click', function(e) {
            var link = e.target.closest('a[href]');
            if (link) {
                var href = link.getAttribute('href') || '';
                if (isGamblingURL(href)) {
                    e.preventDefault();
                    e.stopPropagation();
                    e.stopImmediatePropagation();
                    link.style.setProperty('display', 'none', 'important');
                    return false;
                }
                // Block any external redirect that's not user-intended navigation
                if (link.hostname && link.hostname !== location.hostname) {
                    var targetHost = link.hostname.toLowerCase();
                    var isDomainBlocked = blockedDomainPatterns.some(function(p) { return targetHost.includes(p); });
                    if (isDomainBlocked) {
                        e.preventDefault();
                        e.stopPropagation();
                        e.stopImmediatePropagation();
                        return false;
                    }
                }
            }
        }, true);

        // === 6. BLOCK window.open POPUPS ===
        var origOpen = window.open;
        window.open = function(url) {
            if (url && isGamblingURL(String(url))) return null;
            return origOpen.apply(this, arguments);
        };

        // === 7. NUKE VIDEO OVERLAYS ===
        function nukeVideoOverlays() {
            var videos = document.querySelectorAll('video');
            videos.forEach(function(vid) {
                // Walk up to find the player container
                var player = vid.closest('[class*="player"], [id*="player"]') || vid.parentElement;
                if (!player) return;

                // Find ALL positioned elements on top of video
                var allChildren = player.querySelectorAll('*');
                allChildren.forEach(function(child) {
                    if (child === vid || child.tagName === 'VIDEO') return;
                    if (child.tagName === 'SOURCE' || child.tagName === 'TRACK') return;

                    // If it has a gambling link, nuke it
                    var childLinks = child.querySelectorAll('a[href]');
                    var selfLink = child.tagName === 'A' ? child : null;
                    var hasGambling = false;

                    if (selfLink && isGamblingURL(selfLink.getAttribute('href'))) hasGambling = true;
                    childLinks.forEach(function(cl) {
                        if (isGamblingURL(cl.getAttribute('href'))) hasGambling = true;
                    });

                    if (hasGambling) {
                        child.style.setProperty('display', 'none', 'important');
                        child.style.setProperty('pointer-events', 'none', 'important');
                        return;
                    }

                    // If it's positioned absolute/fixed and covers the video, check if it's an ad
                    var cs = window.getComputedStyle(child);
                    if (cs.position === 'absolute' || cs.position === 'fixed') {
                        var r = child.getBoundingClientRect();
                        // If it's large enough to be an overlay
                        if (r.width > 200 && r.height > 150) {
                            // If it contains external links or gambling text, nuke it
                            var extLinks = child.querySelectorAll('a[href]');
                            var hasExternal = false;
                            extLinks.forEach(function(a) {
                                if (a.hostname !== location.hostname) hasExternal = true;
                            });
                            if (hasExternal || hasGamblingText(child)) {
                                child.style.setProperty('display', 'none', 'important');
                                child.style.setProperty('pointer-events', 'none', 'important');
                            }
                        }
                    }
                });
            });
        }

        // === RUN EVERYTHING ===
        function runAll() {
            nukeGamblingLinks();
            nukeGamblingText();
            clickSkipButtons();
            nukeVideoOverlays();
        }

        // Run aggressively
        runAll();
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', runAll);
        }
        window.addEventListener('load', function() {
            runAll();
            setTimeout(runAll, 300);
            setTimeout(runAll, 800);
            setTimeout(runAll, 1500);
            setTimeout(runAll, 3000);
            setTimeout(runAll, 5000);
        });

        // MutationObserver — runs on EVERY DOM change
        var debounceTimer = null;
        var obs = new MutationObserver(function() {
            clearTimeout(debounceTimer);
            debounceTimer = setTimeout(runAll, 100);
        });
        obs.observe(document.documentElement, { childList: true, subtree: true });
        setTimeout(function() { obs.disconnect(); }, 90000);

        // Periodic skip button check (for countdown timers)
        var skipInterval = setInterval(function() {
            clickSkipButtons();
            nukeVideoOverlays();
        }, 500);
        setTimeout(function() { clearInterval(skipInterval); }, 180000);
    })();
    """
    
    // MARK: - Cookie Consent Auto-Dismiss Script
    static let cookieConsentScript: String = """
    (function() {
        'use strict';
        if (window.__cyberCookieDismiss) return;
        window.__cyberCookieDismiss = true;
        
        function dismissCookies() {
            // Click reject/decline buttons first (prefer rejecting tracking)
            var rejectBtns = document.querySelectorAll(
                '[class*=\"cookie\"] [class*=\"reject\"], [class*=\"cookie\"] [class*=\"decline\"], ' +
                '[class*=\"consent\"] [class*=\"reject\"], [class*=\"consent\"] [class*=\"decline\"], ' +
                '[id*=\"cookie\"] [class*=\"reject\"], [id*=\"cookie\"] [class*=\"decline\"], ' +
                'button[class*=\"reject-all\"], button[class*=\"deny\"], ' +
                '.cmp-reject-all, #onetrust-reject-all-handler, ' +
                '.cookie-decline, .js-cookie-reject, [data-action=\"reject\"]'
            );
            for (var i = 0; i < rejectBtns.length; i++) {
                try { rejectBtns[i].click(); return; } catch(e) {}
            }
            
            // Click "accept necessary only" buttons
            var necessaryBtns = document.querySelectorAll(
                '[class*=\"necessary\"], [class*=\"essential\"], ' +
                'button[class*=\"accept-necessary\"]'
            );
            for (var j = 0; j < necessaryBtns.length; j++) {
                try { necessaryBtns[j].click(); return; } catch(e) {}
            }
            
            // Last resort: close/dismiss the banner
            var closeBtns = document.querySelectorAll(
                '[class*=\"cookie\"] [class*=\"close\"], [class*=\"cookie\"] [class*=\"dismiss\"], ' +
                '[id*=\"cookie\"] button[class*=\"close\"], ' +
                '.cookie-banner .close, #cookie-notice .close'
            );
            for (var k = 0; k < closeBtns.length; k++) {
                try { closeBtns[k].click(); return; } catch(e) {}
            }
        }
        
        // Try multiple times as banners may load late
        setTimeout(dismissCookies, 1000);
        setTimeout(dismissCookies, 3000);
        setTimeout(dismissCookies, 5000);
        
        // Watch for dynamically added banners
        var cookieObserver = new MutationObserver(function() {
            dismissCookies();
        });
        cookieObserver.observe(document.documentElement, { childList: true, subtree: true });
        setTimeout(function() { cookieObserver.disconnect(); }, 15000);
    })();
    """
}

// MARK: - Notification
extension Notification.Name {
    static let adBlockRulesUpdated = Notification.Name("adBlockRulesUpdated")
}
