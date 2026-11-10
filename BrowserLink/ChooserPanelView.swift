import SwiftUI

/// The glass panel shown the instant a link is clicked anywhere on the system.
/// Design intent: translucent, adapts to system accent color, springy entrance,
/// disappears the instant a choice is made.
struct ChooserPanelView: View {
    let url: URL
    let browsers: [InstalledBrowser]
    let onPreview: () -> Void
    let onOpenIn: (InstalledBrowser) -> Void
    let onOpenPreferences: () -> Void
    let onDismiss: () -> Void
    
    
    @ObservedObject var linkQueue: LinkQueue
    let onDismissAll: () -> Void

    @State private var hasAppeared = false
    @State private var hasConfirmedDanger = false
    @StateObject private var faviconLoader = FaviconLoader()
    @ObservedObject private var settings = AppSettings.shared
    @State private var confirmSecondsLeft = 3
    @State private var pauseProgress: CGFloat = 0
    @State private var unlockBounce = false
    
    private var safetyResult: URLSafetyResult {
        URLSafetyChecker.check(url)
    }
    
    /// True while a level 1 or 2 warning is waiting for the user's confirmation.
    private var isLocked: Bool {
        safetyResult.requiresConfirmation && !hasConfirmedDanger
    }
    
    /// True when the 3-second pause applies to this link.
    private var pauseApplies: Bool {
        safetyResult.hasSeriousReason && AppSettings.shared.delaySevereConfirm
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

    /// Counts down once per second, then lets the button work.
    private func runConfirmPause() async {
        guard pauseApplies else { return }
        
        // One smooth sweep for the whole countdown.
        withAnimation(.linear(duration: Double(confirmSecondsLeft))) {
            pauseProgress = 1
        }
        
        while confirmSecondsLeft > 0 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return }
            confirmSecondsLeft -= 1
        }
        
        // Little "ready!" bounce when the button unlocks.
        withAnimation(.spring(response: 0.28, dampingFraction: 0.4)) { unlockBounce = true }
        try? await Task.sleep(nanoseconds: 150_000_000)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { unlockBounce = false }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .opacity(0.15)

            ScrollView {
                if !linkQueue.waiting.isEmpty || linkQueue.blockedCount > 0 {
                    queueNotice
                }
                
                if isLocked {
                    warningBanner
                }

                if !safetyResult.advisoryReasons.isEmpty {
                    advisoryNotice
                }

                VStack(spacing: 14) {
                    
                    if !browsers.isEmpty {
                        switch AppSettings.shared.appMode {
                        case .preview:
                            previewOption
                            Text("Note: browser chooser unavailable because it has been switched off.")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 8))
                        case .chooser:
                            Text("Open your link in:")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .fixedSize()
                            Rectangle().fill(.secondary.opacity(0.2)).frame(height: 1)
                            browserGrid
                            Text("Note: preview window unavailable because it has been switched off.")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 8))
                        case .both:
                            //Both shown
                            previewOption
                            
                            HStack(spacing: 8) {
                                Rectangle().fill(.secondary.opacity(0.2)).frame(height: 1)
                                Text("OR OPEN IN")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                                Rectangle().fill(.secondary.opacity(0.2)).frame(height: 1)
                            }
                            .padding(.vertical, 6)
                            
                            browserGrid
                        }
                    } else if browsers.isEmpty {
                        previewOption
                        Text("Note: browser chooser unavailable because we did not detect a browser on your system.")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 8))
                    }
                }
                .padding(24)
                .disabled(isLocked)
                .opacity(isLocked ? 0.35 : 1)
                
                var appVersion: String {
                    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
                }

                var buildNumber: String {
                    Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
                }
                
                Text("Version \(appVersion) (build \(buildNumber))")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
        }
        .background(
            ZStack {
                // Base liquid-glass material.
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
                // A very faint accent-tinted wash to make it feel "alive" and
                // tied to the system theme rather than generic gray glass.
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(settings.tintColor.opacity(0.06))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
        .onAppear {
            if AppSettings.shared.playSoundOnChooserAppear {
                if let url = Bundle.main.url(forResource: "pop", withExtension: "mp3") {
                    NSSound(contentsOf: url, byReference: true)?.play()
                }
            }
            faviconLoader.load(for: url)
        }
        // Dismiss on Escape, other keybinds.
        .background(
            KeyCatcher(
                onEscape: onDismiss,
                onSelectIndex: { index in
                    // Block shortcuts while the warning is still showing
                    if isLocked { return }
                    if index >= 0 && index < browsers.count {
                        onOpenIn(browsers[index])
                    }
                },
                onPreview: {
                    // Same check for the Preview shortcut
                    if isLocked { return }
                    onPreview()
                }
            )
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            faviconPlaceholder
            VStack(alignment: .leading, spacing: 3) {
                Text(url.host ?? url.absoluteString)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                Text(url.absoluteString)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            HStack(spacing: 8) {
                Button(action: onOpenPreferences) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Circle().fill(.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("Preferences…")

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Circle().fill(.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private var faviconPlaceholder: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(settings.tintColor.opacity(0.18))
            .frame(width: 42, height: 42)
            .overlay(
                Group {
                    if let favicon = faviconLoader.image {
                        Image(nsImage: favicon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(settings.tintColor)
                    }
                }
            )
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

    private var queueNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(queueNoticeText)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Dismiss all", action: onDismissAll)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    // MARK: - Warning Banner

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
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
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

            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    hasConfirmedDanger = true
                }
            }) {
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
                            if isWaitingToConfirm {
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
            .animation(.easeInOut(duration: 0.3), value: isWaitingToConfirm)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tint.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .task { await runConfirmPause() }
    }

    // MARK: - Gentle notice (level 3)

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
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.blue.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.blue.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    // MARK: - Preview Option (the primary, emphasized action)

    private var previewOption: some View {
        Button(action: onPreview) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(settings.tintColor.gradient)
                        .frame(width: 50, height: 50)
                    Image(systemName: "eye.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Quick Preview")
                        .font(.system(size: 16.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Opens instantly · nothing is saved")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                KeyHintBadge(key: "P")
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(settings.tintColor.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(settings.tintColor.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(HoverScaleButtonStyle())
    }

    // MARK: - Browser Grid

    private var browserGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: min(browsers.count, 4)),
            spacing: 10
        ) {
            ForEach(Array(browsers.enumerated()), id: \.element.id) { index, browser in
                Button(action: { onOpenIn(browser) }) {
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
                            .fill(.secondary.opacity(0.06))
                    )
                    .overlay(alignment: .topLeading) {
                        // Only 1–9 work as shortcuts (one keypress each).
                        if index < 9 {
                            KeyHintBadge(key: "\(index + 1)")
                                .padding(6)
                        }
                    }
                }
                .buttonStyle(HoverScaleButtonStyle())
            }
        }
    }
    
    
}

/// Subtle hover + press scale feedback, used across the chooser buttons.
struct HoverScaleButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : (isHovering ? 1.02 : 1.0))
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

/// Tiny NSViewRepresentable that lets us catch the Escape key to dismiss the panel,
/// since SwiftUI-on-NSPanel doesn't get keyboard shortcuts for free the way a normal
/// window/sheet does.
struct KeyCatcher: NSViewRepresentable {
    let onEscape: () -> Void
    let onSelectIndex: (Int) -> Void   // new: 0-based index into browsers
    let onPreview: () -> Void          // new

    func makeNSView(context: Context) -> NSView {
        let view = EscapeCatchingView()
        view.onEscape = onEscape
        view.onSelectIndex = onSelectIndex
        view.onPreview = onPreview
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class EscapeCatchingView: NSView {
        var onEscape: (() -> Void)?
        var onSelectIndex: ((Int) -> Void)?
        var onPreview: (() -> Void)?

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

            guard let chars = event.charactersIgnoringModifiers else {
                super.keyDown(with: event)
                return
            }
            
            guard event.modifierFlags.intersection([.command, .option, .control]) .isEmpty else {
                super.keyDown(with: event)
                return
            }
            
            if let digit = Int(chars) {
                onSelectIndex?(digit - 1) //Index
            } else if chars == "p" || chars == "P" {
                onPreview?() //Preview
            } else {
                super.keyDown(with: event) //else
            }

        }
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
