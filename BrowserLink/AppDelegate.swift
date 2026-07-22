import AppKit
import SwiftUI

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        rebuildMenu()
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
        // selector doesn't exist and would silently no-op.
        for menuItem in menu.items {
            if menuItem.action == #selector(NSApplication.terminate(_:)) {
                menuItem.target = nil
            } else {
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
