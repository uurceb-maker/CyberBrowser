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

final class AdBlockEngine: ObservableObject, @unchecked Sendable {
    
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
        "/kayip-bonusu", "/hosgeldin-bonusu", "/uye-ol", "/iddaa", "/poker", "/jackpot"
    ]
    private let suspiciousGamblingKeywords: Set<String> = [
        "bet", "casino", "bahis", "slot", "jackpot", "spin", "iddaa", "poker"
    ]
    private let suspiciousGamblingTLDs: Set<String> = [
        "bet", "casino", "slot", "poker"
    ]
    private let safeBrowsingHostFragments: Set<String> = [
        "google", "youtube", "apple", "amazon", "trendyol", "hepsiburada", "n11",
        "sahibinden", "yemeksepeti", "getir", "migros", "akakce", "hurriyet",
        "milliyet", "sabah", "sozcu", "ntv", "haberturk", "cnn", "bbc"
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
    private let maxEasyListDownloadBytes = 8 * 1024 * 1024
    private let maxEasyListRuleCount = 150000
    private let easyListIdentifierPrefix = "easylist_"
    private let easyListRuleCountKey = "easyListRuleCount"
    private let easyListChunkCountKey = "easyListChunkCount"
    private var embeddedRuleGroupCount: Int = 0
    private var easyListActiveRuleCount: Int = 0
    private static let expandedRequestResourceTypes = [
        "document", "script", "image", "style-sheet",
        "raw", "font", "svg-document", "popup"
    ]
    private static let mediaAdBlockKeywords: Set<String> = [
        "doubleclick", "googlesyndication", "googleadservices", "pagead", "gampad",
        "pubads", "imasdk", "vast", "vpaid", "adserver", "preroll", "midroll", "2mdn"
    ]
    private static let protectedVideoExtensions: Set<String> = [
        "m3u8", "ts", "mpd", "mp4", "webm", "m4v", "mov"
    ]
    private static let protectedVideoHostFragments: Set<String> = [
        "googlevideo.com", "youtube.com", "youtu.be", "youtubei.googleapis.com",
        "vimeo.com", "player.vimeo.com", "blutv.com", "exxen.com",
        "gain.tv", "mubi.com", "puhutv.com", "tabii.com", "tod.tv"
    ]
    private static let directBypassVideoHosts: Set<String> = [
        "youtube.com", "youtu.be", "vimeo.com", "blutv.com",
        "exxen.com", "gain.tv", "puhutv.com", "tabii.com", "mubi.com", "tod.tv"
    ]
    private static let protectedVideoPathFragments: Set<String> = [
        "videoplayback", "manifest", "segment", "chunk", "playlist", "stream", "hls", "dash"
    ]
    private static let videoAdEndpointFragments: Set<String> = [
        "imasdk.googleapis.com", "pubads.g.doubleclick.net", "googleads.g.doubleclick.net",
        "/api/stats/ads", "/pagead/", "/gampad/", "vast", "vpaid", "preroll", "midroll", "ad_break"
    ]

    private struct PreparedRuleChunk: Sendable {
        let identifier: String
        let encodedContentRuleList: String
        let index: Int
        let ruleCount: Int
    }

    private final class VoidCallbackBox: @unchecked Sendable {
        private let callback: () -> Void

        init(_ callback: @escaping () -> Void) {
            self.callback = callback
        }

        func call() {
            callback()
        }
    }

    private final class BoolCallbackBox: @unchecked Sendable {
        private let callback: (Bool) -> Void

        init(_ callback: @escaping (Bool) -> Void) {
            self.callback = callback
        }

        func call(_ value: Bool) {
            callback(value)
        }
    }
    
    // MARK: - init
    init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "adBlockEnabled") as? Bool ?? true
    }

    @MainActor
    private func contentRuleListStore() -> WKContentRuleListStore? {
        WKContentRuleListStore.default()
    }

    @MainActor
    private func compileRuleList(
        in store: WKContentRuleListStore,
        identifier: String,
        encodedContentRuleList: String
    ) async -> (WKContentRuleList?, Error?) {
        await withCheckedContinuation { continuation in
            store.compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: encodedContentRuleList
            ) { ruleList, error in
                continuation.resume(returning: (ruleList, error))
            }
        }
    }

    @MainActor
    private func loadRuleListFromStore(
        _ identifier: String,
        store: WKContentRuleListStore
    ) async -> WKContentRuleList? {
        try? await store.contentRuleList(forIdentifier: identifier)
    }

    @MainActor
    private func replaceEasyListRuleLists(with ruleLists: [WKContentRuleList]) {
        let embeddedLists = Array(compiledRuleLists.prefix(embeddedRuleGroupCount))
        compiledRuleLists = embeddedLists + ruleLists
    }

    @MainActor
    private func notifyEasyListDidUpdate() {
        NotificationCenter.default.post(name: .easyListDidUpdate, object: nil)
    }

    private static func mergedResourceTypes(existing: [String]) -> [String] {
        let merged = Set(existing).union(expandedRequestResourceTypes)
        return expandedRequestResourceTypes.filter { merged.contains($0) }
    }

    private static func expandBlockRules(_ rules: [[String: Any]]) -> [[String: Any]] {
        rules.map { rule in
            guard
                let action = rule["action"] as? [String: Any],
                let actionType = action["type"] as? String,
                actionType == "block",
                var trigger = rule["trigger"] as? [String: Any]
            else {
                return rule
            }

            let currentTypes = trigger["resource-type"] as? [String] ?? []
            let filterText = (trigger["url-filter"] as? String ?? "").lowercased()
            var resourceTypes = mergedResourceTypes(existing: currentTypes)

            if Self.mediaAdBlockKeywords.contains(where: { filterText.contains($0) }) {
                resourceTypes = resourceTypes + (resourceTypes.contains("media") ? [] : ["media"])
            }

            trigger["resource-type"] = resourceTypes.filter { type in
                type != "media" || Self.mediaAdBlockKeywords.contains(where: { filterText.contains($0) })
            }

            var updatedRule = rule
            updatedRule["trigger"] = trigger
            return updatedRule
        }
    }

    private static func normalizedRuleJSON(_ jsonString: String) -> String {
        guard
            let data = jsonString.data(using: .utf8),
            let rules = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            let normalizedData = try? JSONSerialization.data(withJSONObject: expandBlockRules(rules)),
            let normalizedJSON = String(data: normalizedData, encoding: .utf8)
        else {
            return jsonString
        }

        return normalizedJSON
    }

    private func isKnownSafeHost(_ host: String) -> Bool {
        safeBrowsingHostFragments.contains { host.contains($0) }
    }

    func isSuspiciousGamblingURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        if isKnownSafeHost(host) {
            return false
        }

        if let tld = host.split(separator: ".").last.map(String.init),
           suspiciousGamblingTLDs.contains(tld) {
            return true
        }

        if suspiciousGamblingKeywords.contains(where: { host.contains($0) }) {
            return true
        }

        let absolute = url.absoluteString.lowercased()
        return suspiciousGamblingKeywords.contains(where: { absolute.contains($0) })
    }

    private func writeEasyListCache(_ jsonString: String) {
        guard
            let cacheURL = getCacheFileURL(),
            let data = jsonString.data(using: .utf8),
            data.count <= maxEasyListDownloadBytes
        else {
            return
        }

        try? data.write(to: cacheURL, options: [.atomic, .completeFileProtection])
    }
    
    // MARK: - Compile Rules (Main Entry Point)
    @MainActor
    func compileRules(completion: @escaping () -> Void) {
        let completionBox = VoidCallbackBox(completion)
        guard isEnabled else {
            filterInfo = "Devre dışı"
            compiledRuleLists = []
            completionBox.call()
            return
        }
        
        guard !isCompiling else {
            completionBox.call()
            return
        }
        isCompiling = true
        filterInfo = "Kurallar derleniyor..."
        
        // Step 1: Compile embedded rules FIRST (instant, guaranteed)
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            await self.compileEmbeddedRules()
            self.downloadAndCompileEasyList()
            
            // Don't wait for download — return immediately with embedded rules
            completionBox.call()
        }
    }
    
    // MARK: - Compile Embedded Rules (instant, no download)
    @MainActor
    private func compileEmbeddedRules() async {
        guard let store = contentRuleListStore() else {
            compiledRuleLists = []
            embeddedRuleGroupCount = 0
            easyListActiveRuleCount = 0
            isCompiling = false
            needsRecompile = false
            updateFilterInfo()
            print("[AdBlock] Content rule store unavailable")
            return
        }

        let embeddedSources: [(identifier: String, rules: String, label: String, expandResourceTypes: Bool)] = [
            ("embedded_network", Self.networkBlockRules, "Network", true),
            ("embedded_css", Self.cssHideRules, "CSS", false),
            ("embedded_first_party", Self.firstPartyPathRules, "First-party", true)
        ]

        var compiled: [WKContentRuleList] = []
        compiled.reserveCapacity(embeddedSources.count)

        for source in embeddedSources {
            let encodedRules = source.expandResourceTypes
                ? Self.normalizedRuleJSON(source.rules)
                : source.rules

            let (ruleList, error) = await compileRuleList(
                in: store,
                identifier: source.identifier,
                encodedContentRuleList: encodedRules
            )

            if let ruleList = ruleList {
                compiled.append(ruleList)
                print("[AdBlock] \(source.label) rules compiled")
            } else {
                print("[AdBlock] \(source.label) rules failed: \(error?.localizedDescription ?? "unknown")")
            }
        }

        compiledRuleLists = compiled
        embeddedRuleGroupCount = compiled.count
        easyListActiveRuleCount = 0
        isCompiling = false
        needsRecompile = false
        updateFilterInfo()
        print("[AdBlock] Embedded compilation: \(compiled.count)/3 groups compiled")
    }

#if false
    private func compileEmbeddedRules(completion: @escaping () -> Void) {
        let completionBox = VoidCallbackBox(completion)
        let store = WKContentRuleListStore.default()
        let group = DispatchGroup()
        let compiled = LockedRuleListArray()
        
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
            let compiledLists = compiled.snapshot()
            self.compiledRuleLists = compiledLists
            self.embeddedRuleGroupCount = compiled.count()
            self.easyListActiveRuleCount = 0
            self.isCompiling = false
            self.needsRecompile = false
            self.updateFilterInfo()
            print("[AdBlock] Embedded compilation: \(compiledLists.count)/3 groups compiled")
            completionBox.call()
        }
    }

#endif

    @MainActor
    private func updateFilterInfo() {
        filterInfo = "\(embeddedRuleGroupCount) embedded + \(easyListActiveRuleCount) EasyList kuralı aktif"
    }
    
    // MARK: - Download EasyList (background enhancement with retry + fallback)
    private func downloadAndCompileEasyList() {
        Task { [weak self] in
            guard let self = self else { return }
            if await self.loadCompiledEasyListFromStore() {
                return
            }

            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else { return }
                if let cacheURL = self.getCacheFileURL(),
                   FileManager.default.fileExists(atPath: cacheURL.path),
                   let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
                   let modDate = attrs[.modificationDate] as? Date,
                   let cacheSize = (attrs[.size] as? NSNumber)?.intValue,
                   cacheSize <= self.maxEasyListDownloadBytes,
                   Date().timeIntervalSince(modDate) < self.cacheMaxAgeDays * 86400,
                   let data = try? Data(contentsOf: cacheURL),
                   data.count <= self.maxEasyListDownloadBytes,
                   let rawText = String(data: data, encoding: .utf8) {
                    print("[AdBlock] Loading EasyList from cache")
                    self.processEasyListRawText(rawText)
                    return
                }

                self.tryDownloadEasyList(urlIndex: 0, attempt: 0)
            }
        }
    }

    @MainActor
    private func loadCompiledEasyListFromStore() async -> Bool {
        let chunkCount = UserDefaults.standard.integer(forKey: easyListChunkCountKey)
        guard chunkCount > 0 else {
            return false
        }

        guard let store = contentRuleListStore() else {
            return false
        }

        var ordered: [WKContentRuleList] = []
        ordered.reserveCapacity(chunkCount)

        for i in 0..<chunkCount {
            let identifier = "\(easyListIdentifierPrefix)\(i)"
            guard let ruleList = await loadRuleListFromStore(identifier, store: store) else {
                UserDefaults.standard.removeObject(forKey: easyListChunkCountKey)
                UserDefaults.standard.removeObject(forKey: easyListRuleCountKey)
                return false
            }
            ordered.append(ruleList)
        }

        replaceEasyListRuleLists(with: ordered)
        easyListActiveRuleCount = UserDefaults.standard.integer(forKey: easyListRuleCountKey)
        updateFilterInfo()
        print("[AdBlock] Loaded EasyList from compiled cache (\(ordered.count) chunks)")
        notifyEasyListDidUpdate()
        return true
    }

    private func processEasyListRawText(_ rawText: String, completion: ((Bool) -> Void)? = nil) {
        let completionBox = completion.map(BoolCallbackBox.init)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                completionBox?.call(false)
                return
            }

            if trimmed.hasPrefix("[") {
                self.writeEasyListCache(trimmed)
                self.compileDownloadedRules(trimmed) { success in
                    completionBox?.call(success)
                }
                return
            }

            let parsedRules = EasyListParser.parse(trimmed, maxRules: self.maxRulesPerChunk)
            guard !parsedRules.isEmpty, let parsedJSON = EasyListParser.toJSON(parsedRules) else {
                print("[AdBlock] EasyList parse failed or produced no rules")
                completionBox?.call(false)
                return
            }

            self.writeEasyListCache(parsedJSON)
            print("[AdBlock] Cached parsed EasyList (\(parsedRules.count) rules)")

            self.compileDownloadedRules(parsedJSON) { success in
                completionBox?.call(success)
            }
        }
    }

    private func tryDownloadEasyList(urlIndex: Int, attempt: Int) {
        guard urlIndex < easyListURLs.count else {
            print("[AdBlock] All EasyList sources failed - embedded rules are sufficient")
            return
        }

        guard let url = URL(string: easyListURLs[urlIndex]) else {
            tryDownloadEasyList(urlIndex: urlIndex + 1, attempt: 0)
            return
        }

        print("[AdBlock] Downloading EasyList (source \(urlIndex + 1)/\(easyListURLs.count), attempt \(attempt + 1))...")

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        let session = URLSession(configuration: config)

        session.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            if let data = data,
               error == nil,
               let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                guard data.count <= self.maxEasyListDownloadBytes else {
                    print("[AdBlock] EasyList payload too large: \(data.count) bytes")
                    self.tryDownloadEasyList(urlIndex: urlIndex + 1, attempt: 0)
                    return
                }

                guard let rawText = String(data: data, encoding: .utf8) else {
                    self.tryDownloadEasyList(urlIndex: urlIndex + 1, attempt: 0)
                    return
                }

                self.processEasyListRawText(rawText) { success in
                    guard !success else { return }
                    self.tryDownloadEasyList(urlIndex: urlIndex + 1, attempt: 0)
                }
                return
            }

            let nextAttempt = attempt + 1
            if nextAttempt < self.maxRetryAttempts {
                let delay = Double(nextAttempt) * 2.0
                print("[AdBlock] Retry in \(delay)s...")
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    self.tryDownloadEasyList(urlIndex: urlIndex, attempt: nextAttempt)
                }
            } else {
                print("[AdBlock] Source \(urlIndex + 1) failed, trying next...")
                self.tryDownloadEasyList(urlIndex: urlIndex + 1, attempt: 0)
            }
        }.resume()
    }

    // MARK: - Compile Downloaded Rules
    private func compileDownloadedRules(_ jsonString: String, completion: ((Bool) -> Void)? = nil) {
        let completionBox = completion.map(BoolCallbackBox.init)
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[") else {
            print("[AdBlock] Downloaded list is not JSON rule format, skipped")
            completionBox?.call(false)
            return
        }

        guard trimmed.utf8.count <= maxEasyListDownloadBytes else {
            print("[AdBlock] Downloaded list exceeds size limit")
            completionBox?.call(false)
            return
        }

        guard let data = trimmed.data(using: .utf8),
              let allRules = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            print("[AdBlock] Downloaded JSON parse failed")
            completionBox?.call(false)
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

        let boundedRules: [[String: Any]]
        if validRules.count > maxEasyListRuleCount {
            boundedRules = Array(validRules.prefix(maxEasyListRuleCount))
            print("[AdBlock] Truncated downloaded rules to \(maxEasyListRuleCount)")
        } else {
            boundedRules = validRules
        }

        guard !boundedRules.isEmpty else {
            print("[AdBlock] Downloaded list has no valid rules")
            completionBox?.call(false)
            return
        }

        let normalizedRules = Self.expandBlockRules(boundedRules)
        let totalRules = normalizedRules.count
        let chunks = stride(from: 0, to: totalRules, by: maxRulesPerChunk).map { start in
            Array(normalizedRules[start..<min(start + maxRulesPerChunk, totalRules)])
        }

        var preparedChunks: [PreparedRuleChunk] = []
        preparedChunks.reserveCapacity(chunks.count)
        for (i, chunk) in chunks.enumerated() {
            guard let chunkData = try? JSONSerialization.data(withJSONObject: chunk),
                  let chunkJSON = String(data: chunkData, encoding: .utf8) else {
                continue
            }
            preparedChunks.append(
                PreparedRuleChunk(
                    identifier: "\(easyListIdentifierPrefix)\(i)",
                    encodedContentRuleList: chunkJSON,
                    index: i,
                    ruleCount: chunk.count
                )
            )
        }

        guard !preparedChunks.isEmpty else {
            print("[AdBlock] Failed to prepare EasyList chunks")
            completionBox?.call(false)
            return
        }

        Task { @MainActor [weak self] in
            guard let self = self else {
                completionBox?.call(false)
                return
            }

            let success = await self.compilePreparedEasyListChunks(preparedChunks, totalRules: totalRules)
            completionBox?.call(success)
        }
    }

    @MainActor
    private func compilePreparedEasyListChunks(_ chunks: [PreparedRuleChunk], totalRules _: Int) async -> Bool {
        guard let store = contentRuleListStore() else {
            print("[AdBlock] Content rule store unavailable for EasyList")
            UserDefaults.standard.removeObject(forKey: easyListChunkCountKey)
            UserDefaults.standard.removeObject(forKey: easyListRuleCountKey)
            return false
        }

        var downloaded: [WKContentRuleList] = []
        downloaded.reserveCapacity(chunks.count)
        var successfulRuleCount = 0
        var hadFailures = false

        for chunk in chunks {
            let (ruleList, error) = await compileRuleList(
                in: store,
                identifier: chunk.identifier,
                encodedContentRuleList: chunk.encodedContentRuleList
            )

            guard let ruleList = ruleList else {
                print("[AdBlock] EasyList chunk \(chunk.index) failed: \(error?.localizedDescription ?? "unknown")")
                hadFailures = true
                continue
            }

            downloaded.append(ruleList)
            successfulRuleCount += chunk.ruleCount
            print("[AdBlock] EasyList chunk \(chunk.index): \(chunk.ruleCount) rules")
        }

        guard !downloaded.isEmpty else {
            UserDefaults.standard.removeObject(forKey: easyListChunkCountKey)
            UserDefaults.standard.removeObject(forKey: easyListRuleCountKey)
            return false
        }

        replaceEasyListRuleLists(with: downloaded)
        easyListActiveRuleCount = successfulRuleCount
        if hadFailures {
            UserDefaults.standard.removeObject(forKey: easyListChunkCountKey)
            UserDefaults.standard.removeObject(forKey: easyListRuleCountKey)
        } else {
            UserDefaults.standard.set(successfulRuleCount, forKey: easyListRuleCountKey)
            UserDefaults.standard.set(chunks.count, forKey: easyListChunkCountKey)
        }
        updateFilterInfo()
        print("[AdBlock] EasyList added: \(downloaded.count) chunks")

        notifyEasyListDidUpdate()
        return true
    }
    // MARK: - Apply Rules to WKUserContentController
    @MainActor func applyRules(to controller: WKUserContentController) {
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
            source: Self.antiAdBlockScriptV2,
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
            source: Self.optimizedCosmeticFilterScript,
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

        let trCosmeticScript = WKUserScript(
            source: Self.turkishNewsCosmeticScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        controller.addUserScript(trCosmeticScript)
        
        // Cookie consent auto-dismiss
        let cookieScript = WKUserScript(
            source: Self.cookieConsentScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        controller.addUserScript(cookieScript)
        
        let genericVideoScript = WKUserScript(
            source: Self.genericVideoAdAutomationScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        controller.addUserScript(genericVideoScript)

        let ytScript = WKUserScript(
            source: Self.youtubeAdSkipScriptV3,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        controller.addUserScript(ytScript)

        let ytStyleScript = WKUserScript(
            source: Self.youtubeAdStyleScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        controller.addUserScript(ytStyleScript)
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

        if isSuspiciousGamblingURL(url) {
            return true
        }

        return false
    }

    func shouldBypassBlocking(for url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return Self.directBypassVideoHosts.contains(where: { host.contains($0) })
    }

    func isProtectedVideoURL(_ url: URL) -> Bool {
        let absolute = url.absoluteString.lowercased()
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        let pathExtension = url.pathExtension.lowercased()

        if Self.protectedVideoExtensions.contains(pathExtension) {
            return true
        }

        if absolute.contains("/videoplayback") {
            return true
        }

        if Self.protectedVideoHostFragments.contains(where: { host.contains($0) }) {
            return !isVideoAdEndpoint(url)
        }

        let isGenericVideoHost = host.hasPrefix("cdn.") || host.hasPrefix("video.") || host.hasPrefix("stream.")
        if isGenericVideoHost && Self.protectedVideoPathFragments.contains(where: { absolute.contains($0) || path.contains($0) }) {
            return true
        }

        return false
    }

    func isVideoAdEndpoint(_ url: URL) -> Bool {
        let absolute = url.absoluteString.lowercased()
        return Self.videoAdEndpointFragments.contains(where: { absolute.contains($0) })
    }

    func shouldBlockURL(_ url: URL, mainDocumentURL: URL?) -> Bool {
        guard isEnabled else { return false }

        if isVideoAdEndpoint(url) {
            return true
        }

        if isProtectedVideoURL(url) || shouldBypassBlocking(for: url) {
            return false
        }

        if let mainHost = mainDocumentURL?.host?.lowercased(),
           Self.protectedVideoHostFragments.contains(where: { mainHost.contains($0) }),
           let host = url.host?.lowercased(),
           host == mainHost || host.hasSuffix(".\(mainHost)") {
            return false
        }

        return shouldBlockURL(url)
    }
    
    // MARK: - Handle Blocked Ad
    func handleBlockedAd(count: Int, domain: String) {
        blockedAdsCount += count
        if !domain.isEmpty {
            lastBlockedDomain = domain
        }
    }
    
    // MARK: - Cache Path
    private func getCacheFileURL() -> URL? {
        guard let docs = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
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
        {"trigger":{"url-filter":"^https?://.*\\.(m3u8|ts|mpd|mp4|webm)(\\?.*)?$"},"action":{"type":"ignore-previous-rules"}},
        {"trigger":{"url-filter":"^https?://([^.]+\\.)?(cdn|video|stream)[^/]*?/.*(manifest|segment|chunk|playlist|videoplayback).*"},"action":{"type":"ignore-previous-rules"}},
        {"trigger":{"url-filter":"^https?://.*"},"if-domain":["*blutv.com","*exxen.com","*gain.tv","*mubi.com","*puhutv.com","*tabii.com","*tod.tv"],"action":{"type":"ignore-previous-rules"}},
        {"trigger":{"url-filter":"^https?://.*youtube\\.com/videoplayback.*"},"action":{"type":"ignore-previous-rules"}},
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
        {"trigger":{"url-filter":"[\\/\\-_](reklam|sponsor|sponsored|promo|promotion)[\\/\\-_]","resource-type":["image","script","style-sheet","raw","svg-document","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"(banner|prebid|vast|preroll|midroll|instream|outstream|doubleclick|pagead|googlesyndication)","resource-type":["image","script","raw","popup"]},"action":{"type":"block"}},
        {"trigger":{"url-filter":"(casino|bahis|bet|bonus)","resource-type":["image","script","raw","popup"]},"action":{"type":"block"}}
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
            'casino', 'bahis', 'bonus'
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
            if (container.querySelector && container.querySelector('video')) return 0;
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
            const candidates = document.querySelectorAll('iframe, img, a[href], [id*="reklam"], [class*="reklam"], [id*="sponsor"], [class*="sponsor"]');
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

    static let optimizedCosmeticFilterScript: String = """
    (function() {
        'use strict';
        if (window.__cyberAdBlockInjectedV2) return;
        window.__cyberAdBlockInjectedV2 = true;

        var selectors = [
            '.adsbygoogle', 'ins.adsbygoogle', '[id^="google_ads"]', '[id^="div-gpt-ad"]',
            '[class*="ad-container"]', '[class*="ad-wrapper"]', '[class*="ad-banner"]',
            '[class*="adunit"]', '[class*="ad-slot"]', '[class*="ad_unit"]',
            '[class*="sponsored"]', '[class*="ad-placement"]', '[id*="taboola"]',
            '[class*="taboola"]', '[id*="outbrain"]', '[class*="outbrain"]',
            '.trc_related_container', '#taboola-below-article', '.ad-overlay',
            '#ad-overlay', '[class*="interstitial"]', '[id*="ad-popup"]',
            '[class*="ad-popup"]', '[id*="reklam"]', '[class*="reklam"]',
            '[id*="sponsor"]', '[class*="sponsor"]'
        ];
        var playerSelectors = [
            'video', 'audio', '[class*="player"]', '[id*="player"]',
            '[class*="video-js"]', '[class*="videojs"]', '[class*="jwplayer"]',
            '[id*="jwplayer"]', '[class*="bitmovin"]', '[class*="plyr"]',
            '[class*="vjs-"]', '.html5-video-container', '#movie_player', '.ytd-player'
        ];
        var adKeywords = ['reklam', 'ilan', 'sponsor', 'sponsored', 'promo', 'casino', 'bahis', 'bonus'];
        var pendingNodes = new Set();
        var rafId = null;

        function hasKeyword(text) {
            if (!text) return false;
            var lower = String(text).toLowerCase();
            for (var i = 0; i < adKeywords.length; i++) {
                if (lower.indexOf(adKeywords[i]) !== -1) return true;
            }
            return false;
        }

        function isProtected(node) {
            if (!node || node.nodeType !== 1) return true;
            try {
                if (node.matches(playerSelectors.join(','))) return true;
            } catch (e) {}
            if (node.tagName === 'VIDEO' || node.tagName === 'AUDIO') return true;
            if (node.querySelector && node.querySelector('video, audio')) return true;
            if (node.closest && node.closest('[class*="player"], [id*="player"], [class*="video-js"], [class*="jwplayer"], [class*="bitmovin"], [class*="plyr"], #movie_player, .ytd-player')) {
                return true;
            }
            try {
                var computed = window.getComputedStyle(node);
                var zIndex = parseInt(computed.zIndex || '0', 10);
                if (zIndex > 1000 && node.querySelector && node.querySelector('video, audio')) {
                    return true;
                }
            } catch (e) {}
            return false;
        }

        function notify(count) {
            if (!count) return;
            try {
                window.webkit.messageHandlers.adBlocked.postMessage({ count: count, url: location.hostname });
            } catch (e) {}
        }

        function hardHide(target) {
            if (!target || isProtected(target)) return 0;
            target.style.setProperty('display', 'none', 'important');
            target.style.setProperty('height', '0', 'important');
            target.style.setProperty('overflow', 'hidden', 'important');
            return 1;
        }

        function softHide(target) {
            if (!target || isProtected(target) || target.__cyberSoftHiddenV2) return 0;
            target.__cyberSoftHiddenV2 = true;
            target.style.setProperty('visibility', 'hidden', 'important');
            target.style.setProperty('pointer-events', 'none', 'important');
            setTimeout(function() {
                if (isProtected(target)) return;
                hardHide(target);
            }, 200);
            return 1;
        }

        function cleanNode(node) {
            if (!node || node.nodeType !== 1 || isProtected(node)) return 0;
            var className = typeof node.className === 'string' ? node.className : '';
            var id = node.id || '';
            var fastPath = (className + ' ' + id + ' ' + (node.textContent || '')).toLowerCase();
            var suspicious = hasKeyword(fastPath);
            if (!suspicious && node.matches) {
                suspicious = node.matches('[data-ad],[data-ad-slot],[class*="ads-"],[class*="taboola"],[class*="outbrain"]');
            }
            if (!suspicious) return 0;
            return softHide(node.closest('section, article, div, aside, li, figure') || node);
        }

        function scanSelectors(root) {
            var count = 0;
            var scope = root && root.querySelectorAll ? root : document;
            try {
                scope.querySelectorAll(selectors.join(',')).forEach(function(node) {
                    if (!isProtected(node)) {
                        count += softHide(node.closest('section, article, div, aside, li, figure') || node);
                    }
                });
            } catch (e) {}
            notify(count);
        }

        function flushPendingNodes() {
            var count = 0;
            pendingNodes.forEach(function(node) {
                count += cleanNode(node);
            });
            pendingNodes.clear();
            rafId = null;
            notify(count);
        }

        function scheduleFlush() {
            if (rafId) return;
            rafId = requestAnimationFrame(flushPendingNodes);
        }

        scanSelectors(document);

        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', function() {
                scanSelectors(document);
            }, { once: true });
        }

        window.addEventListener('load', function() {
            scanSelectors(document);
            setTimeout(function() { scanSelectors(document); }, 500);
            setTimeout(function() { scanSelectors(document); }, 1800);
        }, { once: true });

        var observer = new MutationObserver(function(mutations) {
            mutations.forEach(function(mutation) {
                mutation.addedNodes.forEach(function(node) {
                    if (node && node.nodeType === 1) {
                        pendingNodes.add(node);
                    }
                });
            });
            scheduleFlush();
        });
        observer.observe(document.body || document.documentElement, { childList: true });
        setTimeout(function() { observer.disconnect(); }, 60000);

        var deepScan = setInterval(function() {
            scanSelectors(document);
        }, 2500);
        setTimeout(function() { clearInterval(deepScan); }, 60000);
    })();
    """

    static let genericVideoAdAutomationScript: String = """
    (function() {
        'use strict';
        if (window.__cyberGenericVideoAdAutomation) return;
        window.__cyberGenericVideoAdAutomation = true;

        var skipSelectors = [
            '.ytp-ad-skip-button', '.ytp-skip-ad-button', '[class*="skip-button"]',
            '[class*="skip"][class*="ad"]', '[id*="skip"][id*="ad"]',
            '[class*="Skip"][class*="Ad"]', 'button[class*="reklam"]',
            '.skip-ad', '#skip-ad', '.reklamAtla', '.reklam-atla'
        ];
        var overlaySelectors = [
            '.ytp-ad-overlay-container', '.ytp-ad-text-overlay',
            '[class*="ad-overlay"]', '[class*="reklam-overlay"]',
            '.preroll-container', '.video-ads', '#player-ads'
        ];

        function clickVisibleSkipButtons() {
            skipSelectors.forEach(function(selector) {
                document.querySelectorAll(selector).forEach(function(button) {
                    if (button && button.offsetParent !== null) {
                        try { button.click(); } catch (e) {}
                    }
                });
            });
        }

        function removeOverlays() {
            overlaySelectors.forEach(function(selector) {
                document.querySelectorAll(selector).forEach(function(node) {
                    try { node.remove(); } catch (e) {
                        node.style.setProperty('display', 'none', 'important');
                    }
                });
            });
        }

        function accelerateAdVideo() {
            var video = document.querySelector('video');
            if (!video) return;
            var adBadge = document.querySelector('.ytp-ad-badge, .ytp-ad-text, [class*="preroll"], [class*="midroll"], [class*="ad-badge"]');
            if (!adBadge) return;

            if (Number.isFinite(video.duration) && video.duration > 1) {
                try { video.currentTime = Math.max(video.duration - 0.1, 0); } catch (e) {
                    video.playbackRate = 16;
                }
            } else {
                video.playbackRate = 16;
            }
        }

        function run() {
            clickVisibleSkipButtons();
            removeOverlays();
            accelerateAdVideo();
        }

        run();
        var interval = setInterval(run, 500);
        setTimeout(function() { clearInterval(interval); }, 180000);
    })();
    """

    static let youtubeAdSkipScriptV3: String = """
    (function() {
        'use strict';
        if (!location.hostname.includes('youtube.com')) return;
        if (window.__cyberYTv5) return;
        window.__cyberYTv5 = true;

        function clickSkipButton() {
            var skipBtn = document.querySelector(
                '.ytp-ad-skip-button, .ytp-skip-ad-button, .ytp-ad-skip-button-modern, ' +
                'button.ytp-ad-skip-button-modern, .ytp-ad-skip-button-slot, ' +
                '.videoAdUiSkipButton, .ytp-ad-skip-button-container button, [class*="skip-button"]'
            );
            if (skipBtn) {
                try { skipBtn.click(); } catch (e) {}
                return true;
            }
            return false;
        }

        function removeOverlays() {
            [
                '.ytp-ad-overlay-container', '.ytp-ad-text-overlay', '.ytp-ad-image-overlay',
                '.ytp-ad-player-overlay-flyout-cta', '.ytp-ad-action-interstitial',
                'ytd-promoted-sparkles-web-renderer', 'ytd-ad-slot-renderer',
                'ytd-in-feed-ad-layout-renderer', '.ytd-banner-promo-renderer',
                '.ytd-statement-banner-renderer', '#masthead-ad', '#player-ads'
            ].forEach(function(selector) {
                document.querySelectorAll(selector).forEach(function(node) {
                    node.style.setProperty('display', 'none', 'important');
                });
            });
        }

        function handleAdState() {
            var player = document.querySelector('.html5-video-player');
            var video = document.querySelector('video');
            var adBadge = document.querySelector('.ytp-ad-badge, .ytp-ad-text');
            var adShowing = !!(player && player.classList.contains('ad-showing')) || !!adBadge;

            removeOverlays();
            clickSkipButton();

            if (!video) return;

            if (adShowing) {
                video.__cyberAdMuted = true;
                video.muted = true;
                if (Number.isFinite(video.duration) && video.duration > 1) {
                    try { video.currentTime = Math.max(video.duration - 0.1, 0); } catch (e) {
                        video.playbackRate = 16;
                    }
                } else {
                    video.playbackRate = 16;
                }
                return;
            }

            if (video.playbackRate > 1) {
                video.playbackRate = 1;
            }
            if (video.__cyberAdMuted) {
                video.muted = false;
                video.__cyberAdMuted = false;
            }
        }

        function observePlayer() {
            var player = document.querySelector('.html5-video-player');
            if (!player) return;
            var observer = new MutationObserver(function() {
                handleAdState();
            });
            observer.observe(player, { attributes: true, attributeFilter: ['class'] });
            setTimeout(function() { observer.disconnect(); }, 300000);
        }

        handleAdState();
        observePlayer();

        var mainInterval = setInterval(handleAdState, 300);
        setTimeout(function() { clearInterval(mainInterval); }, 300000);
    })();
    """

    static let youtubeAdStyleScript: String = """
    (function() {
        if (window.__cyberYTStyleInjected) return;
        window.__cyberYTStyleInjected = true;

        var style = document.createElement('style');
        style.textContent = `
        .ytp-ad-module,
        .ytp-ad-overlay-container,
        .ytp-ad-progress,
        .ytp-ad-progress-list,
        #masthead-ad,
        .ytd-banner-promo-renderer,
        .ytd-statement-banner-renderer,
        ytd-ad-slot-renderer,
        ytd-in-feed-ad-layout-renderer,
        ytd-promoted-sparkles-web-renderer,
        #player-ads,
        #panels ytd-engagement-panel-section-list-renderer[target-id="engagement-panel-ads"] {
            display: none !important;
        }`;
        (document.head || document.documentElement).appendChild(style);
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

    static let antiAdBlockScriptV2: String = """
    (function() {
        'use strict';
        if (window.__cyberAntiDetectV2) return;

        try {
            Object.defineProperty(window, '__cyberAntiDetectV2', {
                value: true,
                configurable: false,
                writable: false
            });
        } catch (e) {
            window.__cyberAntiDetectV2 = true;
        }

        function defineReadOnly(target, key, value) {
            try {
                Object.defineProperty(target, key, {
                    value: value,
                    configurable: false,
                    writable: false,
                    enumerable: false
                });
            } catch (e) {
                try { target[key] = value; } catch (_) {}
            }
        }

        function noop() {}

        var googletagStub = {
            cmd: {
                push: function(fn) {
                    if (typeof fn === 'function') {
                        try { fn(); } catch (e) {}
                    }
                }
            },
            pubads: function() {
                return {
                    enableSingleRequest: noop,
                    collapseEmptyDivs: noop,
                    refresh: noop,
                    addEventListener: noop,
                    removeEventListener: noop
                };
            },
            enableServices: noop,
            display: noop,
            defineSlot: function() {
                return {
                    addService: function() { return this; },
                    setTargeting: function() { return this; }
                };
            }
        };

        defineReadOnly(window, 'adsbygoogle', {
            loaded: true,
            length: 1,
            push: function() { return 1; }
        });
        defineReadOnly(window, 'googletag', googletagStub);
        defineReadOnly(window, 'canRunAds', true);
        defineReadOnly(window, '_wq', []);
        defineReadOnly(window, 'AFRAME_LOADED', true);

        try {
            Object.defineProperty(navigator, 'webdriver', {
                get: function() { return false; },
                configurable: false
            });
        } catch (e) {}

        var originalCreateElement = Document.prototype.createElement;
        Document.prototype.createElement = new Proxy(originalCreateElement, {
            apply: function(target, thisArg, argArray) {
                var tag = String((argArray && argArray[0]) || '').toLowerCase();
                var element = Reflect.apply(target, thisArg, argArray);

                if (tag === 'ins') {
                    var originalSetAttribute = element.setAttribute;
                    element.setAttribute = function(name, value) {
                        if (
                            String(name).toLowerCase() === 'class' &&
                            String(value).toLowerCase().indexOf('adsbyg') !== -1
                        ) {
                            this.style.setProperty('display', 'none', 'important');
                            return value;
                        }
                        return originalSetAttribute.apply(this, arguments);
                    };

                    try {
                        Object.defineProperty(element, 'className', {
                            get: function() {
                                return this.getAttribute('class') || '';
                            },
                            set: function(value) {
                                if (String(value).toLowerCase().indexOf('adsbyg') !== -1) {
                                    this.style.setProperty('display', 'none', 'important');
                                    return value;
                                }
                                originalSetAttribute.call(this, 'class', value);
                                return value;
                            },
                            configurable: true
                        });
                    } catch (e) {}
                }

                return element;
            }
        });

        function hideInjectedAdNodes(root) {
            if (!root || root.nodeType !== 1) return;

            var targets = [];
            if (
                root.matches &&
                root.matches('.ads-container, #ad-wrapper, [data-ad-slot]')
            ) {
                targets.push(root);
            }

            if (root.querySelectorAll) {
                root.querySelectorAll('.ads-container, #ad-wrapper, [data-ad-slot]').forEach(function(node) {
                    targets.push(node);
                });
            }

            targets.forEach(function(node) {
                node.style.setProperty('display', 'none', 'important');
            });
        }

        hideInjectedAdNodes(document.documentElement);

        var antiDetectObserver = new MutationObserver(function(mutations) {
            mutations.forEach(function(mutation) {
                mutation.addedNodes.forEach(function(node) {
                    hideInjectedAdNodes(node);
                });
            });
        });

        antiDetectObserver.observe(document.documentElement || document, {
            childList: true,
            subtree: true
        });

        try {
            Object.defineProperty(window, 'blockAdBlock', {
                get: function() {
                    return {
                        onDetected: function() {},
                        onNotDetected: function(fn) { if (fn) fn(); }
                    };
                },
                set: function() {},
                configurable: false
            });
        } catch (e) {}

        try {
            Object.defineProperty(window, 'fuckAdBlock', {
                get: function() {
                    return {
                        onDetected: function() {},
                        onNotDetected: function(fn) { if (fn) fn(); }
                    };
                },
                set: function() {},
                configurable: false
            });
        } catch (e) {}
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

    static let turkishNewsCosmeticScript: String = """
    (function() {
        'use strict';
        if (window.__cyberTRCosmetic) return;
        window.__cyberTRCosmetic = true;

        var selectors = [
            '.reklam', '.reklam-alani', '.reklam-banner',
            '.ilan', '.ilan-container', '#ilan',
            "[class*='reklam']", "[id*='reklam']",
            "[class*='ilan']", "[id*='ilan']",
            '.sponsor', '.sponsorlu', "[class*='sponsor']",
            '.popup-overlay', '.popup-reklam', '#popup',
            "iframe[src*='doubleclick']", "iframe[src*='googlesyndication']",
            '.bahis-banner', "[class*='bahis']", "[class*='casino']",
            "div[style*='z-index: 9999'][style*='position: fixed']"
        ];

        function hideMatches(root) {
            if (!root || root.nodeType !== 1) return;

            selectors.forEach(function(selector) {
                try {
                    if (root.matches && root.matches(selector)) {
                        root.style.setProperty('display', 'none', 'important');
                        root.style.setProperty('height', '0', 'important');
                        root.style.setProperty('overflow', 'hidden', 'important');
                    }

                    if (!root.querySelectorAll) return;
                    root.querySelectorAll(selector).forEach(function(node) {
                        node.style.setProperty('display', 'none', 'important');
                        node.style.setProperty('height', '0', 'important');
                        node.style.setProperty('overflow', 'hidden', 'important');
                    });
                } catch (e) {}
            });
        }

        var style = document.createElement('style');
        style.textContent = selectors.join(',\\n') + '{display:none!important;height:0!important;overflow:hidden!important;}';
        (document.head || document.documentElement).appendChild(style);

        hideMatches(document.documentElement);

        var observer = new MutationObserver(function(mutations) {
            mutations.forEach(function(mutation) {
                mutation.addedNodes.forEach(function(node) {
                    hideMatches(node);
                });
            });
        });

        observer.observe(document.documentElement, {
            childList: true,
            subtree: true
        });

        setTimeout(function() {
            observer.disconnect();
        }, 120000);
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
            'bet', 'casino', 'bahis', 'slot', 'jackpot', 'poker', 'iddaa',
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

        blockedTextWords.push('iddaa');

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

        function showBlockedToast(message) {
            try {
                var oldToast = document.getElementById('__cyberToast');
                if (oldToast) oldToast.remove();
                var toast = document.createElement('div');
                toast.id = '__cyberToast';
                toast.textContent = message;
                toast.style.cssText = 'position:fixed;left:50%;bottom:24px;transform:translateX(-50%);z-index:2147483647;background:rgba(0,0,0,0.88);color:#fff;padding:10px 14px;border-radius:999px;font:600 12px -apple-system,BlinkMacSystemFont,sans-serif;';
                (document.body || document.documentElement).appendChild(toast);
                setTimeout(function() {
                    if (toast.parentNode) toast.parentNode.removeChild(toast);
                }, 1800);
            } catch (e) {}
        }

        // === 1. INJECT CSS — instantly hide known ad patterns ===
        var style = document.createElement('style');
        style.textContent = [
            '[class*="reklam"], [id*="reklam"] { display:none!important; height:0!important; }',
            '[class*="adsBox"], [id*="adsBox"] { display:none!important; }',
            '[class*="ad-overlay"], [id*="ad-overlay"] { display:none!important; }',
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
            if (url && isGamblingURL(String(url))) {
                showBlockedToast('Bahis popup engellendi');
                return null;
            }
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
    static let easyListDidUpdate = Notification.Name("easyListDidUpdate")
    static let adBlockRulesUpdated = Notification.Name("adBlockRulesUpdated")
}
