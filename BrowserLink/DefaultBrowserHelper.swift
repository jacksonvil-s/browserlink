import AppKit
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

    static func promptUserToSetDefault() {
        if #available(macOS 12.0, *) {
            var encounteredError = false

            NSWorkspace.shared.setDefaultApplication(
                at: Bundle.main.bundleURL,
                toOpenURLsWithScheme: "https"
            ) { error in
                if let error = error {
                    print("Failed to set default for https: \(error)")
                    encounteredError = true
                    DispatchQueue.main.async {
                        openSystemSettingsFallback()
                    }
                }
            }
            NSWorkspace.shared.setDefaultApplication(
                at: Bundle.main.bundleURL,
                toOpenURLsWithScheme: "http"
            ) { error in
                if let error = error, !encounteredError {
                    print("Failed to set default for http: \(error)")
                    DispatchQueue.main.async {
                        openSystemSettingsFallback()
                    }
                }
            }
        } else {
            openSystemSettingsFallback()
        }
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
