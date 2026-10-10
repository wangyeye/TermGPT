import SwiftUI
import AppKit
import UniformTypeIdentifiers

private struct BackupSettings: Codable {
    var automatic = false
    var folderName: String?
    var folder: Data?
    var deviceID = UUID()
    var lastBackup: Date?
}
@MainActor final class BackupManager: ObservableObject {
    @Published private var settings: BackupSettings
    @Published var status = ""
    @Published var failure = ""
    private var pending: DispatchWorkItem?
    private let settingsURL = DiskStore.directory.appendingPathComponent("backup-settings.json")
    var folderName: String? { settings.folderName }
    var automatic: Bool { settings.automatic }
    var hasFolder: Bool { settings.folder != nil }
    var lastBackup: Date? { settings.lastBackup }
    init() { settings = (try? JSONDecoder().decode(BackupSettings.self, from: Data(contentsOf: settingsURL))) ?? BackupSettings() }
    private func saveSettings() {
        do { try FileManager.default.createDirectory(at: DiskStore.directory, withIntermediateDirectories: true); try ConfigurationBackupCodec.write(JSONEncoder().encode(settings), to: settingsURL) }
        catch { failure = error.localizedDescription }
    }
    private func folder() throws -> URL {
        guard let data = settings.folder else { throw AppError.message(L("请先选择备份文件夹")) }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale)
        if stale { settings.folder = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil); saveSettings() }
        return url
    }
    func selectFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = L("选择备份文件夹")
        let cloud = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if FileManager.default.fileExists(atPath: cloud.path) { panel.directoryURL = cloud }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { settings.folder = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil); settings.folderName = url.lastPathComponent; saveSettings(); status = L("已选择：%@", url.lastPathComponent); failure = "" }
        catch { failure = error.localizedDescription }
    }
    func setAutomatic(_ enabled: Bool, workspace: Workspace) {
        guard !enabled || hasFolder else { failure = L("请先选择备份文件夹"); return }
        settings.automatic = enabled; saveSettings()
        if enabled { backupNow(workspace, automatic: true) } else { pending?.cancel() }
    }
    func schedule(_ workspace: Workspace) {
        guard automatic else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self, weak workspace] in guard let self, let workspace else { return }; self.backupNow(workspace, automatic: true) }
        pending = work; DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
    func flush(_ workspace: Workspace) {
        pending?.cancel(); pending = nil
        if automatic { backupNow(workspace, automatic: true) }
    }
    func backupNow(_ workspace: Workspace, automatic: Bool = false) {
        do {
            let destination = try folder(); let accessed = destination.startAccessingSecurityScopedResource(); defer { if accessed { destination.stopAccessingSecurityScopedResource() } }
            let backup = ConfigurationBackup(state: workspace.savedState(), credentials: nil)
            let prefix = "TermGPT-Auto-" + settings.deviceID.uuidString + "-"
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
            let name = automatic ? prefix + formatter.string(from: Date()) : "TermGPT-" + UUID().uuidString
            let file = destination.appendingPathComponent(name + ".termgptbackup")
            try ConfigurationBackupCodec.write(ConfigurationBackupCodec.encode(backup), to: file)
            if automatic {
                let owned = try FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]).filter { url in
                    let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    return values?.isRegularFile == true && values?.isSymbolicLink != true && url.lastPathComponent.range(of: "^" + prefix + "[0-9]{4}-[0-9]{2}-[0-9]{2}\\.termgptbackup$", options: .regularExpression) != nil
                }.sorted { $0.lastPathComponent > $1.lastPathComponent }
                for old in owned.dropFirst(30) { try FileManager.default.removeItem(at: old) }
            }
            settings.lastBackup = Date(); saveSettings(); status = L("备份已写入；若使用 iCloud Drive，同步由系统完成"); failure = ""
        } catch { failure = error.localizedDescription }
    }
    func export(_ workspace: Workspace, includePasswords: Bool, password: String) {
        do {
            var credentials: CredentialConfiguration?
            if includePasswords { credentials = try CredentialStore.shared.read(); credentials?.chatGPT = nil }
            let data = try ConfigurationBackupCodec.encode(ConfigurationBackup(state: workspace.savedState(), credentials: credentials), password: includePasswords || !password.isEmpty ? password : nil)
            let panel = NSSavePanel(); panel.nameFieldStringValue = "TermGPT.termgptbackup"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try ConfigurationBackupCodec.write(data, to: url); status = L("备份已导出"); failure = ""
        } catch { failure = error.localizedDescription }
    }
    func restore(_ workspace: Workspace, password: String) {
        guard !workspace.busy else { failure = L("请等待 AI 回复完成后再恢复"); return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "termgptbackup") ?? .data]
        panel.directoryURL = try? folder()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { throw AppError.message(L("不是有效的 TermGPT 备份")) }
            let size = values.fileSize ?? 0
            guard size <= ConfigurationBackupCodec.maximumSize else { throw AppError.message(L("备份文件过大")) }
            let data = try Data(contentsOf: url)
            let backup = try ConfigurationBackupCodec.decode(data, password: password.isEmpty ? nil : password)
            try install(backup, workspace: workspace)
        } catch { failure = error.localizedDescription }
    }
    private func install(_ backup: ConfigurationBackup, workspace: Workspace) throws {
            let alert = NSAlert(); alert.messageText = L("恢复配置备份")
            alert.informativeText = L("将替换 %@ 个书签、%@ 条笔记和 %@ 条常用命令。当前配置会先保存到本机恢复前备份，现有连接不会断开。", String(backup.state.bookmarks.count), String(backup.state.savedNotes?.count ?? 0), String(backup.state.savedCommands?.count ?? 0))
            alert.informativeText += "\n" + L(backup.credentials == nil ? "不包含保存的密码；现有密码保持不变。" : "包含保存的密码和 API Key，将替换对应凭据；ChatGPT 登录保持不变。")
            alert.addButton(withTitle: L("恢复")); alert.addButton(withTitle: L("取消"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let oldState = workspace.savedState(); let oldCredentials = try CredentialStore.shared.read()
            let safetyFolder = DiskStore.directory.appendingPathComponent("Restore Safety Copies")
            try FileManager.default.createDirectory(at: safetyFolder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let safety = safetyFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: safety, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try ConfigurationBackupCodec.write(JSONEncoder().encode(oldState), to: safety.appendingPathComponent("workspace.json"))
            try ConfigurationBackupCodec.write(JSONEncoder().encode(oldCredentials), to: safety.appendingPathComponent("credentials.json"))
            do {
                if let imported = backup.credentials { try CredentialStore.shared.update { current in
                    // Account sessions stay local; restoring credentials never replaces ChatGPT tokens.
                    let account = current.chatGPT; current = imported; current.chatGPT = account
                } }
                try DiskStore.save(backup.state)
            } catch {
                try? CredentialStore.shared.update { $0 = oldCredentials }; try? DiskStore.save(oldState)
                throw error
            }
            workspace.applyBackupState(backup.state)
            status = L("配置已恢复；窗口布局将在下次启动时恢复"); failure = ""
    }
    func restorePrevious(_ workspace: Workspace) {
        guard !workspace.busy else { failure = L("请等待 AI 回复完成后再恢复"); return }
        do {
            let root = DiskStore.directory.appendingPathComponent("Restore Safety Copies")
            let candidates = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey]).sorted {
                ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
            }
            guard let latest = candidates.first else { throw AppError.message(L("没有恢复前备份")) }
            let state = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: latest.appendingPathComponent("workspace.json")))
            let credentials = try JSONDecoder().decode(CredentialConfiguration.self, from: Data(contentsOf: latest.appendingPathComponent("credentials.json")))
            try install(ConfigurationBackup(state: state, credentials: credentials), workspace: workspace)
        } catch { failure = error.localizedDescription }
    }
    func openSafetyCopies() {
        let url = DiskStore.directory.appendingPathComponent("Restore Safety Copies")
        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) }
    }
}

struct BackupSettingsPane: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var manager: BackupManager
    @State private var includePasswords = false
    @State private var password = ""
    @State private var confirmation = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("配置备份与恢复")).font(.headline)
            Text(L("包含书签、文件夹、笔记、常用命令、聊天和设置。聊天遵循本机保存设置；ChatGPT 登录信息不导出。")).font(.caption).foregroundStyle(.secondary)
            Toggle(L("手动备份包含保存的密码和 API Key（加密）"), isOn: $includePasswords)
            SecureField(L("备份密码（加密导出或恢复时使用）"), text: $password).textFieldStyle(.roundedBorder)
            if !password.isEmpty { SecureField(L("确认备份密码（仅导出）"), text: $confirmation).textFieldStyle(.roundedBorder) }
            HStack { Button(L("导出备份")) {
                if !password.isEmpty && password != confirmation { manager.failure = L("两次输入的备份密码不一致") }
                else { manager.export(workspace, includePasswords: includePasswords, password: password) }
            }; Button(L("恢复备份")) { manager.restore(workspace, password: password) } }
            Divider()
            Text(L("iCloud Drive 备份")).font(.headline)
            if let folder = manager.folderName { Text(L("备份文件夹：%@", folder)).font(.caption) }
            Button(L("选择备份文件夹")) { manager.selectFolder() }
            Text(L("请选择 iCloud Drive 中的文件夹。无需应用专用 iCloud 授权；上传和下载由 macOS 完成，也可选择本机文件夹。")).font(.caption).foregroundStyle(.secondary)
            Toggle(L("配置变更后自动备份"), isOn: Binding(get: { manager.automatic }, set: { manager.setAutomatic($0, workspace: workspace) })).disabled(!manager.hasFolder)
            Text(L("自动备份不包含保存的密码和 API Key。笔记、命令及聊天中的文字会原样备份。关闭自动备份不会删除已有文件。")).font(.caption).foregroundStyle(.secondary)
            Text(L("自动备份每天保留一个最新快照，每台 Mac 最多保留 30 个；手动备份不会自动删除。")).font(.caption).foregroundStyle(.secondary)
            HStack { Button(L("立即备份")) { manager.backupNow(workspace) }.disabled(!manager.hasFolder); Button(L("恢复上次配置")) { manager.restorePrevious(workspace) }; Button(L("查看恢复前备份")) { manager.openSafetyCopies() } }
            if let date = manager.lastBackup { Text(L("最近备份：%@", date.formatted())).font(.caption) }
            if !manager.status.isEmpty { Text(manager.status).font(.caption).foregroundStyle(.secondary) }
            if !manager.failure.isEmpty { Text(manager.failure).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }.padding(16)
    }
}
