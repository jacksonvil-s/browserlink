import SwiftUI
import Sparkle
import Combine

/// Settings window: a System Settings–style sidebar on the left, one grouped
/// form per category on the right.
struct PreferencesView: View {
    let updater: SPUUpdater
    let onSetDefaultBrowser: () -> Void
    let onRestartOnboarding: () -> Void
    let onShowDebugChooser: () -> Void

    /// Rows below write straight into the shared settings, which keeps this
    /// window and the menu bar menu in sync.
    @ObservedObject private var settings = AppSettings.shared

    @State private var selectedTab: PreferencesTab? = .general

    init(
        updater: SPUUpdater,
        onSetDefaultBrowser: @escaping () -> Void,
        onRestartOnboarding: @escaping () -> Void,
        onShowDebugChooser: @escaping () -> Void
    ) {
        self.updater = updater
        self.onSetDefaultBrowser = onSetDefaultBrowser
        self.onRestartOnboarding = onRestartOnboarding
        self.onShowDebugChooser = onShowDebugChooser
    }

    private var currentTab: PreferencesTab { selectedTab ?? .general }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 240)
        } detail: {
            detail
                .navigationTitle(currentTab.title)
        }
        .tint(settings.tintColor)
        .frame(minWidth: 700, minHeight: 480)
        .onAppear {
            // Catches the case where the user changed the login-item state
            // from outside the app (System Settings → General → Login Items).
            settings.refreshLaunchAtLoginFromSystem()
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selectedTab) {
            ForEach(PreferencesTab.allCases) { tab in
                Label {
                    Text(tab.title)
                } icon: {
                    SidebarIcon(symbol: tab.symbol, tint: tab.tint)
                }
                .tag(tab)
            }
        }
        .listStyle(.sidebar)
        .toolbar(removing: .sidebarToggle)
        .safeAreaInset(edge: .bottom) {
            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit BrowserLink", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .padding(12)
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch currentTab {
        case .general:
            GeneralPane(settings: settings, onRestartOnboarding: onRestartOnboarding)
        case .browsers:
            BrowsersPane(settings: settings, onSetDefaultBrowser: onSetDefaultBrowser)
        case .links:
            LinksPane(settings: settings)
        case .preview:
            QuickPreviewPane(settings: settings)
        case .appearance:
            AppearancePane(settings: settings)
        case .security:
            SecurityPane(settings: settings)
        case .updates:
            UpdatesPane(settings: settings, updater: updater)
        case .about:
            AboutPane(settings: settings, onShowDebugChooser: onShowDebugChooser)
        }
    }
}

// MARK: - Tabs

private enum PreferencesTab: String, CaseIterable, Identifiable, Hashable {
    case general, browsers, links, preview, appearance, security, updates, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .browsers: return "Browsers"
        case .links: return "Links"
        case .preview: return "Quick Preview"
        case .appearance: return "Appearance"
        case .security: return "Security"
        case .updates: return "Updates"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .browsers: return "globe"
        case .links: return "link"
        case .preview: return "eye.fill"
        case .appearance: return "paintpalette.fill"
        case .security: return "checkmark.shield.fill"
        case .updates: return "arrow.triangle.2.circlepath"
        case .about: return "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: return .gray
        case .browsers: return .blue
        case .links: return .teal
        case .preview: return .purple
        case .appearance: return .pink
        case .security: return .green
        case .updates: return .orange
        case .about: return .indigo
        }
    }
}

/// White SF Symbol on a coloured rounded square, like System Settings.
private struct SidebarIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.gradient))
    }
}

// MARK: - Row building blocks

/// A switch with an optional grey explanation underneath.
private struct SettingToggle: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
    }
}

/// Dims and disables a row when its master switch is off.
private extension View {
    func dimmed(unless enabled: Bool) -> some View {
        self.opacity(enabled ? 1 : 0.4)
            .disabled(!enabled)
    }
}

/// Coloured heading for a group of security checks.
private struct SeverityHeader: View {
    let level: SafetyLevel
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(title)
                    .font(.headline)
            } icon: {
                Image(systemName: level.symbolName)
                    .foregroundStyle(level.color)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(nil)
        }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @ObservedObject var settings: AppSettings
    let onRestartOnboarding: () -> Void

    var body: some View {
        Form {
            Section("Startup") {
                SettingToggle("Launch at Login", isOn: $settings.launchAtLoginEnabled)
            }

            Section {
                Picker("When a link opens", selection: $settings.appMode) {
                    ForEach(AppMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            } header: {
                Text("Mode")
            } footer: {
                Text(settings.appMode.explanation)
            }

            Section {
                SettingToggle("Play Sound When Chooser Appears", isOn: $settings.playSoundOnChooserAppear)

                SettingToggle(
                    "Show Site Icons in Chooser",
                    subtitle: "Off by default. Fetched from Google's favicon service, so Google sees the sites you open. Never used for links with warnings, IP addresses or local network names.",
                    isOn: $settings.showFaviconsInChooser
                )

                Picker("Show Chooser On", selection: $settings.chooserScreen) {
                    ForEach(ChooserScreen.allCases) { screen in
                        Text(screen.label).tag(screen)
                    }
                }
            } header: {
                Text("Chooser")
            } footer: {
                Text(settings.chooserScreen.explanation)
            }

            Section("Onboarding") {
                Button("Restart Onboarding…", action: onRestartOnboarding)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Browsers

private struct BrowsersPane: View {
    @ObservedObject var settings: AppSettings
    let onSetDefaultBrowser: () -> Void

    @State private var browsers: [InstalledBrowser] = []
    private let rowHeight: CGFloat = 40

    private func isVisible(_ browser: InstalledBrowser) -> Bool {
        !settings.hiddenBrowsers.contains(browser.id)
    }

    private func visibleBinding(for browser: InstalledBrowser) -> Binding<Bool> {
        Binding(
            get: { isVisible(browser) },
            set: { show in
                if show {
                    settings.hiddenBrowsers.removeAll { $0 == browser.id }
                } else if !settings.hiddenBrowsers.contains(browser.id) {
                    settings.hiddenBrowsers.append(browser.id)
                }
            }
        )
    }

    /// Prevents switching off every browser: the last visible one stays on.
    private func isLastVisible(_ browser: InstalledBrowser) -> Bool {
        isVisible(browser) && browsers.filter { isVisible($0) }.count <= 1
    }

    var body: some View {
        Form {
            Section {
                DefaultBrowserStatusLabel()
                Button("Set as Default Browser…", action: onSetDefaultBrowser)
            } header: {
                Text("Default Browser")
            } footer: {
                Text("BrowserLink intercepts links opened anywhere on your Mac and lets you choose where they go — a quick, private preview or a real browser.")
            }

            Section {
                List {
                    ForEach(browsers) { browser in
                        browserRow(browser)
                    }
                    .onMove { indices, newOffset in
                        browsers.move(fromOffsets: indices, toOffset: newOffset)
                        AppSettings.shared.browserOrder = browsers.map(\.id)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .environment(\.defaultMinListRowHeight, rowHeight)
                .frame(height: CGFloat(browsers.count) * rowHeight + 8)

                Button("Reset to Default Order") {
                    AppSettings.shared.browserOrder = []
                    browsers = BrowserDetector.ordered(BrowserDetector.installedBrowsers(), by: [])
                }
            } header: {
                Text("Display Order")
            } footer: {
                Text(
                    settings.appMode == .preview
                    ? "The browser list is switched off because the mode is set to \"\(AppMode.preview.label)\". You can change this under General."
                    : "Drag a browser up or down to change its order. Use the switch to hide it from the chooser. At least one browser always stays visible; to hide them all, set the mode to \"\(AppMode.preview.label)\" under General."
                )
            }
            .opacity(settings.appMode == .preview ? 0.4 : 1)
            .disabled(settings.appMode == .preview)
        }
        .formStyle(.grouped)
        .onAppear {
            browsers = BrowserDetector.ordered(
                BrowserDetector.installedBrowsers(),
                by: AppSettings.shared.browserOrder
            )
        }
    }

    private func browserRow(_ browser: InstalledBrowser) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Image(nsImage: browser.icon)
                .resizable()
                .frame(width: 22, height: 22)
            Text(browser.name)
            if !browser.isRecognised {
                Text("Potentially unsupported")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                    .help("BrowserLink doesn't recognise this app as a browser. It says it can open web links, but links may not open correctly in it.")
            }
            Spacer()
            Toggle("", isOn: visibleBinding(for: browser))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(isLastVisible(browser))
        }
        .frame(height: rowHeight)
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
    }
}

// MARK: - Links

private struct LinksPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var recentLinks = RecentLinks.shared

    @State private var browsers: [InstalledBrowser] = []
    @State private var siteSearch = ""

    private var filteredSiteRules: [(site: String, browserID: String)] {
        settings.siteRules
            .filter { siteSearch.isEmpty || $0.key.localizedCaseInsensitiveContains(siteSearch) }
            .map { (site: $0.key, browserID: $0.value) }
            .sorted { $0.site < $1.site }
    }

    var body: some View {
        Form {
            Section {
                SettingToggle(
                    "Remove Tracking Parameters",
                    subtitle: "Strips things like utm_source and fbclid from links before they open. The chooser tells you when it did, and lets you use the original.",
                    isOn: $settings.stripTrackingParameters
                )
                SettingToggle(
                    "Skip Redirect Wrappers",
                    subtitle: "Opens the real destination of links wrapped by Google, Facebook, Instagram, LinkedIn, YouTube, Slack and similar. Security scanners such as Outlook Safe Links are left alone.",
                    isOn: $settings.unwrapRedirectLinks
                )
            } header: {
                Text("Link Cleanup")
            }

            Section {
                SettingToggle(
                    "Remember Per-Site Choices",
                    subtitle: "Skip the chooser for sites you've picked a browser for. Links with safety warnings always show it. Hold ⌥ as a link opens to see it anyway (some apps use ⌥-click for their own purposes).",
                    isOn: $settings.rememberPerSiteChoices
                )
                SettingToggle(
                    "Pause Remembered Sites",
                    subtitle: "Show the chooser for every link for now. Resets when BrowserLink restarts. Also in the menu bar.",
                    isOn: $settings.pauseSiteRules
                )
                .disabled(!settings.rememberPerSiteChoices)
            } header: {
                Text("Remembered Sites")
            }

            Section {
                if settings.siteRules.isEmpty {
                    Text("No sites yet. Tick \"Remember my choice for …\" in the chooser and the site will appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    if settings.siteRules.count > 6 {
                        TextField("Search sites", text: $siteSearch)
                    }
                    ForEach(filteredSiteRules, id: \.site) { rule in
                        siteRuleRow(site: rule.site, browserID: rule.browserID)
                    }
                    Button("Forget All", role: .destructive) {
                        settings.siteRules = [:]
                    }
                }
            } header: {
                Text("Saved Sites")
            }

            Section {
                SettingToggle(
                    "Keep a Recent Links List",
                    subtitle: "Adds a Recent Links menu to the menu bar for reopening a link you dismissed by accident. Kept in memory only, never saved, and cleared when BrowserLink quits.",
                    isOn: $settings.keepRecentLinks
                )

                Button("Open Link from Clipboard…") {
                    NotificationCenter.default.post(name: .openClipboardLinkRequested, object: nil)
                }

                if settings.keepRecentLinks {
                    if recentLinks.urls.isEmpty {
                        Text("No recent links yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recentLinks.urls, id: \.self) { url in
                            Button(RecentLinks.title(for: url)) {
                                NotificationCenter.default.post(name: .openRecentLinkRequested, object: url)
                            }
                            .buttonStyle(.link)
                        }
                        Button("Clear Recent Links", role: .destructive) {
                            recentLinks.clear()
                        }
                    }
                }
            } header: {
                Text("Recent & Quick Access")
            } footer: {
                Text("The same shortcuts as the menu bar, for when its icon is hidden.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            browsers = BrowserDetector.installedBrowsers()
        }
    }

    private func siteRuleRow(site: String, browserID: String) -> some View {
        let browser = browsers.first { $0.id == browserID }
        let isPreview = browserID == SiteKey.previewRule
        return HStack(spacing: 10) {
            if isPreview {
                Image(systemName: "eye.fill")
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.secondary)
            } else if let browser {
                Image(nsImage: browser.icon)
                    .resizable()
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: "questionmark.app")
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.secondary)
            }
            Text(site).fontWeight(.medium)
            Spacer()
            Text(isPreview ? "Quick Preview" : (browser?.name ?? "Not installed"))
                .foregroundStyle(.secondary)
            Button {
                settings.siteRules.removeValue(forKey: site)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Forget this site")
            .accessibilityLabel("Forget \(site)")
        }
    }
}

// MARK: - Quick Preview

private struct QuickPreviewPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                SettingToggle(
                    "Allow JavaScript",
                    subtitle: "Turning this off is safer but some pages won't work. You can also switch it per preview with the JS button in the preview window.",
                    isOn: $settings.previewJavaScriptEnabled
                )
            } header: {
                Text("Pages")
            } footer: {
                Text("Quick Preview uses a private, in-memory session. Cookies, cache and history disappear when the window closes.")
            }

            Section("Downloads") {
                SettingToggle(
                    "Reveal Downloads in Finder",
                    subtitle: "After a file finishes saving from Quick Preview.",
                    isOn: $settings.revealDownloadsInFinder
                )
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance

private struct AppearancePane: View {
    @ObservedObject var settings: AppSettings

    private var colorBinding: Binding<Color> {
        Binding(
            get: { settings.resolvedInterfaceColour ?? .accentColor },
            set: { settings.interfaceColour = $0.toHex() ?? "" }
        )
    }

    var body: some View {
        Form {
            Section {
                ColorPicker("Interface Colour", selection: colorBinding, supportsOpacity: false)
                Button("Use System Colour") {
                    settings.interfaceColour = ""
                }
                .disabled(settings.interfaceColour.isEmpty)
            } header: {
                Text("Colour")
            } footer: {
                Text("The interface colour will appear mostly everywhere around the UI. There may be a limited number of places where the system accent colour is still used.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Security

private struct SecurityPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                SettingToggle(
                    "Warn About Suspicious Links",
                    subtitle: "Shows a warning when a link trips any check below. Serious and warning-level ones ask you to confirm first.",
                    isOn: $settings.warnAboutSuspiciousLinks
                )
            }

            Section {
                SettingToggle(
                    "Dangerous Link Types",
                    subtitle: "Flags javascript:, data: and file: links, which can run code or read files on your Mac.",
                    isOn: $settings.flagDangerousSchemes
                )
                .dimmed(unless: settings.warnAboutSuspiciousLinks)

                SettingToggle(
                    "Fake Brand Look-alikes",
                    subtitle: "Flags domains that imitate well-known brands, like paypal-login.com. Strong matches are serious; weaker ones show as a warning or a small notice.",
                    isOn: $settings.flagBrandLookalikes
                )
                .dimmed(unless: settings.warnAboutSuspiciousLinks)

                SettingToggle(
                    "Fake \"@\" Usernames",
                    subtitle: "Flags links like paypal.com@evil-site.xyz, where the real destination is hidden after the @.",
                    isOn: $settings.flagAtSignTrick
                )
                .dimmed(unless: settings.warnAboutSuspiciousLinks)

                SettingToggle(
                    "Pause Before Confirming",
                    subtitle: "Waits 3 seconds before you can click \"I understand the risk\" on a serious warning, to give you time to reconsider.",
                    isOn: $settings.delaySevereConfirm
                )
                .dimmed(unless: settings.warnAboutSuspiciousLinks)
            } header: {
                SeverityHeader(level: .serious, title: "Serious", detail: "Almost certainly an attempt to trick or harm you.")
            }

            Section {
                SettingToggle(
                    "Raw IP Address Links",
                    subtitle: "Links that use numbers (including disguised forms like 0x7f000001) instead of a website name. Addresses on your own network only show a small notice.",
                    isOn: $settings.flagRawIPLinks
                )
                .dimmed(unless: settings.warnAboutSuspiciousLinks)

                SettingToggle(
                    "Mixed-Script (Homograph) Domains",
                    subtitle: "Flags domains mixing alphabets, e.g. Latin + Cyrillic look-alikes.",
                    isOn: $settings.flagMixedScriptDomains
                )
                .dimmed(unless: settings.warnAboutSuspiciousLinks)

                SettingToggle(
                    "Punycode Domains",
                    subtitle: "Domains starting with xn--, which can disguise look-alike characters.",
                    isOn: $settings.flagPunycodeDomains
                )
                .dimmed(unless: settings.warnAboutSuspiciousLinks)

                SettingToggle(
                    "Program & Installer Downloads",
                    subtitle: "Flags links that end in .exe, .dmg, .pkg and similar.",
                    isOn: $settings.flagDownloadLinks
                )
                .dimmed(unless: settings.warnAboutSuspiciousLinks)
            } header: {
                SeverityHeader(level: .warning, title: "Warning", detail: "Suspicious, though sometimes innocent. Asks you to confirm.")
            }

            Section {
                SettingToggle(
                    "Unusually Deep Subdomains",
                    subtitle: "Domains made of six or more dot-separated parts, like a.b.c.d.example.com.",
                    isOn: $settings.flagDeepSubdomains
                )
                .dimmed(unless: settings.warnAboutSuspiciousLinks)

                SettingToggle(
                    "Unencrypted (http) Links",
                    subtitle: "Flags links that use http:// instead of https://. Some older sites still use http, so you may switch this off.",
                    isOn: $settings.flagInsecureHTTP
                )
                .dimmed(unless: settings.warnAboutSuspiciousLinks)

                SettingToggle(
                    "Shortened Links",
                    subtitle: "Shows a gentle notice for links from services like bit.ly that hide where they lead.",
                    isOn: $settings.flagURLShorteners
                )
                .dimmed(unless: settings.warnAboutSuspiciousLinks)
            } header: {
                SeverityHeader(level: .advisory, title: "Advisory", detail: "Worth knowing about. Shown as a small notice and never blocks the buttons.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Updates

private struct UpdatesPane: View {
    @ObservedObject var settings: AppSettings
    let updater: SPUUpdater

    // Local mirrors of the updater's own persisted state. Per Sparkle's
    // guidance these are only WRITTEN when the user changes them — each is
    // seeded once here and pushed back to `updater` in onChange.
    @State private var automaticallyChecksForUpdates: Bool
    @State private var automaticallyDownloadsUpdates: Bool
    @State private var checkFrequency: CheckFrequency
    @StateObject private var updateChecker: CheckForUpdatesViewModel

    init(settings: AppSettings, updater: SPUUpdater) {
        self.settings = settings
        self.updater = updater
        _automaticallyChecksForUpdates = State(initialValue: updater.automaticallyChecksForUpdates)
        _automaticallyDownloadsUpdates = State(initialValue: updater.automaticallyDownloadsUpdates)
        _checkFrequency = State(initialValue: CheckFrequency(seconds: updater.updateCheckInterval))
        _updateChecker = StateObject(wrappedValue: CheckForUpdatesViewModel(updater: updater))
    }

    var body: some View {
        Form {
            Section("Automatic Updates") {
                SettingToggle("Check for Updates Automatically", isOn: $automaticallyChecksForUpdates)
                    .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                        updater.automaticallyChecksForUpdates = newValue
                        // Downloading automatically only makes sense if
                        // checking automatically is also on.
                        if !newValue && automaticallyDownloadsUpdates {
                            automaticallyDownloadsUpdates = false
                            updater.automaticallyDownloadsUpdates = false
                        }
                    }

                Picker("Frequency", selection: $checkFrequency) {
                    ForEach(CheckFrequency.allCases) { frequency in
                        Text(frequency.label).tag(frequency)
                    }
                }
                .disabled(!automaticallyChecksForUpdates)
                .onChange(of: checkFrequency) { _, newValue in
                    updater.updateCheckInterval = newValue.seconds
                }

                SettingToggle("Download Automatically", isOn: $automaticallyDownloadsUpdates)
                    .disabled(!automaticallyChecksForUpdates)
                    .onChange(of: automaticallyDownloadsUpdates) { _, newValue in
                        updater.automaticallyDownloadsUpdates = newValue
                    }
            }

            Section {
                Picker("Update Channel", selection: $settings.updateChannel) {
                    ForEach(UpdateChannel.allCases) { channel in
                        Text(channel.label).tag(channel)
                    }
                }
            } header: {
                Text("Channel")
            } footer: {
                Text(settings.updateChannel.explanation)
            }

            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        Text("Coming Soon")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.secondary.opacity(0.15)))
                        Toggle("", isOn: .constant(false))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(true)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Share Anonymous System Info")
                        Text("Would help decide which macOS versions and Mac models to keep supporting. No personal data included.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                Text("Privacy")
            }

            Section {
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!updateChecker.canCheckForUpdates)

                if let lastCheck = updater.lastUpdateCheckDate {
                    Text("Last checked \(lastCheck.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Never checked for updates")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

private struct AboutPane: View {
    @ObservedObject var settings: AppSettings
    let onShowDebugChooser: () -> Void

    var body: some View {
        // Scrollable and sized from the available space (instead of Spacers and
        // an infinite frame) so this pane can never demand more room than the
        // split view's detail column has, which is what broke the sidebar.
        GeometryReader { geo in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
        }
    }

    private var content: some View {
        VStack(spacing: 14) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(settings.tintColor.gradient)

            VStack(spacing: 4) {
                Text("BrowserLink")
                    .font(.system(size: 22, weight: .semibold))
                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    // Hidden developer shortcut: ⌥-click opens the test-link prompt.
                    .onTapGesture {
                        if NSEvent.modifierFlags.contains(.option) {
                            onShowDebugChooser()
                        }
                    }
            }

            Text("Choose where your links go — a quick, private preview or a real browser, every time.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)

            if let repo = URL(string: "https://github.com/jacksonvil-s/browserlink") {
                Link(destination: repo) {
                    Label("View on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(.bordered)
            }

            VStack(spacing: 3) {
                Text("Update checking powered by Sparkle.")
                Text("BrowserLink, \(currentYear). Licensed under Apache 2.0. The full source code is available on GitHub.")
                Text("Thank you for using the app. Please star the repo if you find it useful.")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
        }
        .padding(24)
    }

    /// Pulled from the bundle rather than hardcoded, so this pane never
    /// silently drifts from the actual shipping version.
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private var currentYear: String {
        String(Calendar.current.component(.year, from: Date()))
    }
}

// MARK: - Update helpers

private enum CheckFrequency: CaseIterable, Identifiable, Hashable {
    case hourly, daily, weekly

    var id: Self { self }

    var seconds: TimeInterval {
        switch self {
        case .hourly: return 3600
        case .daily: return 86400
        case .weekly: return 604800
        }
    }

    var label: String {
        switch self {
        case .hourly: return "Hourly"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        }
    }

    /// Maps an arbitrary stored interval back to the closest bucket, so a
    /// value set outside this UI (or Sparkle's 86400s default) still lands
    /// on a sensible picker selection instead of matching nothing.
    init(seconds: TimeInterval) {
        switch seconds {
        case ..<7200: self = .hourly
        case ..<172800: self = .daily
        default: self = .weekly
        }
    }
}

/// Mirrors Sparkle's `canCheckForUpdates` (it's false while a check or an
/// install is already running), so the button can disable itself.
private final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}
