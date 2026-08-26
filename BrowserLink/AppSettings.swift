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
    
    /// App mode (Preview window, browser chooser, both)
    @Published var appMode: AppMode {
        didSet { persist(newValue: appMode.rawValue, oldValue: oldValue.rawValue, key: Keys.appMode) }
    }

    /// Plays a short sound when the chooser panel appears.
    @Published var playSoundOnChooserAppear: Bool {
        didSet { persist(newValue: playSoundOnChooserAppear, oldValue: oldValue, key: Keys.playSoundOnChooserAppear) }
    }
    
    @Published var browserOrder: [String] {
        didSet { persist(newValue: browserOrder, oldValue: oldValue, key: Keys.browserOrder)}
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

    // MARK: - Future (persisted now, not yet read by any behavior)
    
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

    /// Future: which release channel to receive update notifications for
    /// (would point Sparkle at a different appcast feed per channel). Not
    /// wired to Sparkle or any update logic yet — persisted only.
    @Published var updateChannel: UpdateChannel {
        didSet { persist(newValue: updateChannel.rawValue, oldValue: oldValue.rawValue, key: Keys.updateChannel) }
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
        static let appMode = "appMode"
        static let shareAnonymousSystemInfo = "shareAnonymousSystemInfo"
        static let updateChannel = "updateChannel"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let browserOrder = "browserOrder"
        static let interfaceColour = "interfaceColour"
        static let hasLaunchedBefore = "hasLaunchedBefore"
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
        
        hideMenuBarIcon = defaults.bool(forKey: Keys.hideMenuBarIcon)

        // Defaults chosen so each toggle reflects today's actual behavior
        // (e.g. favicons and safety warnings are already always-on) rather
        // than silently changing what the app does the moment it's updated.
        playSoundOnChooserAppear = defaults.object(forKey: Keys.playSoundOnChooserAppear) as? Bool ?? false
        showFaviconsInChooser = defaults.object(forKey: Keys.showFaviconsInChooser) as? Bool ?? false
        rememberPerSiteChoices = defaults.bool(forKey: Keys.rememberPerSiteChoices)
        revealDownloadsInFinder = defaults.bool(forKey: Keys.revealDownloadsInFinder)
        warnAboutSuspiciousLinks = defaults.object(forKey: Keys.warnAboutSuspiciousLinks) as? Bool ?? true
        flagRawIPLinks = defaults.object(forKey: Keys.flagRawIPLinks) as? Bool ?? true
        flagMixedScriptDomains = defaults.object(forKey: Keys.flagMixedScriptDomains) as? Bool ?? true
        flagPunycodeDomains = defaults.object(forKey: Keys.flagPunycodeDomains) as? Bool ?? true
        flagDeepSubdomains = defaults.object(forKey: Keys.flagDeepSubdomains) as? Bool ?? true
        appMode = AppMode(rawValue: defaults.string(forKey: Keys.appMode) ?? "") ?? .both
        shareAnonymousSystemInfo = defaults.bool(forKey: Keys.shareAnonymousSystemInfo)
        updateChannel = UpdateChannel(rawValue: defaults.string(forKey: Keys.updateChannel) ?? "") ?? .stable
        browserOrder = defaults.stringArray(forKey: Keys.browserOrder) ?? []
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        interfaceColour = defaults.string(forKey: Keys.interfaceColour) ?? ""
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
        if live != launchAtLoginEnabled {
            launchAtLoginEnabled = live
        }
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
            return "Both the browser chooser and priate preview will appear. You can choose between the 2 as you like."
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
