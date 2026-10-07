import XCTest
@testable import TermGPT

final class ChatGPTResponseErrorTests: XCTestCase {
    func testQuotaInStreamingAndHTTPResponses() {
        for event: [String: Any] in [
            ["type": "response.failed", "response": ["error": ["code": "usage_limit_reached"]]],
            ["type": "response.incomplete", "response": ["incomplete_details": ["reason": "insufficient_quota"]]],
            ["error": ["type": "usage_limit_reached", "message": "Limit reached"]],
            ["type": "error", "code": "insufficient_quota"]
        ] {
            XCTAssertTrue(ChatGPTResponseError.message(event).contains("额度已用尽"))
        }
    }

    func testRateLimitIsNotAssumedToBeExhaustedQuota() {
        XCTAssertTrue(ChatGPTResponseError.message([:], status: 429).contains("过于频繁"))
        XCTAssertTrue(ChatGPTResponseError.message(["error": ["code": "rate_limit_exceeded"]]).contains("过于频繁"))
    }

    func testOtherIncompleteReasonsRemainDistinct() {
        XCTAssertTrue(ChatGPTResponseError.message(["response": ["incomplete_details": ["reason": "max_output_tokens"]]]).contains("长度上限"))
        XCTAssertTrue(ChatGPTResponseError.message(["response": ["incomplete_details": ["reason": "content_filter"]]]).contains("内容限制"))
        XCTAssertFalse(ChatGPTResponseError.message([:]).contains("额度"))
    }

    func testQuotaResetTimeWhenProvided() {
        let previous = Localization.shared.selection
        Localization.shared.selection = .chinese
        defer { Localization.shared.selection = previous }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertTrue(ChatGPTResponseError.message(["error": ["code": "usage_limit_reached", "resets_in_seconds": 3600]], now: now).contains("预计恢复时间"))
        XCTAssertFalse(ChatGPTResponseError.message(["error": ["code": "usage_limit_reached", "resets_at": 1]], now: now).contains("预计恢复时间"))
    }
}
