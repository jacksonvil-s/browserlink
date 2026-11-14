import AppKit

/// Represents a real, installed browser on this Mac.
struct InstalledBrowser: Identifiable, Hashable {
    let id: String            // bundle identifier, e.g. "com.apple.Safari"
    let name: String          // display name, e.g. "Safari"
    let icon: NSImage         // the app's actual icon, pulled from disk
    let url: URL              // path to the .app bundle

    /// True for browsers on our built-in list. False for apps we only found by
    /// asking macOS which apps open web links: they declare http/https support,
    /// but we've never tested links in them, so they're shown as
    /// "potentially unsupported".
    let isRecognised: Bool
}

enum BrowserDetector {

    /// The known bundle identifiers we check for, in a sensible display order.
    /// Add more here to make a browser "recognised"; anything else that
    /// declares http/https support is still found by scanning, but is marked
    /// as potentially unsupported.
    private static let knownBrowserIDs: [(id: String, name: String)] = [
        ("com.apple.Safari", "Safari"),
        ("com.apple.SafariTechnologyPreview", "Safari Technology Preview"),
        ("com.google.Chrome", "Chrome"),
        ("com.google.Chrome.beta", "Chrome Beta"),
        ("com.google.Chrome.dev", "Chrome Dev"),
        ("com.google.Chrome.canary", "Chrome Canary"),
        ("org.mozilla.firefox", "Firefox"),
        ("org.mozilla.firefoxdeveloperedition", "Firefox Developer Edition"),
        ("org.mozilla.nightly", "Firefox Nightly"),
        ("com.brave.Browser", "Brave"),
        ("com.brave.Browser.beta", "Brave Beta"),
        ("com.brave.Browser.nightly", "Brave Nightly"),
        ("com.microsoft.edgemac", "Edge"),
        ("com.microsoft.edgemac.Beta", "Edge Beta"),
        ("com.microsoft.edgemac.Dev", "Edge Dev"),
        ("com.microsoft.edgemac.Canary", "Edge Canary"),
        ("company.thebrowser.Browser", "Arc"),
        ("company.thebrowser.dia", "Dia"),
        ("com.kagi.kagimacOS", "Orion"),
        ("com.operasoftware.Opera", "Opera"),
        ("com.operasoftware.OperaGX", "Opera GX"),
        ("org.chromium.Chromium", "Chromium"),
        ("com.vivaldi.Vivaldi", "Vivaldi"),
        ("net.waterfox.waterfox", "Waterfox"),
        ("app.zen-browser.zen", "Zen Browser"),
        ("app.floorp.Floorp", "Floorp"),
        ("io.gitlab.librewolf-community", "LibreWolf"),
        ("org.torproject.torbrowser", "Tor Browser"),
        ("net.mullvad.mullvadbrowser", "Mullvad Browser"),
        ("com.duckduckgo.macos.vpn", "DuckDuckGo Browser"),
        ("com.sigmaos.sigmaos.macos", "SigmaOS"),
        ("com.pushplaylabs.sidekick", "Sidekick"),
        ("com.naver.Whale", "Whale"),
        ("ru.yandex.desktop.yandex-browser", "Yandex Browser")
    ]

    // Scanning reads several Info.plist files, and this is called from view
    // bodies, so the result is kept for a few seconds.
    private static var cache: (date: Date, browsers: [InstalledBrowser])?
    private static let cacheLifetime: TimeInterval = 15

    /// Known browsers that are installed (in list order), followed by any other
    /// app that declares it can open http AND https links (alphabetical,
    /// marked `isRecognised == false`). Never includes BrowserLink itself.
    static func installedBrowsers() -> [InstalledBrowser] {
        if let cache, Date().timeIntervalSince(cache.date) < cacheLifetime {
            return cache.browsers
        }
        let browsers = scanForBrowsers()
        cache = (Date(), browsers)
        return browsers
    }

    private static func scanForBrowsers() -> [InstalledBrowser] {
        let known: [InstalledBrowser] = knownBrowserIDs.compactMap { entry in
            guard let appURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: entry.id
            ) else {
                return nil
            }
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            return InstalledBrowser(id: entry.id, name: entry.name, icon: icon, url: appURL, isRecognised: true)
        }

        let knownIDs = Set(knownBrowserIDs.map(\.id))
        return known + discoverOtherBrowsers(excluding: knownIDs)
    }

    /// Asks LaunchServices which apps can open web links, then keeps only the
    /// ones that look like real browsers: they must declare BOTH the http and
    /// https schemes in their own Info.plist (chat and mail apps usually
    /// declare only their own scheme and rely on universal links instead).
    private static func discoverOtherBrowsers(excluding knownIDs: Set<String>) -> [InstalledBrowser] {
        guard let probe = URL(string: "https://example.com") else { return [] }
        let ownID = Bundle.main.bundleIdentifier

        var seen = Set<String>()
        var found: [InstalledBrowser] = []

        for appURL in NSWorkspace.shared.urlsForApplications(toOpen: probe) {
            // Helper apps tucked inside another app (login items, VPN agents…)
            // aren't browsers in their own right.
            guard !appURL.path.contains(".app/Contents/") else { continue }

            guard let bundle = Bundle(url: appURL),
                  let id = bundle.bundleIdentifier,
                  id != ownID,
                  !knownIDs.contains(id),
                  !seen.contains(id),
                  declaresWebSchemes(bundle) else { continue }
            seen.insert(id)

            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? appURL.deletingPathExtension().lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            found.append(InstalledBrowser(id: id, name: name, icon: icon, url: appURL, isRecognised: false))
        }

        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func declaresWebSchemes(_ bundle: Bundle) -> Bool {
        guard let urlTypes = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else {
            return false
        }
        let schemes = Set(
            urlTypes
                .flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }
                .map { $0.lowercased() }
        )
        return schemes.contains("http") && schemes.contains("https")
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

extension BrowserDetector {
    static func ordered(_ browsers: [InstalledBrowser], by order: [String]) -> [InstalledBrowser] {
        let lookup = Dictionary(browsers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var result: [InstalledBrowser] = []
        for id in order {
            if let browser = lookup[id] {
                result.append(browser)
            }
        }

        let remaining = browsers.filter { !order.contains($0.id) }
        result.append(contentsOf: remaining)

        return result
    }

    /// Installed browsers in the user's chosen order, minus any they switched off.
    static func visibleBrowsers() -> [InstalledBrowser] {
        ordered(installedBrowsers(), by: AppSettings.shared.browserOrder)
            .filter { !AppSettings.shared.hiddenBrowsers.contains($0.id) }
    }
}
