import SwiftUI
import Sparkle

struct PreferencesView: View {
    let updater: SPUUpdater
    let onSetDefaultBrowser: () -> Void
    let onRestartOnboarding: () -> Void
    let onShowDebugChooser: () -> Void

    /// The shared settings object — rows below write straight into it,
    /// which is what keeps this window and the menu bar menu in sync.
    @ObservedObject private var settings = AppSettings.shared

    @State private var selectedTab: PreferencesTab = .general

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

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                GeneralPane(settings: settings, onRestartOnboarding: onRestartOnboarding)
                    .tabItem { Label("General", systemImage: "gearshape") }
                    .tag(PreferencesTab.general)

                BrowserPane(settings: settings, onSetDefaultBrowser: onSetDefaultBrowser)
                    .tabItem { Label("Browser", systemImage: "globe") }
                    .tag(PreferencesTab.browser)
                
                ApperancePane(settings: settings)
                    .tabItem { Label("Appearance", systemImage: "paintpalette") }
                    .tag(PreferencesTab.apperance)
                
                SecurityPane(settings: settings)
                    .tabItem { Label("Security", systemImage: "checkmark.shield") }
                    .tag(PreferencesTab.security)

                UpdatesPane(settings: settings, updater: updater)
                    .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
                    .tag(PreferencesTab.updates)

                AboutPane(settings: settings, onShowDebugChooser: onShowDebugChooser)
                    .tabItem { Label("About", systemImage: "info.circle") }
                    .tag(PreferencesTab.about)
            }

            Divider().opacity(0.15)

            HStack {
                Spacer()
                Button("Quit BrowserLink") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(14)
        }
        .tint(settings.tintColor)
        .frame(minWidth: 560, idealWidth: 560, minHeight: 540, idealHeight: 540)
        .onAppear {
            // Catches the case where the user changed the login-item state
            // from outside the app (System Settings → General → Login
            // Items) since this window was last built. Cheap to call and
            // keeps the toggle honest.
            settings.refreshLaunchAtLoginFromSystem()
        }
    }
}

private enum PreferencesTab: Hashable {
    case general
    case browser
    case apperance
    case security
    case updates
    case about
}

// MARK: - Reusable card + row building blocks

/// A rounded, grouped container with an optional small-caps header.
private struct SettingsCard<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.background.secondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }
}

/// One line inside a SettingsCard — a title, optional subtitle, and
/// trailing control. Separated with `RowDivider` by the caller.
private struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct RowDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 14)
            .opacity(0.5)
    }
}

private struct SwitchRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

/// Drop this on any not-yet-functional toggle — shows a disabled switch
/// plus a small "Coming Soon" capsule. No state or binding needed since
/// it's always off; swap to SwitchRow once the feature is actually wired up.
private struct ComingSoonRow: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
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
        }
    }
}

// MARK: - General Pane

private struct GeneralPane: View {
    @ObservedObject var settings: AppSettings
    let onRestartOnboarding: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsCard(title: "Startup") {
                    SwitchRow(title: "Launch at Login", isOn: $settings.launchAtLoginEnabled)
                }

                SettingsCard(title: "Chooser") {
                    SwitchRow(
                        title: "Play Sound When Chooser Appears",
                        isOn: $settings.playSoundOnChooserAppear
                    )

                    RowDivider()

                    SwitchRow(
                        title: "Show Site Icons in Chooser",
                        subtitle: "Fetched from Google's favicon service. Disable if you don't want data sent to Google.",
                        isOn: $settings.showFaviconsInChooser
                    )
                }
                
                SettingsCard(title: "Onboarding") {
                    Button("Restart onboarding") {
                        onRestartOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(14)

                Spacer()
            }
            .padding(24)
        }
    }
}

// MARK: - Browser Pane

private struct BrowserPane: View {
    @ObservedObject var settings: AppSettings
    let onSetDefaultBrowser: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsCard(title: "Default Browser") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("BrowserLink intercepts links opened anywhere on your Mac and lets you choose where they go — a quick, private preview or a real browser.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button("Set as Default Browser…", action: onSetDefaultBrowser)
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(14)
                }

                SettingsCard(title: "Behaviour") {
                    ComingSoonRow(
                        title: "Remember Per-Site Choices",
                        subtitle: "Skip the chooser next time for a site you've already picked a browser for."//,
                        //isOn: $settings.rememberPerSiteChoices
                    )

                    RowDivider()

                    SwitchRow(
                        title: "Reveal Downloads in Finder",
                        subtitle: "After a file finishes saving from Quick Preview.",
                        isOn: $settings.revealDownloadsInFinder
                    )
                    
                    RowDivider()
                    
                    SettingsRow(
                        title: "App mode",
                        subtitle: settings.appMode.explanation
                    ) {
                        Picker("", selection: $settings.appMode) {
                            ForEach(AppMode.allCases) { mode in
                                Label(mode.label, systemImage: mode.icon)
                                    .tag(mode)
                            }
                        }
                            .labelsHidden()
                            .frame(width: 250)
                    }
                    
                    
                }

                Spacer()
                
            } //VStack
            .padding(24)
        }//Scroll view
    } //View
}

// MARK: - Apperance Pane
private struct ApperancePane: View {
    @ObservedObject var settings: AppSettings
    
    private var colorBinding: Binding<Color> {
        Binding(
            get: { settings.resolvedInterfaceColour ?? .accentColor },
            set: { settings.interfaceColour = $0.toHex() ?? "" }
        )
    }
    
    @State private var browsers: [InstalledBrowser] = []
    private let browserRowHeight: CGFloat = 40
    
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
        ScrollView {
            VStack (alignment: .leading, spacing: 20) {
                
                SettingsCard(title: "Appearance") {
                    ColorPicker("Interface Colour", selection: colorBinding, supportsOpacity: false)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    
                    Divider().opacity(0.5).padding(.leading, 14)
                    
                    Button("Use System Colour") {
                        settings.interfaceColour = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    
                    Text("The interface colour will appear mostly everywhere around the UI. There may be a limited amount of instances where the system accent colour may be seen instead.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 8)
                }
                .padding(14)
                
                SettingsCard(title: "Browser display order") {
                    Text("Drag a browser up or down to change its order. Use the switch to hide it from the chooser.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 4)

                    List {
                        ForEach(browsers) { browser in
                            HStack(spacing: 10) {
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                Image(nsImage: browser.icon)
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                Text(browser.name)
                                    .font(.system(size: 13))
                                Spacer()
                                Toggle("", isOn: visibleBinding(for: browser))
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                                    .disabled(isLastVisible(browser))
                            }
                            .frame(height: browserRowHeight)
                            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                        }
                        .onMove { indices, newOffset in
                            browsers.move(fromOffsets: indices, toOffset: newOffset)
                            AppSettings.shared.browserOrder = browsers.map(\.id)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .environment(\.defaultMinListRowHeight, browserRowHeight)
                    .frame(height: CGFloat(browsers.count) * browserRowHeight + 8)
                    .onAppear {
                        browsers = BrowserDetector.ordered(
                            BrowserDetector.installedBrowsers(),
                            by: AppSettings.shared.browserOrder
                        )
                    }
                    
                    Button("Reset to Default Order") {
                        AppSettings.shared.browserOrder = []
                        browsers = BrowserDetector.ordered(
                            BrowserDetector.installedBrowsers(),
                            by: []
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }
                .opacity(settings.appMode == .preview ? 0.4 : 1)
                .disabled(settings.appMode == .preview)

                Text(
                    settings.appMode == .preview
                    ? "The browser list is switched off because App mode is set to \"\(AppMode.preview.label)\". You can change this in the Browser tab."
                    : "To hide every browser from the chooser, set App mode to \"\(AppMode.preview.label)\" in the Browser tab. Otherwise, at least one browser always stays visible."
                )
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
                
                Spacer()
                
                
            }
            .padding(24)
        }
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
            HStack(spacing: 6) {
                Image(systemName: level.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(level.color)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Security Pane

private struct SecurityPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                SettingsCard(title: "Link Warnings") {
                    SwitchRow(
                        title: "Warn About Suspicious Links",
                        subtitle: "Shows a warning when a link trips any check below. Serious and warning-level ones ask you to confirm first.",
                        isOn: $settings.warnAboutSuspiciousLinks
                    )
                }

                // MARK: Serious
                VStack(alignment: .leading, spacing: 6) {
                    SeverityHeader(
                        level: .serious,
                        title: "Serious",
                        detail: "Almost certainly an attempt to trick or harm you. Links using javascript:, data: or file: are always flagged."
                    )
                    SettingsCard {
                        SwitchRow(
                            title: "Fake Brand Look-alikes",
                            subtitle: "Flags domains that imitate well-known brands, like paypal-login.xyz.",
                            isOn: $settings.flagBrandLookalikes
                        )
                        .dimmed(unless: settings.warnAboutSuspiciousLinks)

                        RowDivider()

                        SwitchRow(
                            title: "Fake \"@\" Usernames",
                            subtitle: "Flags links like paypal.com@evil-site.xyz, where the real destination is hidden after the @.",
                            isOn: $settings.flagAtSignTrick
                        )
                        .dimmed(unless: settings.warnAboutSuspiciousLinks)

                        RowDivider()

                        SwitchRow(
                            title: "Pause Before Confirming",
                            subtitle: "Waits 3 seconds before you can click \"I understand the risk\" on a serious warning, to give you time to reconsider.",
                            isOn: $settings.delaySevereConfirm
                        )
                        .dimmed(unless: settings.warnAboutSuspiciousLinks)
                    }
                }

                // MARK: Warning
                VStack(alignment: .leading, spacing: 6) {
                    SeverityHeader(
                        level: .warning,
                        title: "Warning",
                        detail: "Suspicious, though sometimes innocent. Asks you to confirm."
                    )
                    SettingsCard {
                        SwitchRow(
                            title: "Raw IP Address Links",
                            subtitle: "Links that use numbers like 192.168.0.1 instead of a website name.",
                            isOn: $settings.flagRawIPLinks
                        )
                        .dimmed(unless: settings.warnAboutSuspiciousLinks)

                        RowDivider()

                        SwitchRow(
                            title: "Mixed-Script (Homograph) Domains",
                            subtitle: "Flags domains mixing alphabets, e.g. Latin + Cyrillic look-alikes.",
                            isOn: $settings.flagMixedScriptDomains
                        )
                        .dimmed(unless: settings.warnAboutSuspiciousLinks)

                        RowDivider()

                        SwitchRow(
                            title: "Punycode Domains",
                            subtitle: "Domains starting with xn--, which can disguise look-alike characters.",
                            isOn: $settings.flagPunycodeDomains
                        )
                        .dimmed(unless: settings.warnAboutSuspiciousLinks)

                        RowDivider()

                        SwitchRow(
                            title: "Program & Installer Downloads",
                            subtitle: "Flags links that end in .exe, .dmg, .pkg and similar.",
                            isOn: $settings.flagDownloadLinks
                        )
                        .dimmed(unless: settings.warnAboutSuspiciousLinks)
                    }
                }

                // MARK: Advisory
                VStack(alignment: .leading, spacing: 6) {
                    SeverityHeader(
                        level: .advisory,
                        title: "Advisory",
                        detail: "Worth knowing about. Shown as a small notice and never blocks the buttons."
                    )
                    SettingsCard {
                        SwitchRow(
                            title: "Unusually Deep Subdomains",
                            subtitle: "Domains with more than 5 subdomains contained within.",
                            isOn: $settings.flagDeepSubdomains
                        )
                        .dimmed(unless: settings.warnAboutSuspiciousLinks)

                        RowDivider()

                        SwitchRow(
                            title: "Unencrypted (http) Links",
                            subtitle: "Flags links that use http:// instead of https://. Some older sites still use http, so you may switch this off.",
                            isOn: $settings.flagInsecureHTTP
                        )
                        .dimmed(unless: settings.warnAboutSuspiciousLinks)

                        RowDivider()

                        SwitchRow(
                            title: "Shortened Links",
                            subtitle: "Shows a gentle notice for links from services like bit.ly that hide where they lead.",
                            isOn: $settings.flagURLShorteners
                        )
                        .dimmed(unless: settings.warnAboutSuspiciousLinks)
                    }
                }

                Spacer()
            }
            .padding(24)
        }
    }
}

// MARK: - Updates Pane

private struct UpdatesPane: View {
    @ObservedObject var settings: AppSettings
    let updater: SPUUpdater

    // Local mirrors of the updater's own persisted state. Per Sparkle's own
    // guidance, these should only be WRITTEN when the user changes them —
    // never read back from the updater on every render — so each is seeded
    // once here and pushed back to `updater` in onChange.
    @State private var automaticallyChecksForUpdates: Bool
    @State private var automaticallyDownloadsUpdates: Bool
    @State private var checkFrequency: CheckFrequency
    @State private var selectedUpdateChannel: UpdateChannel

    init(settings: AppSettings, updater: SPUUpdater) {
        self.settings = settings
        self.updater = updater
        _automaticallyChecksForUpdates = State(initialValue: updater.automaticallyChecksForUpdates)
        _automaticallyDownloadsUpdates = State(initialValue: updater.automaticallyDownloadsUpdates)
        _checkFrequency = State(initialValue: CheckFrequency(seconds: updater.updateCheckInterval))
        _selectedUpdateChannel = State(initialValue: settings.updateChannel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsCard(title: "Automatic Updates") {
                    SettingsRow(title: "Check for Updates automatically") {
                        Toggle("", isOn: $automaticallyChecksForUpdates)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                                updater.automaticallyChecksForUpdates = newValue
                                // Sparkle's own UI convention: downloading
                                // automatically only makes sense if checking
                                // automatically is also on.
                                if !newValue && automaticallyDownloadsUpdates {
                                    automaticallyDownloadsUpdates = false
                                    updater.automaticallyDownloadsUpdates = false
                                }
                            }
                    }
                    
                    RowDivider()
                    
                    SettingsRow(title: "Frequency") {
                        Picker("", selection: $checkFrequency) {
                            ForEach(CheckFrequency.allCases) { frequency in
                                Text(frequency.label).tag(frequency)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 120)
                        .disabled(!automaticallyChecksForUpdates)
                        .onChange(of: checkFrequency) { _, newValue in
                            updater.updateCheckInterval = newValue.seconds
                        }
                    }
                    .opacity(automaticallyChecksForUpdates ? 1 : 0.4)
                    
                    RowDivider()
                    
                    SettingsRow(title: "Download Automatically") {
                        Toggle("", isOn: $automaticallyDownloadsUpdates)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(!automaticallyChecksForUpdates)
                            .onChange(of: automaticallyDownloadsUpdates) { _, newValue in
                                updater.automaticallyDownloadsUpdates = newValue
                            }
                    }
                    .opacity(automaticallyChecksForUpdates ? 1 : 0.4)
                    
                    RowDivider()
                    
                    SettingsRow(
                        title: "Update Channel",
                        subtitle: selectedUpdateChannel.explanation
                    ) {
                        Picker("", selection: $selectedUpdateChannel) {
                            ForEach(UpdateChannel.allCases) { channel in
                                Text(channel.label).tag(channel)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 160)
                        .onChange(of: selectedUpdateChannel) { _, newValue in
                            settings.updateChannel = newValue
                        }
                    }
                }

                SettingsCard(title: "Privacy") {
                    ComingSoonRow(
                        title: "Share Anonymous System Info",
                        subtitle: "Would help decide which macOS versions and Mac models to keep supporting. No personal data included. You can see what is being sent by using the button below."
                    )
                }

                SettingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Button("Check for Updates…") {
                            updater.checkForUpdates()
                        }
                        .buttonStyle(.bordered)

                        if let lastCheck = updater.lastUpdateCheckDate {
                            Text("Last checked \(lastCheck.formatted(.relative(presentation: .named)))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Never checked for updates")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                }

                Spacer()
            }
            .padding(24)
        }
    }
}

// MARK: - About Pane

private struct AboutPane: View {
    
    @ObservedObject var settings: AppSettings
    let onShowDebugChooser: () -> Void
    
    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "link.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(settings.tintColor.gradient)

            VStack(spacing: 4) {
                Text("BrowserLink")
                    .font(.system(size: 19, weight: .semibold))
                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Text("Choose where your links go — a quick, private preview or a real browser, every time.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300)

            Spacer()

            VStack(spacing: 3) {
                Text("Update checking powered by Sparkle.")
                Text("BrowserLink, \(currentYear). This project is licensed under Apache 2.0. The full source code is available on Github.")
                Text("Visit https://github.com/jacksonvil-s/browserlink for more info.")
                Text("Thank you for using the app. We appreciate all the support you can give. Please star the repo if you find this app useful.")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            .padding(.bottom, 8)
            
            Spacer()
            
            Button("Debug") {
                onShowDebugChooser()
            }
                
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

