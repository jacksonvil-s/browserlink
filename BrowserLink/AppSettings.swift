import Foundation
import SwiftUI
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

    /// Mirrors SMAppService's actual registration state. Setting this asks
    /// LoginItemHelper to (un)register, then re-reads the real state: if macOS
    /// refused, or still needs the user's approval in System Settings, the
    /// value snaps back so the toggle never claims something that isn't true.
    @Published var launchAtLoginEnabled: Bool {
        didSet {
            guard launchAtLoginEnabled != oldValue, !isSyncingLaunchAtLogin else { return }
            LoginItemHelper.setEnabled(launchAtLoginEnabled)

            let actual = LoginItemHelper.isEnabled
            if actual != launchAtLoginEnabled {
                // Assigning inside our own didSet doesn't re-trigger it.
                launchAtLoginEnabled = actual
            }
        }
    }

    /// True while we're copying the OS state INTO `launchAtLoginEnabled`, so
    /// that write doesn't turn around and call register()/unregister() again.
    private var isSyncingLaunchAtLogin = false

    @Published var hasCompletedOnboarding: Bool {
        didSet { persist(newValue: hasCompletedOnboarding, oldValue: oldValue, key: Keys.hasCompletedOnboarding) }
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
    
    /// Warns when a link uses plain http:// instead of https://.
    @Published var flagInsecureHTTP: Bool {
        didSet { persist(newValue: flagInsecureHTTP, oldValue: oldValue, key: Keys.flagInsecureHTTP) }
    }
    
    /// Fake brand look-alike domains, like paypal-login.xyz.
    @Published var flagBrandLookalikes: Bool {
        didSet { persist(newValue: flagBrandLookalikes, oldValue: oldValue, key: Keys.flagBrandLookalikes) }
    }

    /// The "@" trick, like https://paypal.com@evil-site.xyz.
    @Published var flagAtSignTrick: Bool {
        didSet { persist(newValue: flagAtSignTrick, oldValue: oldValue, key: Keys.flagAtSignTrick) }
    }

    /// Links that point straight at a program or installer.
    @Published var flagDownloadLinks: Bool {
        didSet { persist(newValue: flagDownloadLinks, oldValue: oldValue, key: Keys.flagDownloadLinks) }
    }

    /// Shortened links like bit.ly.
    @Published var flagURLShorteners: Bool {
        didSet { persist(newValue: flagURLShorteners, oldValue: oldValue, key: Keys.flagURLShorteners) }
    }
    
    /// Waits 3 seconds before the "I understand the risk" button works on
    /// serious (red) warnings.
    @Published var delaySevereConfirm: Bool {
        didSet { persist(newValue: delaySevereConfirm, oldValue: oldValue, key: Keys.delaySevereConfirm) }
    }
    
    /// App mode (Preview window, browser chooser, both)
    @Published var appMode: AppMode {
        didSet { persist(newValue: appMode.rawValue, oldValue: oldValue.rawValue, key: Keys.appMode) }
    }

    /// Plays a short sound when the chooser panel appears.
    @Published var playSoundOnChooserAppear: Bool {
        didSet { persist(newValue: playSoundOnChooserAppear, oldValue: oldValue, key: Keys.playSoundOnChooserAppear) }
    }
    
    /// Reveal a file in Finder right after PreviewWindowView
    /// finishes saving it to Downloads.
    @Published var revealDownloadsInFinder: Bool {
        didSet { persist(newValue: revealDownloadsInFinder, oldValue: oldValue, key: Keys.revealDownloadsInFinder) }
    }

    /// URLSafetyChecker's check for javascript:, data: and file: links.
    @Published var flagDangerousSchemes: Bool {
        didSet { persist(newValue: flagDangerousSchemes, oldValue: oldValue, key: Keys.flagDangerousSchemes) }
    }

    /// Whether Quick Preview runs page JavaScript by default. The preview
    /// window also has its own per-preview toggle.
    @Published var previewJavaScriptEnabled: Bool {
        didSet { persist(newValue: previewJavaScriptEnabled, oldValue: oldValue, key: Keys.previewJavaScriptEnabled) }
    }

    /// LinkCleaner: remove utm_*, fbclid and similar tracking parameters.
    @Published var stripTrackingParameters: Bool {
        didSet { persist(newValue: stripTrackingParameters, oldValue: oldValue, key: Keys.stripTrackingParameters) }
    }

    /// LinkCleaner: open the real destination of known redirect wrappers.
    @Published var unwrapRedirectLinks: Bool {
        didSet { persist(newValue: unwrapRedirectLinks, oldValue: oldValue, key: Keys.unwrapRedirectLinks) }
    }

    /// Which screen the chooser panel appears on (multi-monitor setups).
    @Published var chooserScreen: ChooserScreen {
        didSet { persist(newValue: chooserScreen.rawValue, oldValue: oldValue.rawValue, key: Keys.chooserScreen) }
    }

    @Published var browserOrder: [String] {
        didSet { persist(newValue: browserOrder, oldValue: oldValue, key: Keys.browserOrder)}
    }
    
    /// Bundle IDs of browsers the user has switched off in the chooser.
    @Published var hiddenBrowsers: [String] {
        didSet { persist(newValue: hiddenBrowsers, oldValue: oldValue, key: Keys.hiddenBrowsers) }
    }
    
    @Published var interfaceColour: String {
        didSet { persist(newValue: interfaceColour, oldValue: oldValue, key: Keys.interfaceColour)}
    }
    
    var resolvedInterfaceColour: Color? {
        interfaceColour.isEmpty ? nil : Color(hex: interfaceColour)
    }
    
    /// The effective accent color the UI should use — the user's custom
    /// interfaceColour if set, otherwise the system accent color. Views that
    /// want to respect the custom tint should read this instead of writing
    /// `settings.tintColor` directly.
    var tintColor: Color {
        resolvedInterfaceColour ?? .accentColor
    }

    /// Which Sparkle release channel to receive updates from (stable, release
    /// candidate or beta). Read by AppDelegate.allowedChannels(for:).
    @Published var updateChannel: UpdateChannel {
        didSet { persist(newValue: updateChannel.rawValue, oldValue: oldValue.rawValue, key: Keys.updateChannel) }
    }

    /// A plain-value copy of the safety switches, which URLSafetyChecker
    /// takes as input so it never has to read saved preferences itself.
    var safetySettings: SafetySettings {
        SafetySettings(
            warnAboutSuspiciousLinks: warnAboutSuspiciousLinks,
            flagDangerousSchemes: flagDangerousSchemes,
            flagRawIPLinks: flagRawIPLinks,
            flagMixedScriptDomains: flagMixedScriptDomains,
            flagPunycodeDomains: flagPunycodeDomains,
            flagDeepSubdomains: flagDeepSubdomains,
            flagInsecureHTTP: flagInsecureHTTP,
            flagBrandLookalikes: flagBrandLookalikes,
            flagAtSignTrick: flagAtSignTrick,
            flagDownloadLinks: flagDownloadLinks,
            flagURLShorteners: flagURLShorteners
        )
    }

    // MARK: - Future (persisted now, not yet read by any behavior)
    
    /// Keep a short "Recent Links" list in the menu bar. Held in memory only.
    @Published var keepRecentLinks: Bool {
        didSet { persist(newValue: keepRecentLinks, oldValue: oldValue, key: Keys.keepRecentLinks) }
    }
    
    /// Site (e.g. "github.com") -> bundle identifier of the browser to open it in.
    @Published var siteRules: [String: String] {
        didSet { persist(newValue: siteRules, oldValue: oldValue, key: Keys.siteRules) }
    }

    /// Temporarily ignore every site rule. Deliberately NOT saved, so it
    /// resets when the app restarts and can't be left on by accident.
    @Published var pauseSiteRules = false
    
    /// Future: remember a chosen browser per-domain and skip the chooser
    /// next time a link from that domain is opened.
    @Published var rememberPerSiteChoices: Bool {
        didSet { persist(newValue: rememberPerSiteChoices, oldValue: oldValue, key: Keys.rememberPerSiteChoices) }
    }

    /// Future: opt-in to Sparkle's anonymous system-profile data. Currently
    /// UI-only — actually sending this also requires an SUEnableSystemProfiling
    /// entry in Info.plist and a server-side collector, neither of which
    /// exist yet, so this value isn't read by AppDelegate/Sparkle at all.
    @Published var shareAnonymousSystemInfo: Bool {
        didSet { persist(newValue: shareAnonymousSystemInfo, oldValue: oldValue, key: Keys.shareAnonymousSystemInfo) }
    }

    private enum Keys {
        static let playSoundOnChooserAppear = "playSoundOnChooserAppear"
        static let showFaviconsInChooser = "showFaviconsInChooser"
        static let rememberPerSiteChoices = "rememberPerSiteChoices"
        static let siteRules = "siteRules"
        static let keepRecentLinks = "keepRecentLinks"
        static let revealDownloadsInFinder = "revealDownloadsInFinder"
        static let warnAboutSuspiciousLinks = "warnAboutSuspiciousLinks"
        static let flagRawIPLinks = "flagRawIPLinks"
        static let flagMixedScriptDomains = "flagMixedScriptDomains"
        static let flagPunycodeDomains = "flagPunycodeDomains"
        static let flagDeepSubdomains = "flagDeepSubdomains"
        static let flagInsecureHTTP = "flagInsecureHTTP"
        static let flagBrandLookalikes = "flagBrandLookalikes"
        static let flagAtSignTrick = "flagAtSignTrick"
        static let flagDownloadLinks = "flagDownloadLinks"
        static let flagURLShorteners = "flagURLShorteners"
        static let delaySevereConfirm = "delaySevereConfirm"
        static let appMode = "appMode"
        static let shareAnonymousSystemInfo = "shareAnonymousSystemInfo"
        static let updateChannel = "updateChannel"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let browserOrder = "browserOrder"
        static let hiddenBrowsers = "hiddenBrowsers"
        static let interfaceColour = "interfaceColour"
        static let hasLaunchedBefore = "hasLaunchedBefore"
        static let flagDangerousSchemes = "flagDangerousSchemes"
        static let previewJavaScriptEnabled = "previewJavaScriptEnabled"
        static let stripTrackingParameters = "stripTrackingParameters"
        static let unwrapRedirectLinks = "unwrapRedirectLinks"
        static let chooserScreen = "chooserScreen"
    }

    private init() {
        let defaults = UserDefaults.standard
        let hasLaunchedBefore = defaults.bool(forKey: Keys.hasLaunchedBefore)
        
        if hasLaunchedBefore {
            launchAtLoginEnabled = LoginItemHelper.isEnabled
        } else {
            launchAtLoginEnabled = false
            defaults.set(true, forKey: Keys.hasLaunchedBefore)
        }
        
        // The old "Hide Menu Bar Icon" option is gone (macOS has its own switch
        // now); clear any value it left behind.
        defaults.removeObject(forKey: "hideMenuBarIcon")

        // Defaults chosen so each toggle reflects today's actual behavior
        // (e.g. safety warnings are already always-on; favicons stay off
        // because they contact Google) rather
        // than silently changing what the app does the moment it's updated.
        playSoundOnChooserAppear = defaults.object(forKey: Keys.playSoundOnChooserAppear) as? Bool ?? false
        showFaviconsInChooser = defaults.object(forKey: Keys.showFaviconsInChooser) as? Bool ?? false
        rememberPerSiteChoices = defaults.object(forKey: Keys.rememberPerSiteChoices) as? Bool ?? true
        siteRules = defaults.dictionary(forKey: Keys.siteRules) as? [String: String] ?? [:]
        keepRecentLinks = defaults.bool(forKey: Keys.keepRecentLinks)
        revealDownloadsInFinder = defaults.bool(forKey: Keys.revealDownloadsInFinder)
        warnAboutSuspiciousLinks = defaults.object(forKey: Keys.warnAboutSuspiciousLinks) as? Bool ?? true
        flagRawIPLinks = defaults.object(forKey: Keys.flagRawIPLinks) as? Bool ?? true
        flagMixedScriptDomains = defaults.object(forKey: Keys.flagMixedScriptDomains) as? Bool ?? true
        flagPunycodeDomains = defaults.object(forKey: Keys.flagPunycodeDomains) as? Bool ?? true
        flagDeepSubdomains = defaults.object(forKey: Keys.flagDeepSubdomains) as? Bool ?? true
        flagInsecureHTTP = defaults.object(forKey: Keys.flagInsecureHTTP) as? Bool ?? true
        flagBrandLookalikes = defaults.object(forKey: Keys.flagBrandLookalikes) as? Bool ?? true
        flagAtSignTrick = defaults.object(forKey: Keys.flagAtSignTrick) as? Bool ?? true
        flagDownloadLinks = defaults.object(forKey: Keys.flagDownloadLinks) as? Bool ?? true
        flagURLShorteners = defaults.object(forKey: Keys.flagURLShorteners) as? Bool ?? true
        delaySevereConfirm = defaults.object(forKey: Keys.delaySevereConfirm) as? Bool ?? true
        appMode = AppMode(rawValue: defaults.string(forKey: Keys.appMode) ?? "") ?? .both
        shareAnonymousSystemInfo = defaults.bool(forKey: Keys.shareAnonymousSystemInfo)
        updateChannel = UpdateChannel(rawValue: defaults.string(forKey: Keys.updateChannel) ?? "") ?? .stable
        browserOrder = defaults.stringArray(forKey: Keys.browserOrder) ?? []
        hiddenBrowsers = defaults.stringArray(forKey: Keys.hiddenBrowsers) ?? []
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        interfaceColour = defaults.string(forKey: Keys.interfaceColour) ?? ""
        flagDangerousSchemes = defaults.object(forKey: Keys.flagDangerousSchemes) as? Bool ?? true
        previewJavaScriptEnabled = defaults.object(forKey: Keys.previewJavaScriptEnabled) as? Bool ?? true
        stripTrackingParameters = defaults.object(forKey: Keys.stripTrackingParameters) as? Bool ?? true
        unwrapRedirectLinks = defaults.object(forKey: Keys.unwrapRedirectLinks) as? Bool ?? true
        chooserScreen = ChooserScreen(rawValue: defaults.string(forKey: Keys.chooserScreen) ?? "") ?? .underMouse
    }

    private func persist<T: Equatable>(newValue: T, oldValue: T, key: String) {
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
        guard live != launchAtLoginEnabled else { return }
        // Copy the OS state in WITHOUT asking the OS to change anything.
        isSyncingLaunchAtLogin = true
        launchAtLoginEnabled = live
        isSyncingLaunchAtLogin = false
    }
}

// MARK: Update Channel
enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable
    case releaseCandidate
    case beta

    var id: String { rawValue }

    var label: String {
        switch self {
        case .stable: return "Stable"
        case .releaseCandidate: return "Release Candidate"
        case .beta: return "Beta"
        }
    }

    var explanation: String {
        switch self {
        case .stable:
            return "Fully tested releases only. Recommended for most people."
        case .releaseCandidate:
            return "Near-final builds shortly before a stable release. Usually solid, occasional rough edges."
        case .beta:
            return "Early, in-development builds. May be unstable or contain bugs. Rapid changes."
        }
    }
}

// MARK: App mode
enum AppMode: String, CaseIterable, Identifiable {
    case preview
    case chooser
    case both

    var id: String { rawValue }

    var label: String {
        switch self {
        case .preview: return "Preview window only"
        case .chooser: return "Browser chooser only"
        case .both: return "Both preview window and browser chooser"
        }
    }

    var explanation: String {
        switch self {
        case .preview:
            return "Only the private preview window will be used. You can still preview the link and optionally enable security protections."
        case .chooser:
            return "Only the browser chooser is available. You can preview the link and optionally enable security protections."
        case .both:
            return "Both the browser chooser and private preview will appear. You can choose between the two as you like."
        }
    }
    
    var icon: String {
        switch self {
        case .preview:
            return "interface.window"
        case .chooser:
            return "square.grid.3x2"
        case .both:
            return "capsule.on.rectangle"
        }
    }
}

// MARK: Chooser screen
enum ChooserScreen: String, CaseIterable, Identifiable {
    case underMouse
    case mainScreen

    var id: String { rawValue }

    var label: String {
        switch self {
        case .underMouse: return "Screen with the mouse pointer"
        case .mainScreen: return "Screen with the active window"
        }
    }

    var explanation: String {
        switch self {
        case .underMouse:
            return "The chooser appears on whichever display your mouse is on."
        case .mainScreen:
            return "The chooser appears on the display holding the window you're working in."
        }
    }
}
