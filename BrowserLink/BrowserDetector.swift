import AppKit

/// Represents a real, installed browser on this Mac.
struct InstalledBrowser: Identifiable, Hashable {
    let id: String            // bundle identifier, e.g. "com.apple.Safari"
    let name: String          // display name, e.g. "Safari"
    let icon: NSImage         // the app's actual icon, pulled from disk
    let url: URL              // path to the .app bundle
}

enum BrowserDetector {

    /// The known bundle identifiers we check for, in a sensible display order.
    /// Add more here if you want to support additional browsers explicitly —
    /// otherwise this list covers the vast majority of real-world setups.
    private static let knownBrowserIDs: [(id: String, name: String)] = [
        ("com.apple.Safari", "Safari"),
        ("com.google.Chrome", "Chrome"),
        ("org.mozilla.firefox", "Firefox"),
        ("com.brave.Browser", "Brave"),
        ("com.microsoft.edgemac", "Edge"),
        ("company.thebrowser.Browser", "Arc"),
        ("com.kagi.kagimacOS", "Orion"),
        ("com.operasoftware.Opera", "Opera"),
        ("org.chromium.Chromium", "Chromium"),
        ("com.vivaldi.Vivaldi", "Vivaldi"),
    ]

    /// Scans for which of the known browsers are actually installed on this Mac,
    /// pulling real icons and paths via LaunchServices. Returns only what's present —
    /// if someone doesn't have Chrome installed, it simply won't show up as an option.
    static func installedBrowsers() -> [InstalledBrowser] {
        knownBrowserIDs.compactMap { entry in
            guard let appURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: entry.id
            ) else {
                return nil
            }
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            return InstalledBrowser(id: entry.id, name: entry.name, icon: icon, url: appURL)
        }
    }

    /// Opens the given URL in a specific installed browser, bypassing the system
    /// default entirely (important since WE are likely the system default —
    /// otherwise this would just loop back into our own chooser).
    static func open(url: URL, in browser: InstalledBrowser) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: browser.url,
            configuration: config,
            completionHandler: nil
        )
    }
}
