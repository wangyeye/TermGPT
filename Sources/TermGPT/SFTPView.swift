import SwiftUI
import AppKit

@MainActor final class SFTPModel: ObservableObject {
    let bookmark: Bookmark
    let language: String
    @Published var path = "."
    @Published var entries: [SFTPEntry] = []
    @Published var busy = false
    @Published var transferred: UInt64 = 0
    @Published var total: UInt64?
    @Published var transferring = false
    @Published var status = ""
    @Published var error: String?
    private var connection: SFTPConnection?
    private var task: Task<Void, Never>?
    init(bookmark: Bookmark, language: String) { self.bookmark = bookmark; self.language = language }
    func run(_ operation: @escaping @Sendable (SFTPConnection, @escaping @Sendable (UInt64, UInt64?) -> Void) throws -> (String, [SFTPEntry])?) {
        guard !busy else { return }
        do {
            let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/TermGPTSSHAskpass")
            guard FileManager.default.isExecutableFile(atPath: helper.path) else { throw AppError.message("缺少 SSH 密码登录组件，请使用完整安装包") }
            let client = try SFTPConnection(bookmark: bookmark, helper: helper, language: language)
            connection = client; busy = true; error = nil; status = L("正在连接 SFTP…"); transferred = 0; total = nil
            let report: @Sendable (UInt64, UInt64?) -> Void = { [weak self] bytes, total in
                Task { @MainActor [weak self] in
                    guard let self, self.busy, self.connection === client else { return }
                    self.transferred = bytes; self.total = total; self.status = L("正在传输文件…")
                }
            }
            task = Task { [weak self] in
                do {
                    let result = try await Task.detached {
                        defer { client.finish() }
                        try client.start()
                        return try operation(client, report)
                    }.value
                    guard let self else { return }
                    if let result { path = result.0; entries = result.1 }
                    status = L("SFTP 操作完成")
                } catch is CancellationError { self?.status = L("已取消；连接中断时可能留下远端 .partial 临时文件。") }
                catch { self?.error = error.localizedDescription; self?.status = L("SFTP 操作失败") }
                self?.busy = false; self?.transferring = false; self?.connection = nil; self?.task = nil
            }
        } catch { self.error = error.localizedDescription; transferring = false }
    }
    func browse(_ requested: String) { transferring = false; run { client, _ in try client.list(requested) } }
    func cancel() { connection?.cancel() }
    func download(_ entry: SFTPEntry) {
        guard !busy, !entry.isDirectory else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = entry.name
        guard panel.runModal() == .OK, let local = panel.url else { return }
        let remote = SFTPConnection.path(path, entry.name)
        transferring = true; run { client, progress in try client.download(remote, to: local, progress: progress); return nil }
    }
    func upload() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let local = panel.url else { return }
        let overwrite = entries.contains(where: { $0.name == local.lastPathComponent })
        if overwrite {
            let alert = NSAlert(); alert.messageText = L("替换远端同名文件？"); alert.informativeText = local.lastPathComponent
            alert.addButton(withTitle: L("替换")); alert.addButton(withTitle: L("取消"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let directory = path, remote = SFTPConnection.path(path, local.lastPathComponent)
        transferring = true
        run { client, progress in try client.upload(local, to: remote, overwrite: overwrite, progress: progress); return try client.list(directory) }
    }
}

struct SFTPView: View {
    @ObservedObject private var localization = Localization.shared
    @StateObject private var model: SFTPModel
    @Environment(\.dismiss) private var dismiss
    @State private var requestedPath = "."
    @State private var selection: String?
    init(bookmark: Bookmark, language: String) { _model = StateObject(wrappedValue: SFTPModel(bookmark: bookmark, language: language)) }
    var selectedEntry: SFTPEntry? { model.entries.first { $0.name == selection } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("SFTP · " + model.bookmark.name, systemImage: "folder.badge.gearshape").font(.title2.bold())
                Spacer()
                Button(L("关闭")) { model.cancel(); dismiss() }
            }
            Text((model.bookmark.user.isEmpty ? "" : model.bookmark.user + "@") + model.bookmark.host + ":" + String(model.bookmark.port)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            HStack {
                Button { model.browse(SFTPConnection.path(model.path, "..")) } label: { Image(systemName: "arrow.up") }.help(L("上级目录"))
                TextField(L("远端路径"), text: $requestedPath).textFieldStyle(.roundedBorder).onSubmit { model.browse(requestedPath) }
                Button(L("前往")) { model.browse(requestedPath) }
                Button { model.browse(model.path) } label: { Image(systemName: "arrow.clockwise") }.help(L("刷新"))
            }.disabled(model.busy)
            Table(model.entries, selection: $selection) {
                TableColumn(L("名称")) { entry in
                    Label(entry.name, systemImage: entry.isDirectory ? "folder" : entry.isLink ? "link" : "doc")
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        .onTapGesture(count: 2) { if !model.busy { if entry.isDirectory || entry.isLink { model.browse(SFTPConnection.path(model.path, entry.name)) } else { model.download(entry) } } }
                }
                TableColumn(L("大小")) { entry in Text(entry.isDirectory ? "—" : entry.size.map { ByteCountFormatter.string(fromByteCount: Int64(clamping: $0), countStyle: .file) } ?? "—") }.width(100)
            }.contextMenu {
                if let entry = selectedEntry {
                    if entry.isDirectory || entry.isLink { Button(L("打开目录")) { model.browse(SFTPConnection.path(model.path, entry.name)) }.disabled(model.busy) }
                    if !entry.isDirectory { Button(L("下载")) { model.download(entry) }.disabled(model.busy) }
                }
            }
            HStack {
                Button(L("上传文件…")) { model.upload() }.disabled(model.busy)
                Button(L("下载")) { if let entry = selectedEntry { model.download(entry) } }.disabled(model.busy || selectedEntry == nil || selectedEntry?.isDirectory == true)
                Spacer()
                if model.busy { Button(L("取消")) { model.cancel() } }
            }
            if model.busy {
                if model.transferring, let total = model.total {
                    ProgressView(value: Double(model.transferred), total: Double(max(1, total)))
                    Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: model.transferred), countStyle: .file) + " / " + ByteCountFormatter.string(fromByteCount: Int64(clamping: total), countStyle: .file)).font(.caption)
                } else { ProgressView().controlSize(.small) }
            }
            Text(model.status).font(.caption).foregroundStyle(.secondary)
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            Text(L("双击目录进入，双击文件下载。SFTP 使用独立连接，不影响终端会话。")).font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(minWidth: 620, idealWidth: 740, minHeight: 500, idealHeight: 580)
            .onAppear { model.browse(".") }
            .onChange(of: model.path) { requestedPath = $0; selection = nil }
            .onDisappear { model.cancel() }
    }
}
