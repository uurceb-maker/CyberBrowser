import Foundation

// MARK: - AdGuard Filter Converter
// Converts AdGuard/EasyList filter syntax to Apple's Content Blocker JSON format
// This allows using standard ad-blocking filter lists directly in WKContentRuleList

struct AdGuardFilterConverter {
    
    // MARK: - Convert Filter Text to Apple JSON Rules
    /// Parses AdGuard/EasyList format filter rules and generates Apple Content Blocker JSON
    /// - Parameter filterText: Raw filter list text (EasyList, AdGuard Base, etc.)
    /// - Returns: Array of Apple Content Blocker rule dictionaries
    static func convert(filterText: String) -> [[String: Any]] {
        var rules: [[String: Any]] = []
        
        let lines = filterText.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip comments and metadata
            if trimmed.isEmpty || trimmed.hasPrefix("!") || trimmed.hasPrefix("[") {
                continue
            }
            
            // Parse the rule type
            if let rule = parseRule(trimmed) {
                rules.append(rule)
            }
        }
        
        return rules
    }
    
    // MARK: - Parse a Single Filter Rule
    private static func parseRule(_ rule: String) -> [String: Any]? {
        // Whitelist rules: @@||domain^
        if rule.hasPrefix("@@") {
            return parseWhitelistRule(String(rule.dropFirst(2)))
        }
        
        // Element hiding rules: ##.selector or domain##.selector
        if rule.contains("##") {
            return parseElementHideRule(rule)
        }
        
        // Element hiding exception: domain#@#.selector
        if rule.contains("#@#") {
            // Skip exception rules for now (complex)
            return nil
        }
        
        // Network blocking rules: ||domain^ or |https://domain
        return parseNetworkRule(rule)
    }
    
    // MARK: - Network Block Rules
    // ||domain^ → block requests to domain
    private static func parseNetworkRule(_ rule: String) -> [String: Any]? {
        var pattern = rule
        var trigger: [String: Any] = [:]
        var options: [String] = []
        
        // Extract options after $
        if let dollarIndex = pattern.lastIndex(of: "$") {
            let optionsStr = String(pattern[pattern.index(after: dollarIndex)...])
            options = optionsStr.components(separatedBy: ",")
            pattern = String(pattern[..<dollarIndex])
        }
        
        // Remove leading || (domain anchor)
        if pattern.hasPrefix("||") {
            pattern = String(pattern.dropFirst(2))
        }
        
        // Remove leading |
        if pattern.hasPrefix("|") {
            pattern = String(pattern.dropFirst(1))
        }
        
        // Remove trailing ^ (separator)
        if pattern.hasSuffix("^") {
            pattern = String(pattern.dropLast(1))
        }
        
        // Remove trailing |
        if pattern.hasSuffix("|") {
            pattern = String(pattern.dropLast(1))
        }
        
        // Skip if pattern is too short or generic
        guard pattern.count >= 3 else { return nil }
        
        // Convert to regex pattern
        let regexPattern = convertToRegex(pattern)
        trigger["url-filter"] = regexPattern
        
        // Parse options
        var action: [String: Any] = ["type": "block"]
        
        for option in options {
            let opt = option.trimmingCharacters(in: .whitespaces).lowercased()
            
            switch opt {
            case "third-party":
                trigger["load-type"] = ["third-party"]
            case "first-party", "~third-party":
                trigger["load-type"] = ["first-party"]
            case "script":
                trigger["resource-type"] = ["script"]
            case "image":
                trigger["resource-type"] = ["image"]
            case "stylesheet", "css":
                trigger["resource-type"] = ["style-sheet"]
            case "xmlhttprequest", "xhr":
                trigger["resource-type"] = ["raw"]
            case "media":
                trigger["resource-type"] = ["media"]
            case "font":
                trigger["resource-type"] = ["font"]
            case "document", "subdocument":
                trigger["resource-type"] = ["document"]
            case "popup":
                trigger["resource-type"] = ["popup"]
            default:
                // Handle domain= options
                if opt.hasPrefix("domain=") {
                    let domains = String(opt.dropFirst(7))
                    let domainList = domains.components(separatedBy: "|")
                    var ifDomains: [String] = []
                    var unlessDomains: [String] = []
                    
                    for d in domainList {
                        if d.hasPrefix("~") {
                            unlessDomains.append("*" + String(d.dropFirst(1)))
                        } else {
                            ifDomains.append("*" + d)
                        }
                    }
                    
                    if !ifDomains.isEmpty {
                        trigger["if-domain"] = ifDomains
                    }
                    if !unlessDomains.isEmpty {
                        trigger["unless-domain"] = unlessDomains
                    }
                }
            }
        }
        
        return [
            "trigger": trigger,
            "action": action
        ]
    }
    
    // MARK: - Whitelist Rules
    // @@||domain^ → ignore previous rules for domain
    private static func parseWhitelistRule(_ rule: String) -> [String: Any]? {
        var pattern = rule
        
        // Remove || prefix
        if pattern.hasPrefix("||") {
            pattern = String(pattern.dropFirst(2))
        }
        
        // Remove ^ suffix
        if pattern.hasSuffix("^") {
            pattern = String(pattern.dropLast(1))
        }
        
        // Remove options
        if let dollarIndex = pattern.lastIndex(of: "$") {
            pattern = String(pattern[..<dollarIndex])
        }
        
        guard pattern.count >= 3 else { return nil }
        
        return [
            "trigger": [
                "url-filter": convertToRegex(pattern)
            ] as [String: Any],
            "action": [
                "type": "ignore-previous-rules"
            ]
        ]
    }
    
    // MARK: - Element Hiding Rules
    // ##.ad-banner → css-display-none
    // domain##.popup → css-display-none for specific domain
    private static func parseElementHideRule(_ rule: String) -> [String: Any]? {
        let parts = rule.components(separatedBy: "##")
        guard parts.count == 2 else { return nil }
        
        let domains = parts[0]
        let selector = parts[1]
        
        guard !selector.isEmpty else { return nil }
        
        var trigger: [String: Any] = ["url-filter": ".*"]
        
        // If domain-specific
        if !domains.isEmpty {
            let domainList = domains.components(separatedBy: ",")
            var ifDomains: [String] = []
            var unlessDomains: [String] = []
            
            for d in domainList {
                let trimmedDomain = d.trimmingCharacters(in: .whitespaces)
                if trimmedDomain.hasPrefix("~") {
                    unlessDomains.append("*" + String(trimmedDomain.dropFirst(1)))
                } else {
                    ifDomains.append("*" + trimmedDomain)
                }
            }
            
            if !ifDomains.isEmpty {
                trigger["if-domain"] = ifDomains
            }
            if !unlessDomains.isEmpty {
                trigger["unless-domain"] = unlessDomains
            }
        }
        
        return [
            "trigger": trigger,
            "action": [
                "type": "css-display-none",
                "selector": selector
            ] as [String: Any]
        ]
    }
    
    // MARK: - Pattern to Regex Converter
    private static func convertToRegex(_ pattern: String) -> String {
        var regex = pattern
        
        // Escape special regex characters (except *)
        regex = regex.replacingOccurrences(of: ".", with: "\\.")
        regex = regex.replacingOccurrences(of: "?", with: "\\?")
        regex = regex.replacingOccurrences(of: "+", with: "\\+")
        regex = regex.replacingOccurrences(of: "[", with: "\\[")
        regex = regex.replacingOccurrences(of: "]", with: "\\]")
        regex = regex.replacingOccurrences(of: "(", with: "\\(")
        regex = regex.replacingOccurrences(of: ")", with: "\\)")
        regex = regex.replacingOccurrences(of: "{", with: "\\{")
        regex = regex.replacingOccurrences(of: "}", with: "\\}")
        
        // Convert * wildcard to regex .*
        regex = regex.replacingOccurrences(of: "*", with: ".*")
        
        return regex
    }
    
    // MARK: - Convert Rules to JSON String
    static func convertToJSON(filterText: String) -> String? {
        let rules = convert(filterText: filterText)
        guard !rules.isEmpty else { return nil }
        
        guard let data = try? JSONSerialization.data(withJSONObject: rules, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return json
    }
    
    // MARK: - Built-in Filters
    // AdGuard Turkish Filter + popular rules embedded
    static let adguardTurkishFilter: String = """
    ! AdGuard Turkish Filter (subset)
    ! Maintained by AdGuard team
    ||reklam.hurriyet.com.tr^
    ||ads.sahibinden.com^
    ||ad.mncdn.com^
    ||reklam.mynet.com^
    ||ads.milliyet.com.tr^
    ||ads.sozcu.com.tr^
    ||i.hizliresim.com^$third-party
    ||reklamstore.com^
    ||reklam.internethaber.com^
    ||ads.ensonhaber.com^
    ||istatistik.hurriyet.com.tr^
    ||ads.haberturk.com^
    ||reklam.posta.com.tr^
    ||adriver.yandex.com.tr^
    ||hedef.hurriyet.com.tr^
    ||analytics.hurriyet.com.tr^
    ##.reklam-banner
    ##.ad-banner
    ##[class*="reklam"]
    ##[id*="reklam"]
    ##.sponsor-banner
    ##.sponsorlu-icerik
    ##.publicidade
    """
    
    static let adguardBaseSubset: String = """
    ! AdGuard Base Filter (critical rules subset)
    ||doubleclick.net^
    ||googlesyndication.com^$third-party
    ||googleadservices.com^
    ||google-analytics.com^$third-party
    ||googletagmanager.com^$third-party
    ||facebook.net^$third-party
    ||facebook.com/tr^$third-party
    ||hotjar.com^$third-party
    ||clarity.ms^$third-party
    ||segment.com^$third-party
    ||mixpanel.com^$third-party
    ||amplitude.com^$third-party
    ||fullstory.com^$third-party
    ||crazyegg.com^$third-party
    ||mouseflow.com^$third-party
    ||taboola.com^$third-party
    ||outbrain.com^$third-party
    ||amazon-adsystem.com^$third-party
    ||criteo.com^$third-party
    ||adnxs.com^$third-party
    ||rubiconproject.com^$third-party
    ||openx.net^$third-party
    ||pubmatic.com^$third-party
    ||mopub.com^$third-party
    ||adjust.com^$third-party
    ||appsflyer.com^$third-party
    ||branch.io^$third-party
    ||onesignal.com^$third-party
    ||pushwoosh.com^$third-party
    ||scorecardresearch.com^$third-party
    ||quantserve.com^$third-party
    ||newrelic.com^$third-party
    ##.adsbygoogle
    ##ins.adsbygoogle
    ##[class*="ad-container"]
    ##[class*="ad-wrapper"]
    ##[class*="advertisement"]
    ##[class*="sponsored"]
    ##.ytp-ad-module
    ##.ytp-ad-overlay-container
    ##.video-ads
    ##.ad-showing
    """
    
    // MARK: - Generate Apple JSON from Built-in Filters
    static func generateBuiltInFilterRules() -> [[String: Any]] {
        var allRules: [[String: Any]] = []
        
        // Parse Turkish filter
        allRules.append(contentsOf: convert(filterText: adguardTurkishFilter))
        
        // Parse base filter
        allRules.append(contentsOf: convert(filterText: adguardBaseSubset))
        
        return allRules
    }
}
