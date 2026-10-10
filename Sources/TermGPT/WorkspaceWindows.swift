import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor enum SessionReturnDrag {
    static let type = UTType(exportedAs: "local.TermGPT.detached-session")
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
