import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor enum SessionReturnDrag {
    nonisolated static let type = UTType(exportedAs: "local.TermGPT.detached-session")
    static func provider(_ id: UUID) -> NSItemProvider {
        NSItemProvider(item: Data(id.uuidString.utf8) as NSData, typeIdentifier: type.identifier)
    }
    static func accept(_ providers: [NSItemProvider], workspace: Workspace, before target: UUID? = nil) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(type.identifier) }) else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { [weak workspace] data, _ in
            guard let data, let text = String(data: data, encoding: .utf8), let id = UUID(uuidString: text) else { return }
            DispatchQueue.main.async { workspace?.reattach(id, before: target) }
        }
        return true
    }
}

// Observe the main window without replacing SwiftUI's NSWindow delegate.
struct WorkspaceWindowObserver: NSViewRepresentable {
    let workspace: Workspace
    func makeNSView(context: Context) -> WorkspaceWindowObserverView { WorkspaceWindowObserverView(workspace: workspace) }
    func updateNSView(_ view: WorkspaceWindowObserverView, context: Context) {}
}
final class WorkspaceWindowObserverView: NSView {
    private weak var workspace: Workspace?
    private var observers: [NSObjectProtocol] = []
    init(workspace: Workspace) { self.workspace = workspace; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver); observers = []
        guard let window, let workspace else { return }
        DispatchQueue.main.async { [weak workspace, weak window] in
            guard let workspace, let window else { return }; workspace.registerMainWindow(window)
        }
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak workspace, weak window] notification in
                guard let workspace, let window else { return }
                MainActor.assumeIsolated {
                    workspace.updateMainWindow(window, focused: notification.name == NSWindow.didBecomeKeyNotification)
                }
            })
        }
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}

// AppKit owns the drag until mouse-up, including when the pointer leaves the window.
struct SessionTabDrag: NSViewRepresentable {
    let workspace: Workspace
    let id: UUID
    let name: String
    let detachOnExit: Bool
    func makeNSView(context: Context) -> SessionTabDragView { SessionTabDragView() }
    func updateNSView(_ view: SessionTabDragView, context: Context) {
        view.workspace = workspace; view.sessionID = id; view.name = name; view.detachOnExit = detachOnExit
    }
}
final class SessionTabDragView: NSView, NSDraggingSource {
    weak var workspace: Workspace?
    var sessionID = UUID()
    var name = ""
    var detachOnExit = false
    private var down: NSEvent?
    private var strip = CGRect.zero
    override func mouseDown(with event: NSEvent) { down = event }
    override func mouseUp(with event: NSEvent) {
        if down != nil { workspace?.active = sessionID }; down = nil
    }
    override func mouseDragged(with event: NSEvent) {
        guard let down, hypot(event.locationInWindow.x - down.locationInWindow.x, event.locationInWindow.y - down.locationInWindow.y) >= 5, let window else { return }
        self.down = nil
        let row = window.convertToScreen(convert(bounds, to: nil))
        strip = CGRect(x: window.frame.minX, y: row.minY - 32, width: window.frame.width, height: row.height + 64)
        let item = NSDraggingItem(pasteboardWriter: SessionDragPasteboard(id: sessionID))
        let image = NSImage(size: CGSize(width: max(bounds.width, 80), height: max(bounds.height, 24)))
        image.lockFocus()
        (name as NSString).draw(at: CGPoint(x: 6, y: 4), withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
        image.unlockFocus()
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
    func draggingSession(_ session: NSDraggingSession, endedAt point: NSPoint, operation: NSDragOperation) {
        let event = NSApp.currentEvent
        let cancelled = event?.type == .keyDown && event?.keyCode == 53
        guard detachOnExit, operation.isEmpty, !strip.contains(point), !cancelled else { return }
        workspace?.detach(sessionID, at: point)
    }
}
final class SessionDragPasteboard: NSObject, NSPasteboardWriting {
    let id: UUID
    init(id: UUID) { self.id = id }
    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] { [NSPasteboard.PasteboardType(SessionReturnDrag.type.identifier)] }
    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? { Data(id.uuidString.utf8) }
}
