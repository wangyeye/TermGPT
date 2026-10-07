import SwiftUI
import UniformTypeIdentifiers

struct TerminalTabDrop: DropDelegate {
    static let type = UTType(exportedAs: "local.TermGPT.terminal-tab")
    let target: UUID
    let workspace: Workspace
    @Binding var dragged: UUID?

    func validateDrop(info: DropInfo) -> Bool {
        guard let dragged else { return false }
        return info.hasItemsConforming(to: [Self.type]) && workspace.sessions.contains { $0.id == dragged }
    }
    func dropEntered(info: DropInfo) {
        guard validateDrop(info: info), let dragged, dragged != target else { return }
        withAnimation(.easeInOut(duration: 0.15)) { workspace.moveTerminal(dragged, to: target) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        let accepted = validateDrop(info: info)
        dragged = nil
        return accepted
    }
}
