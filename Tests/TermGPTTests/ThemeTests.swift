import XCTest
@testable import TermGPT
final class ThemeTests: XCTestCase {
    func testThemeDefaultsAndRoundTrip() throws {
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8)).interfaceTheme, .system)
        for theme in InterfaceTheme.allCases {
            var p = Preferences(); p.interfaceTheme = theme
            XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p)).interfaceTheme, theme)
        }
    }
}
