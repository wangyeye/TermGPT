#!/usr/bin/env python3
"""Apply the 0.2 provider UI migration to the original 0.1 source (one-time development helper)."""
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
p = ROOT / 'Sources/TermGPT/Core.swift'
s = p.read_text()
if 'enum ProviderKind:' in s:
    print('0.2 migration already applied; no changes needed.')
    raise SystemExit(0)
a=s.index('struct Preferences: Codable {'); b=s.index('enum AppError:', a)
s=s[:a]+'''enum ProviderKind: String, Codable, CaseIterable {
    case chatGPT = "ChatGPT", openAI = "OpenAI API", ollama = "Ollama", lmStudio = "LM Studio", custom = "OpenAI-compatible"
    var defaultEndpoint: String {
        switch self {
        case .ollama: return "http://127.0.0.1:11434/v1"
        case .lmStudio: return "http://127.0.0.1:1234/v1"
        default: return "https://api.openai.com/v1"
        }
    }
}
struct Preferences: Codable {
    var provider = ProviderKind.chatGPT
    var chatGPTModel = ""
    var endpoint = "https://api.openai.com/v1"
    var model = ""
    var shell = "/bin/zsh"
    var fontSize = 14.0
    var lightTerminal = false
    var saveMemory = true
    init() {}
    enum CodingKeys: String, CodingKey { case provider, chatGPTModel, endpoint, model, shell, fontSize, lightTerminal, saveMemory }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try c.decodeIfPresent(String.self, forKey: .endpoint) ?? endpoint
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? model
        provider = try c.decodeIfPresent(ProviderKind.self, forKey: .provider) ?? (model.isEmpty && endpoint == ProviderKind.openAI.defaultEndpoint ? .chatGPT : .openAI)
        chatGPTModel = try c.decodeIfPresent(String.self, forKey: .chatGPTModel) ?? ""
        shell = try c.decodeIfPresent(String.self, forKey: .shell) ?? shell
        fontSize = min(24, max(10, try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? fontSize))
        lightTerminal = try c.decodeIfPresent(Bool.self, forKey: .lightTerminal) ?? lightTerminal
        saveMemory = try c.decodeIfPresent(Bool.self, forKey: .saveMemory) ?? saveMemory
    }
}
'''+s[b:]
p.write_text(s)
p=ROOT/'Sources/TermGPT/Workspace.swift';s=p.read_text().replace('@Published var sessions: [TerminalSession] = []', '''let chatGPT = ChatGPTAccount()
    @Published var sessions: [TerminalSession] = []''')
s=s.replace('try await provider.stream(messages: messages) { [weak self] chunk in', '''let update: (String) async -> Void = { [weak self] chunk in''')
s=s.replace('self.chats[c].messages[m].content += chunk }\n                }', '''self.chats[c].messages[m].content += chunk }
                }
                if self?.preferences.provider == .chatGPT {
                    guard let self else { throw CancellationError() }
                    try await self.chatGPT.stream(messages: messages, model: self.preferences.chatGPTModel, update: update)
                } else {
                    try await provider.stream(messages: messages, update: update)
                }''')
s=s.replace('func shutdown() { cancel(); persist();', 'func shutdown() { cancel(); chatGPT.cancelLogin(); persist();')
p.write_text(s)
p=ROOT/'Sources/TermGPT/App.swift';s=p.read_text()
a=s.index('struct SettingsView: View {');b=s.index('struct BookmarkView: View {',a)
s=s[:a]+'''struct SettingsView: View {
    @ObservedObject var workspace: Workspace
    @Environment(\\.dismiss) var dismiss
    @State private var preferences = Preferences()
    @State private var key = ""
    @State private var advanced = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 44, height: 44)
                VStack(alignment: .leading) { Text("设置").font(.title2.bold()); Text("连接你的 AI，保留完整终端体验。").font(.caption).foregroundStyle(.secondary) }
                Spacer()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ChatGPTSettings(account: workspace.chatGPT, preferences: $preferences, workspace: workspace)
                    DisclosureGroup("Advanced / Other Providers", isExpanded: $advanced) {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("AI Provider", selection: $preferences.provider) {
                                ForEach(ProviderKind.allCases, id: \\.self) { Text($0.rawValue).tag($0) }
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
                        Slider(value: $preferences.fontSize, in: 10...24, step: 1) { Text("字体大小 \\(Int(preferences.fontSize))") }
                        Toggle("浅色终端", isOn: $preferences.lightTerminal)
                        Toggle("保存聊天到本机", isOn: $preferences.saveMemory)
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
'''+s[b:]
s=s.replace('workspace.preferences.model.isEmpty ? "AI 未配置" : "AI 就绪"', 'workspace.preferences.provider == .chatGPT ? "ChatGPT" : (workspace.preferences.model.isEmpty ? "AI 未配置" : workspace.preferences.provider.rawValue)')
s=s.replace('先在设置中填写 API 地址、模型和密钥。支持 OpenAI-compatible API、Ollama 和 LM Studio。', '在设置中 Continue with ChatGPT 即可连接。OpenAI API、Ollama 与 LM Studio 位于 Advanced / Other Providers。')
s=s.replace('Text("命令不会自动执行").font(.caption).foregroundStyle(.secondary)', 'ProviderCaption(account: workspace.chatGPT, provider: workspace.preferences.provider)')
s += '''
struct ProviderCaption: View {
    @ObservedObject var account: ChatGPTAccount
    let provider: ProviderKind
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(provider == .chatGPT ? (account.connected ? "Using ChatGPT plan" : "ChatGPT · Not connected") : provider.rawValue).font(.caption).foregroundStyle(.secondary)
            Text("命令不会自动执行").font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}
'''
p.write_text(s)
