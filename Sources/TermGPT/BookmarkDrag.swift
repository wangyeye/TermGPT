import SwiftUI
import UniformTypeIdentifiers

enum BookmarkDrag {
    static let bookmarkType = UTType(exportedAs: "local.TermGPT.bookmark-order")
    static let folderType = UTType(exportedAs: "local.TermGPT.folder-order")
    static func provider(_ id: UUID, type: UTType) -> NSItemProvider {
        NSItemProvider(item: Data(id.uuidString.utf8) as NSData, typeIdentifier: type.identifier)
    }
}
struct BookmarkRowDrop: DropDelegate {
    let target: UUID
    let workspace: Workspace
    func validateDrop(info: DropInfo) -> Bool { workspace.draggingBookmark != nil && info.hasItemsConforming(to: [BookmarkDrag.bookmarkType]) }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info), let id = workspace.draggingBookmark else { return false }
        workspace.reorderBookmark(id, to: target); workspace.draggingBookmark = nil
        return true
    }
}
struct BookmarkFolderDrop: DropDelegate {
    let target: UUID
    let workspace: Workspace
    func validateDrop(info: DropInfo) -> Bool {
        (workspace.draggingFolder != nil && info.hasItemsConforming(to: [BookmarkDrag.folderType])) ||
        (workspace.draggingBookmark != nil && info.hasItemsConforming(to: [BookmarkDrag.bookmarkType]))
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info) else { return false }
        if let id = workspace.draggingFolder { workspace.reorderFolder(id, to: target) }
        else if let id = workspace.draggingBookmark { workspace.moveBookmark(id, folder: target) }
        workspace.draggingBookmark = nil; workspace.draggingFolder = nil
        return true
    }
}
