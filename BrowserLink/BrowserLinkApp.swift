import SwiftUI
import AppKit

@main
struct BrowserLinkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // This Settings scene is unused — AppDelegate manages its own Preferences
        // NSWindow directly (see openPreferences()), since showSettingsWindow:
        // is unreliable in LSUIElement background-agent apps. This scene exists
        // only because SwiftUI's App protocol requires a non-empty body.
        Settings {
            EmptyView()
        }
    }
}
