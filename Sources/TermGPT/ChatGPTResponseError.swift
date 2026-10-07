import Foundation

enum ChatGPTResponseError {
    static func message(_ event: [String: Any], status: Int? = nil, now: Date = Date()) -> String {
        let response = event["response"] as? [String: Any] ?? [:]
        let error = event["error"] as? [String: Any] ?? response["error"] as? [String: Any] ?? event
        let details = response["incomplete_details"] as? [String: Any] ?? event["incomplete_details"] as? [String: Any] ?? [:]
        let identifiers = [error["code"], error["type"], details["reason"]].compactMap { $0 as? String }.map { $0.lowercased() }
        let description = (error["message"] as? String ?? "").lowercased()
        let quota = identifiers.contains { $0.contains("usage_limit") || $0.contains("quota") || $0.contains("usage_not_included") || $0.contains("limit_reached") }
            || description.contains("usage limit") || description.contains("quota") || description.contains("out of credits")
        if quota {
            let seconds = (error["resets_in_seconds"] as? NSNumber)?.doubleValue
            let timestamp = (error["resets_at"] as? NSNumber)?.doubleValue
            let reset = timestamp.map { Date(timeIntervalSince1970: $0) } ?? seconds.map { now.addingTimeInterval($0) }
            if let reset, reset > now, reset.timeIntervalSince(now) < 366 * 86_400 {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium; formatter.timeStyle = .short
                return L("ChatGPT 使用额度已用尽，预计恢复时间：%@。请等待恢复，或在设置中切换模型或其他 AI 服务。", formatter.string(from: reset))
            }
            return "ChatGPT 使用额度已用尽，请等待额度恢复，或在设置中切换模型或其他 AI 服务。"
        }
        if status == 429 || identifiers.contains(where: { $0.contains("rate_limit") }) {
            return "ChatGPT 请求过于频繁，请稍后再试。"
        }
        if identifiers.contains("max_output_tokens") {
            return "ChatGPT 回复达到长度上限，已保留生成内容，可发送“继续”获取后续内容。"
        }
        if identifiers.contains("content_filter") {
            return "ChatGPT 因内容限制停止了回复，请调整问题。"
        }
        return "ChatGPT 未完成回复，已保留生成内容，请稍后再试。"
    }
}
