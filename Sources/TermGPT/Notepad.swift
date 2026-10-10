import SwiftUI
import AppKit

struct SavedNote: Codable, Identifiable {
    var id = UUID()
    var title = ""
    var folder = ""
    var content = ""
    var updatedAt = Date()
    func matches(_ query: String) -> Bool {
        query.split(whereSeparator: { $0.isWhitespace }).allSatisfy {
            (title + " " + folder + " " + content).localizedStandardContains(String($0))
        }
    }
}

struct NotepadView: View {
    @ObservedObject var workspace: Workspace
    var close: () -> Void
    @State private var query = ""
    @State private var draft: SavedNote?
    @State private var deleting: SavedNote?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(L("记事本")).font(.title2); Spacer(); Button(L("新增笔记")) { draft = SavedNote() } }
            TextField(L("搜索标题、文件夹或内容"), text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(workspace.savedNotes.filter { $0.matches(query) }) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.folder.isEmpty ? item.title : item.folder + " / " + item.title).font(.headline)
                            Text(item.content).lineLimit(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            Text(item.updatedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button(L("复制")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.content, forType: .string) }
                                Button(L("编辑")) { draft = item }
                                Button(L("删除")) { deleting = item }
                            }.buttonStyle(.bordered)
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.primary.opacity(0.04)).cornerRadius(8)
                    }
                    if workspace.savedNotes.filter({ $0.matches(query) }).isEmpty { Text(L("没有匹配的笔记")).foregroundStyle(.secondary).padding(.vertical) }
                }
            }
            HStack { Text(L("笔记仅保存在本机 JSON 配置中。" )).font(.caption).foregroundStyle(.secondary); Spacer(); Button(L("关闭")) { close() } }
        }.padding(20).frame(minWidth: 600, minHeight: 420)
            .sheet(item: $draft) { item in NoteEditor(note: item) { workspace.saveNote($0) } }
            .alert(L("删除笔记？"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button(L("取消"), role: .cancel) { deleting = nil }
                Button(L("删除"), role: .destructive) { if let deleting { workspace.savedNotes.removeAll { $0.id == deleting.id }; workspace.persist() }; deleting = nil }
            } message: { Text(deleting?.title ?? "") }
    }
}

struct NoteEditor: View {
    @State var note: SavedNote
    let save: (SavedNote) -> Void
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("编辑笔记")).font(.title2)
            TextField(L("标题"), text: $note.title)
            TextField(L("文件夹"), text: $note.folder)
            Text(L("内容"))
            TextEditor(text: $note.content).font(.system(.body, design: .monospaced)).frame(minHeight: 260).accessibilityLabel(L("笔记内容"))
            HStack { Button(L("取消")) { dismiss() }; Spacer(); Button(L("保存")) { save(note); dismiss() }.keyboardShortcut("s").buttonStyle(.borderedProminent).disabled(note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(24).frame(width: 620, height: 560).textFieldStyle(.roundedBorder)
    }
}
