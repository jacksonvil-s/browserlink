import Foundation

/// What BrowserLink can and can't do with a given kind of link. Kept in one
/// place so the chooser and AppDelegate always agree.
enum LinkSupport {

    private static let htmlExtensions: Set<String> = ["html", "htm", "xhtml"]

    /// A local .html file, e.g. opened from Finder. Harmless, so the chooser
    /// doesn't show the "dangerous file: link" warning for these.
    static func isLocalHTMLFile(_ url: URL) -> Bool {
        url.isFileURL && htmlExtensions.contains(url.pathExtension.lowercased())
    }

    /// Why Quick Preview can't open this link, or nil if it can.
    ///   - http:  Quick Preview refuses unencrypted pages (App Transport Security).
    ///   - file:  the sandbox can't read files outside the app.
    ///   - other: Quick Preview only shows web pages.
    static func previewUnavailableReason(for url: URL) -> String? {
        switch url.scheme?.lowercased() {
        case "https":
            return nil
        case "http":
            return "Quick Preview needs a secure (https) link."
        case "file":
            return "Quick Preview can't open files on your Mac."
        default:
            return "Quick Preview only opens web links."
        }
    }
}
