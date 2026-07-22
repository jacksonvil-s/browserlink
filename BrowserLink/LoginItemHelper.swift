import ServiceManagement

/// Handles registering BrowserLink to launch automatically at login.
///
/// Uses SMAppService (macOS 13+), Apple's modern replacement for the old
/// SMLoginItemSetEnabled / LSSharedFileList APIs. No helper app or separate
/// bundle target needed — SMAppService.mainApp registers the app itself.
enum LoginItemHelper {

    /// Whether BrowserLink is currently registered to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Enables or disables launch-at-login.
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled {
                    return // already on, nothing to do
                }
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("LoginItemHelper: failed to \(enabled ? "register" : "unregister"): \(error)")
        }
    }
}
