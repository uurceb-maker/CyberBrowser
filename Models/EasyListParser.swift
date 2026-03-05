import Foundation

struct EasyListParser {

    struct ContentBlockerRule: Codable {
        var trigger: Trigger
        var action: Action

        struct Trigger: Codable {
            var urlFilter: String
            var resourceType: [String]?
            var loadType: [String]?
            var ifDomain: [String]?
            var unlessDomain: [String]?

            enum CodingKeys: String, CodingKey {
                case urlFilter = "url-filter"
                case resourceType = "resource-type"
                case loadType = "load-type"
                case ifDomain = "if-domain"
                case unlessDomain = "unless-domain"
            }
        }

        struct Action: Codable {
            var type: String
            var selector: String?
        }
    }

    /// EasyList .txt -> Apple Content Blocker rules.
    static func parse(_ rawText: String, maxRules: Int = 50000) -> [ContentBlockerRule] {
        var rules: [ContentBlockerRule] = []
        let lines = rawText.components(separatedBy: .newlines)

        for line in lines {
            guard rules.count < maxRules else { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip comments and metadata blocks.
            if trimmed.isEmpty || trimmed.hasPrefix("!") || trimmed.hasPrefix("[") { continue }

            if let cssRule = parseCSSHideRule(trimmed) {
                rules.append(cssRule)
                continue
            }

            if let networkRule = parseNetworkRule(trimmed) {
                rules.append(networkRule)
                continue
            }
        }

        return rules
    }

    /// "##.ad-banner" -> css-display-none action.
    private static func parseCSSHideRule(_ line: String) -> ContentBlockerRule? {
        guard let hashIndex = line.range(of: "##") else { return nil }
        let domains = String(line[line.startIndex..<hashIndex.lowerBound])
        let selector = String(line[hashIndex.upperBound...])
        guard !selector.isEmpty else { return nil }

        if line.hasPrefix("@@") { return nil }

        var trigger = ContentBlockerRule.Trigger(urlFilter: ".*")
        if !domains.isEmpty {
            let domainList = domains.split(separator: ",").map {
                "*" + String($0).trimmingCharacters(in: .whitespaces)
            }
            trigger.ifDomain = domainList
        }

        return ContentBlockerRule(
            trigger: trigger,
            action: ContentBlockerRule.Action(type: "css-display-none", selector: selector)
        )
    }

    /// "||ads.example.com^" -> block action.
    private static func parseNetworkRule(_ line: String) -> ContentBlockerRule? {
        if line.hasPrefix("@@") { return nil }
        if line.contains("##") || line.contains("#@#") { return nil }

        var pattern = line
        var resourceTypes: [String]? = nil
        var loadType: [String]? = nil

        if let dollarIndex = pattern.lastIndex(of: "$") {
            let options = String(pattern[pattern.index(after: dollarIndex)...])
            pattern = String(pattern[..<dollarIndex])

            let optList = options.lowercased().split(separator: ",")
            var types: [String] = []

            for opt in optList {
                switch opt {
                case "script":
                    types.append("script")
                case "image":
                    types.append("image")
                case "stylesheet":
                    types.append("style-sheet")
                case "xmlhttprequest":
                    types.append("raw")
                case "subdocument":
                    types.append("document")
                case "media":
                    types.append("media")
                case "popup":
                    types.append("popup")
                case "third-party":
                    loadType = ["third-party"]
                case "~third-party":
                    loadType = ["first-party"]
                default:
                    break
                }
            }

            if !types.isEmpty {
                resourceTypes = Array(Set(types))
            }
        }

        var regex = pattern
        if regex.hasPrefix("||") {
            regex = String(regex.dropFirst(2))
            regex = "^https?://([^/]+\\.)?" + NSRegularExpression.escapedPattern(for: regex)
        } else if regex.hasPrefix("|") {
            regex = "^" + NSRegularExpression.escapedPattern(for: String(regex.dropFirst()))
        } else {
            regex = NSRegularExpression.escapedPattern(for: regex)
        }

        regex = regex.replacingOccurrences(of: "\\^", with: "[^a-z0-9._-]")
        regex = regex.replacingOccurrences(of: "\\*", with: ".*")
        guard !regex.isEmpty else { return nil }

        var trigger = ContentBlockerRule.Trigger(urlFilter: regex)
        trigger.resourceType = resourceTypes
        trigger.loadType = loadType

        return ContentBlockerRule(
            trigger: trigger,
            action: ContentBlockerRule.Action(type: "block")
        )
    }

    static func toJSON(_ rules: [ContentBlockerRule]) -> String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(rules) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
