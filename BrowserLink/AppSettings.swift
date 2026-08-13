import Foundation
import Combine

/// Single source of truth for app preferences. Both the menu bar menu
/// (AppDelegate) and the Preferences window (PreferencesView) read and
/// write through this one shared, observable instance, so they can never
/// drift out of sync with each other.
///
/// Some properties below aren't read by any behavior yet (see the "Future"
/// marker on each) — they exist so the Preferences UI can offer the toggle
/// now, with the value already persisting correctly. Wiring one up later is
/// just a matter of having the relevant code check `AppSettings.shared.x`;
/// no UI or storage work is needed at that point.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // MARK: - Live (already wired to real behavior)

    /// Mirrors SMAppService's actual registration state. Setting this
    /// calls straight through to LoginItemHelper, so the OS-level state
    /// and this published value can't disagree.
    @Published var launchAtLoginEnabled: Bool {
        didSet {
            guard launchAtLoginEnabled != oldValue else { return }
            LoginItemHelper.setEnabled(launchAtLoginEnabled)
        }
    }

    @Published var hideMenuBarIcon: Bool {
        didSet { persist(newValue: hideMenuBarIcon, oldValue: oldValue, key: Keys.hideMenuBarIcon) }
    }
    
    /// FaviconLoader already fetches these — this would let
    /// someone turn the (Google-routed) lookup off entirely for privacy.
    @Published var showFaviconsInChooser: Bool {
        didSet { persist(newValue: showFaviconsInChooser, oldValue: oldValue, key: Keys.showFaviconsInChooser) }
    }
    
    /// master switch for URLSafetyChecker's warning banner.
    @Published var warnAboutSuspiciousLinks: Bool {
        didSet { persist(newValue: warnAboutSuspiciousLinks, oldValue: oldValue, key: Keys.warnAboutSuspiciousLinks) }
    }

    /// URLSafetyChecker's raw-IP-address heuristic, individually toggleable.
    @Published var flagRawIPLinks: Bool {
        didSet { persist(newValue: flagRawIPLinks, oldValue: oldValue, key: Keys.flagRawIPLinks) }
    }

    /// URLSafetyChecker's homograph/mixed-script heuristic, individually toggleable.
    @Published var flagMixedScriptDomains: Bool {
        didSet { persist(newValue: flagMixedScriptDomains, oldValue: oldValue, key: Keys.flagMixedScriptDomains) }
    }

    /// URLSafetyChecker's punycode heuristic, individually toggleable.
    @Published var flagPunycodeDomains: Bool {
        didSet { persist(newValue: flagPunycodeDomains, oldValue: oldValue, key: Keys.flagPunycodeDomains) }
    }
    
    /// URLSafetyChecker's deep subdomain heuristic, individually toggleable.
    @Published var flagDeepSubdomains: Bool {
        didSet { persist(newValue: flagDeepSubdomains, oldValue: oldValue, key: Keys.flagDeepSubdomains) }
    }
    
    @Published var enablePreviewWindow: Bool {
        didSet { persist(newValue: enablePreviewWindow, oldValue: oldValue, key: Keys.enablePreviewWindow) }
    }

    // MARK: - Future (persisted now, not yet read by any behavior)

    /// Future: play a short sound when the chooser panel appears.
    @Published var playSoundOnChooserAppear: Bool {
        didSet { persist(newValue: playSoundOnChooserAppear, oldValue: oldValue, key: Keys.playSoundOnChooserAppear) }
    }

    /// Future: remember a chosen browser per-domain and skip the chooser
    /// next time a link from that domain is opened.
    @Published var rememberPerSiteChoices: Bool {
        didSet { persist(newValue: rememberPerSiteChoices, oldValue: oldValue, key: Keys.rememberPerSiteChoices) }
    }

    /// Future: reveal a file in Finder right after PreviewWindowView
    /// finishes saving it to Downloads.
    @Published var revealDownloadsInFinder: Bool {
        didSet { persist(newValue: revealDownloadsInFinder, oldValue: oldValue, key: Keys.revealDownloadsInFinder) }
    }

    /// Future: opt-in to Sparkle's anonymous system-profile data. Currently
    /// UI-only — actually sending this also requires an SUEnableSystemProfiling
    /// entry in Info.plist and a server-side collector, neither of which
    /// exist yet, so this value isn't read by AppDelegate/Sparkle at all.
    @Published var shareAnonymousSystemInfo: Bool {
        didSet { persist(newValue: shareAnonymousSystemInfo, oldValue: oldValue, key: Keys.shareAnonymousSystemInfo) }
    }

    /// Future: opt in to a beta update channel (would point Sparkle at a
    /// separate appcast feed).
    @Published var notifyAboutBetaUpdates: Bool {
        didSet { persist(newValue: notifyAboutBetaUpdates, oldValue: oldValue, key: Keys.notifyAboutBetaUpdates) }
    }

    private enum Keys {
        static let hideMenuBarIcon = "hideMenuBarIcon"
        static let playSoundOnChooserAppear = "playSoundOnChooserAppear"
        static let showFaviconsInChooser = "showFaviconsInChooser"
        static let rememberPerSiteChoices = "rememberPerSiteChoices"
        static let revealDownloadsInFinder = "revealDownloadsInFinder"
        static let warnAboutSuspiciousLinks = "warnAboutSuspiciousLinks"
        static let flagRawIPLinks = "flagRawIPLinks"
        static let flagMixedScriptDomains = "flagMixedScriptDomains"
        static let flagPunycodeDomains = "flagPunycodeDomains"
        static let flagDeepSubdomains = "flagDeepSubdomains"
        static let enablePreviewWindow = "enablePreviewWindow"
        static let shareAnonymousSystemInfo = "shareAnonymousSystemInfo"
        static let notifyAboutBetaUpdates = "notifyAboutBetaUpdates"
    }

    private init() {
        let defaults = UserDefaults.standard

        launchAtLoginEnabled = LoginItemHelper.isEnabled
        hideMenuBarIcon = defaults.bool(forKey: Keys.hideMenuBarIcon)

        // Defaults chosen so each toggle reflects today's actual behavior
        // (e.g. favicons and safety warnings are already always-on) rather
        // than silently changing what the app does the moment it's updated.
        playSoundOnChooserAppear = defaults.object(forKey: Keys.playSoundOnChooserAppear) as? Bool ?? true
        showFaviconsInChooser = defaults.object(forKey: Keys.showFaviconsInChooser) as? Bool ?? true
        rememberPerSiteChoices = defaults.bool(forKey: Keys.rememberPerSiteChoices)
        revealDownloadsInFinder = defaults.bool(forKey: Keys.revealDownloadsInFinder)
        warnAboutSuspiciousLinks = defaults.object(forKey: Keys.warnAboutSuspiciousLinks) as? Bool ?? true
        flagRawIPLinks = defaults.object(forKey: Keys.flagRawIPLinks) as? Bool ?? true
        flagMixedScriptDomains = defaults.object(forKey: Keys.flagMixedScriptDomains) as? Bool ?? true
        flagPunycodeDomains = defaults.object(forKey: Keys.flagPunycodeDomains) as? Bool ?? true
        flagDeepSubdomains = defaults.object(forKey: Keys.flagDeepSubdomains) as? Bool ?? true
        enablePreviewWindow = defaults.object(forKey: Keys.enablePreviewWindow) as? Bool ?? true
        shareAnonymousSystemInfo = defaults.bool(forKey: Keys.shareAnonymousSystemInfo)
        notifyAboutBetaUpdates = defaults.bool(forKey: Keys.notifyAboutBetaUpdates)
    }

    private func persist(newValue: Bool, oldValue: Bool, key: String) {
        guard newValue != oldValue else { return }
        UserDefaults.standard.set(newValue, forKey: key)
    }

    /// Re-reads the live SMAppService status into the published value.
    /// Useful to call when the app becomes active again — SMAppService's
    /// state can change entirely outside the app (e.g. the user disables
    /// it from System Settings → General → Login Items), and there's no
    /// push notification for that, only polling on demand.
    func refreshLaunchAtLoginFromSystem() {
        let live = LoginItemHelper.isEnabled
        if live != launchAtLoginEnabled {
            launchAtLoginEnabled = live
        }
    }
}
