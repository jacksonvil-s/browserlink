import SwiftUI
import WebKit
import Combine

/// The quick-preview window. Uses an ephemeral (non-persistent) WKWebView data store,
/// meaning cookies/cache/localStorage/history are held only in memory and vanish
/// completely the moment this window closes — nothing touches disk.
struct PreviewWindowView: View {
    let url: URL
    let onOpenInRealBrowser: (InstalledBrowser) -> Void
    let onClose: () -> Void
    /// Reports the page title so the window can carry it (Mission Control, VoiceOver).
    let onTitleChange: (String) -> Void

    @StateObject private var viewModel = PreviewViewModel()
    @ObservedObject private var settings = AppSettings.shared
    @State private var didCopyAddress = false
    @FocusState private var findFieldFocused: Bool
    
    /// True only when the page being shown is loaded over https.
    private var isSecureConnection: Bool {
        (viewModel.currentURL ?? url).scheme?.lowercased() == "https"
    }

    private var downloadErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.downloadError != nil },
            set: { if !$0 { viewModel.downloadError = nil } }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.15)
            if viewModel.isFindBarVisible {
                findBar
                Divider().opacity(0.15)
            }
            ZStack {
                WebView(url: url, viewModel: viewModel)

                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 6)
                        .frame(maxHeight: .infinity, alignment: .top)
                }

                if let error = viewModel.loadError {
                    errorOverlay(error)
                }
            }
            .alert("Download Failed", isPresented: downloadErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.downloadError ?? "")
            }
        }
        .background(.regularMaterial)
        .background(shortcutButtons)
        .onReceive(viewModel.$title) { onTitleChange($0) }
        .alert(item: $viewModel.pendingDownload) { pending in
            let sourceHost = pending.sourceURL?.host ?? "this site"
            return Alert(
                title: Text("Download \"\(pending.suggestedFilename)\"?"),
                message: Text("This file is from \(sourceHost). Only download files from sites you trust — downloaded files are saved to your Downloads folder and are NOT covered by this window's ephemeral/private browsing."),
                primaryButton: .destructive(Text("Download")) {
                    pending.decisionHandler(true)
                },
                secondaryButton: .cancel(Text("Cancel")) {
                    pending.decisionHandler(false)
                }
            )
        }
    }
    
    // MARK: Find bar, zoom and shortcuts

    private func showFindBar() {
        viewModel.isFindBarVisible = true
        DispatchQueue.main.async { findFieldFocused = true }
    }

    private var findBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find in page", text: $viewModel.findText)
                .textFieldStyle(.plain)
                .focused($findFieldFocused)
                .onSubmit { viewModel.find(forward: true) }   // Return = next match
                .onExitCommand { viewModel.closeFind() }      // Esc = close
            if viewModel.findNotFound {
                Text("Not found")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
            }
            toolbarButton(icon: "chevron.up", label: "Previous Match", enabled: !viewModel.findText.isEmpty) {
                viewModel.find(forward: false)
            }
            toolbarButton(icon: "chevron.down", label: "Next Match", enabled: !viewModel.findText.isEmpty) {
                viewModel.find(forward: true)
            }
            Button("Done") { viewModel.closeFind() }
                .buttonStyle(.borderless)
                .font(.system(size: 12, weight: .medium))
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    /// Shows the zoom level only when it isn't 100%. Click to reset.
    @ViewBuilder
    private var zoomBadge: some View {
        if abs(viewModel.zoom - 1) > 0.001 {
            let percent = Int((viewModel.zoom * 100).rounded())
            Button { viewModel.resetZoom() } label: {
                Text("\(percent)%")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.secondary.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .help("Zoom \(percent)%. Click to reset (⌘0).")
            .accessibilityLabel("Zoom \(percent) percent. Reset")
        }
    }

    /// Invisible buttons that only exist to carry keyboard shortcuts.
    private var shortcutButtons: some View {
        Group {
            Button("Find") { showFindBar() }
                .keyboardShortcut("f", modifiers: .command)
            Button("Find Next") { viewModel.find(forward: true) }
                .keyboardShortcut("g", modifiers: .command)
            Button("Find Previous") { viewModel.find(forward: false) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Button("Zoom In") { viewModel.zoomIn() }
                .keyboardShortcut("=", modifiers: .command)
            Button("Zoom In Plus") { viewModel.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
            Button("Zoom Out") { viewModel.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { viewModel.resetZoom() }
                .keyboardShortcut("0", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var displayedURL: URL { viewModel.currentURL ?? url }

    /// The address with the host in bold and everything else dimmed, so a long
    /// path can't push the real host out of view. "https://" is left out (the
    /// lock icon shows it), but a "user@" part is kept visible on purpose.
    private var addressText: Text {
        var full = displayedURL.absoluteString
        if let scheme = full.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) {
            full.removeSubrange(scheme)
        }

        // Find the host inside the authority part only (before the first / ? #),
        // searching from the end so a "host@host" trick bolds the REAL host.
        let authorityEnd = full.firstIndex(where: { "/?#".contains($0) }) ?? full.endIndex
        guard let host = displayedURL.host,
              let range = full[..<authorityEnd].range(of: host, options: [.caseInsensitive, .backwards]) else {
            return Text(full).foregroundStyle(.secondary)
        }
        return Text(full[..<range.lowerBound]).foregroundStyle(.secondary)
            + Text(full[range]).fontWeight(.semibold)
            + Text(full[range.upperBound...]).foregroundStyle(.secondary)
    }

    private func copyAddress() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(displayedURL.absoluteString, forType: .string)
        didCopyAddress = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            didCopyAddress = false
        }
    }

    private func errorOverlay(_ error: PreviewLoadError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: error.systemImage)
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.orange)

            VStack(spacing: 6) {
                Text(error.title)
                    .font(.system(size: 18, weight: .semibold))
                Text(error.message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)
            }

            HStack(spacing: 10) {
                if error.canRetry {
                    Button{
                        viewModel.retryOriginalLoad(url)
                    } label: {
                        Label("Try Again", systemImage: "arrow.clockwise")
                            .font(.system(size: 12.5, weight: .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Menu {
                    ForEach(BrowserDetector.installedBrowsers()) { browser in
                        Button(browser.name) {
                            onOpenInRealBrowser(browser)
                        }
                    }
                } label: {
                    Label("Open in Browser Instead", systemImage: "arrow.up.forward.app")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
        )
        .padding(40)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                toolbarButton(icon: "chevron.left", label: "Back", enabled: viewModel.canGoBack) {
                    viewModel.goBack()
                }
                toolbarButton(icon: "chevron.right", label: "Forward", enabled: viewModel.canGoForward) {
                    viewModel.goForward()
                }
                toolbarButton(icon: "arrow.clockwise", label: "Reload", enabled: true) {
                    viewModel.reload()
                }
            }

            HStack(spacing: 6) {
                Image(systemName: isSecureConnection ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(isSecureConnection ? Color.secondary : Color.red)
                addressText
                    .font(.system(size: 11.5))
                    .lineLimit(1)
                    .truncationMode(.tail)   // tail, so the host at the front is never the part that gets cut
                    .help(displayedURL.absoluteString)
                Button(action: copyAddress) {
                    Image(systemName: didCopyAddress ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(didCopyAddress ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy link")
                .accessibilityLabel(didCopyAddress ? "Link copied" : "Copy link")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(.secondary.opacity(0.1))
            )
            .frame(maxWidth: .infinity)

            HStack(spacing: 6) {
                toolbarButton(icon: "magnifyingglass", label: "Find in Page (⌘F)", enabled: true) {
                    showFindBar()
                }
                zoomBadge
                jsToggle
                ephemeralBadge

                Menu {
                    ForEach(BrowserDetector.installedBrowsers()) { browser in
                        Button(browser.name) {
                            onOpenInRealBrowser(browser)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 12, weight: .medium))
                        .accessibilityLabel("Open in another browser")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Open in another browser")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Turns page JavaScript on/off for this preview (and reloads). Starts
    /// from the "Allow JavaScript in Quick Preview" preference.
    private var jsToggle: some View {
        let on = viewModel.javaScriptEnabled
        let tint: Color = on ? .secondary : .orange
        return Button {
            viewModel.setJavaScriptEnabled(!on)
        } label: {
            Text("JS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .strikethrough(!on)
                .foregroundStyle(tint)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Capsule().fill(tint.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .help(on ? "JavaScript is on. Click to turn it off and reload." : "JavaScript is off. Click to turn it on and reload.")
        .accessibilityLabel("JavaScript")
        .accessibilityValue(on ? "On" : "Off")
    }

    private var ephemeralBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 9))
            Text("Ephemeral")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(settings.tintColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(settings.tintColor.opacity(0.14))
        )
    }

    private func toolbarButton(icon: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(enabled ? .primary : .tertiary)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .help(label)
    }
}

// MARK: - View Model

final class PreviewViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var currentURL: URL?
    @Published var title = ""

    /// Starts from the preference; the toolbar's JS button flips it per preview.
    @Published var javaScriptEnabled = AppSettings.shared.previewJavaScriptEnabled

    /// Set when a download fails, triggering an error alert.
    @Published var downloadError: String?

    /// Set when a download is attempted, triggering a confirmation alert
    /// before anything is written to disk.
    @Published var pendingDownload: PendingDownload?

    /// Set whenever loading fails — either a transport-level failure (no
    /// internet, DNS failure, timeout) or an HTTP error status code (404,
    /// 503, etc). Previously these failed silently with a blank window;
    /// now they populate this and the view shows a real error screen.
    @Published var loadError: PreviewLoadError?

    // MARK: Find in page and zoom

    @Published var isFindBarVisible = false
    @Published var findText = ""
    @Published var findNotFound = false
    /// Page zoom for this preview (1.0 = 100%).
    @Published var zoom: CGFloat = 1.0

    private static let zoomSteps: [CGFloat] = [0.5, 0.67, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

    func zoomIn() {
        if let next = Self.zoomSteps.first(where: { $0 > zoom + 0.001 }) { setZoom(next) }
    }
    func zoomOut() {
        if let previous = Self.zoomSteps.last(where: { $0 < zoom - 0.001 }) { setZoom(previous) }
    }
    func resetZoom() { setZoom(1.0) }

    private func setZoom(_ value: CGFloat) {
        zoom = value
        webView?.pageZoom = value
    }

    /// Finds the next (or previous) match, wrapping around at the ends.
    func find(forward: Bool = true) {
        guard let webView, !findText.isEmpty else { findNotFound = false; return }
        let configuration = WKFindConfiguration()
        configuration.backwards = !forward
        configuration.wraps = true
        configuration.caseSensitive = false
        webView.find(findText, configuration: configuration) { [weak self] result in
            DispatchQueue.main.async { self?.findNotFound = !result.matchFound }
        }
    }

    func closeFind() {
        isFindBarVisible = false
        findText = ""
        findNotFound = false
        webView?.evaluateJavaScript("window.getSelection().removeAllRanges()", completionHandler: nil)
        webView?.window?.makeFirstResponder(webView)   // give the keyboard back to the page
    }
    
    weak var webView: WKWebView?

    /// KVO (Key-Value Observing) lets WebKit tell us the moment one of its
    /// properties changes. WKWebView updates `url`, `title`, `canGoBack` and
    /// `canGoForward` itself, so we subscribe instead of copying them by hand
    /// at "page finished" time (which left the lock icon and Back button stale
    /// during redirects and in-page navigation).
    private var observers = Set<AnyCancellable>()

    func attach(_ webView: WKWebView) {
        self.webView = webView
        observers.removeAll()

        // receive(on:) defers delivery a tick, which keeps SwiftUI from
        // complaining about state changes while a view is being built.
        webView.publisher(for: \.url)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.currentURL = $0 }
            .store(in: &observers)
        webView.publisher(for: \.title)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.title = $0 ?? "" }
            .store(in: &observers)
        webView.publisher(for: \.canGoBack)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canGoBack = $0 }
            .store(in: &observers)
        webView.publisher(for: \.canGoForward)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canGoForward = $0 }
            .store(in: &observers)
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() {
        loadError = nil
        webView?.reload()
    }

    /// The Coordinator applies this on the next navigation, so reloading is
    /// what makes the change take effect.
    func setJavaScriptEnabled(_ enabled: Bool) {
        javaScriptEnabled = enabled
        reload()
    }

    /// Retries the ORIGINAL url, not just webView.reload() — important
    /// because reload() on a page that never successfully loaded (e.g. a
    /// DNS failure) can sometimes no-op rather than actually retry.
    func retryOriginalLoad(_ url: URL) {
        loadError = nil
        webView?.load(URLRequest(url: url))
    }
}

/// Describes why a page failed to load, in language a non-technical person
/// can act on — not a raw NSError dump.
struct PreviewLoadError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let systemImage: String
    /// False when retrying can't possibly help (e.g. a blocked insecure site).
    var canRetry = true

    static func transport(_ error: Error) -> PreviewLoadError {
        let nsError = error as NSError

        // Common, human-meaningful transport failures.
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet:
            return PreviewLoadError(
                title: "No Internet Connection",
                message: "Your Mac doesn't appear to be connected to the internet right now.",
                systemImage: "wifi.slash"
            )
        case NSURLErrorTimedOut:
            return PreviewLoadError(
                title: "Connection Timed Out",
                message: "The site took too long to respond. It may be down, or your connection may be slow right now.",
                systemImage: "clock.badge.exclamationmark"
            )
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return PreviewLoadError(
                title: "Site Can't Be Found",
                message: "This domain doesn't seem to exist, or there was a problem resolving it. (DNS error)",
                systemImage: "questionmark.circle"
            )
        case NSURLErrorAppTransportSecurityRequiresSecureConnection:
            return PreviewLoadError(
                title: "Insecure Site Blocked",
                message: "This link uses plain http://, which Quick Preview won't load because anything sent or received could be read by others on the network. You can open it in a regular browser instead.",
                systemImage: "lock.open.fill",
                canRetry: false
            )
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted:
            return PreviewLoadError(
                title: "Secure Connection Failed",
                message: "This site's security certificate couldn't be verified. Proceed with caution if you choose to open it in a real browser instead.",
                systemImage: "lock.trianglebadge.exclamationmark"
            )
        default:
            return PreviewLoadError(
                title: "Couldn't Load Page",
                message: nsError.localizedDescription,
                systemImage: "exclamationmark.triangle"
            )
        }
    }

    static func httpStatus(_ code: Int, url: URL?) -> PreviewLoadError {
        let host = url?.host ?? "This site"
        switch code {
        case 404:
            return PreviewLoadError(
                title: "Page Not Found (404)",
                message: "\(host) says this page doesn't exist. It may have been moved or removed.",
                systemImage: "questionmark.folder"
            )
        case 403:
            return PreviewLoadError(
                title: "Access Denied (403)",
                message: "\(host) is refusing to show this page — you lack permission.",
                systemImage: "lock.fill"
            )
        case 401:
            return PreviewLoadError(
                title: "Authentication needed (401)",
                message: "\(host) requires authentication from your end. You might need to sign in",
                systemImage: "lock.fill"
            )
        case 500, 502, 503, 504:
            return PreviewLoadError(
                title: "Server Error (\(code))",
                message: "\(host) is having server problems right now. This usually isn't something on your end — try again in a bit.",
                systemImage: "server.rack"
            )
        default:
            return PreviewLoadError(
                title: "Error \(code)",
                message: "\(host) returned an error loading this page.",
                systemImage: "exclamationmark.triangle"
            )
        }
    }
}

/// Represents a download the user hasn't yet confirmed or rejected.
struct PendingDownload: Identifiable {
    let id = UUID()
    let suggestedFilename: String
    let sourceURL: URL?
    let decisionHandler: (Bool) -> Void
}

// MARK: - WKWebView Bridge

struct WebView: NSViewRepresentable {
    let url: URL
    @ObservedObject var viewModel: PreviewViewModel

    func makeNSView(context: Context) -> WKWebView {
        // The critical line: .nonPersistent() means this session's cookies,
        // cache, and local storage live only in RAM. Closing the window and
        // deallocating this WKWebView erases it completely — nothing is
        // written to disk, ever, for this preview.
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        viewModel.attach(webView)

        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKDownloadDelegate, WKUIDelegate {
        let viewModel: PreviewViewModel
        /// Where each in-flight download is being saved, so "reveal in Finder"
        /// points at the real (possibly renamed) file.
        private var downloadDestinations: [ObjectIdentifier: URL] = [:]

        /// Error statuses whose page body is still worth showing: login
        /// prompts, rate-limit pages and Cloudflare-style challenge pages
        /// (which arrive as 403/503) all need to render to be usable.
        private static let statusesThatStillRender: Set<Int> = [401, 403, 429, 503]

        init(viewModel: PreviewViewModel) {
            self.viewModel = viewModel
        }
        
        // MARK: Page dialogs and file pickers
        //
        // WKWebView ignores JavaScript alert()/confirm()/prompt() and
        // <input type="file"> unless we implement these. Dialogs are titled
        // with the page's host so a page can't pass one off as a system message,
        // and each has a "don't allow more dialogs" box so a page can't trap you
        // in a loop.

        /// Set when the user ticks "don't allow more dialogs"; cleared on the next page load.
        private var dialogsSuppressed = false

        private func makeAlert(message: String, frame: WKFrameInfo, buttons: [String]) -> NSAlert {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "\(frame.request.url?.host ?? "This page") says:"
            alert.informativeText = message
            for title in buttons { alert.addButton(withTitle: title) }
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Don't allow this page to show more dialogs"
            return alert
        }

        /// Shows the alert as a sheet on the preview window (or modally if the
        /// window is gone) and always calls `completion` exactly once.
        private func show(_ alert: NSAlert, in webView: WKWebView, completion: @escaping (NSApplication.ModalResponse) -> Void) {
            if let window = webView.window {
                alert.beginSheetModal(for: window) { [weak self] response in
                    if alert.suppressionButton?.state == .on { self?.dialogsSuppressed = true }
                    completion(response)
                }
            } else {
                let response = alert.runModal()
                if alert.suppressionButton?.state == .on { dialogsSuppressed = true }
                completion(response)
            }
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            guard !dialogsSuppressed else { completionHandler(); return }
            show(makeAlert(message: message, frame: frame, buttons: ["OK"]), in: webView) { _ in
                completionHandler()
            }
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            guard !dialogsSuppressed else { completionHandler(false); return }
            show(makeAlert(message: message, frame: frame, buttons: ["OK", "Cancel"]), in: webView) { response in
                completionHandler(response == .alertFirstButtonReturn)
            }
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (String?) -> Void
        ) {
            guard !dialogsSuppressed else { completionHandler(nil); return }
            let alert = makeAlert(message: prompt, frame: frame, buttons: ["OK", "Cancel"])
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
            field.stringValue = defaultText ?? ""
            alert.accessoryView = field
            show(alert, in: webView) { response in
                completionHandler(response == .alertFirstButtonReturn ? field.stringValue : nil)
            }
        }

        /// File upload buttons. Needs the "User Selected File: Read Only"
        /// sandbox entitlement (com.apple.security.files.user-selected.read-only).
        func webView(
            _ webView: WKWebView,
            runOpenPanelWith parameters: WKOpenPanelParameters,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping ([URL]?) -> Void
        ) {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = parameters.allowsMultipleSelection
            panel.canChooseDirectories = parameters.allowsDirectories
            panel.canChooseFiles = true
            panel.message = "\(frame.request.url?.host ?? "This page") is asking for a file. Only choose files you want to share with it."

            let finish: (NSApplication.ModalResponse) -> Void = { response in
                completionHandler(response == .OK ? panel.urls : nil)
            }
            if let window = webView.window {
                panel.beginSheetModal(for: window, completionHandler: finish)
            } else {
                finish(panel.runModal())
            }
        }

        /// Called when a page tries to open a link in a new tab/window
        /// (target="_blank" or window.open). Preview has no tabs, so we
        /// load it in the same window instead.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
        
        /// Errors that are expected when a page turns into a download.
        /// They aren't real failures, so we don't show an error screen.
        private func isIgnorableError(_ error: Error) -> Bool {
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled { return true }
            // 102 = "Frame load interrupted", sent when a load becomes a download
            if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return true }
            return false
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            viewModel.isLoading = true
            viewModel.loadError = nil
            dialogsSuppressed = false   // a new page gets a fresh start
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            viewModel.isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            viewModel.isLoading = false
            if !isIgnorableError(error) {
                viewModel.loadError = .transport(error)
            }
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            // This is the one that was silently swallowing failures before —
            // didFailProvisionalNavigation fires for failures that happen
            // BEFORE any content starts loading (no internet, DNS failure,
            // connection refused), which is the most common real-world case.
            // The old code had no handler for this at all.
            //
            // NSURLErrorCancelled is filtered out because WebKit legitimately
            // cancels its own provisional navigation when a response turns
            // into a download (see decidePolicyFor below) — that's expected
            // behavior, not a real failure, and shouldn't show an error screen.
            viewModel.isLoading = false
            if !isIgnorableError(error) {
                viewModel.loadError = .transport(error)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            // Check for HTTP-level error status codes. These are NOT
            // transport failures from WebKit's point of view — the server
            // DID respond, just with an error — so didFail never fires for
            // these. Previously this meant a 404 or 503 just rendered
            // whatever (often blank) HTML the server sent, with zero
            // explanation to the user.
            // Only the page itself decides whether we show an error screen.
            // This is also called for iframes/ads, and a 404 on one of those
            // must not blank the whole window.
            guard navigationResponse.isForMainFrame else {
                decisionHandler(navigationResponse.canShowMIMEType ? .allow : .cancel)
                return
            }

            if let httpResponse = navigationResponse.response as? HTTPURLResponse,
               httpResponse.statusCode >= 400,
               !Self.statusesThatStillRender.contains(httpResponse.statusCode) {
                DispatchQueue.main.async {
                    self.viewModel.isLoading = false
                    self.viewModel.loadError = .httpStatus(
                        httpResponse.statusCode,
                        url: httpResponse.url
                    )
                }
                decisionHandler(.cancel)
                return
            }

            if navigationResponse.canShowMIMEType {
                decisionHandler(.allow)
            } else {
                // WebKit can't render this inline, meaning it's very likely
                // a file WebKit would otherwise silently start downloading.
                decisionHandler(.download)
            }
        }

        func webView(
            _ webView: WKWebView,
            navigationResponse: WKNavigationResponse,
            didBecome download: WKDownload
        ) {
            download.delegate = self
        }
        
        /// Applies the JavaScript on/off choice to each navigation.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            preferences: WKWebpagePreferences,
            decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
        ) {
            preferences.allowsContentJavaScript = viewModel.javaScriptEnabled
            decisionHandler(.allow, preferences)
        }

        /// Downloads that start from a link/navigation (e.g. <a download>)
        /// rather than from a response.
        func webView(
            _ webView: WKWebView,
            navigationAction: WKNavigationAction,
            didBecome download: WKDownload
        ) {
            download.delegate = self
        }

        func downloadDidFinish(_ download: WKDownload) {
            guard let destination = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
            guard AppSettings.shared.revealDownloadsInFinder else { return }
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
            // Declining the confirmation alert cancels the download; that's
            // the user's choice, not a failure.
            if (error as NSError).code == NSURLErrorCancelled { return }
            DispatchQueue.main.async {
                self.viewModel.downloadError = error.localizedDescription
            }
        }

        /// WKDownload fails outright if a file already exists at the
        /// destination, so pick "name (1).ext", "name (2).ext", … instead.
        private static func uniqueDestination(for suggestedFilename: String, in directory: URL) -> URL {
            let fileManager = FileManager.default
            let cleanName = (suggestedFilename as NSString).lastPathComponent
            let name = cleanName.isEmpty ? "download" : cleanName

            var candidate = directory.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

            let stem = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            var counter = 1
            repeat {
                let numbered = ext.isEmpty ? "\(stem) (\(counter))" : "\(stem) (\(counter)).\(ext)"
                candidate = directory.appendingPathComponent(numbered)
                counter += 1
            } while fileManager.fileExists(atPath: candidate.path)
            return candidate
        }

        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String,
            completionHandler: @escaping (URL?) -> Void
        ) {
            DispatchQueue.main.async {
                self.viewModel.pendingDownload = PendingDownload(
                    suggestedFilename: suggestedFilename,
                    sourceURL: response.url,
                    decisionHandler: { confirmed in
                        guard confirmed,
                              let downloadsDir = FileManager.default.urls(
                                for: .downloadsDirectory,
                                in: .userDomainMask
                              ).first else {
                            completionHandler(nil) // cancels the download entirely
                            return
                        }
                        // User confirmed — save to their actual Downloads folder,
                        // exactly like a normal browser would, never overwriting.
                        let destination = Self.uniqueDestination(for: suggestedFilename, in: downloadsDir)
                        self.downloadDestinations[ObjectIdentifier(download)] = destination
                        completionHandler(destination)
                    }
                )
            }
        }
    }
}
