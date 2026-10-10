import SwiftUI
import AppKit

@MainActor enum LibraryWindows {
    enum Kind: String { case notepad, commands }
    private static var observers: [NSObjectProtocol] = []
    private static var windows: [Kind: NSWindow] = [:]

    static func show(_ kind: Kind, workspace: Workspace, frame: SavedWindowFrame? = nil) {
        if let window = windows[kind] {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = L(kind == .notepad ? "记事本" : "常用命令库")
        window.identifier = NSUserInterfaceItemIdentifier("TermGPT.library." + kind.rawValue)
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 600, height: 420)
        window.contentView = NSHostingView(rootView: LibraryWindowContent(workspace: workspace, kind: kind, close: { window.close() }))
        if let restored = frame?.fitted(to: NSScreen.screens.map(\.visibleFrame), minimum: window.contentMinSize) { window.setFrame(restored, display: false) }
        else { window.center() }
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak workspace] event in
                MainActor.assumeIsolated {
                    workspace?.updateLibraryLayout(focused: event.name == NSWindow.didBecomeKeyNotification ? kind.rawValue : nil, closing: event.name == NSWindow.willCloseNotification ? kind.rawValue : nil)
                }
            })
        }
        windows[kind] = window
        window.makeKeyAndOrderFront(nil)
    }

    static func snapshot(excluding kind: String? = nil) -> [RestoredLibraryWindow] {
        windows.compactMap { key, window in window.isVisible && key.rawValue != kind ? RestoredLibraryWindow(kind: key.rawValue, frame: SavedWindowFrame(window.frame)) : nil }.sorted { $0.kind < $1.kind }
    }
    static func focus(_ kind: String) { if let kind = Kind(rawValue: kind) { windows[kind]?.makeKeyAndOrderFront(nil) } }
    static func closeFocused() -> Bool {
        guard let window = NSApp.keyWindow else { return false }
        let owner = window.sheetParent ?? window
        guard owner.identifier?.rawValue.hasPrefix("TermGPT.library.") == true else { return false }
        // Keep unsaved editors open; their Cancel button dismisses the draft.
        guard owner.attachedSheet == nil else { return true }
        owner.performClose(nil)
        return true
    }
}

private struct LibraryWindowContent: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject private var localization = Localization.shared
    let kind: LibraryWindows.Kind
    let close: () -> Void
    var body: some View {
        Group {
            if kind == .notepad { NotepadView(workspace: workspace, close: close) }
            else { CommandLibraryView(workspace: workspace, close: close) }
        }
        .preferredColorScheme(workspace.preferences.interfaceTheme.colorScheme)
        .environment(\.locale, Locale(identifier: workspace.preferences.language.resolved() == .chinese ? "zh-Hans" : "en"))
    }
}
