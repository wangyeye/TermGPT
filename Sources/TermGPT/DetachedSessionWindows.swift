import SwiftUI
import AppKit

enum TabDetachPolicy {
    static func shouldDetach(at point: CGPoint, strip: CGRect) -> Bool {
        !strip.isEmpty && !strip.insetBy(dx: -32, dy: -32).contains(point)
    }
}
struct TabFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
struct TabStripBoundsKey: PreferenceKey {
    static var defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

@MainActor final class DetachedSessionWindows: NSObject, NSWindowDelegate {
    private static var controllers: [UUID: DetachedSessionWindows] = [:]
    let session: TerminalSession
    private weak var workspace: Workspace?
    private let window: NSWindow
    private var reattaching = false
    private init(session: TerminalSession, workspace: Workspace, at point: NSPoint, frame savedFrame: SavedWindowFrame? = nil) {
        self.session = session; self.workspace = workspace
        window = NSWindow(contentRect: NSRect(x: point.x - 200, y: point.y - 500, width: 900, height: 600), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = session.name
        window.identifier = NSUserInterfaceItemIdentifier("TermGPT.detached." + session.id.uuidString)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentMinSize = NSSize(width: 400, height: 300)
        window.delegate = self
        window.contentView = NSHostingView(rootView: DetachedSessionContent(session: session, workspace: workspace))
        if let frame = savedFrame?.fitted(to: NSScreen.screens.map(\.visibleFrame), minimum: NSSize(width: 400, height: 300)) { window.setFrame(frame, display: false) }
        else if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            var frame = window.frame; let visible = screen.visibleFrame
            frame.size.width = min(frame.width, visible.width); frame.size.height = min(frame.height, visible.height)
            frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
            frame.origin.y = max(visible.minY, min(frame.minY, visible.maxY - frame.height))
            window.setFrame(frame, display: false)
        }
    }
    static func show(session: TerminalSession, workspace: Workspace, at point: NSPoint, frame savedFrame: SavedWindowFrame? = nil) {
        let controller = controllers[session.id] ?? DetachedSessionWindows(session: session, workspace: workspace, at: point, frame: savedFrame)
        controllers[session.id] = controller
        controller.window.makeKeyAndOrderFront(nil)
        workspace.updateDetachedFrame(session.id, frame: controller.window.frame)
    }
    static func focus(_ id: UUID) { controllers[id]?.window.makeKeyAndOrderFront(nil) }
    static func removeForReattach(_ id: UUID) {
        guard let controller = controllers[id] else { return }
        controller.reattaching = true
        controller.window.contentView = nil
        controller.window.close()
    }
    func windowDidMove(_ notification: Notification) { workspace?.updateDetachedFrame(session.id, frame: window.frame) }
    func windowDidResize(_ notification: Notification) { workspace?.updateDetachedFrame(session.id, frame: window.frame) }
    private static var focused: DetachedSessionWindows? { controllers.values.first { $0.window === NSApp.keyWindow } }
    static var canFindFocused: Bool { focused.map { $0.session.isTerminal && !$0.session.awaitingRestore } ?? false }
    static func findFocused() -> Bool {
        guard let controller = focused else { return false }
        if canFindFocused { controller.session.searchShown = true }; return true
    }
    static func closeFocused() -> Bool {
        guard let controller = focused else { return false }
        controller.window.performClose(nil); return true
    }
    func windowDidBecomeKey(_ notification: Notification) {
        workspace?.focusDetached(session.id)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window.isKeyWindow, self.session.isTerminal, !self.session.searchShown, self.session.view.window === self.window else { return }
            self.window.makeFirstResponder(self.session.view)
        }
    }
    func windowWillClose(_ notification: Notification) {
        if !reattaching { workspace?.closeDetached(session.id) }
        Self.controllers.removeValue(forKey: session.id)
    }
}

private struct DetachedSessionContent: View {
    @ObservedObject var session: TerminalSession
    @ObservedObject var workspace: Workspace
    @ObservedObject private var localization = Localization.shared
    @State private var sftp: Bookmark?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(session.name).lineLimit(1).overlay(SessionTabDrag(workspace: workspace, id: session.id, name: session.name, detachOnExit: false)).help(L("拖到主窗口标签栏"))
                Spacer()
                Button { workspace.reattach(session.id) } label: { Image(systemName: "arrow.uturn.backward") }.help(L("移回主窗口")).accessibilityLabel(L("移回主窗口"))
                if session.isTerminal { Button { session.searchShown.toggle() } label: { Image(systemName: "magnifyingglass") }.help(L("搜索终端内容")) }
                if let bookmark = session.bookmark, bookmark.kind == .ssh { Button { sftp = bookmark } label: { Image(systemName: "folder") }.help(L("SFTP 文件")) }
                if let browser = session.web { Button { browser.view.reloadFromOrigin() } label: { Image(systemName: "arrow.clockwise") }.help(L("强制刷新")) }
                if session.bookmark?.kind == .ssh || session.desktop != nil {
                    Menu { ConnectionTabActions(session: session, preferences: workspace.preferences); if let desktop = session.desktop { DesktopTabActions(desktop: desktop, workspace: workspace) } } label: { Image(systemName: "ellipsis") }.help(L("会话功能"))
                }
            }.padding(8)
            Divider()
            SessionContent(session: session, preferences: workspace.preferences, active: true, restore: { workspace.restore(session) })
            if session.isTerminal { SessionFooter(session: session) }
        }
        .preferredColorScheme(workspace.preferences.interfaceTheme.colorScheme)
        .environment(\.locale, Locale(identifier: workspace.preferences.language.resolved() == .chinese ? "zh-Hans" : "en"))
        .sheet(item: $sftp) { bookmark in SFTPView(bookmark: bookmark, language: workspace.preferences.language.resolved().rawValue) }
    }
}
