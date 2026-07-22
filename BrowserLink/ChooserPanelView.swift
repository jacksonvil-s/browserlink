import SwiftUI

/// The glass panel shown the instant a link is clicked anywhere on the system.
/// Design intent: translucent, adapts to system accent color, springy entrance,
/// disappears the instant a choice is made.
struct ChooserPanelView: View {
    let url: URL
    let browsers: [InstalledBrowser]
    let onPreview: () -> Void
    let onOpenIn: (InstalledBrowser) -> Void
    let onDismiss: () -> Void

    @State private var hasAppeared = false
    @State private var hasConfirmedDanger = false
    @StateObject private var faviconLoader = FaviconLoader()
    @Environment(\.colorScheme) private var colorScheme

    private var safetyResult: URLSafetyResult {
        URLSafetyChecker.check(url)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .opacity(0.15)

            ScrollView {
                if safetyResult.isSuspicious && !hasConfirmedDanger {
                    warningBanner
                }

                VStack(spacing: 14) {
                    previewOption

                    if !browsers.isEmpty {
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
                }
                .padding(24)
                .disabled(safetyResult.isSuspicious && !hasConfirmedDanger)
                .opacity(safetyResult.isSuspicious && !hasConfirmedDanger ? 0.35 : 1)
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
                    .fill(Color.accentColor.opacity(0.06))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
        .scaleEffect(hasAppeared ? 1 : 0.9)
        .opacity(hasAppeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                hasAppeared = true
            }
            faviconLoader.load(for: url)
        }
        // Dismiss on Escape.
        .background(
            KeyCatcher(onEscape: onDismiss)
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
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(Circle().fill(.secondary.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private var faviconPlaceholder: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(Color.accentColor.opacity(0.18))
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
                            .foregroundStyle(Color.accentColor)
                    }
                }
            )
    }

    // MARK: - Warning Banner

    private var warningBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("This link looks suspicious")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(safetyResult.reasons, id: \.self) { reason in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(.orange.opacity(0.6))
                            .frame(width: 4, height: 4)
                            .padding(.top, 6)
                        Text(reason)
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
                Text("I understand the risk — show me the options anyway")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.orange.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.orange.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    // MARK: - Preview Option (the primary, emphasized action)

    private var previewOption: some View {
        Button(action: onPreview) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.accentColor.gradient)
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
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
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
            ForEach(browsers) { browser in
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

    func makeNSView(context: Context) -> NSView {
        let view = EscapeCatchingView()
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class EscapeCatchingView: NSView {
        var onEscape: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { // Escape
                onEscape?()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
