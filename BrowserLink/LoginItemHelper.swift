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

    /// Enables or disables launch-at-login. Callers should re-read `isEnabled`
    /// afterwards, because registration can succeed but still need the user's
    /// approval in System Settings, or fail outright.
    static func setEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                guard service.status != .enabled else { return } // already on
                try service.register()
                if service.status == .requiresApproval {
                    // Registered, but macOS wants the user to switch it on.
                    SMAppService.openSystemSettingsLoginItems()
                }
            } else {
                // unregister() throws if there's nothing registered, e.g. the
                // user already switched it off in System Settings.
                guard service.status == .enabled || service.status == .requiresApproval else { return }
                try service.unregister()
            }
        } catch {
            print("LoginItemHelper: failed to \(enabled ? "register" : "unregister"): \(error)")
        }
    }
}
