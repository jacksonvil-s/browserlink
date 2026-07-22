import SwiftUI
import Sparkle

struct PreferencesView: View {
    let updater: SPUUpdater
    let onSetDefaultBrowser: () -> Void
    let onHideMenuBarIconChanged: (Bool) -> Void

    @State private var launchAtLoginEnabled = LoginItemHelper.isEnabled
    @State private var hideMenuBarIcon = PreferencesHelper.isMenuBarIconHidden
    @State private var automaticallyChecksForUpdates: Bool

    init(
        updater: SPUUpdater,
        onSetDefaultBrowser: @escaping () -> Void,
        onHideMenuBarIconChanged: @escaping (Bool) -> Void
    ) {
        self.updater = updater
        self.onSetDefaultBrowser = onSetDefaultBrowser
        self.onHideMenuBarIconChanged = onHideMenuBarIconChanged
        _automaticallyChecksForUpdates = State(initialValue: updater.automaticallyChecksForUpdates)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            VStack(alignment: .leading, spacing: 14) {
                sectionLabel("Browser")

                Button(action: onSetDefaultBrowser) {
                    HStack {
                        Image(systemName: "globe")
                        Text("Set BrowserLink as Default Browser…")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                Divider()

                sectionLabel("General")

                Toggle("Launch at Login", isOn: $launchAtLoginEnabled)
                    .onChange(of: launchAtLoginEnabled) { _, newValue in
                        LoginItemHelper.setEnabled(newValue)
                    }

                Toggle("Hide Menu Bar Icon", isOn: $hideMenuBarIcon)
                    .onChange(of: hideMenuBarIcon) { _, newValue in
                        PreferencesHelper.isMenuBarIconHidden = newValue
                        onHideMenuBarIconChanged(newValue)
                    }

                if hideMenuBarIcon {
                    Text("Press ⌥⇧B (Option-Shift-B) anytime to reopen this window if the menu bar icon is hidden.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 2)
                }

                Divider()

                sectionLabel("Updates")

                Toggle("Automatically Check for Updates", isOn: $automaticallyChecksForUpdates)
                    .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                        updater.automaticallyChecksForUpdates = newValue
                    }

                Button(action: {
                    updater.checkForUpdates()
                }) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Check for Updates…")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Quit BrowserLink") {
                    NSApplication.shared.terminate(nil)
                }
                .foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(width: 420, height: 420)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("BrowserLink")
                    .font(.system(size: 16, weight: .semibold))
                Text("Preferences")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}
