import Foundation

/// How serious a safety finding is.
enum SafetyLevel: Int, Comparable {
    case serious = 1    // red stop icon: can run code or harm the system
    case warning = 2    // yellow warning icon: likely deception
    case advisory = 3   // blue info icon: worth knowing, not alarming

    static func < (lhs: SafetyLevel, rhs: SafetyLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var symbolName: String {
        switch self {
        case .serious: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .advisory: return "info.circle.fill"
        }
    }
}

/// One finding: how serious it is, and what to tell the user.
struct SafetyReason: Identifiable, Hashable {
    let level: SafetyLevel
    let message: String
    var id: String { "\(level.rawValue)-\(message)" }
}

/// Result of a heuristic safety check on a URL.
struct URLSafetyResult {
    let reasons: [SafetyReason]

    static let safe = URLSafetyResult(reasons: [])

    /// Level 1 and 2 findings: these lock the options until the user confirms.
    var blockingReasons: [SafetyReason] { reasons.filter { $0.level != .advisory } }

    /// Level 3 findings: a gentle notice that never blocks anything.
    var advisoryReasons: [SafetyReason] { reasons.filter { $0.level == .advisory } }

    var requiresConfirmation: Bool { !blockingReasons.isEmpty }
    var hasSeriousReason: Bool { reasons.contains { $0.level == .serious } }
}

/// A snapshot of which checks are switched on. The checker takes one of these
/// instead of reading the user's saved preferences directly, so the same link
/// always gives the same answer for the same snapshot. That is what lets the
/// automated tests run on any machine (see URLSafetyCheckerTests).
struct SafetySettings: Equatable {
    var warnAboutSuspiciousLinks = true
    var flagDangerousSchemes = true
    var flagRawIPLinks = true
    var flagMixedScriptDomains = true
    var flagPunycodeDomains = true
    var flagDeepSubdomains = true
    var flagInsecureHTTP = true
    var flagBrandLookalikes = true
    var flagAtSignTrick = true
    var flagDownloadLinks = true
    var flagURLShorteners = true

    /// Every check on: the factory defaults.
    static let allOn = SafetySettings()
}

/// Performs local, instant heuristic analysis on URLs to flag common signs
/// of phishing or malicious intent — no network calls, no API key required.
///
/// This is NOT a replacement for a real threat-intelligence blocklist (like
/// Google Safe Browsing or URLhaus) — it catches obvious red flags a
/// bad actor's URL construction tends to leave behind, but a well-crafted
/// phishing link on a clean-looking domain will slip through. Treat this as
/// a first line of defense, not a guarantee.
enum URLSafetyChecker {

    // MARK: - Brand data

    private struct Brand {
        let keyword: String
        /// Domains that genuinely belong to the brand. A host equal to one of
        /// these, or a subdomain of one, is never flagged for this brand.
        let realDomains: [String]
    }

    private static let countrySuffixes = [
        "com", "co.uk", "de", "fr", "it", "es", "ca", "com.au", "co.jp", "in",
        "com.br", "com.mx", "nl", "se", "pl", "ae", "sa", "sg", "com.tr",
        "co.in", "cn", "com.cn", "ie", "be", "at", "ch", "co.nz", "dk", "fi",
        "no", "pt", "ru", "co.za", "com.hk", "tw", "co.kr", "com.ar", "cl"
    ]

    private static func variants(_ name: String) -> [String] {
        countrySuffixes.map { "\(name).\($0)" }
    }

    private static let microsoftDomains = [
        "microsoft.com", "microsoftonline.com", "live.com", "office.com",
        "office365.com", "outlook.com", "sharepoint.com", "windows.com",
        "windows.net", "azure.com", "msn.com", "bing.com", "skype.com",
        "xbox.com", "onedrive.com", "msft.net", "microsoft.net"
    ]

    private static let appleDomains = [
        "apple.com", "icloud.com", "me.com", "mac.com", "itunes.com",
        "apple.news", "cdn-apple.com", "mzstatic.com", "icloud.com.cn"
    ]

    private static let googleDomains = variants("google") + [
        "gmail.com", "googlemail.com", "google.org", "google.dev",
        "googleapis.com", "gstatic.com", "googleusercontent.com", "youtube.com",
        "goo.gl", "g.co", "withgoogle.com", "googlesource.com", "blogspot.com"
    ]

    private static let brands: [Brand] = [
        Brand(keyword: "paypal", realDomains: ["paypal.com", "paypal.me", "paypalobjects.com", "paypal-community.com"]),
        Brand(keyword: "apple", realDomains: appleDomains),
        Brand(keyword: "icloud", realDomains: appleDomains),
        Brand(keyword: "microsoft", realDomains: microsoftDomains),
        Brand(keyword: "outlook", realDomains: microsoftDomains),
        Brand(keyword: "office365", realDomains: microsoftDomains),
        Brand(keyword: "google", realDomains: googleDomains),
        Brand(keyword: "amazon", realDomains: variants("amazon") + [
            "amazonaws.com", "amazon.jobs", "amazon.science", "amazonpay.com",
            "a.co", "amzn.to", "amzn.com"
        ]),
        Brand(keyword: "netflix", realDomains: ["netflix.com", "netflix.net", "nflxext.com", "nflximg.net"]),
        Brand(keyword: "facebook", realDomains: ["facebook.com", "fb.com", "fb.me", "facebook.net", "fbcdn.net", "messenger.com", "meta.com"]),
        Brand(keyword: "instagram", realDomains: ["instagram.com", "cdninstagram.com"]),
        Brand(keyword: "bankofamerica", realDomains: ["bankofamerica.com", "bofa.com", "ml.com"]),
        Brand(keyword: "wellsfargo", realDomains: ["wellsfargo.com", "wf.com"]),
        Brand(keyword: "chase", realDomains: ["chase.com", "jpmorgan.com", "jpmorganchase.com"]),
        Brand(keyword: "americanexpress", realDomains: ["americanexpress.com", "aexp.com", "amex.com"]),
        Brand(keyword: "venmo", realDomains: ["venmo.com"]),
        Brand(keyword: "coinbase", realDomains: ["coinbase.com"]),
        Brand(keyword: "binance", realDomains: ["binance.com", "binance.us"]),
        Brand(keyword: "irs", realDomains: ["irs.gov"]),
        Brand(keyword: "usps", realDomains: ["usps.com", "usps.gov"]),
        Brand(keyword: "fedex", realDomains: ["fedex.com"]),
        Brand(keyword: "dhl", realDomains: variants("dhl"))
    ]

    /// Words scammers glue onto a brand name ("paypal-login", "appleid").
    private static let baitWords: Set<String> = [
        "id", "login", "signin", "secure", "security", "verify", "verification",
        "account", "accounts", "support", "help", "service", "services",
        "billing", "pay", "payment", "payments", "update", "care", "online",
        "wallet", "team", "alert", "alerts", "refund", "delivery", "tracking",
        "parcel", "package", "customer"
    ]

    private static let suspiciousTLDs = [
        ".tk", ".ml", ".ga", ".cf", ".gq", ".xyz", ".top", ".club", ".work",
        ".click", ".link", ".zip", ".review", ".online"
    ]

    /// File types that install or run a program. Downloading one is not
    /// necessarily bad, but it's worth a pause.
    private static let downloadExtensions: Set<String> = [
        "exe", "msi", "scr", "bat", "cmd", "ps1", "vbs",
        "dmg", "pkg", "command", "sh", "jar", "apk"
    ]

    /// Link shorteners hide the real destination until you open them.
    private static let urlShorteners = [
        "bit.ly", "t.co", "tinyurl.com", "goo.gl", "ow.ly", "is.gd",
        "buff.ly", "rebrand.ly", "cutt.ly", "t.ly", "shorturl.at",
        "rb.gy", "lnkd.in", "tiny.cc", "bl.ink"
    ]

    // MARK: - Check

    static func check(_ url: URL, settings: SafetySettings = AppSettings.shared.safetySettings) -> URLSafetyResult {
        guard settings.warnAboutSuspiciousLinks else { return .safe }

        var reasons: [SafetyReason] = []

        // Dangerous URI schemes. Checked first because such links often
        // have no host at all.
        if settings.flagDangerousSchemes,
           let scheme = url.scheme?.lowercased(), ["javascript", "data", "file"].contains(scheme) {
            reasons.append(SafetyReason(
                level: .serious,
                message: "This link uses the \"\(scheme):\" scheme, which can run code or access local files directly."
            ))
        }

        guard let rawHost = url.host else {
            return URLSafetyResult(reasons: reasons)
        }
        var host = (rawHost.removingPercentEncoding ?? rawHost).lowercased()
        if host.hasSuffix(".") { host.removeLast() } // "paypal.com." is the same site

        // Raw IP address instead of a domain name.
        if settings.flagRawIPLinks, let kind = classifyIP(host) {
            switch kind {
            case .publicAddress:
                reasons.append(SafetyReason(
                    level: .warning,
                    message: "This link points directly to a raw IP address instead of a normal domain name — legitimate sites almost never do this."
                ))
            case .disguised:
                reasons.append(SafetyReason(
                    level: .warning,
                    message: "This link uses a disguised numeric address (a single big number, hex or similar), a trick to hide that it points at a raw IP address."
                ))
            case .localAddress:
                reasons.append(SafetyReason(
                    level: .advisory,
                    message: "This link points to an address on your own device or local network. That's normal for a router or a development server, but only continue if you expect it."
                ))
            }
        }

        // Homograph / mixed-script detection.
        if settings.flagMixedScriptDomains, containsMixedScripts(host) {
            reasons.append(SafetyReason(
                level: .warning,
                message: "This domain mixes different alphabets/scripts, a common trick to visually impersonate a trusted site."
            ))
        }

        // Brand look-alikes, in three confidence levels (see brandMatch).
        let labelCount = host.components(separatedBy: ".").count
        if settings.flagBrandLookalikes, let match = brandMatch(host: host, labelCount: labelCount) {
            let message: String
            switch match.level {
            case .serious:
                message = "This domain includes \"\(match.keyword)\" but isn't \(match.keyword)'s actual domain, which is a common phishing pattern."
            case .warning:
                message = "This domain looks like it imitates \"\(match.keyword)\" and has an unusual address structure, but it isn't \(match.keyword)'s actual domain."
            case .advisory:
                message = "This domain starts with \"\(match.keyword)\" but isn't \(match.keyword)'s actual website. Make sure it's the site you expect."
            }
            reasons.append(SafetyReason(level: match.level, message: message))
        }

        // Punycode domains (xn--).
        if settings.flagPunycodeDomains, host.contains("xn--") {
            reasons.append(SafetyReason(
                level: .warning,
                message: "This domain uses punycode encoding, which can be used to visually disguise the real destination."
            ))
        }

        // Excessive subdomain nesting.
        if settings.flagDeepSubdomains, labelCount > 5 {
            reasons.append(SafetyReason(
                level: .advisory,
                message: "This domain has an unusually deep subdomain structure, which is sometimes used to disguise the real destination."
            ))
        }

        // Unencrypted http:// links.
        if settings.flagInsecureHTTP, url.scheme?.lowercased() == "http" {
            reasons.append(SafetyReason(
                level: .advisory,
                message: "This link isn't encrypted (http://), so anything you send or receive on this page could be read by others on the network."
            ))
        }

        // The "@" trick: https://paypal.com@evil-site.xyz really goes to
        // evil-site.xyz. Everything before the @ is just a "username".
        if settings.flagAtSignTrick,
           let user = URLComponents(url: url, resolvingAgainstBaseURL: false)?.user, !user.isEmpty {
            reasons.append(SafetyReason(
                level: .serious,
                message: "This link has a fake \"username\" (\(user)) in front of the real address, a trick to make it look like a trusted site. It actually goes to \(host)."
            ))
        }

        // Links that point straight at a program or installer.
        let fileExtension = url.pathExtension.lowercased()
        if settings.flagDownloadLinks, downloadExtensions.contains(fileExtension) {
            reasons.append(SafetyReason(
                level: .warning,
                message: "This link downloads a program or installer (.\(fileExtension)). Only open it if you trust the site."
            ))
        }

        // Shortened links hide where they really lead.
        if settings.flagURLShorteners,
           urlShorteners.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            reasons.append(SafetyReason(
                level: .advisory,
                message: "This is a shortened link, so the real destination is hidden until you open it."
            ))
        }

        // Most serious first.
        return URLSafetyResult(reasons: reasons.sorted { $0.level < $1.level })
    }

    // MARK: - Brand look-alikes

    /// Three confidence levels, strongest first:
    ///   1 (serious):  a part of the host IS the brand ("paypal", "apple.com.evil.com")
    ///                 or the brand plus a bait word ("paypal-login", "appleid").
    ///   2 (warning):  a part only STARTS with the brand ("applebees") AND the
    ///                 address looks off (suspicious TLD or deep nesting).
    ///   3 (advisory): a part starts with the brand on an ordinary address.
    /// The brand's real domains are exempt at every level. Short brand names
    /// (irs, dhl, usps) only count as whole words, never as prefixes, because
    /// "irs" would otherwise match "irsmith.com".
    private static func brandMatch(host: String, labelCount: Int) -> (keyword: String, level: SafetyLevel)? {
        let words = host.split(whereSeparator: { $0 == "." || $0 == "-" }).map(String.init)
        let looksOff = suspiciousTLDs.contains { host.hasSuffix($0) } || labelCount > 3
        var best: (keyword: String, level: SafetyLevel)?

        for brand in brands {
            let isRealDomain = brand.realDomains.contains { host == $0 || host.hasSuffix(".\($0)") }
            if isRealDomain { continue }

            var level: SafetyLevel?
            for word in words {
                if isBrandOrBait(word, keyword: brand.keyword) {
                    level = .serious
                    break
                }
                if brand.keyword.count >= 5, word.hasPrefix(brand.keyword) {
                    let candidate: SafetyLevel = looksOff ? .warning : .advisory
                    level = level.map { min($0, candidate) } ?? candidate
                }
            }

            if let level {
                if let current = best {
                    if level < current.level { best = (brand.keyword, level) }
                } else {
                    best = (brand.keyword, level)
                }
            }
        }
        return best
    }

    private static func isBrandOrBait(_ word: String, keyword: String) -> Bool {
        if word == keyword { return true }
        if word.hasPrefix(keyword), baitWords.contains(String(word.dropFirst(keyword.count))) { return true }
        if word.hasSuffix(keyword), baitWords.contains(String(word.dropLast(keyword.count))) { return true }
        return false
    }

    // MARK: - IP addresses

    private enum HostIP {
        case publicAddress   // an ordinary internet address
        case localAddress    // this device or the local network
        case disguised       // written in a non-standard way (0x7f000001, 2130706433, 127.1)
    }

    private static func classifyIP(_ host: String) -> HostIP? {
        host.contains(":") ? classifyIPv6(host) : classifyIPv4(host)
    }

    /// Parses the way web browsers do, so "2130706433", "0x7f000001",
    /// "0177.0.0.1" and "127.1" are all recognised as the same loopback address.
    private static func classifyIPv4(_ host: String) -> HostIP? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard (1...4).contains(parts.count) else { return nil }

        var values: [UInt64] = []
        var disguised = parts.count != 4
        for part in parts {
            guard let parsed = parseIPv4Part(part) else { return nil }
            values.append(parsed.value)
            if !parsed.isPlain { disguised = true }
        }

        // Every part but the last is one byte; the last fills the remaining bytes.
        for value in values.dropLast() where value > 255 { return nil }
        let last = values[values.count - 1]
        let limit: UInt64 = 1 << (8 * UInt64(5 - parts.count))
        guard last < limit else { return nil }

        var address = last
        for (index, value) in values.dropLast().enumerated() {
            address += value << (8 * UInt64(3 - index))
        }

        if disguised { return .disguised }
        return isLocalIPv4(UInt32(truncatingIfNeeded: address)) ? .localAddress : .publicAddress
    }

    private static func parseIPv4Part(_ part: String) -> (value: UInt64, isPlain: Bool)? {
        let lower = part.lowercased()
        guard !lower.isEmpty else { return nil }

        if lower.hasPrefix("0x") {
            let digits = String(lower.dropFirst(2))
            guard !digits.isEmpty, digits.allSatisfy({ $0.isHexDigit }),
                  let value = UInt64(digits, radix: 16) else { return nil }
            return (value, false)
        }
        guard lower.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        if lower.count > 1, lower.hasPrefix("0") {
            // Leading zero means octal ("0177" is 127).
            guard let value = UInt64(lower, radix: 8) else { return nil }
            return (value, false)
        }
        guard let value = UInt64(lower, radix: 10) else { return nil }
        return (value, true)
    }

    /// Loopback, "this host", link-local, and the three private ranges.
    /// Note 172.x is only private for 172.16 through 172.31.
    private static func isLocalIPv4(_ address: UInt32) -> Bool {
        let first = (address >> 24) & 0xFF
        let second = (address >> 16) & 0xFF
        switch first {
        case 0, 10, 127: return true
        case 169: return second == 254
        case 172: return (16...31).contains(second)
        case 192: return second == 168
        default: return false
        }
    }

    private static func classifyIPv6(_ host: String) -> HostIP? {
        // Drop a zone id like "fe80::1%en0".
        let address = host.split(separator: "%", maxSplits: 1).first.map(String.init) ?? host
        guard address.allSatisfy({ $0.isHexDigit || $0 == ":" || $0 == "." }) else { return nil }

        if address == "::" || address == "::1" { return .localAddress }

        // IPv4-mapped, e.g. ::ffff:192.168.1.1
        if address.hasPrefix("::ffff:"), address.contains("."),
           let mapped = classifyIPv4(String(address.dropFirst(7))) {
            return mapped
        }

        if !address.hasPrefix(":"),
           let firstGroup = address.split(separator: ":").first,
           let value = UInt16(firstGroup, radix: 16) {
            if (value & 0xFE00) == 0xFC00 { return .localAddress }  // fc00::/7 private
            if (value & 0xFFC0) == 0xFE80 { return .localAddress }  // fe80::/10 link-local
        }
        return .publicAddress
    }

    // MARK: - Mixed scripts

    private enum ScriptKind { case latin, lookalike, other }

    private static func scriptKind(_ value: UInt32) -> ScriptKind {
        switch value {
        case 0x41...0x5A, 0x61...0x7A, 0xC0...0xD6, 0xD8...0xF6, 0xF8...0x2AF:
            return .latin
        case 0x370...0x3FF, 0x1F00...0x1FFF,   // Greek
             0x400...0x52F,                     // Cyrillic (+ supplement)
             0x530...0x58F,                     // Armenian
             0x13A0...0x13FF,                   // Cherokee
             0xFF21...0xFF3A, 0xFF41...0xFF5A:  // full-width Latin letters
            return .lookalike
        default:
            return .other
        }
    }

    /// True if any single dot-separated part of the host mixes Latin letters
    /// with a look-alike alphabet. Parts are checked one at a time, so
    /// "test.рф" (Latin name, Cyrillic TLD) is fine, but "аpple.com" is not.
    /// `xn--` parts are decoded first so the real characters get checked.
    private static func containsMixedScripts(_ host: String) -> Bool {
        for label in host.split(separator: ".") {
            let text = decodedLabel(String(label))
            var hasLatin = false
            var hasLookalike = false
            for scalar in text.unicodeScalars {
                switch scriptKind(scalar.value) {
                case .latin: hasLatin = true
                case .lookalike: hasLookalike = true
                case .other: break
                }
            }
            if hasLatin && hasLookalike { return true }
        }
        return false
    }

    private static func decodedLabel(_ label: String) -> String {
        if label.hasPrefix("xn--"), let decoded = punycodeDecode(String(label.dropFirst(4))) {
            return decoded
        }
        return label
    }

    // MARK: - Punycode (RFC 3492)

    /// Decodes the part of an "xn--" label after the prefix. Returns nil for
    /// anything malformed. Internal (not private) so tests can call it directly.
    static func punycodeDecode(_ input: String) -> String? {
        let base = 36, tMin = 1, tMax = 26
        var n = 128, i = 0, bias = 72
        var output: [Unicode.Scalar] = []

        let chars = Array(input.unicodeScalars)
        var position = 0

        // Everything before the last "-" is plain ASCII, copied as-is.
        if let delimiter = chars.lastIndex(of: "-") {
            for scalar in chars[..<delimiter] {
                guard scalar.isASCII else { return nil }
                output.append(scalar)
            }
            position = delimiter + 1
        }

        while position < chars.count {
            let oldI = i
            var weight = 1
            var k = base
            while true {
                guard position < chars.count, let digit = punycodeDigit(chars[position]) else { return nil }
                position += 1

                let (scaled, overflow1) = digit.multipliedReportingOverflow(by: weight)
                let (sum, overflow2) = i.addingReportingOverflow(scaled)
                guard !overflow1, !overflow2 else { return nil }
                i = sum

                let threshold = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
                if digit < threshold { break }

                let (nextWeight, overflow3) = weight.multipliedReportingOverflow(by: base - threshold)
                guard !overflow3 else { return nil }
                weight = nextWeight
                k += base
            }

            let count = output.count + 1
            bias = punycodeAdapt(delta: i - oldI, numPoints: count, isFirst: oldI == 0)

            let (nextN, overflow4) = n.addingReportingOverflow(i / count)
            guard !overflow4 else { return nil }
            n = nextN
            i %= count

            guard n <= 0x10FFFF, let scalar = Unicode.Scalar(UInt32(n)) else { return nil }
            output.insert(scalar, at: i)
            i += 1
        }

        var view = String.UnicodeScalarView()
        view.append(contentsOf: output)
        return String(view)
    }

    private static func punycodeDigit(_ scalar: Unicode.Scalar) -> Int? {
        switch scalar.value {
        case 0x30...0x39: return Int(scalar.value) - 0x30 + 26   // 0-9
        case 0x41...0x5A: return Int(scalar.value) - 0x41        // A-Z
        case 0x61...0x7A: return Int(scalar.value) - 0x61        // a-z
        default: return nil
        }
    }

    private static func punycodeAdapt(delta: Int, numPoints: Int, isFirst: Bool) -> Int {
        let base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700
        var delta = isFirst ? delta / damp : delta / 2
        delta += delta / numPoints
        var k = 0
        while delta > ((base - tMin) * tMax) / 2 {
            delta /= base - tMin
            k += base
        }
        return k + ((base - tMin + 1) * delta) / (delta + skew)
    }
}
