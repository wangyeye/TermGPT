import SwiftUI
import AppKit

enum TermGPTIcon {
    static let image: NSImage = Bundle.main.url(forResource: "TermGPT", withExtension: "icns").flatMap { NSImage(contentsOf: $0) } ?? NSApp.applicationIconImage
}

@main struct TermGPTApp: App {
    @StateObject private var workspace = Workspace()
    var body: some Scene {
        WindowGroup("TermGPT") {
            MainView(workspace: workspace).frame(minWidth: 1080, minHeight: 680)
                .onAppear { NSApp.applicationIconImage = TermGPTIcon.image }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in workspace.shutdown() }
        }.commands {
            CommandGroup(replacing: .newItem) {
                Button("新建本地终端") { workspace.newLocal() }.keyboardShortcut("t")
                Button("新建聊天") { workspace.newChat() }.keyboardShortcut("n", modifiers: [.command, .shift])
                Button("关闭当前终端") { if let id = workspace.active { workspace.close(id) } }.keyboardShortcut("w")
            }
            CommandGroup(replacing: .appSettings) { Button("设置…") { workspace.settingsShown = true }.keyboardShortcut(",") }
            CommandMenu("终端") {
                Button("终端历史与搜索") { workspace.historyShown = true }.keyboardShortcut("f")
                Button("导出会话") { workspace.export() }
            }
        }
    }
}
struct MainView: View {
    @ObservedObject var workspace: Workspace
    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                sidebar.frame(minWidth: 170, idealWidth: 190, maxWidth: 260)
                terminal.frame(minWidth: 400, idealWidth: 680)
                chat.frame(minWidth: 350, idealWidth: 430)
            }
            Divider()
            HStack {
                Label(workspace.activeSession?.name ?? "无终端", systemImage: "terminal")
                Text(workspace.notice.isEmpty ? "上下文：\(workspace.contextMode.rawValue) · 默认仅建议命令" : workspace.notice).lineLimit(1)
                Spacer()
                Text(workspace.busy ? "AI 正在回复" : (workspace.preferences.provider == .chatGPT ? "ChatGPT" : (workspace.preferences.model.isEmpty ? "AI 未配置" : workspace.preferences.provider.rawValue))).foregroundStyle(workspace.busy ? .orange : .secondary)
            }.font(.caption).padding(10)
        }
        .sheet(isPresented: $workspace.settingsShown) { SettingsView(workspace: workspace) }
        .sheet(isPresented: $workspace.bookmarkShown) { BookmarkView(workspace: workspace) }
        .sheet(isPresented: $workspace.historyShown) { HistoryView(workspace: workspace) }
        .sheet(item: $workspace.proposal) { p in RunView(workspace: workspace, proposal: p) }
        .alert("TermGPT", isPresented: Binding(get: { workspace.error != nil }, set: { if !$0 { workspace.error = nil } })) { Button("好") { workspace.error = nil } } message: { Text(workspace.error ?? "") }
        .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Image(nsImage: TermGPTIcon.image).resizable().frame(width: 28, height: 28); Text("TermGPT").font(.title2.bold()) }.padding(.top, 8)
            Text("AI TERMINAL WORKBENCH").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            Divider()
            HStack { Text("SSH 书签").font(.headline); Spacer(); Button { workspace.bookmarkShown = true } label: { Image(systemName: "plus") }.buttonStyle(.plain) }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Button { workspace.newLocal() } label: { Label("Local Shell", systemImage: "laptopcomputer") }.buttonStyle(.plain).padding(.vertical, 8)
                    ForEach(workspace.bookmarks) { bookmark in
                        Button { workspace.open(name: bookmark.name, bookmark: bookmark) } label: {
                            VStack(alignment: .leading, spacing: 4) { Label(bookmark.name, systemImage: "server.rack"); Text(bookmark.host).font(.caption).foregroundStyle(.secondary) }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain).contextMenu {
                            Button("连接") { workspace.open(name: bookmark.name, bookmark: bookmark) }
                            Button("删除书签", role: .destructive) { workspace.bookmarks.removeAll { $0.id == bookmark.id }; workspace.persist() }
                        }
                    }
                    if workspace.bookmarks.isEmpty { Text("添加主机书签后点击连接。SSH 密码及主机指纹确认会在真实终端中显示。").font(.caption).foregroundStyle(.secondary).padding(.vertical, 10) }
                }
            }
            Divider()
            HStack { Text("聊天").font(.headline); Spacer(); Button { workspace.newChat() } label: { Image(systemName: "plus") }.buttonStyle(.plain).disabled(workspace.busy) }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) { ForEach(workspace.chats) { c in Button { workspace.chatID = c.id } label: { Text(c.name).lineLimit(1).padding(7).frame(maxWidth: .infinity, alignment: .leading).background(workspace.chatID == c.id ? Color.accentColor.opacity(0.14) : Color.clear).cornerRadius(6) }.buttonStyle(.plain) } }
            }.frame(maxHeight: 180)
            Spacer()
            Button { workspace.export() } label: { Label("导出会话", systemImage: "square.and.arrow.up") }.buttonStyle(.plain)
            Button { workspace.settingsShown = true } label: { Label("设置", systemImage: "gearshape") }.buttonStyle(.plain)
        }.padding(16).background(Color(nsColor: .controlBackgroundColor))
    }
    var terminal: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(workspace.sessions) { session in TerminalTab(session: session, active: workspace.active == session.id, select: { workspace.active = session.id }, close: { workspace.close(session.id) }) }
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
                VStack(spacing: 18) { Image(systemName: "terminal").font(.largeTitle); Button("打开本地终端") { workspace.newLocal() } }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    var chat: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Label("AI Chat", systemImage: "sparkles").font(.headline); Spacer(); Button { workspace.clearChat() } label: { Image(systemName: "trash") }.disabled(workspace.busy).help("清空当前聊天") }.padding(16)
            Divider()
            HStack {
                Picker("Context", selection: $workspace.contextMode) { ForEach(ContextMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(maxWidth: 175)
                Spacer()
                Text(workspace.contextMode == .off ? "No Terminal" : workspace.contextSession?.name ?? "No Terminal").font(.caption).lineLimit(1)
                Button { workspace.locked = workspace.locked == nil ? workspace.active : nil } label: { Image(systemName: workspace.locked == nil ? "lock.open" : "lock.fill") }.help("锁定 AI 上下文；命令仍发送到当前可见终端")
            }.padding(12)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if workspace.currentChat.messages.isEmpty {
                            VStack(alignment: .leading, spacing: 15) {
                                Image(systemName: "sparkles").font(.system(size: 35)).foregroundStyle(.mint)
                                Text("终端与 AI，一起工作。").font(.title2.bold())
                                Text("可以问普通问题，也可以分析当前终端。选中终端文本后右键 Ask AI，即可带入上下文。").foregroundStyle(.secondary)
                                Text("在设置中 Continue with ChatGPT 即可连接。OpenAI API、Ollama 与 LM Studio 位于 Advanced / Other Providers。").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 30)
                        }
                        ForEach(workspace.currentChat.messages) { message in MessageView(message: message, workspace: workspace).id(message.id) }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(18)
                }.onChange(of: workspace.currentChat.messages.last?.content) { _ in proxy.scrollTo("bottom", anchor: .bottom) }
            }
            Divider()
            VStack(spacing: 8) {
                ChatInput(text: $workspace.input, onSubmit: { workspace.send() }).font(.body).frame(height: 76).overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.25)))
                HStack {
                    ProviderCaption(account: workspace.chatGPT, provider: workspace.preferences.provider)
                    Spacer()
                    if workspace.busy { Button("停止") { workspace.cancel() } }
                    else { Button("发送") { workspace.send() }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command).disabled(workspace.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
            }.padding(14)
        }
    }
}
struct TerminalTab: View {
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
    @ObservedObject var session: TerminalSession
    var body: some View { HStack { Text(session.status); Spacer(); Text(session.cwd).lineLimit(1) }.font(.caption).foregroundStyle(.secondary).padding(8) }
}
struct MessageView: View {
    let message: Message
    @ObservedObject var workspace: Workspace
    var parts: [String] { message.content.components(separatedBy: "```") }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message.role == "user" ? "你" : "AI").font(.caption.bold()).foregroundStyle(message.role == "user" ? Color.secondary : Color.mint)
            if message.role == "user" {
                Text(message.content.components(separatedBy: "\n\n<terminal_context")[0]).textSelection(.enabled)
                if message.content.contains("<terminal_context") { Text("已附终端上下文").font(.caption).foregroundStyle(.secondary) }
            } else {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    if index % 2 == 0 { Text(.init(part)).textSelection(.enabled) }
                    else {
                        let code = part.contains("\n") ? String(part.drop(while: { $0 != "\n" }).dropFirst()).trimmingCharacters(in: .newlines) : part
                        VStack(alignment: .leading, spacing: 10) {
                            Text(code).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            HStack {
                                Text(Safety.highRisk(code) ? "需谨慎确认" : "LOW").font(.system(size: 10, weight: .bold)).foregroundStyle(Safety.highRisk(code) ? .orange : .green)
                                Spacer()
                                Button("复制") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string) }
                                Button("填入") { workspace.insert(code) }.disabled(!Safety.insertable(code) || workspace.busy || index == parts.count - 1)
                                Button("执行…") { workspace.propose(code) }.disabled(!Safety.insertable(code) || workspace.busy || index == parts.count - 1)
                            }.font(.caption)
                        }.padding(12).background(Color.primary.opacity(0.055)).cornerRadius(8)
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct RunView: View {
    @ObservedObject var workspace: Workspace
    let proposal: RunProposal
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(proposal.high ? "潜在危险命令" : "确认执行", systemImage: proposal.high ? "exclamationmark.triangle" : "terminal").font(.title2)
            Text("目标终端：\(proposal.name)").font(.headline)
            Text(proposal.command).font(.system(.body, design: .monospaced)).textSelection(.enabled).padding().frame(maxWidth: .infinity, alignment: .leading).background(Color.secondary.opacity(0.1)).cornerRadius(8)
            Text("如果终端正在 vim、密码提示或其他交互程序中，请先取消并退出该程序。").font(.caption).foregroundStyle(.secondary)
            HStack { Button("取消") { workspace.proposal = nil }; Spacer(); Button("确认执行") { workspace.proposal = nil; workspace.run(proposal) }.buttonStyle(.borderedProminent) }
        }.padding(24).frame(width: 560)
    }
}
struct SettingsView: View {
    @ObservedObject var workspace: Workspace
    @Environment(\.dismiss) var dismiss
    @State private var preferences = Preferences()
    @State private var key = ""
    @State private var advanced = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(nsImage: TermGPTIcon.image).resizable().frame(width: 44, height: 44)
                VStack(alignment: .leading) { Text("设置").font(.title2.bold()); Text("连接你的 AI，保留完整终端体验。").font(.caption).foregroundStyle(.secondary) }
                Spacer()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ChatGPTSettings(account: workspace.chatGPT, preferences: $preferences, workspace: workspace)
                    DisclosureGroup("Advanced / Other Providers", isExpanded: $advanced) {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("AI Provider", selection: $preferences.provider) {
                                ForEach(ProviderKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }.onChange(of: preferences.provider) { kind in
                                guard kind != .chatGPT else { return }
                                preferences.endpoint = kind.defaultEndpoint; preferences.model = ""
                            }
                            if preferences.provider != .chatGPT {
                                TextField("API Base URL", text: $preferences.endpoint)
                                TextField("模型名称", text: $preferences.model)
                                if preferences.provider != .ollama && preferences.provider != .lmStudio { SecureField("API Key（Keychain）", text: $key) }
                                Text(preferences.provider == .openAI ? "OpenAI API 使用独立 API 密钥与计费。ChatGPT 连接保存在上方。" : "请先启动服务，并填写该服务实际提供的模型名称。").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.top, 12)
                    }.padding(16).background(Color.primary.opacity(0.04)).cornerRadius(12)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Terminal & Privacy").font(.headline)
                        TextField("Shell 路径", text: $preferences.shell)
                        Slider(value: $preferences.fontSize, in: 10...24, step: 1) { Text("字体大小 \(Int(preferences.fontSize))") }
                        Toggle("浅色终端", isOn: $preferences.lightTerminal)
                        Toggle("保存聊天到本机", isOn: $preferences.saveMemory)
                        Toggle("发送前自动脱敏", isOn: $preferences.redactBeforeSending)
                        Text(preferences.redactBeforeSending ? "自动替换消息、历史聊天及终端上下文中的常见敏感字段，不弹出确认框。" : "按原文发送消息、历史聊天及终端上下文；其中的密码、Token 或私钥也会发送给当前 AI Provider。")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("终端回滚仅保存在当前进程。发送问题时，所选上下文会提交给当前 AI Provider。").font(.caption).foregroundStyle(.secondary)
                    }.padding(16)
                }
            }.frame(maxHeight: 590)
            HStack { Button("取消") { dismiss() }; Spacer(); Button("保存") {
                do {
                    // Selecting ChatGPT must never erase a separately saved API key.
                    if preferences.provider == .openAI || preferences.provider == .custom { try Keychain.write(key) }
                    workspace.preferences = preferences; workspace.sessions.forEach { $0.apply(preferences) }; workspace.persist(); dismiss()
                } catch { workspace.error = error.localizedDescription }
            }.buttonStyle(.borderedProminent) }
        }.padding(24).frame(width: 660).onAppear { preferences = workspace.preferences; key = Keychain.read(); advanced = preferences.provider != .chatGPT }
    }
}
struct ChatGPTSettings: View {
    @ObservedObject var account: ChatGPTAccount
    @Binding var preferences: Preferences
    @ObservedObject var workspace: Workspace
    @State private var disconnecting = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text("AI Provider").font(.caption).foregroundStyle(.secondary); Text("ChatGPT").font(.title2.bold()) }
                Spacer()
                if preferences.provider == .chatGPT { Text("首选").font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 5).background(Color.mint.opacity(0.15)).cornerRadius(20) }
                else { Button("使用 ChatGPT") { preferences.provider = .chatGPT } }
            }
            Divider()
            if account.connected {
                HStack { Text("Account").foregroundStyle(.secondary); Spacer(); Label("已连接", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                if let current = account.account {
                    if !current.email.isEmpty { Text(current.email).font(.callout).textSelection(.enabled) }
                    HStack { Text("Plan").foregroundStyle(.secondary); Spacer(); Text(current.plan ?? "ChatGPT plan（套餐名称未返回）") }
                }
                Picker("Model", selection: $preferences.chatGPTModel) {
                    Text("Auto").tag("")
                    ForEach(account.models) { Text($0.name).tag($0.id) }
                    if !preferences.chatGPTModel.isEmpty && !account.models.contains(where: { $0.id == preferences.chatGPTModel }) { Text(preferences.chatGPTModel + "（待验证）").tag(preferences.chatGPTModel) }
                }
                HStack {
                    Button("Disconnect", role: .destructive) {
                        workspace.cancel(); disconnecting = true
                        Task { await account.disconnect(); disconnecting = false }
                    }.disabled(disconnecting || account.connecting || workspace.busy)
                    Button("刷新模型") { Task { await account.refreshModels() } }.disabled(workspace.busy)
                    Spacer()
                    Link("Manage usage", destination: URL(string: "https://chatgpt.com/#settings/Usage")!)
                }
                if account.vault.registrations.count > 1 {
                    Picker("账户", selection: Binding(get: { account.vault.selected ?? "" }, set: { account.select($0); preferences.chatGPTModel = "" })) {
                        ForEach(account.vault.registrations) { record in Text((record.email.isEmpty ? "待验证账户" : record.email) + " · " + String(record.clientID.suffix(6))).tag(record.clientID) }
                    }.disabled(workspace.busy || account.connecting)
                }
                Button("连接其他 ChatGPT 账户") { account.connect(newAccount: true) }.disabled(workspace.busy || account.connecting)
                Text("Using ChatGPT plan · 合资格请求使用你授权的套餐或可用额度。").font(.caption).foregroundStyle(.secondary)
            } else {
                HStack { Text("Status").foregroundStyle(.secondary); Spacer(); Text(account.connecting ? "Connecting…" : "Not connected").foregroundStyle(.secondary) }
                Button { account.connect() } label: {
                    HStack { Image(systemName: "person.crop.circle"); Text("Continue with ChatGPT").fontWeight(.semibold) }.frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.borderedProminent).tint(.primary).disabled(account.connecting || workspace.busy)
                if account.connecting { Button("取消连接") { account.cancelLogin() } }
                Text("在系统浏览器完成登录和套餐授权，无需 API Key。成功验证身份后显示账户与模型。").font(.caption).foregroundStyle(.secondary)
            }
            if !account.message.isEmpty && account.message != "已连接" { Text(account.message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
        }.padding(18).background(Color.primary.opacity(0.035)).cornerRadius(14)
        .task { if account.connected { await account.refreshModels() } }
        .alert("You're using your ChatGPT plan", isPresented: $account.welcome) { Button("Got it") { account.acknowledgeWelcome(); preferences.provider = .chatGPT } } message: { Text("TermGPT 中合资格的 AI 请求会使用你授权的 ChatGPT 套餐或可用额度。你可以在 ChatGPT Settings → Usage 管理访问和用量。") }
    }
}
struct BookmarkView: View {
    @ObservedObject var workspace: Workspace
    @Environment(\.dismiss) var dismiss
    @State private var bookmark = Bookmark()
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("新增 SSH 书签").font(.title2.bold())
            Form {
                TextField("名称", text: $bookmark.name)
                TextField("主机 / SSH config 别名", text: $bookmark.host)
                TextField("端口", value: $bookmark.port, formatter: NumberFormatter())
                TextField("用户名（空则使用 SSH config）", text: $bookmark.user)
                TextField("私钥路径（空则使用 Agent / config）", text: $bookmark.keyPath)
                TextField("ProxyJump（如 user@gateway）", text: $bookmark.jump)
                TextField("备注", text: $bookmark.notes)
                Text("采用系统 OpenSSH，兼容 ~/.ssh/config、SSH Agent、Known Hosts。密码只在终端提示中输入，不保存到书签。").font(.caption).foregroundStyle(.secondary)
            }
            HStack { Button("取消") { dismiss() }; Spacer(); Button("保存") { do { _ = try bookmark.arguments(); workspace.bookmarks.append(bookmark); workspace.persist(); dismiss() } catch { workspace.error = error.localizedDescription } }.buttonStyle(.borderedProminent).disabled(bookmark.name.isEmpty || bookmark.host.isEmpty) }
        }.padding(24).frame(width: 620)
    }
}
struct HistoryView: View {
    @ObservedObject var workspace: Workspace
    @Environment(\.dismiss) var dismiss
    @State private var snapshot = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("终端历史 · \(workspace.activeSession?.name ?? "无终端")").font(.title2)
            TextField("搜索文本", text: $workspace.search)
            ScrollView { Text(workspace.search.isEmpty ? snapshot : snapshot.components(separatedBy: "\n").filter { $0.localizedCaseInsensitiveContains(workspace.search) }.joined(separator: "\n")).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            HStack { Button("刷新") { snapshot = workspace.activeSession?.snapshot() ?? "" }; Spacer(); Button("关闭") { dismiss() } }
        }.padding(24).frame(width: 800, height: 560).onAppear { snapshot = workspace.activeSession?.snapshot() ?? "" }
    }
}

struct ProviderCaption: View {
    @ObservedObject var account: ChatGPTAccount
    let provider: ProviderKind
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(provider == .chatGPT ? (account.connected ? "Using ChatGPT plan" : "ChatGPT · Not connected") : provider.rawValue).font(.caption).foregroundStyle(.secondary)
            Text("Enter 发送 · ⌥Enter 换行").font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}
