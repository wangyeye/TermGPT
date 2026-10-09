import AppKit
import SwiftUI

enum BookmarkSearch {
    static func matches(_ bookmark: Bookmark, query: String, folders: [BookmarkFolder]) -> Bool {
        let folder = folders.first { $0.id == bookmark.folderID }?.name ?? ""
        let text = "\(bookmark.name) \(bookmark.host) \(bookmark.kind.rawValue) \(folder)"
        return query.split(whereSeparator: { $0.isWhitespace }).allSatisfy { text.localizedStandardContains(String($0)) }
    }
    static func recent(_ ids: [UUID], bookmarks: [Bookmark]) -> [Bookmark] {
        var seen = Set<UUID>()
        return ids.compactMap { id in guard seen.insert(id).inserted else { return nil }; return bookmarks.first { $0.id == id } }.prefix(10).map { $0 }
    }
}
struct QuickOpenPane: View {
    @ObservedObject var workspace: Workspace
    let close: () -> Void
    @State private var query = ""
    @State private var selection: String?
    @FocusState private var focused: Bool
    private var matching: [Bookmark] { workspace.bookmarks.filter { BookmarkSearch.matches($0, query: query, folders: workspace.folders) } }
    private var tabs: [TerminalSession] { workspace.sessions.filter { query.isEmpty || ($0.name + " " + ($0.bookmark?.host ?? "")).localizedStandardContains(query) } }
    private var ordered: [Bookmark] {
        guard query.isEmpty else { return matching }
        let recent = workspace.recentBookmarks
        return recent + matching.filter { item in !recent.contains(where: { $0.id == item.id }) }
    }
    private var ids: [String] { tabs.map { "tab:" + $0.id.uuidString } + ordered.map { "bookmark:" + $0.id.uuidString } }
    private func choose(_ id: String?) {
        guard let id else { return }
        close()
        DispatchQueue.main.async {
            if let tab = workspace.sessions.first(where: { "tab:" + $0.id.uuidString == id }) { workspace.active = tab.id; if let bookmark = tab.bookmark { workspace.recordRecent(bookmark.id) } }
            else if let bookmark = workspace.bookmarks.first(where: { "bookmark:" + $0.id.uuidString == id }) { workspace.openBookmark(bookmark) }
        }
    }
    var body: some View {
        VStack(spacing: 8) {
            TextField(L("搜索书签或已打开标签…"), text: $query).textFieldStyle(.roundedBorder).focused($focused)
                .onSubmit { choose(selection ?? ids.first) }
            List(selection: $selection) {
                if !tabs.isEmpty {
                    Section(L("已打开标签")) {
                        ForEach(tabs) { tab in
                            Button { choose("tab:" + tab.id.uuidString) } label: { Label(tab.name, systemImage: tab.bookmark?.kind.icon ?? "terminal").frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.plain).tag("tab:" + tab.id.uuidString)
                        }
                    }
                }
                Section(query.isEmpty ? L("书签（最近使用优先）") : L("搜索结果")) {
                    ForEach(ordered) { bookmark in
                        Button { choose("bookmark:" + bookmark.id.uuidString) } label: {
                            VStack(alignment: .leading) { Label(bookmark.name, systemImage: bookmark.kind.icon); Text(bookmark.kind.rawValue.uppercased() + " · " + bookmark.host).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).tag("bookmark:" + bookmark.id.uuidString)
                    }
                }
                if ids.isEmpty { Text(L("没有匹配的书签或标签")).foregroundStyle(.secondary) }
            }
            Text(L("↑↓ 选择 · 回车打开 · Esc 关闭")).font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(width: 560, height: 440)
            .onAppear { selection = ids.first; DispatchQueue.main.async { focused = true } }
            .onChange(of: query) { _ in selection = ids.first }
            .onExitCommand(perform: close)
            .onReceive(NotificationCenter.default.publisher(for: .quickOpenKey)) { event in
                guard let key = event.object as? UInt16 else { return }
                if key == 36 { choose(selection ?? ids.first) }
                else if key == 53 { close() }
                else if !ids.isEmpty {
                    let index = ids.firstIndex(of: selection ?? "") ?? 0
                    selection = ids[min(max(0, index + (key == 125 ? 1 : -1)), ids.count - 1)]
                }
            }
            .onMoveCommand { direction in
                guard !ids.isEmpty else { return }; let index = ids.firstIndex(of: selection ?? "") ?? 0
                if direction == .down { selection = ids[min(index + 1, ids.count - 1)] }
                if direction == .up { selection = ids[max(index - 1, 0)] }
            }
    }
}
private extension Notification.Name { static let quickOpenKey = Notification.Name("TermGPTQuickOpenKey") }
private final class QuickOpenPanel: NSPanel {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, [UInt16(36), 53, 125, 126].contains(event.keyCode),
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           (firstResponder as? NSTextView)?.hasMarkedText() != true {
            NotificationCenter.default.post(name: .quickOpenKey, object: event.keyCode); return
        }
        super.sendEvent(event)
    }
}
final class QuickOpenWindow {
    private static var window: NSPanel?
    static func show(_ workspace: Workspace) {
        if let window, window.isVisible { window.makeKeyAndOrderFront(nil); return }
        let panel = QuickOpenPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 440), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.title = L("快速打开")
        panel.contentView = NSHostingView(rootView: QuickOpenPane(workspace: workspace, close: { [weak panel] in panel?.close() }))
        window = panel; panel.center(); panel.makeKeyAndOrderFront(nil)
    }
}
