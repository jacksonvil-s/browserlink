import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Handles registering BrowserLink as the system default browser.
///
/// Important nuance: macOS does NOT let an app silently make itself the default —
/// the user must confirm via a system-presented dialog (as of macOS 12+, this is
/// `NSWorkspace.shared.setDefaultApplication`, which triggers Apple's own permission
/// prompt). This is intentional OS-level protection against browser hijacking, and
/// there's no way around it — nor should there be.
///
/// Known gotcha: `setDefaultApplication` can fail with a LaunchServices `permErr`
/// (-54) if the app isn't properly registered/signed yet, or if it's being run
/// directly from DerivedData without ever having been "seen" by LaunchServices
/// through a normal Finder/Dock interaction. If that happens, we fall back to
/// opening System Settings directly so the user can pick it manually — which
/// always works regardless of signing state.
enum DefaultBrowserHelper {

    /// Posted (on the main queue) after a "set as default" attempt finishes,
    /// so any status UI can re-check.
    static let didChangeNotification = Notification.Name("BrowserLinkDefaultBrowserDidChange")

    /// True when macOS currently routes https:// links to this app.
    static var isDefault: Bool {
        guard let ownID = Bundle.main.bundleIdentifier else { return false }
        return handlerBundleID(forScheme: "https") == ownID
    }

    private static func handlerBundleID(forScheme scheme: String) -> String? {
        guard let probe = URL(string: "\(scheme)://example.com"),
              let handlerURL = NSWorkspace.shared.urlForApplication(toOpen: probe) else { return nil }
        return Bundle(url: handlerURL)?.bundleIdentifier
    }

    private static func notifyChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    /// Asks macOS to make BrowserLink the default for web links.
    ///
    /// The two requests (https, then http) run ONE AFTER THE OTHER, never at
    /// the same time:
    ///   - if the user cancels the first prompt, nothing else happens (no
    ///     second request, and no "set it manually" alert);
    ///   - a real failure shows the manual-setup alert exactly once.
    static func promptUserToSetDefault() {
        // https first: that's the request whose confirmation macOS shows.
        setDefault(forScheme: "https") { result in
            switch result {
            case .cancelled:
                notifyChanged()

            case .failed(let error):
                print("Failed to set default for https: \(error)")
                openSystemSettingsFallback()
                notifyChanged()

            case .succeeded:
                // macOS may have switched http along with https already; only
                // ask again if it didn't.
                if handlerBundleID(forScheme: "http") == Bundle.main.bundleIdentifier {
                    notifyChanged()
                    return
                }
                setDefault(forScheme: "http") { result in
                    if case .failed(let error) = result {
                        print("Failed to set default for http: \(error)")
                        openSystemSettingsFallback()
                    }
                    notifyChanged()
                }
            }
        }
    }

    private enum SetDefaultResult {
        case succeeded
        case cancelled
        case failed(Error)
    }

    /// Wraps NSWorkspace's callback API, always answering on the main queue.
    private static func setDefault(forScheme scheme: String, completion: @escaping (SetDefaultResult) -> Void) {
        NSWorkspace.shared.setDefaultApplication(
            at: Bundle.main.bundleURL,
            toOpenURLsWithScheme: scheme
        ) { error in
            DispatchQueue.main.async {
                guard let error else {
                    completion(.succeeded)
                    return
                }
                completion(isUserCancellation(error) ? .cancelled : .failed(error))
            }
        }
    }

    /// Clicking Cancel in the system prompt arrives as a Cocoa error (code 256)
    /// wrapping NSOSStatusErrorDomain -128, "userCanceledErr". That's the
    /// user's choice, not a failure.
    private static func isUserCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError { return true }
        if nsError.domain == NSOSStatusErrorDomain && nsError.code == -128 { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return underlying.domain == NSOSStatusErrorDomain && underlying.code == -128
        }
        return false
    }

    /// Opens System Settings directly to the default-browser picker, as a
    /// reliable fallback when the programmatic API fails.
    private static func openSystemSettingsFallback() {
        // Deep link into the General pane; from macOS 13+ "Desktop & Dock"
        // holds the default browser picker, but this general anchor works
        // across versions and gets the user 90% of the way there.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.general") {
            NSWorkspace.shared.open(url)
        }

        let alert = NSAlert()
        alert.messageText = "Set BrowserLink Manually"
        alert.informativeText = "macOS didn't allow the automatic prompt this time. In System Settings, go to Desktop & Dock → Default web browser, and choose BrowserLink from the list."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

/// One-line "is BrowserLink your default browser?" indicator, used in
/// onboarding and Preferences. Re-checks whenever the app becomes active
/// again (e.g. after System Settings) and after a set-default attempt.
struct DefaultBrowserStatusLabel: View {
    @State private var isDefault = DefaultBrowserHelper.isDefault

    var body: some View {
        Label(
            isDefault
                ? "BrowserLink is your default browser."
                : "BrowserLink isn't your default browser yet, so links won't open in it until you set it.",
            systemImage: isDefault ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        )
        .font(.system(size: 12))
        .foregroundStyle(isDefault ? Color.green : Color.orange)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { isDefault = DefaultBrowserHelper.isDefault }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isDefault = DefaultBrowserHelper.isDefault
        }
        .onReceive(NotificationCenter.default.publisher(for: DefaultBrowserHelper.didChangeNotification)) { _ in
            isDefault = DefaultBrowserHelper.isDefault
        }
    }
}
