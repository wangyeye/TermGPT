import XCTest
@testable import TermGPT

final class ZmodemTests: XCTestCase {
    func testFragmentedHeadersAndNormalOutput() {
        var detector = ZmodemDetector()
        let a = detector.append(Data("hello **".utf8))
        XCTAssertEqual(String(decoding: a.display, as: UTF8.self), "hello "); XCTAssertNil(a.direction)
        let b = detector.append(Data([24, 66, 48]))
        XCTAssertNil(b.direction)
        let c = detector.append(Data("0abcd".utf8))
        XCTAssertEqual(c.direction, true); XCTAssertEqual(c.protocolData, Data([42, 42, 24, 66, 48, 48]) + Data("abcd".utf8))
        var upload = ZmodemDetector()
        XCTAssertEqual(upload.append(Data([42, 42, 24, 66, 48, 49])).direction, false)
        var plain = ZmodemDetector()
        XCTAssertEqual(plain.append(Data("a*b shell$ ".utf8)).display, Data("a*b shell$ ".utf8))
    }
}
