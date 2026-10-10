import SwiftUI
import AppKit

@MainActor enum LibraryWindows {
    enum Kind: String { case notepad, commands }
    private static var windows: [Kind: NSWindow] = [:]

    static func show(_ kind: Kind, workspace: Workspace) {
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
        window.center()
        windows[kind] = window
        window.makeKeyAndOrderFront(nil)
    }

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
