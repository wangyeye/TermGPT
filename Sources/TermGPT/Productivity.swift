import SwiftUI
import AppKit
import SwiftTerm

struct SavedCommand: Codable, Identifiable {
    var id = UUID()
    var name = ""
    var folder = ""
    var command = ""
    var note = ""
    func matches(_ query: String) -> Bool {
        query.split(whereSeparator: { $0.isWhitespace }).allSatisfy { (name + " " + folder + " " + command + " " + note).localizedStandardContains(String($0)) }
    }
}
struct RestoredTab: Codable, Identifiable {
    var id: UUID
    var name: String
    var bookmarkID: UUID?
}
struct RestoredWorkspace: Codable {
    var tabs: [RestoredTab]
    var active: UUID?
    var detached: [RestoredDetachedTab]? = nil
    var mainFrame: SavedWindowFrame? = nil
    var focusedDetached: UUID? = nil
    var libraries: [RestoredLibraryWindow]? = nil
    var focusedLibrary: String? = nil
}
struct RestoredDetachedTab: Codable {
    var tab: RestoredTab
    var frame: SavedWindowFrame?
}
struct RestoredLibraryWindow: Codable {
    var kind: String
    var frame: SavedWindowFrame
}
struct SavedWindowFrame: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    init(_ rect: CGRect) { x = rect.minX; y = rect.minY; width = rect.width; height = rect.height }
    var rect: CGRect? {
        guard [x, y, width, height].allSatisfy(\.isFinite), width > 0, height > 0 else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }
    // Bring windows back onto an available display when a monitor was removed.
    func fitted(to screens: [CGRect], minimum: CGSize) -> CGRect? {
        guard var frame = rect, let screen = screens.max(by: { $0.intersection(frame).area < $1.intersection(frame).area }) else { return nil }
        frame.size.width = min(max(frame.width, minimum.width), screen.width)
        frame.size.height = min(max(frame.height, minimum.height), screen.height)
        frame.origin.x = max(screen.minX, min(frame.minX, screen.maxX - frame.width))
        frame.origin.y = max(screen.minY, min(frame.minY, screen.maxY - frame.height))
        return frame
    }
}
private extension CGRect {
    var area: CGFloat { isNull || isEmpty ? 0 : width * height }
}

struct TerminalFindBar: View {
    @ObservedObject var session: TerminalSession
    @State private var query = ""
    @State private var sensitive = false
    @State private var regex = false
    @State private var matches: [TerminalSearchMatch] = []
    @State private var index = 0
    @State private var error = ""
    @FocusState private var focused: Bool
    func refresh() {
        do { matches = try session.view.searchBuffer(query, caseSensitive: sensitive, regex: regex); index = 0; error = ""; reveal() }
        catch { matches = []; self.error = L("正则表达式无效") }
    }
    func reveal() { if matches.indices.contains(index) { session.view.revealSearchMatch(matches[index]) } }
    func move(_ delta: Int) { guard !matches.isEmpty else { return }; index = (index + delta + matches.count) % matches.count; reveal() }
    var body: some View {
        HStack {
            TextField(L("搜索终端内容"), text: $query).focused($focused).onSubmit { move(1) }.frame(minWidth: 100)
            Toggle("Aa", isOn: $sensitive).toggleStyle(.button).help(L("区分大小写"))
            Toggle(".*", isOn: $regex).toggleStyle(.button).help(L("正则表达式"))
            Text(error.isEmpty ? "\(matches.isEmpty ? 0 : index + 1)/\(matches.count)" : error).font(.caption)
            Button { move(-1) } label: { Image(systemName: "chevron.up") }.help(L("上一条"))
            Button { move(1) } label: { Image(systemName: "chevron.down") }.help(L("下一条"))
            Button(L("刷新"), action: refresh)
            Button { session.searchShown = false } label: { Image(systemName: "xmark") }.help(L("关闭"))
        }.padding(8).textFieldStyle(.roundedBorder)
            .onAppear { DispatchQueue.main.async { focused = true } }.onChange(of: query) { _ in refresh() }
            .onChange(of: sensitive) { _ in refresh() }.onChange(of: regex) { _ in refresh() }
            .onExitCommand { session.searchShown = false }
    }
}

struct CommandLibraryView: View {
    @ObservedObject var workspace: Workspace
    var close: () -> Void
    @State private var query = ""
    @State private var draft: SavedCommand?
    @State private var deleting: SavedCommand?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(L("常用命令库")).font(.title2); Spacer(); Button(L("新增命令")) { draft = SavedCommand() } }
            TextField(L("搜索名称、文件夹、命令或备注"), text: $query).textFieldStyle(.roundedBorder)
            Text(L("填入目标：%@", workspace.executionTargetLabel)).font(.caption)
            List {
                ForEach(workspace.savedCommands.filter { $0.matches(query) }) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.folder.isEmpty ? item.name : item.folder + " / " + item.name).font(.headline)
                        Text(item.command).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        if !item.note.isEmpty { Text(item.note).font(.caption).foregroundStyle(.secondary) }
                        HStack {
                            Button(L("复制")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.command, forType: .string) }
                            Button(L("填入")) { workspace.insert(item.command) }.disabled(!Safety.insertable(item.command) || workspace.activeSession?.running != true || workspace.activeSession?.isTerminal != true || workspace.activeSession?.transferring == true)
                            Button(L("编辑")) { draft = item }
                            Button(L("删除")) { deleting = item }
                        }.buttonStyle(.bordered)
                    }.padding(.vertical, 6).accessibilityElement(children: .contain)
                }
            }
            HStack { Text(L("命令仅保存在本机，请勿在其中保存密码。多行命令可复制。" )).font(.caption).foregroundStyle(.secondary); Spacer(); Button(L("关闭")) { close() } }
        }.padding(20).frame(minWidth: 600, minHeight: 420)
            .sheet(item: $draft) { item in CommandEditor(command: item) { workspace.saveCommand($0) } }
            .alert(L("删除命令？"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button(L("取消"), role: .cancel) { deleting = nil }
                Button(L("删除"), role: .destructive) { if let deleting { workspace.savedCommands.removeAll { $0.id == deleting.id }; workspace.persist() }; deleting = nil }
            }
    }
}
struct CommandEditor: View {
    @State var command: SavedCommand
    let save: (SavedCommand) -> Void
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("编辑命令")).font(.title2)
            TextField(L("名称"), text: $command.name)
            TextField(L("文件夹"), text: $command.folder)
            Text(L("命令")); TextEditor(text: $command.command).font(.system(.body, design: .monospaced)).frame(height: 140)
            TextField(L("备注"), text: $command.note)
            HStack { Button(L("取消")) { dismiss() }; Spacer(); Button(L("保存")) { save(command); dismiss() }.disabled(command.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || command.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(24).frame(width: 560).textFieldStyle(.roundedBorder)
    }
}
