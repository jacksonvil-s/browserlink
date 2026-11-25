import AppKit
import SwiftUI
import Sparkle
import Combine
import UserNotifications
import os

/// The real brain of the app. Because this is a background agent (LSUIElement = true,
/// set in Info.plist), there's no Dock icon and no default window — everything is
/// driven from here.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation, SPUUpdaterDelegate, SPUStandardUserDriverDelegate, UNUserNotificationCenterDelegate {
    
    /// The persistent menu bar item — our only always-visible presence.
    private var statusItem: NSStatusItem?
    
    /// The floating chooser panel. Recreated each time a link comes in,
    /// released once the user makes a choice (or dismisses it).
    private var chooserPanel: NSPanel?
    
    /// Every currently-open preview window, keyed by a UUID so multiple
    /// previews can be open at once without stomping on each other.
    private var previewWindows: [UUID: NSWindow] = [:]
    
    /// One "window will close" observer per preview window. Closing a preview
    /// by ANY route (toolbar button, red close button) must drop the window
    /// from `previewWindows`; otherwise it, its web view and its in-memory
    /// cookies/cache would stay alive forever.
    private var previewCloseObservers: [UUID: NSObjectProtocol] = [:]
    
    /// Sparkle's standard updater controller — handles checking the appcast
    /// feed (see Info.plist SUFeedURL), downloading, verifying the EdDSA
    /// signature, and installing updates. `startingUpdater: true` means it
    /// begins its periodic background check automatically at launch.
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: self
    )
    
    /// Links whose address LinkCleaner changed, keyed by the cleaned URL that
    /// went into the queue, so the chooser can explain it and offer the original.
    private var cleanedLinks: [URL: LinkCleaner.Cleaned] = [:]
    
    /// The first menu item, whose title/state tracks whether we're the default browser.
    private var defaultBrowserMenuItem: NSMenuItem?
    
    private var pauseRulesMenuItem: NSMenuItem?
    private var recentLinksMenuItem: NSMenuItem?
    private let toast = ToastPresenter()
    
    /// The Preferences window. Built once, shown/hidden as needed rather
    /// than recreated each time (avoids losing toggle state / flicker).
    private var preferencesWindow: NSWindow?
    
    /// The first-run onboarding window. Only ever created once per launch —
    /// and only at all if `AppSettings.shared.hasCompletedOnboarding` is
    /// still false — then released for good once the user finishes it.
    private var onboardingWindow: NSWindow?
    
    /// Holds the Combine subscriptions that keep the status bar menu in
    /// sync with AppSettings — cancelled automatically on dealloc.
    private var cancellables = Set<AnyCancellable>()
    
    /// True while Sparkle has found an update the user hasn't looked at yet.
    private var updateIsAvailable = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Must be set before launch finishes so a click on an update
        // notification that launched/woke the app is delivered.
        UNUserNotificationCenter.current().delegate = self
        
        // Sparkle shows its own "check for updates automatically?" prompt when
        // the user has never made that choice. BrowserLink asks during onboarding
        // instead. People who finished onboarding before that question existed
        // get the default (on) here, BEFORE Sparkle starts, so they're not
        // prompted. (First-time users are asked in onboarding and never reach this.)
        if AppSettings.shared.hasCompletedOnboarding,
           UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") == nil {
            UserDefaults.standard.set(true, forKey: "SUEnableAutomaticChecks")
        }
        
        observeSettings()
        
        if AppSettings.shared.hasCompletedOnboarding {
            completeLaunchSetup()
        } else {
            presentOnboarding()
        }
    }
    
    /// The normal launch path: status item + menu. Split out
    /// from `applicationDidFinishLaunching` so onboarding's completion
    /// handler can trigger it too, once the user finishes the first-run flow.
    private func completeLaunchSetup() {
        setupStatusItem()
        rebuildMenu()
        // Scan for installed browsers a few seconds from now, once launch
        // work has settled, so the first chooser appears instantly.
        BrowserDetector.prewarm()
        resumePendingUpdateReminder()
    }
    
    /// Subscribes to the shared settings so that ANY change — whether it
    /// came from the menu bar menu, the Preferences window, or anywhere
    /// else — automatically rebuilds the menu. This is what replaces the old scattered manual
    /// `rebuildMenu()` calls and fixes the menu/window sync bug: there is
    /// now exactly one place that reacts to a change, no matter its source.
    private func observeSettings() {
        AppSettings.shared.$launchAtLoginEnabled
            .dropFirst() // ignore the initial value published on subscribe
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)
        
        // Preferences has buttons for the menu-bar actions (the menu is
        // unreachable while the status icon is hidden) and asks us via these.
        NotificationCenter.default.publisher(for: .openClipboardLinkRequested)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.openClipboardLink() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .openRecentLinkRequested)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                if let url = note.object as? URL { self?.presentChooser(for: url) }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Onboarding
    
    /// Builds and shows the onboarding window — called either once at
    /// first launch (from `applicationDidFinishLaunching`) or on demand
    /// (from `restartOnboarding()`, wired to Preferences → "Restart
    /// onboarding"). If a window is already open, just brings it forward
    /// instead of creating a duplicate.
    private func presentOnboarding() {
        if let existing = onboardingWindow {
            NSApp.activate()
            existing.makeKeyAndOrderFront(nil)
            return
        }
        
        let view = OnboardingView(
            onFinish: { [weak self] in
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
                AppSettings.shared.hasCompletedOnboarding = true
                self?.completeLaunchSetup()
            }, promptSetDefaultBrowser: { [weak self] in
                self?.promptSetDefaultBrowser()
            },
            updater: updaterController.updater
        )
        let hosting = NSHostingController(rootView: view)
        
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let windowWidth = min(max(screenFrame.width * 0.4, 640), 760)
        let windowHeight = min(max(screenFrame.height * 0.62, 620), 760)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.fullSizeContentView, .miniaturizable, .titled],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        
        // Same fix as ChooserPanelView/PreviewWindow: NSHostingController
        // sizes itself to its SwiftUI content's ideal size rather than
        // honoring contentRect, which is what made this window render at
        // OnboardingView's old hardcoded 520x460 regardless of what was
        // requested here. Forcing the hosting view's frame (and setting
        // content size explicitly) makes the window actually match.
        hosting.view.frame = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)
        window.setContentSize(NSSize(width: windowWidth, height: windowHeight))
        
        window.title = "Welcome to BrowserLink"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.center()
        onboardingWindow = window
        
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
    
    /// Re-opens onboarding on demand without relaunching the app. Resets
    /// `hasCompletedOnboarding` first, so if the user closes the window via
    /// the close button mid-flow (rather than finishing it), it'll
    /// correctly show again on next launch too.
    func restartOnboarding() {
        onboardingWindow?.close()
        onboardingWindow = nil
        AppSettings.shared.hasCompletedOnboarding = false
        presentOnboarding()
    }
    
    // MARK: - Menu Bar
    
    /// Creates the persistent status bar item ONCE. This should never be
    /// called again after launch — recreating it is what caused the item to
    /// intermittently vanish after toggling Launch at Login, since the old
    /// NSStatusItem would get silently released while still mid-click.
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            // SF Symbol as the glyph — a simple "app window with link" style icon.
            // Swap for a custom asset later if you want a bespoke mark.
            button.image = NSImage(
                systemSymbolName: "link.circle.fill",
                accessibilityDescription: "BrowserLink"
            )
        }
        statusItem = item
    }
    
    /// Builds (or rebuilds) just the NSMenu and assigns it to the existing
    /// status item. Safe to call repeatedly — e.g. whenever AppSettings
    /// changes, to refresh the checkmark state — since it never touches the
    /// status item itself.
    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        let defaultItem = NSMenuItem(
            title: "Set BrowserLink as Default Browser…",
            action: #selector(promptSetDefaultBrowser),
            keyEquivalent: ""
        )
        defaultBrowserMenuItem = defaultItem
        menu.addItem(defaultItem)
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(
            title: "Open Link from Clipboard",
            action: #selector(openClipboardLink),
            keyEquivalent: ""
        ))

        let recentItem = NSMenuItem(title: "Recent Links", action: nil, keyEquivalent: "")
        recentItem.submenu = NSMenu()
        recentLinksMenuItem = recentItem
        menu.addItem(recentItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.state = AppSettings.shared.launchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)
        
        let pauseItem = NSMenuItem(
            title: "Pause Remembered Sites",
            action: #selector(toggleSiteRulesPaused),
            keyEquivalent: ""
        )
        pauseRulesMenuItem = pauseItem
        menu.addItem(pauseItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let updateItem = NSMenuItem(
            title: updateReadyToInstall
                ? "Update Ready: Restart to Install…"
                : (updateIsAvailable ? "Update Available: Install…" : "Check for Updates…"),
            action: #selector(checkForUpdatesFromMenu),
            keyEquivalent: ""
        )
        menu.addItem(updateItem)
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(
            NSMenuItem(
                title: "Preferences…",
                action: #selector(openPreferences),
                keyEquivalent: ","
            )
        )
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit BrowserLink",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        
        // Only wire our own AppDelegate methods to `self`. The Quit item uses
        // NSApplication's own terminate(_:), so it must keep targeting nil
        // (which lets AppKit route it to the app itself / first responder
        // chain) rather than being forced onto AppDelegate, where that
        // selector doesn't exist and would silently no-op. The "Check for
        // Updates…" item already has its target set explicitly to
        // updaterController, so it's skipped here too.
        for menuItem in menu.items {
            if menuItem.action == #selector(NSApplication.terminate(_:)) {
                menuItem.target = nil
            } else if menuItem.target == nil {
                menuItem.target = self
            }
        }
        refreshDefaultBrowserMenuItem()
        statusItem?.menu = menu
    }
    
    // MARK: NSMenuDelegate
    
    /// Called just before the menu opens, so the default-browser line is
    /// always current even though the menu itself is only rebuilt on changes.
    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshDefaultBrowserMenuItem()
        refreshRecentLinksMenu()
        let settings = AppSettings.shared
        pauseRulesMenuItem?.state = settings.pauseSiteRules ? .on : .off
        // Nothing to pause if the feature is off or no site has been saved.
        pauseRulesMenuItem?.isHidden = !settings.rememberPerSiteChoices || settings.siteRules.isEmpty
    }
    
    // MARK: Clipboard and recent links

    /// Reads the clipboard only when the user clicks the menu item.
    @objc private func openClipboardLink() {
        let raw = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard raw.count < 4096, !raw.contains(where: \.isWhitespace),
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host != nil else {
            let alert = NSAlert()
            alert.messageText = "No Web Link on the Clipboard"
            alert.informativeText = "Copy a link that starts with http:// or https://, then try again."
            NSApp.activate()
            alert.runModal()
            return
        }
        application(NSApp, open: [url])   // same path as a real incoming link
    }

    /// Rebuilt every time the menu opens, so it's always current.
    private func refreshRecentLinksMenu() {
        guard let item = recentLinksMenuItem, let submenu = item.submenu else { return }

        let enabled = AppSettings.shared.keepRecentLinks
        item.isHidden = !enabled
        guard enabled else { return }

        let links = RecentLinks.shared.urls
        submenu.removeAllItems()
        if links.isEmpty {
            submenu.addItem(NSMenuItem(title: "No Recent Links", action: nil, keyEquivalent: ""))
            return
        }
        for url in links {
            let entry = NSMenuItem(title: RecentLinks.title(for: url), action: #selector(openRecentLink(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = url
            submenu.addItem(entry)
        }
        submenu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear Recent Links", action: #selector(clearRecentLinks), keyEquivalent: "")
        clear.target = self
        submenu.addItem(clear)
    }

    @objc private func openRecentLink(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        presentChooser(for: url)   // straight to the chooser; saved site rules are skipped
    }

    @objc private func clearRecentLinks() {
        RecentLinks.shared.clear()
    }

    @objc private func toggleSiteRulesPaused() {
        AppSettings.shared.pauseSiteRules.toggle()
    }
    
    private func refreshDefaultBrowserMenuItem() {
        guard let item = defaultBrowserMenuItem else { return }
        if DefaultBrowserHelper.isDefault {
            item.title = "BrowserLink Is Your Default Browser"
            item.state = .on
            item.action = nil // nothing to do, so it greys out
        } else {
            item.title = "Set BrowserLink as Default Browser…"
            item.state = .off
            item.action = #selector(promptSetDefaultBrowser)
        }
    }
    
    @objc private func toggleLaunchAtLogin() {
        // Just flip the shared setting — the observeSettings() subscription
        // picks this up and calls rebuildMenu() automatically, and if the
        // Preferences window is open its toggle updates too, instantly.
        AppSettings.shared.launchAtLoginEnabled.toggle()
    }
    
    @objc private func promptSetDefaultBrowser() {
        DefaultBrowserHelper.promptUserToSetDefault()
    }
    
    /// True while a Preferences window creation is in progress — guards
    /// against re-entrant calls piling up (e.g. from rapid shortcut presses)
    /// stacking multiple window/hosting-controller creations on top of each
    /// other, which is what caused the app to hang.
    private var isCreatingPreferencesWindow = false
    
    @objc private func openPreferences() {
        // If the window already exists, just bring it forward — cheap, safe
        // to call as often as needed.
        if let existing = preferencesWindow {
            NSApp.activate()
            existing.makeKeyAndOrderFront(nil)
            return
        }
        
        // Prevent re-entrant creation if somehow called again before the
        // first creation finishes.
        guard !isCreatingPreferencesWindow else { return }
        isCreatingPreferencesWindow = true
        defer { isCreatingPreferencesWindow = false }
        
        let view = PreferencesView(
            updater: updaterController.updater,
            onSetDefaultBrowser: { [weak self] in
                self?.promptSetDefaultBrowser()
            },
            onRestartOnboarding: { [weak self] in
                self?.restartOnboarding()
            },
            onShowDebugChooser: { [weak self] in
                self?.promptForDebugURL()
            }
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // The sidebar layout is resizable, so the window (not the SwiftUI
        // content) decides its size.
        hosting.sizingOptions = []
        window.contentViewController = hosting
        
        hosting.view.frame = NSRect(x: 0, y: 0, width: 980, height: 720)
        window.setContentSize(NSSize(width: 980, height: 720))
        // The smallest the window can be dragged to. contentMinSize limits the
        // content area itself, so the sidebar and panes always have room.
        window.contentMinSize = NSSize(width: 860, height: 620)
        window.minSize = NSSize(width: 860, height: 620)
        window.toolbarStyle = .unified
        
        window.title = "BrowserLink Preferences"
        window.isReleasedWhenClosed = false
        window.center()
        preferencesWindow = window
        
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
    
    // MARK: - URL Interception
    //
    // This is the method macOS calls when the app is registered as a URL handler
    // and a link is opened anywhere in the system (Mail, Slack, Messages, Safari's
    // "open in default browser," etc). This fires via the Info.plist CFBundleURLTypes
    // registration — see Info.plist for the http/https scheme declarations.
    
    /// Links waiting for their turn, with built-in protection against spam.
    private let linkQueue = LinkQueue()
    
    /// The link the chooser is showing right now (nil when none).
    private var currentChooserURL: URL?
    
    func application(_ application: NSApplication, open urls: [URL]) {
        // Holding ⌥ as the link arrives means "show me the chooser this time".
        let optionHeld = NSEvent.modifierFlags.contains(.option)

        for original in urls {
            let cleaned = LinkCleaner.clean(
                original,
                stripTracking: AppSettings.shared.stripTrackingParameters,
                unwrapRedirects: AppSettings.shared.unwrapRedirectLinks
            )
            RecentLinks.shared.record(cleaned.url)
            if !optionHeld, openWithRememberedBrowser(cleaned.url) { continue }
            if cleaned.note != nil {
                cleanedLinks[cleaned.url] = cleaned
            }
            linkQueue.add(cleaned.url, currentlyShowing: currentChooserURL)
        }
        
        // Only start right away if no chooser is already on screen.
        if chooserPanel == nil {
            showNextQueuedURL()
        }
    }
    
    /// If a saved rule covers this link, opens it straight away and shows a
    /// toast. Returns false (so the chooser appears) whenever a rule shouldn't apply.
    private func openWithRememberedBrowser(_ url: URL) -> Bool {
        let settings = AppSettings.shared
        guard settings.rememberPerSiteChoices,
              !settings.pauseSiteRules,
              settings.appMode != .preview,
              let site = SiteKey.key(for: url),
              let browserID = settings.siteRules[site] else { return false }

        // Anything suspicious always gets the chooser and its warnings.
        guard URLSafetyChecker.check(url).reasons.isEmpty else { return false }

        // An app spamming links to a remembered site would otherwise open
        // unlimited tabs (the queue's spam protection only covers the
        // chooser). Past the limit, links fall through to the chooser path.
        guard allowRememberedOpen() else { return false }
        
        // "Always use Quick Preview" rule.
        if browserID == SiteKey.previewRule {
            guard settings.appMode != .chooser else { return false }   // preview is switched off
            // This link can't be previewed (e.g. plain http), so ask instead.
            guard LinkSupport.previewUnavailableReason(for: url) == nil else { return false }
            openPreviewWindow(for: url)
            toast.show(
                message: "Opened \(site) in Quick Preview",
                icon: NSImage(systemSymbolName: "eye.fill", accessibilityDescription: nil),
                actionTitle: "Change",
                screen: targetScreen()
            ) { [weak self] in
                self?.presentChooser(for: url)
            }
            return true
        }

        guard let browser = BrowserDetector.installedBrowsers().first(where: { $0.id == browserID }) else {
            settings.siteRules.removeValue(forKey: site)   // that browser was uninstalled
            return false
        }

        BrowserDetector.open(url: url, in: browser)
        toast.show(
            message: "Opened \(site) in \(browser.name)",
            icon: browser.icon,
            actionTitle: "Change",
            screen: targetScreen()
        ) { [weak self] in
            self?.presentChooser(for: url)
        }
        return true
    }
    
    /// When remembered-site links were last opened without the chooser.
    private var rememberedOpenTimes: [Date] = []

    /// At most 5 automatic opens per 5 seconds.
    private func allowRememberedOpen() -> Bool {
        let now = Date()
        rememberedOpenTimes.removeAll { now.timeIntervalSince($0) > 5 }
        guard rememberedOpenTimes.count < 5 else { return false }
        rememberedOpenTimes.append(now)
        return true
    }

    private func showNextQueuedURL() {
        guard let next = linkQueue.next() else { return }
        presentChooser(for: next)
    }
    
    /// Closes the chooser, then shows the next waiting link (if any).
    private func closeChooser() {
        chooserPanel?.close()
        chooserPanel = nil
        currentChooserURL = nil
        
        guard !linkQueue.waiting.isEmpty else {
            linkQueue.finishBatch()
            cleanedLinks.removeAll()
            return
        }
        
        // Wait a moment so the old window finishes closing first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self, self.chooserPanel == nil else { return }
            self.showNextQueuedURL()
        }
    }
    
    /// "Dismiss all": closes the chooser and throws away every waiting link.
    private func dismissAllLinks() {
        linkQueue.clear()
        cleanedLinks.removeAll()
        closeChooser()
    }
    
    
    
    
    /// Called when the user launches the app again while it's already
    /// running (Spotlight, Launchpad, Finder). This is the way back into
    /// Preferences if the menu bar icon is hidden: macOS lets people hide it
    /// from System Settings → Menu Bar, and BrowserLink has no icon-hiding
    /// option of its own. Just search for "BrowserLink" in Spotlight.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openPreferences()
        return true
    }
    
    // MARK: - Chooser Panel
    
    /// The display the chooser should appear on, per the "Show chooser on" setting.
    private func targetScreen() -> NSScreen? {
        switch AppSettings.shared.chooserScreen {
        case .underMouse:
            let mouse = NSEvent.mouseLocation
            return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        case .mainScreen:
            return NSScreen.main
        }
    }
    
    private func presentChooser(for url: URL) {
        // If a chooser is already open (rapid double-click, etc.), close it first
        // rather than stacking panels.
        chooserPanel?.close()
        currentChooserURL = url
        
        let installedBrowsers = BrowserDetector.visibleBrowsers()
        
        // If LinkCleaner changed this link, tell the user and let them undo it.
        // A local .html file is harmless; skip the "dangerous file: link" warning.
        let safetyResult = LinkSupport.isLocalHTMLFile(url) ? URLSafetyResult.safe : URLSafetyChecker.check(url)
        let cleaning = cleanedLinks.removeValue(forKey: url)
        var useOriginal: (() -> Void)? = nil
        if let cleaning {
            useOriginal = { [weak self] in
                // The original isn't in `cleanedLinks`, so it shows as-is.
                self?.presentChooser(for: cleaning.original)
            }
        }
        
        // Per-site memory: which site this is, and the browser already saved for it.
        let site = AppSettings.shared.rememberPerSiteChoices ? SiteKey.key(for: url) : nil
        let rememberedName: String? = site
            .flatMap { AppSettings.shared.siteRules[$0] }
            .flatMap { id in
                id == SiteKey.previewRule
                    ? "Quick Preview"
                    : BrowserDetector.installedBrowsers().first { $0.id == id }?.name
            }
        
        let contentView = ChooserPanelView(
            url: url,
            browsers: installedBrowsers,
            onPreview: { [weak self] in
                self?.closeChooser()
                self?.openPreviewWindow(for: url)
            },
            onOpenIn: { [weak self] browser in
                self?.closeChooser()
                BrowserDetector.open(url: url, in: browser)
            },
            onOpenPreferences: { [weak self] in
                self?.closeChooser()
                self?.openPreferences()
            },
            onDismiss: { [weak self] in
                self?.closeChooser()
            },
            linkQueue: linkQueue,
            onDismissAll: { [weak self] in
                self?.dismissAllLinks()
            },
            cleaningNote: cleaning?.note,
            onUseOriginal: useOriginal,
            safetyResult: safetyResult,
            siteKey: site,
            rememberedName: rememberedName,
            onRememberSite: { ruleID in
                if let site { AppSettings.shared.siteRules[site] = ruleID }
            },
            onForgetSite: {
                if let site { AppSettings.shared.siteRules.removeValue(forKey: site) }
            },
            onPreferredHeight: { [weak self] height in
                self?.resizeChooser(toContentHeight: height)
            }
        )
        
        let hosting = NSHostingController(rootView: contentView)
        hosting.sizingOptions = []
        
        // Scale panel size relative to the screen it'll appear on, rather than
        // a fixed pixel value — this keeps it proportionally sized whether
        // you're on a 13" laptop or a 32" external display.
        let screen = targetScreen()
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // The width is fixed; the height is only a starting guess. The view
        // reports the height it really needs and resizeChooser(…) applies it.
        // Width comes from the chosen size (Small…Very Large), never wider
        // than the screen. Text and icons keep their normal size.
        let panelWidth = min(AppSettings.shared.chooserSize.width, screenFrame.width * 0.95)
        let panelHeight: CGFloat = max(380, screenFrame.height * AppSettings.shared.chooserSize.minHeightFraction)
        
        // ChooserPanel (see ChooserPanelView.swift) is a non-activating panel
        // that can still take keyboard focus.
        let panel = ChooserPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        
        // CRITICAL FIX: NSHostingController can size itself to its SwiftUI
        // content's ideal/fitting size rather than honoring the panel's frame,
        // which is why the panel was rendering as a tiny box regardless of the
        // contentRect above. Explicitly forcing the hosting view's frame (and
        // disabling its autoresizing translation) makes it actually fill the
        // panel we just sized.
        hosting.view.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        panel.setContentSize(NSSize(width: panelWidth, height: panelHeight))
        
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        // .fullScreenAuxiliary is what lets the chooser appear on top of a
        // full-screen app instead of on some other Space; .canJoinAllSpaces
        // keeps it on whichever Space is current.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        
        // Spotlight-style placement: horizontally centred, with the TOP edge
        // fixed near the top of the screen so the panel grows downward as its
        // content changes.
        if let screen = screen {
            let visible = screen.visibleFrame
            chooserTopY = visible.maxY - visible.height * 0.20
            let x = visible.midX - panel.frame.width / 2
            panel.setFrameOrigin(NSPoint(x: x, y: chooserTopY - panel.frame.height))
        } else {
            chooserTopY = panel.frame.maxY
        }
        
        chooserPanel = panel
        chooserPreferredHeight = nil
        chooserAnimatingIn = true
        
        // Fade in while rising slightly. With Reduce Motion on, skip the rise
        // and just fade in quickly.
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = 0
        
        // The first panel has to build its SwiftUI view and window surface,
        // which can swallow an animation started in the same run-loop pass.
        // So lay out now, show the (still transparent) panel, and start the
        // animation on the next pass.
        hosting.view.layoutSubtreeIfNeeded()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.displayIfNeeded()
        // Rescan in the background of the open animation, so a browser
        // installed since the last scan appears on the next link.
        BrowserDetector.refreshSoon()
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // The view usually reported its real height during layout above;
            // animate to THAT size so the panel never opens at a wrong one.
            let height = self.chooserPreferredHeight ?? panel.frame.height
            let finalFrame = NSRect(
                x: panel.frame.minX,
                y: self.chooserTopY - height,
                width: panel.frame.width,
                height: height
            )
            var startFrame = finalFrame
            if !reduceMotion { startFrame.origin.y -= 28 }
            panel.setFrame(startFrame, display: false)
            
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = reduceMotion ? 0.15 : 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                panel.animator().alphaValue = 1
                panel.animator().setFrame(finalFrame, display: true)
            }, completionHandler: { [weak self] in
                guard let self, self.chooserPanel === panel else { return }
                self.chooserAnimatingIn = false
                // Catch up with any size change that arrived mid-animation.
                self.applyChooserHeight(animated: false)
            })
        }
    }
    
    // MARK: - Chooser sizing
    
    /// The Y of the chooser's top edge; the panel grows and shrinks downward from it.
    private var chooserTopY: CGFloat = 0
    /// The latest height the chooser's content asked for (already clamped).
    private var chooserPreferredHeight: CGFloat?
    /// True while the open animation runs; size changes wait until it ends.
    private var chooserAnimatingIn = false
    
    /// Called by the chooser view whenever its content height changes
    /// (e.g. when a warning is confirmed and its banner disappears).
    private func resizeChooser(toContentHeight height: CGFloat) {
        guard let panel = chooserPanel else { return }
        let visible = (panel.screen ?? targetScreen())?.visibleFrame
        let size = AppSettings.shared.chooserSize
        let screenHeight = visible?.height ?? 900
        let maxHeight = screenHeight * size.maxHeightFraction
        let minHeight = max(200, screenHeight * size.minHeightFraction)
        chooserPreferredHeight = min(max(height, minHeight), maxHeight)
        if !chooserAnimatingIn {
            applyChooserHeight(animated: true)
        }
    }
    
    private func applyChooserHeight(animated: Bool) {
        guard let panel = chooserPanel, let height = chooserPreferredHeight else { return }
        let frame = NSRect(
            x: panel.frame.minX,
            y: chooserTopY - height,
            width: panel.frame.width,
            height: height
        )
        guard abs(panel.frame.height - height) > 1 || abs(panel.frame.minY - frame.minY) > 1 else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(frame, display: true, animate: animated && !reduceMotion)
    }
    
    
    /// Debug helper: asks for any URL and sends it through the real chooser.
    private func promptForDebugURL() {
        let alert = NSAlert()
        alert.messageText = "Open a Test Link"
        alert.informativeText = "Enter any URL. It goes through the normal chooser, cleaning and safety checks."
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "https://example.com"
        field.stringValue = UserDefaults.standard.string(forKey: "debugLastURL") ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        
        // A sheet on the Settings window instead of runModal(): runModal blocks
        // the main thread in a nested loop while AppKit waits on lower-priority
        // text-input services (a priority inversion). The prompt is only
        // reachable from Settings, so that window is always there.
        guard let window = preferencesWindow else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.openDebugURL(from: field.stringValue)
        }
    }
    
    /// Sends the text typed into the debug prompt through the real link path.
    private func openDebugURL(from input: String) {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Bare "example.com" gets https://; anything with a scheme is used as
        // typed, so javascript: / file: links can be tested too.
        if !text.contains(":") { text = "https://" + text }
        guard let url = URL(string: text) else { NSSound.beep(); return }
        
        UserDefaults.standard.set(input, forKey: "debugLastURL")
        application(NSApp, open: [url])   // same path as a real incoming link
    }

    // MARK: - Preview Window

    private func openPreviewWindow(for url: URL) {
        // Defence in depth: the chooser already hides Quick Preview for links
        // it can't open.
        guard LinkSupport.previewUnavailableReason(for: url) == nil else {
            NSSound.beep()
            return
        }
        let id = UUID()

        let contentView = PreviewWindowView(
            url: url,
            onOpenInRealBrowser: { [weak self] browser in
                BrowserDetector.open(url: url, in: browser)
                self?.closePreviewWindow(id: id)
            },
            onClose: { [weak self] in
                self?.closePreviewWindow(id: id)
            },
            onTitleChange: { [weak self] title in
                self?.previewWindows[id]?.title = title.isEmpty ? (url.host ?? "Preview") : title
            }
        )

        let hosting = NSHostingController(rootView: contentView)

        let screenFrame = targetScreen()?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let windowWidth = min(max(screenFrame.width * 0.55, 800), 1400)
        let windowHeight = min(max(screenFrame.height * 0.68, 560), 950)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        hosting.view.frame = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)
        window.setContentSize(NSSize(width: windowWidth, height: windowHeight))
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 640, height: 480)
        // Centre on the screen chosen in "Show chooser on", not always the main one.
        window.setFrameOrigin(NSPoint(
            x: screenFrame.midX - windowWidth / 2,
            y: screenFrame.midY - windowHeight / 2
        ))
        window.isReleasedWhenClosed = false

        previewWindows[id] = window
        previewCloseObservers[id] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.forgetPreviewWindow(id: id)
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func closePreviewWindow(id: UUID) {
        previewWindows[id]?.close()
        forgetPreviewWindow(id: id)
    }

    /// Releases everything we hold for a preview window. Safe to call twice.
    private func forgetPreviewWindow(id: UUID) {
        previewWindows.removeValue(forKey: id)
        if let token = previewCloseObservers.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(token)
        }
    }
    
    // MARK: - SPUUpdaterDelegate

        /// Sparkle calls this before every check to decide which
        /// sparkle:channel-tagged items are eligible. Returning an empty set
        /// (stable) means only untagged items qualify — RC and beta releases
        /// are invisible to stable users.
        func allowedChannels(for updater: SPUUpdater) -> Set<String> {
            switch AppSettings.shared.updateChannel {
            case .stable:
                return []
            case .releaseCandidate:
                return ["rc"]
            case .beta:
                // Beta users also see RC builds — betas are rarer, so this
                // keeps them from missing intermediate stabilizing releases.
                return ["rc", "beta"]
            }
        }
    
    // MARK: - Updates: gentle reminders
    //
    // BrowserLink has no Dock icon, so Sparkle's pop-up for a SCHEDULED check
    // would appear out of nowhere. Instead, when a scheduled check finds an
    // update we (1) put a ↓ next to the menu bar icon and (2) post a system
    // notification, because a menu bar manager can hide the icon without
    // macOS knowing. Clicking either brings up Sparkle's normal update window.

    private static let pendingUpdateKey = "pendingUpdateBuild"
    private static let notifiedUpdateKey = "lastNotifiedUpdateBuild"
    private static let updateNotificationID = "BrowserLink.updateAvailable"

    /// Visible in Console.app: filter by subsystem = BrowserLink's bundle ID, category "updates".
    private let updateLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "BrowserLink", category: "updates")

    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Set by the ⌥ "Check for Updates…" test so that check always takes the
    /// gentle path (arrow + notification), whatever the app's focus state.
    private var forceGentleReminder = false

    /// True once an update was downloaded automatically and is waiting to be
    /// installed when BrowserLink quits ("Download Automatically" is on).
    private var updateReadyToInstall = false

    /// True only while the user is working in one of BrowserLink's own windows.
    private var userIsInOurWindows: Bool {
        guard let key = NSApp.keyWindow else { return false }
        return key === preferencesWindow || key === onboardingWindow
    }

    /// Sparkle asks: "should I pop up the update alert myself?"
    /// Only if the user is already in a BrowserLink window, or the menu bar
    /// icon is hidden by macOS (otherwise they'd never find out).
    ///
    /// Sparkle's own `immediateFocus` is NOT enough: for a menu bar app it is
    /// true whenever the app is active, which includes the moment after
    /// clicking its menu, and then no arrow would ever appear.
    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        let handle = !forceGentleReminder
            && ((immediateFocus && userIsInOurWindows) || statusItem?.isVisible == false)
        updateLog.info("Scheduled check found \(update.displayVersionString, privacy: .public); sparkleImmediateFocus=\(immediateFocus, privacy: .public) inOurWindow=\(self.userIsInOurWindows, privacy: .public) iconVisible=\(self.statusItem?.isVisible ?? false, privacy: .public) -> Sparkle shows its own window: \(handle, privacy: .public)")
        return handle
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        forceGentleReminder = false
        updateLog.info("Will handle showing update: sparkleShows=\(handleShowingUpdate, privacy: .public) userInitiated=\(state.userInitiated, privacy: .public)")
        // The arrow shows whenever an update is found, whether Sparkle opens
        // its own window or not. It then stays until the update is installed,
        // skipped, or no longer offered, so "Remind Me Later" keeps it.
        setUpdateAvailable(true)
        UserDefaults.standard.set(update.versionString, forKey: Self.pendingUpdateKey)

        if handleShowingUpdate {
            // Sparkle is showing its own alert: bring it to the front.
            NSApp.activate()
        } else {
            // Gentle path: no window, so also post a notification.
            notifyAboutUpdate(update)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        // The user has seen it, so the notification can go. The arrow stays.
        removeUpdateNotification()
    }

    func standardUserDriverWillFinishUpdateSession() {
        // Deliberately NOT clearing the arrow here: this also runs for
        // "Remind Me Later" and right after an automatic download, when the
        // update is still waiting. See clearUpdateReminder().
    }

    /// The update is no longer waiting: skipped, or Sparkle no longer offers it.
    private func clearUpdateReminder() {
        updateReadyToInstall = false
        UserDefaults.standard.removeObject(forKey: Self.pendingUpdateKey)
        removeUpdateNotification()
        if updateIsAvailable { setUpdateAvailable(false) }
    }

    private func setUpdateAvailable(_ available: Bool) {
        updateIsAvailable = available

        if let button = statusItem?.button {
            // Always keep the normal logo...
            button.image = NSImage(
                systemSymbolName: "link.circle.fill",
                accessibilityDescription: available ? "BrowserLink: update available" : "BrowserLink"
            )
            // ...and put a small arrow to its right while an update waits.
            button.imagePosition = .imageLeading
            button.title = available ? "↓" : ""
            button.font = .systemFont(ofSize: 13, weight: .bold)
            button.toolTip = available ? "BrowserLink: an update is available" : nil
        }

        // The icon is square normally, but needs more room for logo + arrow.
        statusItem?.length = available ? NSStatusItem.variableLength : NSStatusItem.squareLength

        rebuildMenu()
    }

    // MARK: Notification

    /// One notification per version, so a daily check doesn't nag.
    private func notifyAboutUpdate(_ update: SUAppcastItem, readyToInstall: Bool = false) {
        let defaults = UserDefaults.standard
        let build = update.versionString
        guard defaults.string(forKey: Self.notifiedUpdateKey) != build else { return }

        let version = update.displayVersionString
        let body = readyToInstall
            ? "Version \(version) is downloaded. It installs when you quit BrowserLink, or click to restart and install now."
            : "Version \(version) is ready. Click to review and install."
        let center = UNUserNotificationCenter.current()
        let log = updateLog
        center.requestAuthorization(options: [.alert]) { granted, error in
            guard granted else {
                log.info("Notification permission not granted; relying on the menu bar arrow")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "A BrowserLink update is available"
            content.body = body
            let request = UNNotificationRequest(
                identifier: AppDelegate.updateNotificationID,
                content: content,
                trigger: nil
            )
            center.add(request) { error in
                if error == nil { defaults.set(build, forKey: AppDelegate.notifiedUpdateKey) }
            }
        }
    }

    private func removeUpdateNotification() {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [Self.updateNotificationID])
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Show the banner even while BrowserLink is the active app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    /// Clicking the notification opens Sparkle's update window.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.identifier == Self.updateNotificationID {
            DispatchQueue.main.async { [weak self] in
                NSApp.activate()
                self?.updaterController.checkForUpdates(nil)
            }
        }
        completionHandler()
    }

    // MARK: Surviving a relaunch

    /// The reminder only lives in memory, and Sparkle's next scheduled check
    /// can be a day away. So if a reminder was pending when the app last ran
    /// and we're still on an older build, quietly check again shortly after
    /// launch; that brings the arrow back through the same gentle path.
    private func resumePendingUpdateReminder() {
        let defaults = UserDefaults.standard
        guard let pending = defaults.string(forKey: Self.pendingUpdateKey) else { return }

        let current = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        guard SUStandardVersionComparator.default.compareVersion(current, toVersion: pending) == .orderedAscending else {
            defaults.removeObject(forKey: Self.pendingUpdateKey)   // already updated
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self else { return }
            let updater = self.updaterController.updater
            // Respect "Check for Updates Automatically" being switched off.
            guard updater.automaticallyChecksForUpdates, updater.canCheckForUpdates else { return }
            self.updateLog.info("Re-checking for the update that was pending at last quit")
            updater.checkForUpdatesInBackground()
        }
    }

    // MARK: Menu item

    /// "Check for Updates…" / "Update Available: Install…". Holding ⌥ runs a
    /// background-style check instead, which is exactly what a scheduled
    /// check does, so the gentle reminder path can be tested on demand.
    @objc private func checkForUpdatesFromMenu() {
        let updater = updaterController.updater
        guard updater.canCheckForUpdates else { return }
        if NSEvent.modifierFlags.contains(.option) {
            updateLog.info("⌥ check: running a background-style check")
            forceGentleReminder = true
            updater.checkForUpdatesInBackground()
        } else {
            NSApp.activate()
            updaterController.checkForUpdates(nil)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdatesFromMenu) {
            return updaterController.updater.canCheckForUpdates
        }
        return true
    }

    // MARK: SPUUpdaterDelegate diagnostics

    /// What the user chose in Sparkle's window. "Skip This Version" ends the
    /// reminder; "Install" and "Remind Me Later" keep the arrow.
    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        updateLog.info("User chose \(String(describing: choice), privacy: .public) for \(updateItem.displayVersionString, privacy: .public)")
        if choice == .skip { clearUpdateReminder() }
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        updateLog.info("Downloaded \(item.displayVersionString, privacy: .public)")
    }

    /// "Download Automatically" is on: Sparkle downloads silently and installs
    /// on quit, and never asks to "show" the update, so the gentle callbacks
    /// above don't run. This is the hook for that case. Returning false leaves
    /// the install-on-quit to Sparkle; we only show the arrow and notification.
    /// Clicking either runs a normal check, and Sparkle then offers its
    /// "Install and Relaunch" window for the already-downloaded update.
    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        updateLog.info("Update \(item.displayVersionString, privacy: .public) is downloaded and will install on quit")
        forceGentleReminder = false
        updateReadyToInstall = true
        UserDefaults.standard.set(item.versionString, forKey: Self.pendingUpdateKey)
        setUpdateAvailable(true)
        notifyAboutUpdate(item, readyToInstall: true)
        return false
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        updateLog.info("Appcast has a newer version: \(item.displayVersionString, privacy: .public) (build \(item.versionString, privacy: .public))")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        // Nothing newer (or the user skipped it): there is no reminder to keep.
        forceGentleReminder = false
        clearUpdateReminder()
        updateLog.info("No update to offer: \(error.localizedDescription, privacy: .public)")
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        forceGentleReminder = false
        updateLog.error("Update check failed: \(error.localizedDescription, privacy: .public)")
    }
}

/// Links waiting for their turn, with protection against apps that spam links.
final class LinkQueue: ObservableObject {
    static let maxWaiting = 5
    static let repeatWindow: TimeInterval = 2
    static let muteAfterDismissAll: TimeInterval = 5

    @Published private(set) var waiting: [URL] = []
    @Published private(set) var blockedCount = 0

    private var lastSeen: [URL: Date] = [:]
    private var mutedUntil = Date.distantPast
    
    /// Called when the line has fully drained and the last chooser closed.
    func finishBatch() {
        blockedCount = 0
    }

    func add(_ url: URL, currentlyShowing: URL?) {
        let now = Date()
        let previous = lastSeen[url]
        lastSeen[url] = now   // sliding window: stays muted while it keeps coming
        lastSeen = lastSeen.filter { now.timeIntervalSince($0.value) < 60 }

        if now < mutedUntil { return }
        if url == currentlyShowing || waiting.contains(url) { return }
        if let previous, now.timeIntervalSince(previous) < Self.repeatWindow { return }

        if waiting.count >= Self.maxWaiting {
            blockedCount += 1
            return
        }
        waiting.append(url)
    }

    func next() -> URL? {
        if waiting.isEmpty {
            blockedCount = 0
            return nil
        }
        return waiting.removeFirst()
    }

    /// "Dismiss all": empties the line and ignores new links for a few seconds.
    func clear() {
        waiting.removeAll()
        blockedCount = 0
        mutedUntil = Date().addingTimeInterval(Self.muteAfterDismissAll)
    }
}
