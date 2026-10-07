import Foundation

enum TerminalTabOrder {
    static func right(of id: UUID, in order: [UUID]) -> [UUID] {
        guard let index = order.firstIndex(of: id) else { return [] }
        return Array(order.dropFirst(index + 1))
    }
    static func moving(_ id: UUID, to target: UUID, in order: [UUID]) -> [UUID] {
        guard id != target, let source = order.firstIndex(of: id), let destination = order.firstIndex(of: target) else { return order }
        var result = order
        result.insert(result.remove(at: source), at: destination)
        return result
    }
}
