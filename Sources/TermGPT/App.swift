import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum TermGPTIcon {
    static let image: NSImage = Bundle.main.url(forResource: "TermGPT", withExtension: "icns").flatMap { NSImage(contentsOf: $0) } ?? NSApp.applicationIconImage
}

@main struct TermGPTApp: App {
    @StateObject private var workspace = Workspace()
    var body: some Scene {
        WindowGroup("TermGPT") {
            MainView(workspace: workspace).frame(minWidth: 500 + (workspace.preferences.showBookmarks ? 190 : 0) + (workspace.preferences.showChat ? 350 : 0), minHeight: 680)
                .onAppear { NSApp.applicationIconImage = TermGPTIcon.image }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in workspace.shutdown() }
        }.commands {
            CommandGroup(replacing: .newItem) {
                Button(L("新建本地终端")) { workspace.newLocal() }.keyboardShortcut("t")
                Button(L("新建聊天")) { workspace.newChat() }.keyboardShortcut("n", modifiers: [.command, .shift])
                Button(L("关闭当前终端")) { if let id = workspace.active { workspace.close(id) } }.keyboardShortcut("w")
            }
            CommandGroup(replacing: .appSettings) { Button(L("设置…")) { workspace.settingsShown = true }.keyboardShortcut(",") }
            CommandMenu(L("终端")) {
                Button(L("终端历史与搜索")) { workspace.historyShown = true }.keyboardShortcut("f")
                Button(L("导出会话")) { workspace.export() }
            }
            CommandGroup(after: .sidebar) {
                Button(L("显示书签栏")) { workspace.setLayout(bookmarks: !workspace.preferences.showBookmarks, chat: workspace.preferences.showChat) }.keyboardShortcut("b", modifiers: [.command, .control])
                Button(L("显示聊天栏")) { workspace.setLayout(bookmarks: workspace.preferences.showBookmarks, chat: !workspace.preferences.showChat) }.keyboardShortcut("j", modifiers: [.command, .control])
            }
        }
    }
}
struct MainView: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var workspace: Workspace
    @State private var renameTarget: Chat?
    @State private var deleteTarget: Chat?
    @State private var scrollToLatestRequest = 0
    @State private var draggedTerminal: UUID?
    @State private var sftpBookmark: Bookmark?
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                if workspace.preferences.showBookmarks { sidebar.frame(minWidth: 170, idealWidth: 190, maxWidth: 260) }
                terminal.frame(minWidth: 400, idealWidth: 680)
                if workspace.preferences.showChat { chat.frame(minWidth: 350, idealWidth: 430) }
            }
            Divider()
            HStack {
                Label(workspace.activeSession?.name ?? L("无终端"), systemImage: "terminal")
                Text(workspace.notice.isEmpty ? L("上下文：%@ · 默认仅建议命令", L(workspace.contextMode.rawValue)) : L(workspace.notice)).lineLimit(1)
                Spacer()
                Text(workspace.busy ? L("AI 正在回复") : (workspace.preferences.provider == .chatGPT ? "ChatGPT" : (workspace.preferences.model.isEmpty ? L("AI 未配置") : workspace.preferences.provider.rawValue))).foregroundStyle(workspace.busy ? .orange : .secondary)
            }.font(.caption).padding(10)
        }
        .preferredColorScheme(workspace.preferences.interfaceTheme.colorScheme)
        .environment(\.locale, Locale(identifier: workspace.preferences.language.resolved() == .chinese ? "zh-Hans" : "en"))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { sftpBookmark = workspace.activeSession?.bookmark } label: { Image(systemName: "folder") }
                    .disabled(workspace.activeSession?.bookmark == nil).help(L("打开当前主机 SFTP")).accessibilityLabel(L("打开当前主机 SFTP"))
                Button { workspace.setLayout(bookmarks: !workspace.preferences.showBookmarks, chat: workspace.preferences.showChat) } label: {
                    Image(systemName: "sidebar.left").foregroundStyle(workspace.preferences.showBookmarks ? Color.accentColor : Color.secondary)
                }.help(L("显示书签栏")).accessibilityLabel(L("显示书签栏"))
                Menu {
                    Toggle(L("显示书签栏"), isOn: Binding(get: { workspace.preferences.showBookmarks }, set: { workspace.setLayout(bookmarks: $0, chat: workspace.preferences.showChat) }))
                    Toggle(L("显示聊天栏"), isOn: Binding(get: { workspace.preferences.showChat }, set: { workspace.setLayout(bookmarks: workspace.preferences.showBookmarks, chat: $0) }))
                    Divider()
                    Button(L("恢复默认布局")) { workspace.setLayout(bookmarks: true, chat: true) }
                } label: { Image(systemName: "square.grid.2x2") }
                    .help(L("界面布局")).accessibilityLabel(L("界面布局"))
                Button { workspace.setLayout(bookmarks: false, chat: false) } label: { Image(systemName: "rectangle") }
                    .help(L("仅终端")).accessibilityLabel(L("仅终端"))
                Button { workspace.setLayout(bookmarks: workspace.preferences.showBookmarks, chat: !workspace.preferences.showChat) } label: {
                    Image(systemName: "sidebar.right").foregroundStyle(workspace.preferences.showChat ? Color.accentColor : Color.secondary)
                }.help(L("显示聊天栏")).accessibilityLabel(L("显示聊天栏"))
            }
        }
        .onChange(of: colorScheme) { scheme in workspace.applyTerminalTheme(light: scheme == .light) }
        .sheet(item: $sftpBookmark) { bookmark in SFTPView(bookmark: bookmark, language: workspace.preferences.language.resolved().rawValue) }
        .sheet(item: $renameTarget) { chat in RenameChatView(workspace: workspace, chat: chat) }
        .alert(L("删除聊天？"), isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
            Button(L("取消"), role: .cancel) { deleteTarget = nil }
            Button(L("删除"), role: .destructive) { if let chat = deleteTarget { workspace.deleteChat(chat.id) }; deleteTarget = nil }
        } message: { Text(L("删除“%@”及其本地消息记录。", deleteTarget?.name ?? "")) }
        .sheet(isPresented: $workspace.settingsShown) { SettingsView(workspace: workspace) }
        .sheet(isPresented: $workspace.bookmarkShown) { BookmarkView(workspace: workspace, existing: workspace.editingBookmark) }
        .sheet(isPresented: $workspace.foldersShown) { FolderManagerView(workspace: workspace) }
        .sheet(isPresented: $workspace.historyShown) { HistoryView(workspace: workspace) }
        .sheet(item: $workspace.proposal) { p in RunView(workspace: workspace, proposal: p) }
        .alert("TermGPT", isPresented: Binding(get: { workspace.error != nil }, set: { if !$0 { workspace.error = nil } })) { Button(L("好")) { workspace.error = nil } } message: { Text(L(workspace.error ?? "")) }
        .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true); workspace.applyTerminalTheme(light: colorScheme == .light) }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Image(nsImage: TermGPTIcon.image).resizable().frame(width: 28, height: 28); Text("TermGPT").font(.title2.bold()) }.padding(.top, 8)
            Text("AI TERMINAL WORKBENCH").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            Divider()
            HStack { Text(L("SSH 书签")).font(.headline); Spacer(); Button { workspace.foldersShown = true } label: { Image(systemName: "folder.badge.gearshape") }.buttonStyle(.plain).help(L("管理文件夹")); Button { workspace.editingBookmark = nil; workspace.bookmarkShown = true } label: { Image(systemName: "plus") }.buttonStyle(.plain) }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Button { workspace.newLocal() } label: { Label(L("Local Shell"), systemImage: "laptopcomputer").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 18).padding(.vertical, 8).contentShape(Rectangle()) }.buttonStyle(.plain)
                    ForEach(workspace.folders) { folder in BookmarkFolderSection(workspace: workspace, folder: folder) }
                    ForEach(workspace.bookmarks.filter { item in item.folderID == nil || !workspace.folders.contains(where: { $0.id == item.folderID }) }) { bookmark in
                        BookmarkRow(workspace: workspace, bookmark: bookmark).padding(.leading, 11)
                    }
                    if workspace.bookmarks.isEmpty { Text(L("添加主机书签后点击连接。SSH 密码及主机指纹确认会在真实终端中显示。")).font(.caption).foregroundStyle(.secondary).padding(.vertical, 10) }
                }
            }
            Divider()
            HStack { Text(L("聊天")).font(.headline); Spacer(); Button { workspace.newChat() } label: { Image(systemName: "plus") }.buttonStyle(.plain).disabled(workspace.busy) }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(workspace.chats) { chat in
                        HStack(spacing: 0) {
                            Button { workspace.chatID = chat.id } label: {
                                Text(chat.nameIsCustom != true && chat.name == "新聊天" ? L("新聊天") : chat.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).padding(7).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Menu {
                                Button(L("重命名")) { renameTarget = chat }
                                Button(L("删除"), role: .destructive) { deleteTarget = chat }
                            } label: { Image(systemName: "ellipsis") }
                                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22).padding(7).disabled(workspace.busy)
                                .accessibilityLabel(L("聊天菜单：%@", chat.name))
                        }.background(workspace.chatID == chat.id ? Color.accentColor.opacity(0.14) : Color.clear).cornerRadius(6)
                            .contextMenu {
                                Button(L("重命名")) { renameTarget = chat }.disabled(workspace.busy)
                                Button(L("删除"), role: .destructive) { deleteTarget = chat }.disabled(workspace.busy)
                            }
                    }
                }
            }.frame(maxHeight: 180)
            Spacer()
            Button { workspace.export() } label: { Label(L("导出会话"), systemImage: "square.and.arrow.up") }.buttonStyle(.plain)
            Button { workspace.settingsShown = true } label: { Label(L("设置"), systemImage: "gearshape") }.buttonStyle(.plain)
        }.padding(16).background(Color(nsColor: .controlBackgroundColor))
    }
    var terminal: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(workspace.sessions) { session in
                        TerminalTab(session: session, active: workspace.active == session.id, select: { workspace.active = session.id }, close: { workspace.close(session.id) })
                            .contextMenu {
                                Button(L("关闭当前终端")) { workspace.close(session.id) }
                                Button(L("关闭右侧标签页")) { workspace.closeRight(of: session.id) }
                                    .disabled(workspace.sessions.last?.id == session.id)
                                Button(L("关闭全部标签页")) { workspace.closeAllTerminals() }
                            }
                            .onDrag {
                                draggedTerminal = session.id
                                return NSItemProvider(item: Data(session.id.uuidString.utf8) as NSData, typeIdentifier: TerminalTabDrop.type.identifier)
                            }
                            .onDrop(of: [TerminalTabDrop.type], delegate: TerminalTabDrop(target: session.id, workspace: workspace, dragged: $draggedTerminal))
                    }
                    Button { workspace.newLocal() } label: { Image(systemName: "plus") }.buttonStyle(.plain).padding(10)
                }.padding(6)
            }.frame(height: 47)
            Divider()
            if let session = workspace.activeSession {
                ZStack {
                    ForEach(workspace.sessions) { pane in
                        TerminalHost(session: pane)
                            .opacity(workspace.active == pane.id ? 1 : 0)
                            .allowsHitTesting(workspace.active == pane.id)
                            .accessibilityHidden(workspace.active != pane.id)
                    }
                }
                SessionFooter(session: session)
            } else {
                VStack(spacing: 18) { Image(systemName: "terminal").font(.largeTitle); Button(L("打开本地终端")) { workspace.newLocal() } }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    var chat: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(L("AI 助手"), systemImage: "sparkles").font(.headline)
                Spacer()
                Button { scrollToLatestRequest += 1 } label: { Image(systemName: "arrow.down.to.line") }
                    .help(L("滚动到最新")).accessibilityLabel(L("滚动到最新"))
                Button { workspace.clearChat() } label: { Image(systemName: "trash") }.disabled(workspace.busy).help(L("清空当前聊天"))
            }.padding(16)
            Divider()
            HStack {
                Picker("Context", selection: $workspace.contextMode) { ForEach(ContextMode.allCases, id: \.self) { Text(L($0.rawValue)).tag($0) } }.labelsHidden().frame(maxWidth: 175)
                Spacer()

                Button { workspace.locked = workspace.locked == nil ? workspace.active : nil } label: { Image(systemName: workspace.locked == nil ? "lock.open" : "lock.fill") }.help(L("锁定 AI 上下文；命令仍发送到当前可见终端"))
            }.padding(12)
            VStack(alignment: .leading, spacing: 5) {
                Label(L(workspace.busy ? "本次正在分析：%@" : "下次上下文：%@", workspace.busy ? (workspace.replyAnalysisTarget ?? L("未附终端上下文")) : workspace.analysisTargetLabel), systemImage: "text.magnifyingglass")
                if !workspace.busy && workspace.contextMode == .auto { Text(L("自动模式仅在问题与终端相关时附加上下文。")).foregroundStyle(.secondary) }
                if workspace.locked != nil { Text(L("上下文已锁定；切换标签页不会改变分析来源。")).foregroundStyle(.secondary) }
                Label(L("命令发送到：%@", workspace.executionTargetLabel), systemImage: "terminal")
            }.font(.caption).textSelection(.enabled).padding(.horizontal, 12).padding(.bottom, 12)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if workspace.currentChat.messages.isEmpty {
                            VStack(alignment: .leading, spacing: 15) {
                                Image(systemName: "sparkles").font(.system(size: 35)).foregroundStyle(.mint)
                                Text(L("终端与 AI，一起工作。")).font(.title2.bold())
                                Text(L("可以问普通问题，也可以分析当前终端。选中终端文本后右键 Ask AI，即可带入上下文。")).foregroundStyle(.secondary)
                                Text(L("在设置中 Continue with ChatGPT 即可连接。OpenAI API、Ollama 与 LM Studio 位于 Advanced / Other Providers。")).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 30)
                        }
                        ForEach(workspace.currentChat.messages) { message in MessageView(message: message, workspace: workspace).id(message.id) }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(18)
                // Streaming updates never change the user's scroll position.
                // Switching conversations or explicitly requesting latest scrolls to the bottom.
                }.onChange(of: scrollToLatestRequest) { _ in proxy.scrollTo("bottom", anchor: .bottom) }
                    .task(id: workspace.chatID) {
                        // Yield until the newly selected conversation is laid out.
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
            }
            Divider()
            VStack(spacing: 8) {
                ChatInput(text: $workspace.input, onSubmit: { workspace.send() }).font(.body).frame(height: 76).overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.25)))
                HStack {
                    ProviderCaption(account: workspace.chatGPT, provider: workspace.preferences.provider)
                    Spacer()
                    if workspace.busy { Button(L("停止")) { workspace.cancel() } }
                    else { Button(L("发送")) { workspace.send() }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command).disabled(workspace.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
            }.padding(14)
        }
    }
}
struct TerminalTab: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var session: TerminalSession
    let active: Bool
    let select: () -> Void
    let close: () -> Void
    var body: some View {
        HStack(spacing: 7) {
            Button(action: select) { HStack { Circle().fill(session.running ? (session.bookmark == nil ? Color.green : Color.yellow) : Color.gray).frame(width: 7, height: 7); Text(session.name) } }.buttonStyle(.plain)
            Button(action: close) { Image(systemName: "xmark").font(.system(size: 9)) }.buttonStyle(.plain)
        }.padding(9).background(active ? Color.accentColor.opacity(0.13) : Color.clear).cornerRadius(7)
    }
}
struct SessionFooter: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var session: TerminalSession
    var body: some View { HStack { Text(L(session.status)); Spacer(); Text(session.cwd).lineLimit(1) }.font(.caption).foregroundStyle(.secondary).padding(8) }
}
struct MessageView: View {
    @ObservedObject private var localization = Localization.shared
    let message: Message
    @ObservedObject var workspace: Workspace
    var parts: [String] { message.content.components(separatedBy: "```") }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message.role == "user" ? L("你") : "AI").font(.caption.bold()).foregroundStyle(message.role == "user" ? Color.secondary : Color.mint)
            if message.role == "user" {
                Text(message.content.components(separatedBy: "\n\n<terminal_context")[0]).textSelection(.enabled)
                if message.content.contains("<terminal_context") { Text(L("已附终端上下文")).font(.caption).foregroundStyle(.secondary) }
            } else {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    if index % 2 == 0 { Text(.init(part)).textSelection(.enabled) }
                    else {
                        let block = ReplyCodeBlock(part)
                        let code = block.content
                        VStack(alignment: .leading, spacing: 10) {
                            Text(code).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            if block.isShellCommand {
                                Label(L("填入 / 执行目标：%@", workspace.executionTargetLabel), systemImage: "terminal")
                                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                if workspace.locked != nil && workspace.locked != workspace.active {
                                    Text(L("分析来源与执行目标不同，请核对目标主机。")).font(.caption).foregroundStyle(.orange)
                                }
                            }
                            HStack {
                                if block.isShellCommand {
                                    Text(Safety.highRisk(code) ? L("需谨慎确认") : L("LOW")).font(.system(size: 10, weight: .bold)).foregroundStyle(Safety.highRisk(code) ? .orange : .green)
                                }
                                Spacer()
                                Button(L("复制")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string) }
                                if block.isShellCommand {
                                    Button(L("填入")) { workspace.insert(code) }.disabled(!Safety.insertable(code) || workspace.busy || workspace.activeSession?.running != true || index == parts.count - 1)
                                    Button(L("执行…")) { workspace.propose(code) }.disabled(!Safety.insertable(code) || workspace.busy || workspace.activeSession?.running != true || index == parts.count - 1)
                                }
                            }.font(.caption)
                        }.padding(12).background(Color.primary.opacity(0.055)).cornerRadius(8)
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct RunView: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var workspace: Workspace
    let proposal: RunProposal
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(proposal.high ? L("潜在危险命令") : L("确认执行"), systemImage: proposal.high ? "exclamationmark.triangle" : "terminal").font(.title2)
            Text(L("目标终端：%@", workspace.sessions.first(where: { $0.id == proposal.target })?.targetLabel ?? proposal.name)).font(.headline)
            Text(proposal.command).font(.system(.body, design: .monospaced)).textSelection(.enabled).padding().frame(maxWidth: .infinity, alignment: .leading).background(Color.secondary.opacity(0.1)).cornerRadius(8)
            Text(L("如果终端正在 vim、密码提示或其他交互程序中，请先取消并退出该程序。")).font(.caption).foregroundStyle(.secondary)
            HStack { Button(L("取消")) { workspace.proposal = nil }; Spacer(); Button(L("确认执行")) { workspace.proposal = nil; workspace.run(proposal) }.buttonStyle(.borderedProminent) }
        }.padding(24).frame(width: 560)
    }
}
struct SettingsView: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var workspace: Workspace
    @Environment(\.dismiss) var dismiss
    @State private var preferences = Preferences()
    @State private var key = ""
    @State private var advanced = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(nsImage: TermGPTIcon.image).resizable().frame(width: 44, height: 44)
                VStack(alignment: .leading) { Text(L("设置")).font(.title2.bold()); Text(L("连接你的 AI，保留完整终端体验。")).font(.caption).foregroundStyle(.secondary) }
                Spacer()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ChatGPTSettings(account: workspace.chatGPT, preferences: $preferences, workspace: workspace)
                    DisclosureGroup(L("Advanced / Other Providers"), isExpanded: $advanced) {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker(L("AI Provider"), selection: $preferences.provider) {
                                ForEach(ProviderKind.allCases, id: \.self) { Text(L($0.rawValue)).tag($0) }
                            }.onChange(of: preferences.provider) { kind in
                                guard kind != .chatGPT else { return }
                                preferences.endpoint = kind.defaultEndpoint; preferences.model = ""
                            }
                            if preferences.provider != .chatGPT {
                                TextField(L("API Base URL"), text: $preferences.endpoint)
                                TextField(L("模型名称"), text: $preferences.model)
                                if preferences.provider != .ollama && preferences.provider != .lmStudio { SecureField(L("API Key（JSON 配置）"), text: $key) }
                                Text(preferences.provider == .openAI ? L("OpenAI API 使用独立 API 密钥与计费。ChatGPT 连接保存在上方。") : L("请先启动服务，并填写该服务实际提供的模型名称。")).font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.top, 12)
                    }.padding(16).background(Color.primary.opacity(0.04)).cornerRadius(12)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Terminal & Privacy")).font(.headline)
                        Picker(L("界面语言"), selection: $preferences.language) {
                            ForEach(InterfaceLanguage.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        Text(L("系统语言为中文时使用中文，其他语言使用英语。保存后立即生效。")).font(.caption).foregroundStyle(.secondary)
                        TextField(L("Shell 路径"), text: $preferences.shell)
                        Slider(value: $preferences.fontSize, in: 10...24, step: 1) { Text(L("字体大小 %@", String(Int(preferences.fontSize)))) }
                        Picker(L("界面主题"), selection: $preferences.interfaceTheme) {
                            ForEach(InterfaceTheme.allCases, id: \.self) { Text(L($0.rawValue)).tag($0) }
                        }
                        Text(L("主题应用于整个界面、弹窗、聊天输入框和终端。")).font(.caption).foregroundStyle(.secondary)
                        Toggle(L("保存聊天到本机"), isOn: $preferences.saveMemory)
                        Toggle(L("发送前自动脱敏"), isOn: $preferences.redactBeforeSending)
                        Text(preferences.redactBeforeSending ? L("自动替换消息、历史聊天及终端上下文中的常见敏感字段，不弹出确认框。") : L("按原文发送消息、历史聊天及终端上下文；其中的密码、Token 或私钥也会发送给当前 AI Provider。"))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(L("终端回滚仅保存在当前进程。发送问题时，所选上下文会提交给当前 AI Provider。")).font(.caption).foregroundStyle(.secondary)
                    }.padding(16)
                }
            }.frame(maxHeight: 590)
            HStack { Button(L("取消")) { dismiss() }; Spacer(); Button(L("保存")) {
                do {
                    // Selecting ChatGPT must never erase a separately saved API key.
                    if preferences.provider == .openAI || preferences.provider == .custom { try APIKeyStore.write(key) }
                    workspace.preferences = preferences; workspace.sessions.forEach { $0.apply(preferences) }; workspace.persist(); dismiss()
                } catch { workspace.error = error.localizedDescription }
            }.buttonStyle(.borderedProminent) }
        }.padding(24).frame(width: 660).onAppear { preferences = workspace.preferences; do { key = try APIKeyStore.read() } catch { workspace.error = error.localizedDescription }; advanced = preferences.provider != .chatGPT }
    }
}
struct ChatGPTSettings: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var account: ChatGPTAccount
    @Binding var preferences: Preferences
    @ObservedObject var workspace: Workspace
    @State private var disconnecting = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text(L("AI Provider")).font(.caption).foregroundStyle(.secondary); Text("ChatGPT").font(.title2.bold()) }
                Spacer()
                if preferences.provider == .chatGPT { Text(L("首选")).font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 5).background(Color.mint.opacity(0.15)).cornerRadius(20) }
                else { Button(L("使用 ChatGPT")) { preferences.provider = .chatGPT } }
            }
            Divider()
            if account.connected {
                HStack { Text(L("Account")).foregroundStyle(.secondary); Spacer(); Label(L("已连接"), systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                if let current = account.account {
                    if !current.email.isEmpty { Text(current.email).font(.callout).textSelection(.enabled) }
                    HStack { Text(L("Plan")).foregroundStyle(.secondary); Spacer(); Text(current.plan ?? L("ChatGPT plan（套餐名称未返回）")) }
                }
                Picker(L("Model"), selection: $preferences.chatGPTModel) {
                    Text(L("Auto")).tag("")
                    ForEach(account.models) { Text($0.name).tag($0.id) }
                    if !preferences.chatGPTModel.isEmpty && !account.models.contains(where: { $0.id == preferences.chatGPTModel }) { Text(preferences.chatGPTModel + L("（待验证）")).tag(preferences.chatGPTModel) }
                }
                HStack {
                    Button(L("Disconnect"), role: .destructive) {
                        workspace.cancel(); disconnecting = true
                        Task { await account.disconnect(); disconnecting = false }
                    }.disabled(disconnecting || account.connecting || workspace.busy)
                    Button(L("刷新模型")) { Task { await account.refreshModels() } }.disabled(workspace.busy)
                    Spacer()
                    Link(L("Manage usage"), destination: URL(string: "https://chatgpt.com/#settings/Usage")!)
                }
                if account.vault.registrations.count > 1 {
                    Picker(L("账户"), selection: Binding(get: { account.vault.selected ?? "" }, set: { account.select($0); preferences.chatGPTModel = "" })) {
                        ForEach(account.vault.registrations) { record in Text((record.email.isEmpty ? L("待验证账户") : record.email) + " · " + String(record.clientID.suffix(6))).tag(record.clientID) }
                    }.disabled(workspace.busy || account.connecting)
                }
                Button(L("连接其他 ChatGPT 账户")) { account.connect(newAccount: true) }.disabled(workspace.busy || account.connecting)
                Text(L("Using ChatGPT plan · 合资格请求使用你授权的套餐或可用额度。")).font(.caption).foregroundStyle(.secondary)
            } else {
                HStack { Text(L("Status")).foregroundStyle(.secondary); Spacer(); Text(account.loadingAccount ? L("读取账户…") : (account.connecting ? L("Connecting…") : L("Not connected"))).foregroundStyle(.secondary) }
                Button { account.connect() } label: {
                    HStack { Image(systemName: "person.crop.circle"); Text(L("Continue with ChatGPT")).fontWeight(.semibold) }.frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.borderedProminent).tint(.primary).disabled(account.loadingAccount || account.connecting || workspace.busy)
                if account.connecting { Button(L("取消连接")) { account.cancelLogin() } }
                Text(L("在系统浏览器完成登录和套餐授权，无需 API Key。成功验证身份后显示账户与模型。")).font(.caption).foregroundStyle(.secondary)
            }
            if !account.message.isEmpty && account.message != "已连接" { Text(L(account.message)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
        }.padding(18).background(Color.primary.opacity(0.035)).cornerRadius(14)
        .task { if account.connected { await account.refreshModels() } }
        .alert(L("You're using your ChatGPT plan"), isPresented: $account.welcome) { Button(L("Got it")) { account.acknowledgeWelcome(); preferences.provider = .chatGPT } } message: { Text(L("TermGPT 中合资格的 AI 请求会使用你授权的 ChatGPT 套餐或可用额度。你可以在 ChatGPT Settings → Usage 管理访问和用量。")) }
    }
}
struct BookmarkRow: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var workspace: Workspace
    let bookmark: Bookmark
    var body: some View {
        HStack(spacing: 0) {
            Button { workspace.open(name: bookmark.name, bookmark: bookmark) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Label(bookmark.name, systemImage: "server.rack").lineLimit(1)
                    Text(bookmark.host).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(7).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Menu { actions } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22).padding(7).accessibilityLabel(L("书签菜单：%@", bookmark.name))
        }.contextMenu { actions }
    }
    @ViewBuilder private var actions: some View {
        Button(L("连接")) { workspace.open(name: bookmark.name, bookmark: bookmark) }
        Button(L("编辑 / 重命名")) { workspace.editingBookmark = bookmark; workspace.bookmarkShown = true }
        Menu(L("移动到文件夹")) {
            Button(L("未分类")) { workspace.moveBookmark(bookmark.id, folder: nil) }
            ForEach(workspace.folders) { folder in Button(folder.name) { workspace.moveBookmark(bookmark.id, folder: folder.id) } }
        }
        Button(L("删除书签"), role: .destructive) { workspace.deleteBookmark(bookmark.id) }
    }
}
struct BookmarkFolderSection: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var workspace: Workspace
    let folder: BookmarkFolder
    @State private var expanded = true
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .semibold)).frame(width: 12)
                    Label(folder.name, systemImage: "folder").lineLimit(1)
                    Spacer(minLength: 0)
                }.contentShape(Rectangle()).padding(.vertical, 8)
            }.buttonStyle(.plain)
                .accessibilityValue(expanded ? L("已展开") : L("已折叠"))
                .contextMenu { Button(L("管理文件夹")) { workspace.foldersShown = true } }
            if expanded {
                ForEach(workspace.bookmarks.filter { $0.folderID == folder.id }) {
                    BookmarkRow(workspace: workspace, bookmark: $0).padding(.leading, 36)
                }
            }
        }
    }
}
struct FolderManagerView: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var workspace: Workspace
    @Environment(\.dismiss) var dismiss
    @State private var folders: [BookmarkFolder] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(L("管理书签文件夹")).font(.title2.bold()); Spacer(); Button(L("新建文件夹")) { folders.append(BookmarkFolder(name: L("新文件夹"))) } }
            ScrollView {
                VStack(spacing: 12) {
                    ForEach($folders) { $folder in
                        HStack {
                            Image(systemName: "folder")
                            TextField(L("文件夹名称"), text: $folder.name).textFieldStyle(.roundedBorder)
                            Button(L("删除"), role: .destructive) { folders.removeAll { $0.id == folder.id } }
                        }
                    }
                }
            }
            Text(L("删除文件夹后，其中的书签移到未分类，不删除书签。修改名称后点击保存。"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L("取消")) { dismiss() }; Spacer()
                Button(L("保存")) { workspace.saveFolders(folders); dismiss() }.buttonStyle(.borderedProminent)
                    .disabled(folders.contains { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            }
        }.padding(24).frame(width: 500, height: 400).onAppear { folders = workspace.folders }
    }
}
struct RenameChatView: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var workspace: Workspace
    let chat: Chat
    @Environment(\.dismiss) var dismiss
    @State private var title = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("重命名聊天")).font(.title2.bold())
            TextField(L("聊天名称"), text: $title).textFieldStyle(.roundedBorder).focused($focused)
                .onSubmit { save() }
            HStack {
                Button(L("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L("保存")) { save() }.buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || workspace.busy)
            }
        }.padding(24).frame(width: 400).onAppear { title = chat.name; focused = true }
    }
    private func save() {
        guard !workspace.busy, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        workspace.renameChat(chat.id, title: title); dismiss()
    }
}
struct BookmarkView: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var workspace: Workspace
    @Environment(\.dismiss) var dismiss
    let existing: Bookmark?
    @State private var bookmark = Bookmark()
    @State private var password = ""
    @State private var formError = ""
    @FocusState private var nameFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(existing == nil ? L("新增 SSH 书签") : L("编辑 SSH 书签")).font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field(L("名称")) { TextField(L("例如：开发服务器"), text: $bookmark.name).focused($nameFocused) }
                    field(L("主机 / SSH config 别名")) { TextField(L("主机名或 config 别名"), text: $bookmark.host) }
                    HStack(alignment: .top, spacing: 16) {
                        field(L("端口")) { TextField("22", value: $bookmark.port, formatter: NumberFormatter()) }.frame(width: 100)
                        field(L("用户名"), help: L("留空使用 SSH config")) { TextField(L("可选"), text: $bookmark.user) }
                    }
                    field(L("文件夹")) {
                        Picker(L("文件夹"), selection: $bookmark.folderID) {
                            Text(L("未分类")).tag(Optional<UUID>.none)
                            ForEach(workspace.folders) { folder in Text(folder.name).tag(Optional(folder.id)) }
                        }.labelsHidden()
                    }
                    field(L("登录方式")) {
                        Picker(L("登录方式"), selection: Binding(get: { bookmark.authentication ?? (bookmark.keyPath.isEmpty ? .automatic : .key) }, set: { bookmark.authentication = $0 })) {
                            ForEach(SSHAuthentication.allCases, id: \.self) { Text(L($0.rawValue)).tag($0) }
                        }.labelsHidden()
                    }
                    if bookmark.authentication == .password {
                        field(L("密码"), help: L("保存到本机 JSON 配置，不使用钥匙串")) { SecureField(L("SSH 登录密码"), text: $password) }
                    } else if bookmark.authentication == .key || (bookmark.authentication == nil && !bookmark.keyPath.isEmpty) {
                        field(L("私钥路径"), help: L("私钥文件留在本机；加密私钥的口令由终端提示或 SSH Agent 处理")) {
                            HStack {
                                TextField("~/.ssh/id_ed25519", text: $bookmark.keyPath)
                                Button(L("选择…")) {
                                    let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
                                    if panel.runModal() == .OK, let path = panel.url?.path { bookmark.keyPath = path }
                                }
                            }
                        }
                    }
                    field(L("备注")) { TextField(L("可选"), text: $bookmark.notes) }
                    Text(L("采用系统 OpenSSH，兼容 ~/.ssh/config、SSH Agent 和 Known Hosts。保存的密码仅通过 SSH 认证组件使用；首次连接仍需确认主机指纹。"))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 8)
            }
            if !formError.isEmpty { Text(L(formError)).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            Divider()
            HStack {
                Button(L("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L("保存")) {
                    do { try workspace.saveBookmark(bookmark, password: password); dismiss() }
                    catch { formError = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled(bookmark.name.isEmpty || bookmark.host.isEmpty)
            }
        }.textFieldStyle(.roundedBorder).padding(24).frame(width: 600, height: 640)
            .onAppear { if let existing {
                    bookmark = existing
                    bookmark.authentication = existing.authentication ?? (existing.keyPath.isEmpty ? .automatic : .key)
                    let load = Task.detached { try SSHPasswordStore.read(id: existing.id) }
                    Task { do { let saved = try await load.value; if password.isEmpty { password = saved ?? "" } } catch { formError = error.localizedDescription } }
                }; nameFocused = true }
    }
    private func field<Content: View>(_ title: String, help: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.medium))
            content().accessibilityLabel(title)
            if let help {
                Text(help).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct HistoryView: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var workspace: Workspace
    @Environment(\.dismiss) var dismiss
    @State private var snapshot = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("终端历史 · %@", workspace.activeSession?.name ?? L("无终端"))).font(.title2)
            TextField(L("搜索文本"), text: $workspace.search)
            ScrollView { Text(workspace.search.isEmpty ? snapshot : snapshot.components(separatedBy: "\n").filter { $0.localizedCaseInsensitiveContains(workspace.search) }.joined(separator: "\n")).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            HStack { Button(L("刷新")) { snapshot = workspace.activeSession?.snapshot() ?? "" }; Spacer(); Button(L("关闭")) { dismiss() } }
        }.padding(24).frame(width: 800, height: 560).onAppear { snapshot = workspace.activeSession?.snapshot() ?? "" }
    }
}

struct ProviderCaption: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var account: ChatGPTAccount
    let provider: ProviderKind
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(provider == .chatGPT ? (account.connected ? L("Using ChatGPT plan") : L("ChatGPT · Not connected")) : provider.rawValue).font(.caption).foregroundStyle(.secondary)
            Text(L("Enter 发送 · ⌥Enter 换行")).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

extension InterfaceTheme {
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}
