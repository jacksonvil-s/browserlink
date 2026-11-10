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

/// Performs local, instant heuristic analysis on URLs to flag common signs
/// of phishing or malicious intent — no network calls, no API key required.
///
/// This is NOT a replacement for a real threat-intelligence blocklist (like
/// Google Safe Browsing or URLhaus) — it catches obvious red flags a
/// bad actor's URL construction tends to leave behind, but a well-crafted
/// phishing link on a clean-looking domain will slip through. Treat this as
/// a first line of defense, not a guarantee.
enum URLSafetyChecker {

    private static let commonlyImpersonatedBrands = [
        "paypal", "apple", "microsoft", "google", "amazon", "netflix",
        "facebook", "instagram", "bankofamerica", "wellsfargo", "chase",
        "americanexpress", "venmo", "coinbase", "binance", "irs", "usps",
        "fedex", "dhl", "icloud", "outlook", "office365"
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

    static func check(_ url: URL) -> URLSafetyResult {
        guard AppSettings.shared.warnAboutSuspiciousLinks else { return .safe }

        var reasons: [SafetyReason] = []

        // Dangerous URI schemes. Checked first because such links often
        // have no host at all.
        if let scheme = url.scheme?.lowercased(), ["javascript", "data", "file"].contains(scheme) {
            reasons.append(SafetyReason(
                level: .serious,
                message: "This link uses the \"\(scheme):\" scheme, which can run code or access local files directly."
            ))
        }

        guard let host = url.host?.lowercased() else {
            return URLSafetyResult(reasons: reasons)
        }

        // Raw IP address instead of a domain name.
        if AppSettings.shared.flagRawIPLinks, isIPAddress(host) {
            reasons.append(SafetyReason(
                level: .warning,
                message: "This link points directly to a raw IP address instead of a normal domain name — legitimate sites almost never do this."
            ))
        }

        // Homograph / mixed-script detection.
        if AppSettings.shared.flagMixedScriptDomains, containsMixedScripts(host) {
            reasons.append(SafetyReason(
                level: .warning,
                message: "This domain mixes different alphabets/scripts, a common trick to visually impersonate a trusted site."
            ))
        }

        // Brand name + suspicious TLD or excessive subdomain combination.
        // Split the host into words (at dots and dashes) and check whether
        // any word STARTS with a brand name.
        let words = host.split(whereSeparator: { $0 == "." || $0 == "-" }).map(String.init)
        let brandMatch = commonlyImpersonatedBrands.first { brand in
            words.contains { $0.hasPrefix(brand) }
        }
        if AppSettings.shared.flagBrandLookalikes, let brand = brandMatch {
            let isBrandsOwnDomain = host == "\(brand).com" || host.hasSuffix(".\(brand).com")
            let hasSuspiciousTLD = suspiciousTLDs.contains { host.hasSuffix($0) }
            let subdomainCount = host.components(separatedBy: ".").count

            if !isBrandsOwnDomain && (hasSuspiciousTLD || subdomainCount > 3) {
                reasons.append(SafetyReason(
                    level: .serious,
                    message: "This domain includes \"\(brand)\" but isn't \(brand)'s actual domain, which is a common phishing pattern."
                ))
            }
        }

        // Punycode domains (xn--).
        if AppSettings.shared.flagPunycodeDomains, host.contains("xn--") {
            reasons.append(SafetyReason(
                level: .warning,
                message: "This domain uses punycode encoding, which can be used to visually disguise the real destination."
            ))
        }

        // Excessive subdomain nesting.
        if AppSettings.shared.flagDeepSubdomains {
            let labelCount = host.components(separatedBy: ".").count
            if labelCount > 5 {
                reasons.append(SafetyReason(
                    level: .advisory,
                    message: "This domain has an unusually deep subdomain structure, which is sometimes used to disguise the real destination."
                ))
            }
        }

        // Unencrypted http:// links.
        if AppSettings.shared.flagInsecureHTTP, url.scheme?.lowercased() == "http" {
            reasons.append(SafetyReason(
                level: .advisory,
                message: "This link isn't encrypted (http://), so anything you send or receive on this page could be read by others on the network."
            ))
        }
        
        // The "@" trick: https://paypal.com@evil-site.xyz really goes to
        // evil-site.xyz. Everything before the @ is just a "username".
        if AppSettings.shared.flagAtSignTrick,
           let user = URLComponents(url: url, resolvingAgainstBaseURL: false)?.user, !user.isEmpty {
            reasons.append(SafetyReason(
                level: .serious,
                message: "This link has a fake \"username\" (\(user)) in front of the real address, a trick to make it look like a trusted site. It actually goes to \(host)."
            ))
        }

        // Links that point straight at a program or installer.
        let fileExtension = url.pathExtension.lowercased()
        if AppSettings.shared.flagDownloadLinks, downloadExtensions.contains(fileExtension) {
            reasons.append(SafetyReason(
                level: .warning,
                message: "This link downloads a program or installer (.\(fileExtension)). Only open it if you trust the site."
            ))
        }

        // Shortened links hide where they really lead.
        if AppSettings.shared.flagURLShorteners {
            if urlShorteners.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
                reasons.append(SafetyReason(
                    level: .advisory,
                    message: "This is a shortened link, so the real destination is hidden until you open it."
                ))
            }
        }

        // Most serious first.
        return URLSafetyResult(reasons: reasons.sorted { $0.level < $1.level })
    }

    private static func isIPAddress(_ host: String) -> Bool {
        let ipv4Pattern = #"^(\d{1,3}\.){3}\d{1,3}$"#
        if host.range(of: ipv4Pattern, options: .regularExpression) != nil {
            return true
        }
        if host.contains(":") && host.range(of: #"^[0-9a-fA-F:]+$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func containsMixedScripts(_ host: String) -> Bool {
        var hasLatin = false
        var hasOtherScript = false

        for scalar in host.unicodeScalars {
            switch scalar.value {
            case 0x0041...0x005A, 0x0061...0x007A: // A-Z, a-z
                hasLatin = true
            case 0x0400...0x04FF: // Cyrillic
                hasOtherScript = true
            case 0x0370...0x03FF: // Greek
                hasOtherScript = true
            default:
                continue
            }
        }

        return hasLatin && hasOtherScript
    }
}
