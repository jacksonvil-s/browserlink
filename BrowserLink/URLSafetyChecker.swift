import Foundation

/// Result of a heuristic safety check on a URL.
struct URLSafetyResult {
    let isSuspicious: Bool
    let reasons: [String]

    static let safe = URLSafetyResult(isSuspicious: false, reasons: [])
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

    /// A small set of high-value brand names commonly impersonated in
    /// phishing URLs. Not exhaustive — just enough to catch the most common
    /// lookalike-domain pattern (brand name + suspicious extra words/TLD).
    private static let commonlyImpersonatedBrands = [
        "paypal", "apple", "microsoft", "google", "amazon", "netflix",
        "facebook", "instagram", "bankofamerica", "wellsfargo", "chase",
        "americanexpress", "venmo", "coinbase", "binance", "irs", "usps",
        "fedex", "dhl", "icloud", "outlook", "office365"
    ]

    /// TLDs that are disproportionately used for throwaway phishing domains.
    /// Having one of these is not proof of anything by itself — it's only
    /// treated as suspicious when COMBINED with a brand name in the same host.
    private static let suspiciousTLDs = [
        ".tk", ".ml", ".ga", ".cf", ".gq", ".xyz", ".top", ".club", ".work",
        ".click", ".link", ".zip", ".review"
    ]

    static func check(_ url: URL) -> URLSafetyResult {
        var reasons: [String] = []

        guard let host = url.host?.lowercased() else {
            return URLSafetyResult(isSuspicious: false, reasons: [])
        }

        // 1. Raw IP address instead of a domain name.
        if isIPAddress(host) {
            reasons.append("This link points directly to a raw IP address instead of a normal domain name — legitimate sites almost never do this.")
        }

        // 2. Dangerous URI schemes that can execute code or access local data.
        if let scheme = url.scheme?.lowercased(), ["javascript", "data", "file"].contains(scheme) {
            reasons.append("This link uses the \"\(scheme):\" scheme, which can run code or access local files directly.")
        }

        // 3. Homograph / mixed-script detection — catches lookalike domains
        // using non-Latin characters that visually resemble Latin ones
        // (e.g. Cyrillic "а" instead of Latin "a").
        if containsMixedScripts(host) {
            reasons.append("This domain mixes different alphabets/scripts, a common trick to visually impersonate a trusted site.")
        }

        // 4. Brand name + suspicious TLD or excessive subdomain combination.
        let brandMatch = commonlyImpersonatedBrands.first { host.contains($0) }
        if let brand = brandMatch {
            let isBrandsOwnDomain = host == "\(brand).com" || host.hasSuffix(".\(brand).com")
            let hasSuspiciousTLD = suspiciousTLDs.contains { host.hasSuffix($0) }
            let subdomainCount = host.components(separatedBy: ".").count

            if !isBrandsOwnDomain && (hasSuspiciousTLD || subdomainCount > 3) {
                reasons.append("This domain includes \"\(brand)\" but isn't \(brand)'s actual domain — a common phishing pattern.")
            }
        }

        // 5. Excessive subdomain nesting, a classic obfuscation tactic
        // (e.g. paypal.com.verify-account.suspicious-site.xyz).
        let labelCount = host.components(separatedBy: ".").count
        if labelCount > 4 {
            reasons.append("This domain has an unusually deep subdomain structure, which is sometimes used to disguise the real destination.")
        }

        // 6. Punycode domains (xn--) — often used for homograph attacks,
        // though also legitimately used for real internationalized domains.
        if host.contains("xn--") {
            reasons.append("This domain uses punycode encoding, which can be used to visually disguise the real destination.")
        }

        return URLSafetyResult(isSuspicious: !reasons.isEmpty, reasons: reasons)
    }

    private static func isIPAddress(_ host: String) -> Bool {
        // IPv4 check.
        let ipv4Pattern = #"^(\d{1,3}\.){3}\d{1,3}$"#
        if host.range(of: ipv4Pattern, options: .regularExpression) != nil {
            return true
        }
        // IPv6 check (simplified — looks for colon-separated hex groups).
        if host.contains(":") && host.range(of: #"^[0-9a-fA-F:]+$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func containsMixedScripts(_ host: String) -> Bool {
        // Strip the TLD/common structure and just look at the character scripts
        // present in the host. If we see both Latin AND another alphabetic
        // script (Cyrillic, Greek, etc.) in the same host, that's a strong
        // signal of a homograph attack rather than a legitimately
        // internationalized domain (which usually stays within one script).
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
