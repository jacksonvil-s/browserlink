import SwiftUI
import AppKit

// MARK: - Panel

/// The floating chooser window.
///
/// A borderless, non-activating panel that can still take keyboard focus.
/// Appearing over full-screen apps also needs `.fullScreenAuxiliary` in its
/// collection behavior and a floating level, which AppDelegate sets.
final class ChooserPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - View

/// The panel shown the instant a link is clicked anywhere on the system.
///
/// A command-palette layout, top to bottom:
///   address bar – site icon and the address with the REAL host in bold
///   notices     – queue, link cleaning, safety warnings
///   list        – Quick Preview, then one row per browser (↑↓ to move)
///   footer      – "remember this site", key hints, version
///
/// The panel reports the height its content wants (`onPreferredHeight`) and
/// AppDelegate resizes the window to match, so it is never taller than needed.
struct ChooserPanelView: View {
    let url: URL
    let browsers: [InstalledBrowser]
    let onPreview: () -> Void
    let onOpenIn: (InstalledBrowser) -> Void
    let onOpenPreferences: () -> Void
    let onDismiss: () -> Void

    @ObservedObject var linkQueue: LinkQueue
    let onDismissAll: () -> Void

    /// What LinkCleaner changed about this link (nil if nothing), and a way
    /// to switch back to the link exactly as it arrived.
    let cleaningNote: String?
    let onUseOriginal: (() -> Void)?

    /// Computed once by AppDelegate when the chooser opens.
    let safetyResult: URLSafetyResult

    /// Per-site memory. `siteKey` is e.g. "github.com" (nil = not offered),
    /// `rememberedName` is the browser already saved for it, if any.
    let siteKey: String?
    let rememberedName: String?
    /// Receives a browser's bundle ID, or SiteKey.previewRule for Quick Preview.
    let onRememberSite: (String) -> Void
    let onForgetSite: () -> Void

    /// The total height this content would like, in points.
    let onPreferredHeight: (CGFloat) -> Void

    @StateObject private var faviconLoader = FaviconLoader()
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hasConfirmedDanger = false
    @State private var confirmSecondsLeft = 3
    @State private var pauseProgress: CGFloat = 0
    @State private var unlockBounce = false
    @State private var didCopyLink = false
    @State private var rememberThisSite = false
    @State private var didForget = false

    /// Position in `targets` that the keyboard has highlighted (nil = nothing yet).
    @State private var focusIndex: Int?

    private static let cornerRadius: CGFloat = 22

    /// Loaded once and reused, instead of reading the file on every chooser.
    private static let popSound: NSSound? = Bundle.main
        .url(forResource: "pop", withExtension: "mp3")
        .flatMap { NSSound(contentsOf: $0, byReference: true) }

    // MARK: Derived state

    /// Why Quick Preview can't open this particular link (nil = it can).
    private var previewUnavailableReason: String? {
        LinkSupport.previewUnavailableReason(for: url)
    }

    /// Quick Preview is listed in every mode except "chooser only"
    /// (or as the fallback when no browser was found).
    private var showsPreview: Bool {
        guard previewUnavailableReason == nil else { return false }
        return settings.appMode != .chooser || browsers.isEmpty
    }

    /// The browser rows are listed unless the mode is "preview only".
    /// In "preview only" mode they still appear for links that can't be
    /// previewed, otherwise there would be nothing to click.
    private var showsBrowsers: Bool {
        guard !browsers.isEmpty else { return false }
        return settings.appMode != .preview || previewUnavailableReason != nil
    }

    private var isLocked: Bool {
        safetyResult.requiresConfirmation && !hasConfirmedDanger
    }

    private var pauseApplies: Bool {
        safetyResult.hasSeriousReason && settings.delaySevereConfirm
    }

    private var isWaitingToConfirm: Bool {
        pauseApplies && confirmSecondsLeft > 0
    }

    private var confirmButtonTitle: String {
        if isWaitingToConfirm { return "Please wait \(confirmSecondsLeft)…" }
        return safetyResult.hasSeriousReason
            ? "I understand the risk — show me the options anyway (this may cause harm to your system!)"
            : "I understand the risk — show me the options anyway"
    }

    private var rememberRowIsVisible: Bool {
        siteKey != nil && safetyResult.reasons.isEmpty && showsBrowsers
    }

    /// Small grey note explaining why part of the list is missing.
    private var modeNote: String? {
        if let reason = previewUnavailableReason {
            if browsers.isEmpty {
                return reason + " No browser was detected on your system, so there is nothing to open this link with."
            }
            return settings.appMode == .preview ? reason + " Showing your browsers instead." : reason
        }
        if browsers.isEmpty {
            return "Browser chooser unavailable because we did not detect a browser on your system."
        }
        switch settings.appMode {
        case .preview: return "Browser chooser unavailable because it has been switched off."
        case .chooser: return "Preview window unavailable because it has been switched off."
        case .both: return nil
        }
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(version) (build \(build))"
    }

    // MARK: Keyboard targets

    private enum FocusTarget: Equatable {
        case preview
        case browser(Int)
        case remember
    }

    /// Everything the arrow keys can land on, top to bottom.
    private var targets: [FocusTarget] {
        var list: [FocusTarget] = []
        if showsPreview { list.append(.preview) }
        if showsBrowsers { list += browsers.indices.map { FocusTarget.browser($0) } }
        if rememberRowIsVisible { list.append(.remember) }
        return list
    }

    private var isGrid: Bool { settings.chooserLayout == .grid }

    /// Tiles per row in grid layout.
    private var gridColumns: Int { max(min(browsers.count, 4), 1) }

    private func isFocused(_ target: FocusTarget) -> Bool {
        guard let index = focusIndex, targets.indices.contains(index) else { return false }
        return targets[index] == target
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            addressBar
                .reportsHeight()
            Divider().opacity(0.12)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 10) {
                        notices

                        list
                            .disabled(isLocked)
                            .opacity(isLocked ? 0.35 : 1)

                        if let modeNote {
                            Text(modeNote)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 2)
                        }
                    }
                    .padding(10)
                    .reportsHeight()
                }
                .onChange(of: focusIndex) { _, newValue in
                    guard let newValue, targets.indices.contains(newValue) else { return }
                    switch targets[newValue] {
                    case .preview: proxy.scrollTo("quick-preview")
                    case .browser(let index): proxy.scrollTo(browsers[index].id)
                    case .remember: break
                    }
                }
            }

            Divider().opacity(0.12)
            footer
                .reportsHeight()
        }
        .onPreferenceChange(ChooserHeightKey.self) { height in
            // Two 1pt dividers aren't measured.
            // Deferred: resizing the window while SwiftUI is still updating the
            // view triggers "Publishing changes from within view updates".
            guard height > 50 else { return }
            DispatchQueue.main.async { onPreferredHeight(height + 2) }
        }
        .background(glass)
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .onAppear {
            if settings.playSoundOnChooserAppear {
                Self.popSound?.stop()
                Self.popSound?.play()
            }
            faviconLoader.load(for: url, safetyResult: safetyResult)
        }
        .background(
            KeyCatcher(
                onEscape: onDismiss,
                onSelectIndex: { index in
                    if isLocked { return }
                    guard showsBrowsers, browsers.indices.contains(index) else { return }
                    choose(browsers[index])
                },
                onPreview: {
                    if isLocked { return }
                    guard showsPreview else { return }
                    choosePreview()
                },
                onArrow: moveSelection,
                onReturn: activateFocus
            )
        )
    }

    /// Translucent material with a faint wash of the interface colour.
    private var glass: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(settings.tintColor.opacity(0.06))
        }
    }

    // MARK: Address bar

    private var securityIcon: (name: String, color: Color)? {
        switch url.scheme?.lowercased() {
        case "https": return ("lock.fill", .secondary)
        case "http": return ("lock.open.fill", .orange)
        case "file": return ("doc.text.fill", .secondary)
        default: return nil
        }
    }

    /// The address with the host in bold and everything else dimmed, so a
    /// long path or a "paypal.com@evil.com" trick can't hide the real host.
    /// "https://" is left out (the lock shows it). Local files show their
    /// name in bold and their folder dimmed.
    private var addressText: Text {
        if url.isFileURL {
            let name = url.lastPathComponent
            return Text(name.isEmpty ? url.path : name).fontWeight(.semibold)
                + Text("   " + url.deletingLastPathComponent().path).foregroundStyle(.secondary)
        }

        var full = url.absoluteString
        if let scheme = full.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) {
            full.removeSubrange(scheme)
        }

        // Find the host inside the authority part only (before the first / ? #),
        // searching from the end so a "host@host" trick bolds the REAL host.
        let authorityEnd = full.firstIndex(where: { "/?#".contains($0) }) ?? full.endIndex
        guard let host = url.host,
              let range = full[..<authorityEnd].range(of: host, options: [.caseInsensitive, .backwards]) else {
            return Text(full).foregroundStyle(.secondary)
        }
        return Text(full[..<range.lowerBound]).foregroundStyle(.secondary)
            + Text(full[range]).fontWeight(.semibold)
            + Text(full[range.upperBound...]).foregroundStyle(.secondary)
    }

    private var addressBar: some View {
        HStack(spacing: 12) {
            faviconTile

            HStack(spacing: 6) {
                if let securityIcon {
                    Image(systemName: securityIcon.name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(securityIcon.color)
                        .accessibilityHidden(true)
                }
                addressText
                    .font(.system(size: 14))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(url.absoluteString)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                HeaderIconButton(
                    symbol: didCopyLink ? "checkmark" : "doc.on.doc",
                    label: didCopyLink ? "Link copied" : "Copy link",
                    tint: didCopyLink ? .green : .secondary,
                    action: copyLink
                )
                HeaderIconButton(symbol: "gearshape", label: "Preferences…", action: onOpenPreferences)
                HeaderIconButton(symbol: "xmark", label: "Dismiss", action: onDismiss)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var faviconTile: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(settings.tintColor.opacity(0.16))
            .frame(width: 36, height: 36)
            .overlay {
                if let favicon = faviconLoader.image {
                    Image(nsImage: favicon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 22, height: 22)
                } else {
                    Image(systemName: url.isFileURL ? "doc.text" : "globe")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(settings.tintColor)
                }
            }
    }

    /// Works even while a warning has the options locked: copying a link
    /// doesn't open it.
    private func copyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        didCopyLink = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            didCopyLink = false
        }
    }

    // MARK: Notices

    @ViewBuilder
    private var notices: some View {
        if !linkQueue.waiting.isEmpty || linkQueue.blockedCount > 0 {
            NoticeRow(
                symbol: "square.stack.3d.up.fill",
                text: queueNoticeText,
                actionTitle: "Dismiss all",
                action: onDismissAll
            )
        }

        if let cleaningNote {
            NoticeRow(
                symbol: "sparkles",
                text: cleaningNote,
                actionTitle: onUseOriginal == nil ? nil : "Use original link",
                action: onUseOriginal
            )
        }

        if isLocked {
            warningBanner
        }

        if !safetyResult.advisoryReasons.isEmpty {
            advisoryNotice
        }
    }

    private var queueNoticeText: String {
        let waiting = linkQueue.waiting.count
        var parts: [String] = []
        if waiting > 0 {
            parts.append("\(waiting) more link\(waiting == 1 ? "" : "s") waiting")
        }
        if linkQueue.blockedCount > 0 {
            parts.append("\(linkQueue.blockedCount) blocked (an app may be opening links repeatedly)")
        }
        return parts.joined(separator: " · ")
    }

    private var warningBanner: some View {
        let isSerious = safetyResult.hasSeriousReason
        let tint: Color = isSerious ? .red : .orange
        let headerLevel: SafetyLevel = isSerious ? .serious : .warning

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: headerLevel.symbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(headerLevel.color)
                Text("This link looks suspicious. The reasons are listed below.")
                    .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(safetyResult.blockingReasons) { reason in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: reason.level.symbolName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(reason.level.color)
                            .padding(.top, 1)
                        Text(reason.message)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                    hasConfirmedDanger = true
                }
            } label: {
                Text(confirmButtonTitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(tint)
                    .contentTransition(.opacity)
                    .frame(maxWidth: .infinity, minHeight: pauseApplies ? 32 : 0)
                    .padding(.vertical, 10)
                    .background(
                        ZStack(alignment: .leading) {
                            tint.opacity(0.12)
                            if isWaitingToConfirm && !reduceMotion {
                                tint.opacity(0.30)
                                    .scaleEffect(x: pauseProgress, y: 1, anchor: .leading)
                                    .transition(.opacity)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    )
            }
            .buttonStyle(.plain)
            .disabled(isWaitingToConfirm)
            .opacity(isWaitingToConfirm ? 0.8 : 1)
            .scaleEffect(unlockBounce ? 1.05 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: isWaitingToConfirm)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tint.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tint.opacity(0.3), lineWidth: 1))
        .task { await runConfirmPause() }
    }

    /// Counts down once per second, then lets the button work.
    private func runConfirmPause() async {
        guard pauseApplies else { return }

        if !reduceMotion {
            withAnimation(.linear(duration: Double(confirmSecondsLeft))) {
                pauseProgress = 1
            }
        }

        while confirmSecondsLeft > 0 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return }
            confirmSecondsLeft -= 1
        }

        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.4)) { unlockBounce = true }
        try? await Task.sleep(nanoseconds: 150_000_000)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { unlockBounce = false }
    }

    private var advisoryNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(safetyResult.advisoryReasons) { reason in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: reason.level.symbolName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(reason.level.color)
                        .padding(.top, 1)
                    Text(reason.message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.blue.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.blue.opacity(0.25), lineWidth: 1))
    }

    // MARK: List

    private var list: some View {
        VStack(alignment: .leading, spacing: 2) {
            if showsPreview {
                sectionLabel("Private")
                ChooserRow(
                    title: "Quick Preview",
                    subtitle: "Private window · nothing is saved",
                    badge: "P",
                    isFocused: isFocused(.preview),
                    tint: settings.tintColor,
                    action: choosePreview
                ) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(settings.tintColor.gradient)
                        .overlay(
                            Image(systemName: "eye.fill")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white)
                        )
                }
                .id("quick-preview")
            }

            if showsBrowsers {
                sectionLabel(showsPreview ? "Or open in" : "Open in")
                if isGrid {
                    browserGrid
                } else {
                ForEach(Array(browsers.enumerated()), id: \.element.id) { index, browser in
                    ChooserRow(
                        title: browser.name,
                        subtitle: browser.isRecognised ? nil : "Potentially unsupported",
                        subtitleTint: .orange,
                        badge: index < 9 ? "\(index + 1)" : nil,
                        isFocused: isFocused(.browser(index)),
                        tint: settings.tintColor,
                        action: { choose(browser) }
                    ) {
                        Image(nsImage: browser.icon)
                            .resizable()
                    }
                    .id(browser.id)
                    .help(browser.isRecognised ? "" : "BrowserLink doesn't recognise this app as a browser, so links may not open correctly in it.")
                }
                }
            }
        }
    }

    /// Icon tiles, up to four across.
    private var browserGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: gridColumns),
            spacing: 8
        ) {
            ForEach(Array(browsers.enumerated()), id: \.element.id) { index, browser in
                let focused = isFocused(.browser(index))
                Button(action: { choose(browser) }) {
                    VStack(spacing: 8) {
                        Image(nsImage: browser.icon)
                            .resizable()
                            .frame(width: 42, height: 42)
                        Text(browser.name)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(focused ? settings.tintColor.opacity(0.20) : Color.secondary.opacity(0.06))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(settings.tintColor.opacity(focused ? 0.7 : 0), lineWidth: 1.5)
                    }
                    .overlay(alignment: .topLeading) {
                        if index < 9 {
                            KeyHintBadge(key: "\(index + 1)").padding(6)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if !browser.isRecognised {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                                .padding(6)
                                .help("Potentially unsupported: BrowserLink doesn't recognise this app as a browser, so links may not open correctly in it.")
                                .accessibilityLabel("Potentially unsupported")
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressDimStyle())
                .id(browser.id)
                .accessibilityAddTraits(focused ? .isSelected : [])
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 3)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if rememberRowIsVisible {
                rememberRow
            }

            HStack(spacing: 14) {
                if !isLocked {
                    keyLegend(isGrid && showsBrowsers ? "↑↓←→" : "↑↓", "select")
                    keyLegend("↩", "open")
                }
                keyLegend("esc", "dismiss")
                Spacer(minLength: 8)
                Text(versionText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func keyLegend(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            KeyHintBadge(key: key)
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var rememberRow: some View {
        if let siteKey {
            Group {
                if let rememberedName, !didForget {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("\(siteKey) opens in \(rememberedName) automatically.")
                        Button("Forget") {
                            didForget = true
                            onForgetSite()
                        }
                        .buttonStyle(.link)
                    }
                } else {
                    Toggle("Remember my choice for \(siteKey)", isOn: $rememberThisSite)
                        .toggleStyle(.checkbox)
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(settings.tintColor, lineWidth: 2)
                    .opacity(isFocused(.remember) ? 1 : 0)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Choosing

    /// Opens the link in `browser`, first saving a rule if the box is ticked.
    private func choose(_ browser: InstalledBrowser) {
        if rememberThisSite, siteKey != nil { onRememberSite(browser.id) }
        onOpenIn(browser)
    }

    /// Same as `choose`, for the Quick Preview row and its P shortcut.
    private func choosePreview() {
        if rememberThisSite, siteKey != nil { onRememberSite(SiteKey.previewRule) }
        onPreview()
    }

    // MARK: Keyboard

    /// ↑ and ↓ walk through the list (Quick Preview, browsers, then the
    /// "remember" checkbox). Return or Space activates the highlighted row.
    /// Nothing is highlighted until a key is pressed, so a stray Return
    /// from whatever you were typing never opens anything.
    private func moveSelection(_ arrow: KeyCatcher.Arrow) {
        guard !isLocked else { return }
        let all = targets
        guard !all.isEmpty else { return }

        guard let index = focusIndex, all.indices.contains(index) else {
            // First key press: start at the top (down) or bottom (up).
            switch arrow {
            case .down, .right: focusIndex = 0
            case .up, .left: focusIndex = all.count - 1
            }
            return
        }

        if isGrid, case .browser(let b) = all[index] {
            moveInGrid(from: b, arrow, targets: all, index: index)
            return
        }

        switch arrow {
        case .down:
            // Entering the grid from above lands on its first tile.
            focusIndex = min(index + 1, all.count - 1)
        case .up:
            focusIndex = max(index - 1, 0)
        case .left, .right:
            break
        }
    }

    /// 2-D movement across the tiles; leaves the grid at its top and bottom edges.
    private func moveInGrid(from b: Int, _ arrow: KeyCatcher.Arrow, targets all: [FocusTarget], index: Int) {
        let count = browsers.count
        let columns = gridColumns
        func focus(browser i: Int) {
            if let pos = all.firstIndex(of: .browser(i)) { focusIndex = pos }
        }
        switch arrow {
        case .left:
            if b > 0 { focus(browser: b - 1) }
        case .right:
            if b + 1 < count { focus(browser: b + 1) }
        case .up:
            if b - columns >= 0 { focus(browser: b - columns) }
            else if let pos = all.firstIndex(of: .browser(0)), pos > 0 { focusIndex = pos - 1 }  // Quick Preview
        case .down:
            let lastRowStart = ((count - 1) / columns) * columns
            if b + columns < count { focus(browser: b + columns) }
            else if b < lastRowStart { focus(browser: count - 1) }   // short last row
            else if all.last == .remember { focusIndex = all.count - 1 }
        }
    }

    private func activateFocus() {
        guard !isLocked, let index = focusIndex, targets.indices.contains(index) else { return }
        switch targets[index] {
        case .preview:
            choosePreview()
        case .browser(let browserIndex):
            if browsers.indices.contains(browserIndex) { choose(browsers[browserIndex]) }
        case .remember:
            if rememberedName != nil, !didForget {
                didForget = true
                onForgetSite()
            } else {
                rememberThisSite.toggle()
            }
        }
    }
}

// MARK: - Height reporting

/// Each measured section adds its height; the total is what the panel wants.
private struct ChooserHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value += nextValue()
    }
}

private extension View {
    func reportsHeight() -> some View {
        background(
            GeometryReader { geometry in
                Color.clear.preference(key: ChooserHeightKey.self, value: geometry.size.height)
            }
        )
    }
}

// MARK: - Building blocks

/// One line in the list: icon, title, optional subtitle, and a key hint that
/// turns into ↩ while the row is highlighted by the keyboard.
private struct ChooserRow<Icon: View>: View {
    let title: String
    var subtitle: String? = nil
    var subtitleTint: Color = .secondary
    var badge: String? = nil
    let isFocused: Bool
    let tint: Color
    let action: () -> Void
    @ViewBuilder var icon: Icon

    @State private var isHovering = false

    private var fill: Color {
        if isFocused { return tint.opacity(0.20) }
        return isHovering ? Color.secondary.opacity(0.12) : Color.clear
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(subtitleTint)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if isFocused {
                    KeyHintBadge(key: "↩")
                } else if let badge {
                    KeyHintBadge(key: badge)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(tint.opacity(isFocused ? 0.7 : 0), lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressDimStyle())
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isFocused ? .isSelected : [])
    }
}

private struct PressDimStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// A small round icon button for the address bar.
private struct HeaderIconButton: View {
    let symbol: String
    let label: String
    var tint: Color = .secondary
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.secondary.opacity(isHovering ? 0.22 : 0.12)))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// A one-line grey notice with an optional button, used for the queue and
/// link-cleaning messages.
private struct NoticeRow: View {
    let symbol: String
    let text: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.secondary.opacity(0.08)))
    }
}

/// Small rounded label showing which key triggers an action.
struct KeyHintBadge: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(.secondary.opacity(0.15)))
            .accessibilityHidden(true)
    }
}

extension SafetyLevel {
    /// Level 1 red, level 2 yellow, level 3 blue.
    var color: Color {
        switch self {
        case .serious: return .red
        case .warning: return .yellow
        case .advisory: return .blue
        }
    }
}

// MARK: - Keyboard

/// Lets the panel catch Escape, arrows, Return/Space, 1–9 and P, since
/// SwiftUI-on-NSPanel doesn't get keyboard shortcuts for free.
struct KeyCatcher: NSViewRepresentable {
    let onEscape: () -> Void
    let onSelectIndex: (Int) -> Void   // 0-based index into browsers
    let onPreview: () -> Void
    let onArrow: (Arrow) -> Void
    let onReturn: () -> Void

    enum Arrow { case left, right, up, down }

    func makeNSView(context: Context) -> NSView {
        let view = EscapeCatchingView()
        apply(to: view)
        return view
    }

    /// Keep the callbacks current so they never act on stale values.
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? EscapeCatchingView else { return }
        apply(to: view)
    }

    private func apply(to view: EscapeCatchingView) {
        view.onEscape = onEscape
        view.onSelectIndex = onSelectIndex
        view.onPreview = onPreview
        view.onArrow = onArrow
        view.onReturn = onReturn
    }

    final class EscapeCatchingView: NSView {
        var onEscape: (() -> Void)?
        var onSelectIndex: ((Int) -> Void)?
        var onPreview: (() -> Void)?
        var onArrow: ((Arrow) -> Void)?
        var onReturn: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { // Escape
                onEscape?()
                return
            }

            // Everything else only when no ⌘/⌥/⌃ is held.
            guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
                super.keyDown(with: event)
                return
            }

            switch event.keyCode {
            case 123: onArrow?(.left); return
            case 124: onArrow?(.right); return
            case 125: onArrow?(.down); return
            case 126: onArrow?(.up); return
            case 36, 76, 49: onReturn?(); return   // Return, keypad Enter, Space
            default: break
            }

            guard let chars = event.charactersIgnoringModifiers else {
                super.keyDown(with: event)
                return
            }

            if let digit = Int(chars) {
                onSelectIndex?(digit - 1)
            } else if chars == "p" || chars == "P" {
                onPreview?()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
