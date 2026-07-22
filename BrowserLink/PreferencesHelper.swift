import Foundation

/// Simple UserDefaults-backed storage for app preferences that need to
/// persist across launches.
enum PreferencesHelper {
    private static let hideMenuBarIconKey = "hideMenuBarIcon"

    static var isMenuBarIconHidden: Bool {
        get { UserDefaults.standard.bool(forKey: hideMenuBarIconKey) }
        set { UserDefaults.standard.set(newValue, forKey: hideMenuBarIconKey) }
    }
}
