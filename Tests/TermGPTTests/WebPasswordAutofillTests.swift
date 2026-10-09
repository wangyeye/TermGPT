import XCTest
@testable import TermGPT

final class WebPasswordAutofillTests: XCTestCase {
    func testCredentialOriginsSeparateSchemeHostAndPort() {
        XCTAssertEqual(WebPasswordAutofill.origin(URL(string: "https://EXAMPLE.com/login")), "https://example.com:443")
        XCTAssertEqual(WebPasswordAutofill.origin(URL(string: "https://example.com:443/other")), "https://example.com:443")
        XCTAssertNotEqual(WebPasswordAutofill.origin(URL(string: "http://example.com")), WebPasswordAutofill.origin(URL(string: "https://example.com")))
        XCTAssertNotEqual(WebPasswordAutofill.origin(URL(string: "https://example.com:8443")), WebPasswordAutofill.origin(URL(string: "https://other.example.com:8443")))
        XCTAssertNotEqual(WebPasswordAutofill.origin(URL(string: "https://example.com:8443")), WebPasswordAutofill.origin(URL(string: "https://example.com")))
        XCTAssertNil(WebPasswordAutofill.origin(URL(string: "file:///tmp/login.html")))
        XCTAssertNil(WebPasswordAutofill.origin(URL(string: "about:blank")))
    }
}
