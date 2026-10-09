#if os(macOS)
import Foundation

public struct TerminalSearchMatch {
    public let row: Int
    public let startColumn: Int
    public let endColumn: Int
}
extension TerminalView {
    /// Searches cell text and preserves wide-character column coordinates.
    public func searchBuffer(_ query: String, caseSensitive: Bool, regex: Bool) throws -> [TerminalSearchMatch] {
        guard !query.isEmpty else { return [] }
        let pattern = regex ? query : NSRegularExpression.escapedPattern(for: query)
        let expression = try NSRegularExpression(pattern: pattern, options: caseSensitive ? [] : [.caseInsensitive])
        var results: [TerminalSearchMatch] = []
        for row in 0..<terminal.buffer.lines.count {
            let line = terminal.buffer.lines[row]
            var text = "", columns: [Int] = []
            for column in 0..<line.count where line[column].width != 0 {
                let character = line[column].code == 0 ? " " : String(terminal.getCharacter(for: line[column]))
                text += character
                columns += Array(repeating: column, count: character.utf16.count)
            }
            for match in expression.matches(in: text, range: NSRange(location: 0, length: text.utf16.count)) where match.range.length > 0 {
                let end = columns[NSMaxRange(match.range)-1]
                results.append(TerminalSearchMatch(row: row, startColumn: columns[match.range.location], endColumn: end + max(1, Int(line[end].width))))
                if results.count >= 10000 { return results }
            }
        }
        return results
    }
    public func revealSearchMatch(_ match: TerminalSearchMatch) {
        guard match.row < terminal.buffer.lines.count else { return }
        scrollTo(row: min(match.row, terminal.buffer.yBase))
        selection.setSelection(start: Position(col: match.startColumn, row: match.row), end: Position(col: match.endColumn, row: match.row))
        needsDisplay = true
    }
}
#endif
