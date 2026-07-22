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

    @StateObject private var viewModel = PreviewViewModel()
    @State private var showBrowserMenu = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.15)
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
        }
        .background(.regularMaterial)
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
                Button(action: {
                    viewModel.retryOriginalLoad(url)
                }) {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .font(.system(size: 12.5, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)

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
                toolbarButton(icon: "chevron.left", enabled: viewModel.canGoBack) {
                    viewModel.goBack()
                }
                toolbarButton(icon: "chevron.right", enabled: viewModel.canGoForward) {
                    viewModel.goForward()
                }
                toolbarButton(icon: "arrow.clockwise", enabled: true) {
                    viewModel.reload()
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(viewModel.currentURL?.host ?? url.host ?? "")
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(.secondary.opacity(0.1))
            )
            .frame(maxWidth: .infinity)

            HStack(spacing: 6) {
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
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var ephemeralBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 9))
            Text("Ephemeral")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color.accentColor.opacity(0.14))
        )
    }

    private func toolbarButton(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(enabled ? .primary : .tertiary)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - View Model

final class PreviewViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var currentURL: URL?

    /// Set when a download is attempted, triggering a confirmation alert
    /// before anything is written to disk.
    @Published var pendingDownload: PendingDownload?

    /// Set whenever loading fails — either a transport-level failure (no
    /// internet, DNS failure, timeout) or an HTTP error status code (404,
    /// 503, etc). Previously these failed silently with a blank window;
    /// now they populate this and the view shows a real error screen.
    @Published var loadError: PreviewLoadError?

    weak var webView: WKWebView?

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() {
        loadError = nil
        webView?.reload()
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
                message: "This domain doesn't seem to exist, or there was a problem resolving it.",
                systemImage: "questionmark.circle"
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
                message: "\(host) is refusing to show this page — you may need to log in or lack permission.",
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
        webView.allowsBackForwardNavigationGestures = true
        viewModel.webView = webView

        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKDownloadDelegate {
        let viewModel: PreviewViewModel

        init(viewModel: PreviewViewModel) {
            self.viewModel = viewModel
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            viewModel.isLoading = true
            viewModel.loadError = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            viewModel.isLoading = false
            viewModel.canGoBack = webView.canGoBack
            viewModel.canGoForward = webView.canGoForward
            viewModel.currentURL = webView.url
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            viewModel.isLoading = false
            if (error as NSError).code != NSURLErrorCancelled {
                viewModel.loadError = .transport(error)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
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
            if (error as NSError).code != NSURLErrorCancelled {
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
            if let httpResponse = navigationResponse.response as? HTTPURLResponse,
               httpResponse.statusCode >= 400 {
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
                        guard confirmed else {
                            completionHandler(nil) // cancels the download entirely
                            return
                        }
                        // User confirmed — save to their actual Downloads folder,
                        // exactly like a normal browser would.
                        let downloadsDir = FileManager.default.urls(
                            for: .downloadsDirectory,
                            in: .userDomainMask
                        ).first
                        let destination = downloadsDir?.appendingPathComponent(suggestedFilename)
                        completionHandler(destination)
                    }
                )
            }
        }
    }
}
