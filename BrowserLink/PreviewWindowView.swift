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

    weak var webView: WKWebView?

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
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
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            viewModel.isLoading = false
            viewModel.canGoBack = webView.canGoBack
            viewModel.canGoForward = webView.canGoForward
            viewModel.currentURL = webView.url
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            viewModel.isLoading = false
        }

        // MARK: - Download Interception
        //
        // Any navigation that WebKit determines should be a download (based
        // on Content-Disposition headers or MIME type) routes through here
        // FIRST — before any bytes are written to disk. We pause it with a
        // confirmation prompt via the view model, which the SwiftUI layer
        // renders as an alert. Nothing downloads until the user explicitly
        // confirms.

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
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
