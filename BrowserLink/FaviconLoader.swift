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
/// consistently-sized PNG, which is a much better fit for a quick popup
/// than rolling our own HTML-parsing favicon resolver.
@MainActor
final class FaviconLoader: ObservableObject {
    @Published var image: NSImage?

    private static var cache: [String: NSImage] = [:]

    func load(for url: URL) {
        guard let host = url.host else { return }

        if let cached = Self.cache[host] {
            self.image = cached
            return
        }

        guard let faviconURL = URL(
            string: "https://www.google.com/s2/favicons?sz=128&domain=\(host)"
        ) else { return }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: faviconURL)
                if let nsImage = NSImage(data: data) {
                    Self.cache[host] = nsImage
                    self.image = nsImage
                }
            } catch {
                // Silent failure — the view falls back to the glass globe
                // placeholder, which is a perfectly good default.
            }
        }
    }
}
