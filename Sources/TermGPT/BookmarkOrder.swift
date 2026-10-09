import Foundation

enum BookmarkOrder {
    static func moving(_ id: UUID, to target: UUID, in bookmarks: [Bookmark]) -> [Bookmark] {
        guard id != target, let destination = bookmarks.first(where: { $0.id == target }), bookmarks.contains(where: { $0.id == id }) else { return bookmarks }
        var result = reordered(id, to: target, in: bookmarks)
        if let index = result.firstIndex(where: { $0.id == id }) { result[index].folderID = destination.folderID }
        return result
    }
    static func movingFolder(_ id: UUID, to target: UUID, in folders: [BookmarkFolder]) -> [BookmarkFolder] {
        reordered(id, to: target, in: folders)
    }
    private static func reordered<Element: Identifiable>(_ id: UUID, to target: UUID, in items: [Element]) -> [Element] where Element.ID == UUID {
        guard id != target, let source = items.firstIndex(where: { $0.id == id }), let destination = items.firstIndex(where: { $0.id == target }) else { return items }
        var result = items
        result.insert(result.remove(at: source), at: destination)
        return result
    }
}
