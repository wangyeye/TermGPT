import Foundation

/// Only explicitly labelled shell blocks receive terminal actions. Untagged
/// quotes, logs, configuration and other languages remain copyable references.
struct ReplyCodeBlock {
    let content: String
    let isShellCommand: Bool

    init(_ fencedPart: String) {
        guard let newline = fencedPart.firstIndex(of: "\n") else {
            content = fencedPart
            isShellCommand = false
            return
        }
        let language = fencedPart[..<newline].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        content = String(fencedPart[fencedPart.index(after: newline)...]).trimmingCharacters(in: .newlines)
        isShellCommand = ["bash", "sh", "shell", "zsh", "fish", "ksh"].contains(language) && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
