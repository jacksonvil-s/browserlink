import XCTest
import AppKit
@testable import BrowserLink   // change this if your app target's module name differs

// Add this file to the same Unit Testing Bundle target as URLSafetyCheckerTests,
// then press ⌘U. None of these touch saved preferences.

// MARK: - LinkCleaner

final class LinkCleanerTests: XCTestCase {

    private func clean(_ string: String, strip: Bool = true, unwrap: Bool = true) -> LinkCleaner.Cleaned {
        guard let url = URL(string: string) else {
            XCTFail("Not a valid URL: \(string)")
            return LinkCleaner.Cleaned(original: URL(fileURLWithPath: "/"), url: URL(fileURLWithPath: "/"), note: nil)
        }
        return LinkCleaner.clean(url, stripTracking: strip, unwrapRedirects: unwrap)
    }

    func testStripsTrackingAndKeepsRealParameters() {
        let result = clean("https://example.com/a?utm_source=x&id=5&fbclid=abc")
        XCTAssertEqual(result.url.absoluteString, "https://example.com/a?id=5")
        XCTAssertEqual(result.note, "Removed tracking (utm_source, fbclid).")
    }

    func testRemovingEveryParameterLeavesNoQuestionMark() {
        XCTAssertEqual(clean("https://example.com/a?utm_source=x").url.absoluteString, "https://example.com/a")
    }

    func testKeptParametersAreNotReEncoded() {
        let result = clean("https://example.com/?q=a%20b%2Bc&utm_medium=x")
        XCTAssertEqual(result.url.absoluteString, "https://example.com/?q=a%20b%2Bc")
    }

    func testCleanLinkIsUntouched() {
        let result = clean("https://example.com/page?id=5")
        XCTAssertEqual(result.url, result.original)
        XCTAssertNil(result.note)
    }

    func testUnwrapsGoogleRedirect() {
        let result = clean("https://www.google.com/url?q=https%3A%2F%2Fexample.com%2Fpage&sa=U")
        XCTAssertEqual(result.url.absoluteString, "https://example.com/page")
        XCTAssertEqual(result.note, "Skipped the redirect through google.com.")
    }

    func testUnwrapsFacebookRedirect() {
        let result = clean("https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.com%2F&h=xyz")
        XCTAssertEqual(result.url.absoluteString, "https://example.com/")
    }

    func testUnwrapsNestedRedirects() {
        // Google wrapping a YouTube redirect wrapping example.com (double-encoded).
        let result = clean("https://www.google.com/url?q=https%3A%2F%2Fwww.youtube.com%2Fredirect%3Fq%3Dhttps%253A%252F%252Fexample.com")
        XCTAssertEqual(result.url.absoluteString, "https://example.com")
    }

    func testUnwrapsThenStrips() {
        let result = clean("https://www.google.com/url?q=https%3A%2F%2Fexample.com%2F%3Futm_source%3Dx")
        XCTAssertEqual(result.url.absoluteString, "https://example.com/")
        XCTAssertNotNil(result.note)
    }

    func testLookAlikeHostIsNotUnwrapped() {
        let result = clean("https://evilgoogle.com/url?q=https%3A%2F%2Fexample.com")
        XCTAssertEqual(result.url, result.original)
    }

    func testNonWebTargetIsNotUnwrapped() {
        let result = clean("https://www.google.com/url?q=javascript%3Aalert(1)")
        XCTAssertEqual(result.url, result.original)
    }

    func testSecurityRewritersAreLeftAlone() {
        let result = clean("https://nam01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fexample.com")
        XCTAssertEqual(result.url, result.original)
    }

    func testNonWebLinksAreLeftAlone() {
        let result = clean("mailto:someone@example.com?utm_source=x")
        XCTAssertEqual(result.url, result.original)
    }

    func testSwitchesTurnEachFeatureOff() {
        let wrapped = "https://www.google.com/url?q=https%3A%2F%2Fexample.com"
        XCTAssertEqual(clean(wrapped, unwrap: false).url.absoluteString, wrapped)
        let tracked = "https://example.com/?utm_source=x"
        XCTAssertEqual(clean(tracked, strip: false).url.absoluteString, tracked)
    }
}

// MARK: - SiteKey (per-site memory)

final class SiteKeyTests: XCTestCase {

    private func key(_ string: String) -> String? {
        guard let url = URL(string: string) else {
            XCTFail("Not a valid URL: \(string)")
            return nil
        }
        return SiteKey.key(for: url)
    }

    func testSubdomainsShareOneKey() {
        XCTAssertEqual(key("https://github.com/x"), "github.com")
        XCTAssertEqual(key("https://gist.github.com/x"), "github.com")
        XCTAssertEqual(key("https://a.b.c.example.com"), "example.com")
    }

    func testTwoPartSuffixes() {
        XCTAssertEqual(key("https://www.bbc.co.uk/news"), "bbc.co.uk")
        XCTAssertEqual(key("https://bbc.co.uk"), "bbc.co.uk")
        XCTAssertEqual(key("https://shop.example.com.au"), "example.com.au")
    }

    func testCaseAndPortAreIgnored() {
        XCTAssertEqual(key("https://GitHub.com"), "github.com")
        XCTAssertEqual(key("https://example.com:8080/x"), "example.com")
    }

    func testNoKeyForAddressesThatCantHaveRules() {
        for link in [
            "https://192.168.0.1", "https://8.8.8.8", "http://[::1]/",
            "https://localhost", "https://intranet",
            "mailto:x@example.com", "javascript:alert(1)",
            "file:///etc/passwd", "ftp://example.com"
        ] {
            XCTAssertNil(key(link), link)
        }
    }
}

// MARK: - BrowserDetector.ordered

final class BrowserOrderingTests: XCTestCase {

    private func browser(_ id: String) -> InstalledBrowser {
        InstalledBrowser(id: id, name: id, icon: NSImage(), url: URL(fileURLWithPath: "/Applications/\(id).app"), isRecognised: true)
    }

    private func ids(_ browsers: [InstalledBrowser]) -> [String] { browsers.map(\.id) }

    func testFollowsTheSavedOrder() {
        let result = BrowserDetector.ordered([browser("A"), browser("B"), browser("C")], by: ["C", "A", "B"])
        XCTAssertEqual(ids(result), ["C", "A", "B"])
    }

    func testNewBrowsersGoAtTheEndInTheirOriginalOrder() {
        let result = BrowserDetector.ordered([browser("A"), browser("B"), browser("C"), browser("D")], by: ["C"])
        XCTAssertEqual(ids(result), ["C", "A", "B", "D"])
    }

    func testUninstalledBrowsersInTheOrderAreIgnored() {
        let result = BrowserDetector.ordered([browser("A"), browser("B")], by: ["Gone", "B", "AlsoGone", "A"])
        XCTAssertEqual(ids(result), ["B", "A"])
    }

    func testEmptyOrderKeepsDetectionOrder() {
        let result = BrowserDetector.ordered([browser("A"), browser("B")], by: [])
        XCTAssertEqual(ids(result), ["A", "B"])
    }

    func testDuplicateDetectionsAppearOnce() {
        let result = BrowserDetector.ordered([browser("A"), browser("B"), browser("B")], by: ["B"])
        XCTAssertEqual(ids(result), ["B", "A"])
    }
}
