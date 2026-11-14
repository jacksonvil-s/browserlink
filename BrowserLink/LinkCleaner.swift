import Foundation

/// Tidies a link before the chooser shows it:
///   1. Unwraps well-known redirect pages (e.g. google.com/url?q=…) so the
///      real destination is what gets safety-checked, previewed and opened.
///   2. Strips tracking query parameters (utm_*, fbclid, gclid, …).
///
/// Anything it changes is reported in `Cleaned.note` so the chooser can tell
/// the user, and the original is kept so they can go back to it.
///
/// Deliberately NOT unwrapped: link rewriters that exist for security, such as
/// Outlook Safe Links or Proofpoint URL Defense. Those scan the destination
/// when you click, and skipping them would remove that protection.
enum LinkCleaner {

    struct Cleaned {
        let original: URL
        let url: URL
        /// Human-readable summary of what changed, or nil if nothing did.
        let note: String?
    }

    private struct Wrapper {
        let host: String      // exact host, or a parent domain (matches subdomains too)
        let path: String      // exact path, ignoring a trailing slash
        let params: [String]  // query parameters that may hold the real URL
    }

    private static let wrappers: [Wrapper] = [
        Wrapper(host: "google.com", path: "/url", params: ["q", "url"]),
        Wrapper(host: "youtube.com", path: "/redirect", params: ["q"]),
        Wrapper(host: "facebook.com", path: "/l.php", params: ["u"]),
        Wrapper(host: "l.instagram.com", path: "", params: ["u"]),
        Wrapper(host: "linkedin.com", path: "/safety/go", params: ["url"]),
        Wrapper(host: "slack-redir.net", path: "/link", params: ["url"]),
        Wrapper(host: "duckduckgo.com", path: "/l", params: ["uddg"]),
        Wrapper(host: "steamcommunity.com", path: "/linkfilter", params: ["u", "url"])
    ]

    private static let trackingParameters: Set<String> = [
        "fbclid", "gclid", "gbraid", "wbraid", "dclid", "msclkid", "twclid",
        "ttclid", "li_fat_id", "igshid", "yclid", "mc_eid", "mc_cid",
        "_hsenc", "_hsmi", "mkt_tok", "vero_id", "oly_enc_id", "oly_anon_id",
        "s_kwcid", "ef_id"
    ]

    static func clean(_ original: URL, stripTracking: Bool, unwrapRedirects: Bool) -> Cleaned {
        var url = original
        var notes: [String] = []

        if unwrapRedirects {
            // Wrappers can be nested, but never loop forever.
            for _ in 0..<3 {
                guard let (inner, via) = unwrapOnce(url) else { break }
                url = inner
                notes.append("Skipped the redirect through \(via)")
            }
        }

        if stripTracking, let (stripped, removed) = stripTrackingParameters(from: url) {
            url = stripped
            let shown = removed.prefix(4).joined(separator: ", ")
            let extra = removed.count > 4 ? " +\(removed.count - 4) more" : ""
            notes.append("Removed tracking (\(shown)\(extra))")
        }

        return Cleaned(
            original: original,
            url: url,
            note: notes.isEmpty ? nil : notes.joined(separator: ". ") + "."
        )
    }

    // MARK: - Unwrapping

    private static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }

    private static func normalizedPath(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : (path == "/" ? "" : path)
    }

    private static func unwrapOnce(_ url: URL) -> (URL, String)? {
        guard isWebURL(url),
              let host = url.host?.lowercased(),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        let path = normalizedPath(components.path)

        for wrapper in wrappers {
            guard host == wrapper.host || host.hasSuffix("." + wrapper.host),
                  path == wrapper.path else { continue }

            for name in wrapper.params {
                // `queryItems` hands back the percent-DECODED value, which is
                // exactly the inner URL.
                if let value = components.queryItems?.first(where: { $0.name == name })?.value,
                   let inner = URL(string: value),
                   isWebURL(inner) {
                    return (inner, wrapper.host)
                }
            }
        }
        return nil
    }

    // MARK: - Tracking parameters

    private static func isTracking(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.hasPrefix("utm_") || trackingParameters.contains(lowered)
    }

    private static func stripTrackingParameters(from url: URL) -> (URL, [String])? {
        guard isWebURL(url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.percentEncodedQueryItems,
              !items.isEmpty else { return nil }

        let removed = items.filter { isTracking($0.name) }
        guard !removed.isEmpty else { return nil }

        // Work on the percent-ENCODED items so the parameters we keep are
        // passed through byte-for-byte.
        let kept = items.filter { !isTracking($0.name) }
        components.percentEncodedQueryItems = kept.isEmpty ? nil : kept

        guard let cleaned = components.url else { return nil }

        var seen = Set<String>()
        let names = removed.map(\.name).filter { seen.insert($0.lowercased()).inserted }
        return (cleaned, names)
    }
}
