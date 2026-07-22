import AppKit
import SwiftUI
import Sparkle

/// The real brain of the app. Because this is a background agent (LSUIElement = true,
/// set in Info.plist), there's no Dock icon and no default window — everything is
/// driven from here.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// The persistent menu bar item — our only always-visible presence.
    private var statusItem: NSStatusItem?

    /// The floating chooser panel. Recreated each time a link comes in,
    /// released once the user makes a choice (or dismisses it).
    private var chooserPanel: NSPanel?

    /// Every currently-open preview window, keyed by a UUID so multiple
    /// previews can be open at once without stomping on each other.
    private var previewWindows: [UUID: NSWindow] = [:]

    /// Sparkle's standard updater controller — handles checking the appcast
    /// feed (see Info.plist SUFeedURL), downloading, verifying the EdDSA
    /// signature, and installing updates. `startingUpdater: true` means it
    /// begins its periodic background check automatically at launch.
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    /// The Preferences window. Built once, shown/hidden as needed rather
    /// than recreated each time (avoids losing toggle state / flicker).
    private var preferencesWindow: NSWindow?

    /// Global keyboard shortcut monitor (⌥⇧B) that reopens Preferences even
    /// when the menu bar icon is hidden — otherwise a hidden icon would leave
    /// no way back into settings at all.
    private var globalShortcutMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !PreferencesHelper.isMenuBarIconHidden {
            setupStatusItem()
            rebuildMenu()
        }
        setupGlobalShortcut()
    }

    /// Guards against the global shortcut firing many times in rapid
    /// succession (e.g. someone holding the keys down, which repeats the
    /// keyDown event continuously) — without this, each repeat could queue
    /// up another window-creation call, and enough of them piling up on the
    /// main thread is what caused Xcode/the app to hang entirely.
    private var lastShortcutTriggerTime: Date = .distantPast

    /// Registers the ⌥⇧B global shortcut that reopens Preferences regardless
    /// of whether the menu bar icon is currently shown. This is the escape
    /// hatch that makes "Hide Menu Bar Icon" safe to offer at all — without
    /// it, hiding the icon would strand the user with no way back in short
    /// of quitting via Activity Monitor.
    private func setupGlobalShortcut() {
        globalShortcutMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            // ⌥⇧B: keyCode 11 is 'B' on US layouts; checking modifiers this way
            // is simple and reliable enough for a single fixed shortcut like this.
            guard event.modifierFlags.contains([.option, .shift]) && event.keyCode == 11 else {
                return
            }

            // Debounce: ignore repeats within half a second of the last trigger.
            let now = Date()
            guard now.timeIntervalSince(self.lastShortcutTriggerTime) > 0.5 else {
                return
            }
            self.lastShortcutTriggerTime = now

            // CRITICAL: global monitor callbacks are not guaranteed to run on
            // the main thread. All AppKit window/view work below MUST happen
            // on main, or rapid triggers can corrupt AppKit state and hang
            // the app (this is what caused the freeze).
            DispatchQueue.main.async {
                self.openPreferences()
            }
        }
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
    /// status item. Safe to call repeatedly — e.g. after toggling Launch at
    /// Login, to refresh the checkmark state — since it never touches the
    /// status item itself.
    private func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(
                title: "Set BrowserLink as Default Browser…",
                action: #selector(promptSetDefaultBrowser),
                keyEquivalent: ""
            )
        )
        menu.addItem(NSMenuItem.separator())

        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.state = LoginItemHelper.isEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        let updateItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updateItem.target = updaterController
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
        statusItem?.menu = menu
    }

    @objc private func toggleLaunchAtLogin() {
        LoginItemHelper.setEnabled(!LoginItemHelper.isEnabled)
        // Rebuild just the menu so the checkmark reflects the new state —
        // does NOT touch the status item itself.
        rebuildMenu()
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
            NSApp.activate(ignoringOtherApps: true)
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
            onHideMenuBarIconChanged: { [weak self] hidden in
                self?.setStatusItemVisible(!hidden)
            }
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.title = "BrowserLink Preferences"
        window.isReleasedWhenClosed = false
        window.center()
        preferencesWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Shows or hides the menu bar status item. When hiding, the item is
    /// fully removed from the status bar (not just its icon cleared) so it
    /// doesn't leave an invisible-but-clickable gap behind. When showing
    /// again, it's recreated fresh and the menu rebuilt.
    private func setStatusItemVisible(_ visible: Bool) {
        if visible {
            if statusItem == nil {
                setupStatusItem()
                rebuildMenu()
            }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
            }
            statusItem = nil
        }
    }

    // MARK: - URL Interception
    //
    // This is the method macOS calls when the app is registered as a URL handler
    // and a link is opened anywhere in the system (Mail, Slack, Messages, Safari's
    // "open in default browser," etc). This fires via the Info.plist CFBundleURLTypes
    // registration — see Info.plist for the http/https scheme declarations.

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        presentChooser(for: url)
    }

    // MARK: - Chooser Panel

    private func presentChooser(for url: URL) {
        // If a chooser is already open (rapid double-click, etc.), close it first
        // rather than stacking panels.
        chooserPanel?.close()

        let installedBrowsers = BrowserDetector.installedBrowsers()

        let contentView = ChooserPanelView(
            url: url,
            browsers: installedBrowsers,
            onPreview: { [weak self] in
                self?.chooserPanel?.close()
                self?.openPreviewWindow(for: url)
            },
            onOpenIn: { [weak self] browser in
                self?.chooserPanel?.close()
                BrowserDetector.open(url: url, in: browser)
            },
            onDismiss: { [weak self] in
                self?.chooserPanel?.close()
            }
        )

        let hosting = NSHostingController(rootView: contentView)

        // Scale panel size relative to the screen it'll appear on, rather than
        // a fixed pixel value — this keeps it proportionally sized whether
        // you're on a 13" laptop or a 32" external display.
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panelWidth = min(max(screenFrame.width * 0.34, 620), 900)
        let panelHeight = min(max(screenFrame.height * 0.42, 420), 620)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
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
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]

        // Center it, slightly above true vertical center — see design notes.
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.midX - panel.frame.width / 2
            let y = screen.visibleFrame.midY - panel.frame.height / 2 + (screen.visibleFrame.height * 0.08)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        chooserPanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: - Preview Window

    private func openPreviewWindow(for url: URL) {
        let id = UUID()

        let contentView = PreviewWindowView(
            url: url,
            onOpenInRealBrowser: { [weak self] browser in
                BrowserDetector.open(url: url, in: browser)
                self?.closePreviewWindow(id: id)
            },
            onClose: { [weak self] in
                self?.closePreviewWindow(id: id)
            }
        )

        let hosting = NSHostingController(rootView: contentView)

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let windowWidth = min(max(screenFrame.width * 0.68, 900), 1600)
        let windowHeight = min(max(screenFrame.height * 0.78, 640), 1100)

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
        window.center()
        window.isReleasedWhenClosed = false

        previewWindows[id] = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func closePreviewWindow(id: UUID) {
        previewWindows[id]?.close()
        previewWindows.removeValue(forKey: id)
    }
}
