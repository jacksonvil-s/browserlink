import SwiftUI
import Combine

/// Fetches a favicon image for a given URL's host, with a simple in-memory
/// cache so repeated links to the same site don't re-fetch every time.
///
/// Approach: Google's favicon service (https://www.google.com/s2/favicons)
/// is used instead of trying `{host}/favicon.ico` directly, because a large
/// fraction of real-world sites either don't serve one at that exact path,
/// serve a low-res/no icon, or use a `<link rel="icon">` pointing somewhere
/// entirely different that only a full HTML parse would find. Google's
/// service already resolves all of that server-side and returns a
/// consistently-sized PNG.
///
/// Privacy: every lookup tells Google which site you're opening, so it is
/// skipped for anything where that would be a leak or pointless:
///   - links that trip a blocking (red/yellow) safety warning,
///   - IP addresses, `localhost` and single-label / local-network hostnames.
@MainActor
final class FaviconLoader: ObservableObject {
    @Published var image: NSImage?
    private static var cache: [String: NSImage] = [:]

    func load(for url: URL, safetyResult: URLSafetyResult) {
        guard AppSettings.shared.showFaviconsInChooser else { return }
        guard let host = url.host?.lowercased(), Self.isPublicHostname(host) else { return }

        // Never tell a third party about a link we're about to warn the user about.
        guard !safetyResult.requiresConfirmation else { return }

        if let cached = Self.cache[host] {
            image = cached
            return
        }

        var components = URLComponents(string: "https://www.google.com/s2/favicons")
        components?.queryItems = [
            URLQueryItem(name: "sz", value: "128"),
            URLQueryItem(name: "domain", value: host)
        ]
        guard let faviconURL = components?.url else { return }

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: faviconURL)
                // Google answers unknown sites with a non-200 status and its own
                // generic globe; keep our placeholder instead of showing that.
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let nsImage = NSImage(data: data) else { return }
                Self.cache[host] = nsImage
                self.image = nsImage
            } catch {
                // Silent failure — the view falls back to the glass globe
                // placeholder, which is a perfectly good default.
            }
        }
    }

    /// True only for hostnames that exist on the public internet.
    private static func isPublicHostname(_ host: String) -> Bool {
        // IPv6 literals
        if host.contains(":") { return false }
        // IPv4 literals (digits and dots only)
        if host.range(of: #"^[0-9.]+$"#, options: .regularExpression) != nil { return false }
        // Single-label names like "intranet" or "router"
        guard host.contains(".") else { return false }

        let localSuffixes = [".local", ".localhost", ".lan", ".internal", ".home", ".corp", ".intranet", ".home.arpa"]
        if localSuffixes.contains(where: { host.hasSuffix($0) }) { return false }
        return true
    }
}
