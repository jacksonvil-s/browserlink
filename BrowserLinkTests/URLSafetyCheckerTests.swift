import XCTest
@testable import BrowserLink   // change this if your app target's module name differs

/// Automated checks for URLSafetyChecker. Add this file to a Unit Testing
/// Bundle target (File → New → Target → Unit Testing Bundle), then press ⌘U.
///
/// Every test passes an explicit `SafetySettings`, so results never depend on
/// the preferences saved on the machine running them.
final class URLSafetyCheckerTests: XCTestCase {

    // MARK: - Helpers

    private func result(_ string: String, _ settings: SafetySettings = .allOn) -> URLSafetyResult {
        guard let url = URL(string: string) else {
            XCTFail("Not a valid URL: \(string)")
            return .safe
        }
        return URLSafetyChecker.check(url, settings: settings)
    }

    /// The most serious finding for a link, or nil if it's completely clean.
    private func worst(_ string: String, _ settings: SafetySettings = .allOn) -> SafetyLevel? {
        result(string, settings).reasons.map(\.level).min()
    }

    private func assertWorst(_ links: [String], is expected: SafetyLevel?, file: StaticString = #filePath, line: UInt = #line) {
        for link in links {
            XCTAssertEqual(worst(link), expected, link, file: file, line: line)
        }
    }

    // MARK: - Clean links

    func testRealSitesAreNotFlagged() {
        assertWorst([
            "https://www.apple.com/iphone",
            "https://support.apple.com",
            "https://smile.amazon.co.uk",
            "https://mail.google.co.uk",
            "https://accounts.google.com",
            "https://login.microsoftonline.com",
            "https://outlook.office.com",
            "https://www.paypal.com/signin",
            "https://www.irs.gov/refunds",
            "https://github.com",
            "https://test.example.com/page?x=1"
        ], is: nil)
    }

    // MARK: - Brand look-alikes (three levels)

    func testBrandLevel1IsSerious() {
        assertWorst([
            "https://paypal-login.com",
            "https://secure-paypal.com",
            "https://appleid-verify.com",
            "https://apple.com.evil.com",
            "https://chase.xyz"
        ], is: .serious)
    }

    func testBrandLevel2IsWarning() {
        assertWorst(["https://applebees.xyz"], is: .warning)
    }

    func testBrandLevel3IsAdvisory() {
        assertWorst([
            "https://applebees.com",
            "https://amazonfreshmarket.net"
        ], is: .advisory)
    }

    func testShortBrandsOnlyMatchWholeWords() {
        assertWorst(["https://first.com", "https://irsmith.com"], is: nil)
        assertWorst(["https://irs-refund.com"], is: .serious)
    }

    func testBrandCheckCanBeSwitchedOff() {
        var settings = SafetySettings.allOn
        settings.flagBrandLookalikes = false
        XCTAssertNil(worst("https://paypal-login.com", settings))
    }

    // MARK: - Dangerous schemes, master switch

    func testDangerousSchemesAreSerious() {
        assertWorst([
            "javascript:alert(1)",
            "data:text/html,hello",
            "file:///etc/passwd"
        ], is: .serious)
    }

    func testDangerousSchemeToggle() {
        var settings = SafetySettings.allOn
        settings.flagDangerousSchemes = false
        XCTAssertNil(worst("javascript:alert(1)", settings))
    }

    func testMasterSwitchTurnsEverythingOff() {
        var settings = SafetySettings.allOn
        settings.warnAboutSuspiciousLinks = false
        XCTAssertNil(worst("javascript:alert(1)", settings))
        XCTAssertNil(worst("https://paypal.com@evil-site.xyz", settings))
    }

    // MARK: - @ trick, downloads, shorteners, http, deep subdomains

    func testAtSignTrickIsSerious() {
        assertWorst(["https://paypal.com@evil-site.xyz"], is: .serious)
    }

    func testMostSevereReasonComesFirst() {
        XCTAssertEqual(result("https://paypal.com@paypal-login.xyz").reasons.first?.level, .serious)
    }

    func testDownloadLinkIsWarning() {
        assertWorst(["https://example.com/setup.exe"], is: .warning)
    }

    func testShortenerAndHTTPAreAdvisory() {
        assertWorst(["https://bit.ly/abc", "http://example.com"], is: .advisory)
    }

    func testDeepSubdomains() {
        assertWorst(["https://a.b.c.d.example.com"], is: .advisory)
        assertWorst(["https://a.b.example.com"], is: nil)
    }

    // MARK: - IP addresses

    func testPublicIPIsWarning() {
        assertWorst(["https://8.8.8.8/", "https://172.15.0.1", "https://172.32.0.1",
                     "https://192.169.0.1", "https://11.0.0.1"], is: .warning)
    }

    func testPrivateAndLoopbackAddressesAreOnlyAdvisory() {
        assertWorst([
            "https://192.168.0.1",
            "https://10.0.0.5",
            "https://172.16.0.1",
            "https://172.31.255.255",
            "https://127.0.0.1:8080",
            "https://169.254.1.1",
            "http://[::1]/",
            "http://[fe80::1]/"
        ], is: .advisory)
    }

    /// If one of these fails, Foundation may be rewriting the host before we
    /// see it (e.g. turning 2130706433 into 127.0.0.1). Tell me and I'll adjust.
    func testDisguisedIPAddressesAreWarning() {
        assertWorst([
            "https://2130706433/",
            "https://0x7f000001/",
            "https://0177.0.0.1/",
            "https://127.1/"
        ], is: .warning)
    }

    // MARK: - Mixed scripts and punycode

    func testMixedScriptPunycodeIsDetected() {
        // xn--pple-43d.com is "аpple.com" with a Cyrillic "а".
        let reasons = result("https://xn--pple-43d.com").reasons.map(\.message)
        XCTAssertTrue(reasons.contains { $0.contains("mixes different alphabets") })
    }

    func testSingleScriptInternationalDomainIsNotMixed() {
        // xn--e1afmkfd.xn--p1ai is "пример.рф": entirely Cyrillic.
        let reasons = result("https://xn--e1afmkfd.xn--p1ai").reasons.map(\.message)
        XCTAssertFalse(reasons.contains { $0.contains("mixes different alphabets") })
    }

    func testPunycodeDecoder() {
        XCTAssertEqual(URLSafetyChecker.punycodeDecode("pple-43d"), "\u{0430}pple")
        XCTAssertEqual(URLSafetyChecker.punycodeDecode("e1afmkfd"), "пример")
        XCTAssertEqual(URLSafetyChecker.punycodeDecode("bcher-kva"), "bücher")
        XCTAssertNil(URLSafetyChecker.punycodeDecode("!!!"))
    }
}
