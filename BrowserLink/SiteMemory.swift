import SwiftUI
import AppKit
import Combine

/// Turns a link into the "site" a remembered-browser rule belongs to.
/// "https://gist.github.com/x" and "https://github.com/y" both become
/// "github.com", so one rule covers a whole site.
enum SiteKey {
    /// Stored in place of a browser ID when the rule is "always use Quick Preview".
    static let previewRule = "quick-preview"
    
    /// Common two-part endings where the site name is one label further left
    /// ("bbc.co.uk", not "co.uk"). Not the full public-suffix list; extend if needed.
    private static let twoPartSuffixes: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk", "me.uk",
        "com.au", "net.au", "org.au", "edu.au", "gov.au",
        "co.nz", "org.nz", "co.jp", "ne.jp", "or.jp", "co.kr",
        "co.in", "com.br", "com.mx", "com.ar", "com.tr", "com.cn",
        "com.hk", "com.sg", "com.tw", "co.za", "co.il", "com.ua", "com.pl"
    ]

    /// nil for anything that shouldn't get a rule: non-web links, IP
    /// addresses, localhost and single-label (local network) names.
    static func key(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased() else { return nil }
        if host.contains(":") { return nil }
        if host.range(of: #"^[0-9.]+$"#, options: .regularExpression) != nil { return nil }

        let labels = host.split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return nil }

        let lastTwo = labels.suffix(2).joined(separator: ".")
        if twoPartSuffixes.contains(lastTwo), labels.count >= 3 {
            return labels.suffix(3).joined(separator: ".")
        }
        return lastTwo
    }
}

/// A small banner near the top of the screen ("Opened github.com in Firefox ·
/// Change") that never takes focus and fades away by itself.
final class ToastPresenter {
    private var panel: NSPanel?
    private var dismissTimer: Timer?

    func show(
        message: String,
        icon: NSImage?,
        actionTitle: String,
        screen: NSScreen?,
        action: @escaping () -> Void
    ) {
        dismiss()

        let size = NSSize(width: 380, height: 56)
        let view = ToastView(message: message, icon: icon, actionTitle: actionTitle) { [weak self] in
            self?.dismiss()
            action()
        }
        let hosting = NSHostingController(rootView: view)
        hosting.view.frame = NSRect(origin: .zero, size: size)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.setContentSize(size)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]

        let area = (screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let finalOrigin = NSPoint(x: area.midX - size.width / 2, y: area.maxY - size.height - 14)

        // Same two rules as the chooser: respect Reduce Motion, and start the
        // animation on the next run-loop pass so it isn't swallowed.
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var startOrigin = finalOrigin
        if !reduceMotion { startOrigin.y += 10 }
        panel.setFrameOrigin(startOrigin)
        panel.alphaValue = 0
        hosting.view.layoutSubtreeIfNeeded()
        panel.orderFrontRegardless()
        self.panel = panel

        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = reduceMotion ? 0.15 : 0.25
                context.allowsImplicitAnimation = true
                panel.animator().alphaValue = 1
                panel.animator().setFrameOrigin(finalOrigin)
            }
        }

        dismissTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        guard let old = panel else { return }
        panel = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            old.animator().alphaValue = 0
        }, completionHandler: {
            old.close()
        })
    }
}

private struct ToastView: View {
    let message: String
    let icon: NSImage?
    let actionTitle: String
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 26, height: 26)
            }
            Text(message)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(2)
            Spacer(minLength: 8)
            Button(actionTitle, action: onAction)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .frame(width: 380, height: 56)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
    }
}


// MARK: - Recent links and shared notifications

extension Notification.Name {
    /// Posted by Preferences so its buttons do what the menu-bar items do
    /// (the menu is unreachable while the status icon is hidden).
    static let openClipboardLinkRequested = Notification.Name("BrowserLink.openClipboardLinkRequested")
    /// `object` is the URL to show in the chooser.
    static let openRecentLinkRequested = Notification.Name("BrowserLink.openRecentLinkRequested")
}

/// The "Recent Links" list, shared by the menu bar and Preferences. Memory
/// only: nothing is saved, and quitting the app (or switching the setting
/// off) clears it.
final class RecentLinks: ObservableObject {
    static let shared = RecentLinks()

    /// Newest first, at most 10.
    @Published private(set) var urls: [URL] = []
    private var cancellable: AnyCancellable?

    private init() {
        cancellable = AppSettings.shared.$keepRecentLinks
            .dropFirst()
            .removeDuplicates()
            .filter { !$0 }
            .sink { [weak self] _ in self?.clear() }
    }

    func record(_ url: URL) {
        guard AppSettings.shared.keepRecentLinks,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        var list = urls
        list.removeAll { $0 == url }
        list.insert(url, at: 0)
        urls = Array(list.prefix(10))
    }

    func clear() {
        if !urls.isEmpty { urls = [] }
    }

    /// Host and path only: the query string (which can hold tokens) stays out of the UI.
    static func title(for url: URL) -> String {
        let text = (url.host ?? url.absoluteString) + (url.path == "/" ? "" : url.path)
        return text.count > 48 ? String(text.prefix(47)) + "…" : text
    }
}
