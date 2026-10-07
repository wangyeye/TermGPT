import Foundation
import AppKit
import CryptoKit
import Security
import Network

// Public native client, using the documented Sign in with ChatGPT plan-usage flow.
enum ChatGPTOAuth {
    static let issuer = "https://auth.openai.com"
    static let resource = "https://api.openai.com/v1"
    static let scope = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    static func base64url(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    static func decode(_ string: String) throws -> Data {
        let s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: s + String(repeating: "=", count: (4 - s.count % 4) % 4)) else { throw AppError.message("登录令牌编码无效") }
        return data
    }
    static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AppError.message("无法创建安全登录请求") }
        return base64url(Data(bytes))
    }
    static func challenge(_ verifier: String) -> String { base64url(Data(SHA256.hash(data: Data(verifier.utf8)))) }
    static func form(_ values: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return Data(values.sorted { $0.key < $1.key }.map { "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)" }.joined(separator: "&").utf8)
    }
    static func authorize(clientID: String, hostID: String, redirect: String, state: String, nonce: String, verifier: String) -> URL {
        var c = URLComponents(string: issuer + "/api/accounts/authorize")!
        var q = ["client_id": clientID, "ext_agent_host_id": hostID, "redirect_uri": redirect, "response_type": "code", "scope": scope, "resource": resource, "state": state, "nonce": nonce, "code_challenge_method": "S256", "code_challenge": challenge(verifier)]
        if clientID == "dynamic_agent_client" { q["agent_name_hint"] = "TermGPT" }
        c.queryItems = q.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return c.url!
    }
    static func callback(_ url: URL, state: String, registeredClient: String?) throws -> (code: String, client: String) {
        guard url.scheme == "http", url.host == "127.0.0.1", url.path == "/auth/callback", let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { throw AppError.message("登录回调无效") }
        // Reject duplicate security-critical parameters, not just a mismatched state.
        for key in ["state", "code", "client_id", "error"] { guard items.filter({ $0.name == key }).count <= 1 else { throw AppError.message("登录回调参数重复") } }
        func value(_ key: String) -> String? { items.first { $0.name == key }?.value }
        guard value("state") == state else { throw AppError.message("登录 state 校验失败") }
        if value("error") != nil { throw AppError.message("ChatGPT 授权未完成或已取消") }
        guard let code = value("code"), !code.isEmpty else { throw AppError.message("登录回调缺少授权码") }
        let client: String
        if let registeredClient {
            guard value("client_id") == nil || value("client_id") == registeredClient else { throw AppError.message("返回的账户注册不匹配") }
            client = registeredClient
        } else {
            guard let issued = value("client_id"), !issued.isEmpty, issued != "dynamic_agent_client" else { throw AppError.message("ChatGPT 尚未完成应用注册") }
            client = issued
        }
        return (code, client)
    }
    static func validateClaims(_ claims: [String: Any], client: String, nonce: String, now: Date = Date()) throws {
        let audience = (claims["aud"] as? [String]) ?? (claims["aud"] as? String).map { [$0] } ?? []
        guard claims["iss"] as? String == issuer, audience.contains(client), claims["nonce"] as? String == nonce,
              let exp = claims["exp"] as? Double, exp > now.timeIntervalSince1970,
              let sub = claims["sub"] as? String, !sub.isEmpty else { throw AppError.message("ChatGPT 身份校验失败，请重新连接") }
        if let nbf = claims["nbf"] as? Double, nbf > now.timeIntervalSince1970 + 30 { throw AppError.message("登录令牌尚未生效") }
    }
    static func permitted(_ scope: String) -> Bool {
        let scopes = Set(scope.split(separator: " ").map(String.init))
        return scopes.contains("chatgpt.tokens.use.direct") && scopes.contains("resource.invoke")
    }
    static func planName(_ claims: [String: Any]) -> String? {
        let auth = claims["https://api.openai.com/auth"] as? [String: Any]
        guard let plan = (auth?["chatgpt_plan_type"] ?? claims["chatgpt_plan_type"]) as? String else { return nil }
        let known = ["plus": "ChatGPT Plus", "pro": "ChatGPT Pro", "free": "ChatGPT Free", "team": "ChatGPT Team", "business": "ChatGPT Business", "enterprise": "ChatGPT Enterprise", "edu": "ChatGPT Edu"]
        return known[plan.lowercased()]
    }
}

struct ChatGPTRegistration: Codable, Identifiable {
    var id: String { clientID }
    var clientID: String
    var subject = ""
    var email = ""
    var plan: String?
    var accessToken = ""
    var refreshToken = ""
    var idToken = ""
    var scope = ""
    var expiresAt = Date.distantPast
    var connected: Bool { !accessToken.isEmpty && ChatGPTOAuth.permitted(scope) }
}
struct ChatGPTVault: Codable {
    var hostID = "urn:uuid:" + UUID().uuidString.lowercased()
    var registrations: [ChatGPTRegistration] = []
    var selected: String?
    var welcomeShown = false
}
@MainActor final class OAuthLoopback {
    private var listener: NWListener?
    private var continuation: CheckedContinuation<URL, Error>?
    private var callback: URL?
    private var timeout: Task<Void, Never>?
    private var redirect = ""
    private var connections: [NWConnection] = []
    func start() async throws -> String {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        return try await withCheckedThrowingContinuation { ready in
            var resolved = false
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated {
                    switch state {
                    case .ready:
                        guard !resolved, let port = listener.port else { return }; resolved = true
                        self?.redirect = "http://127.0.0.1:\(port.rawValue)/auth/callback"
                        ready.resume(returning: self!.redirect)
                    case .failed:
                        if !resolved { resolved = true; ready.resume(throwing: AppError.message("无法启动本机登录回调")) }
                        self?.cancel()
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in MainActor.assumeIsolated { self?.receive(connection) } }
            listener.start(queue: .main)
        }
    }
    private func receive(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: .main)
        read(connection, buffer: Data())
    }
    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, done, error in
            MainActor.assumeIsolated {
                guard let self else { connection.cancel(); return }
                var buffer = buffer; if let data { buffer.append(data) }
                guard buffer.count <= 16384 else { connection.cancel(); return }
                if !buffer.contains(Data("\r\n\r\n".utf8)), !done, error == nil { self.read(connection, buffer: buffer); return }
                let line = String(decoding: buffer, as: UTF8.self).components(separatedBy: "\r\n").first ?? ""
                let parts = line.split(separator: " ")
                guard parts.count >= 2, parts[0] == "GET", let url = URL(string: self.redirect.components(separatedBy: "/auth/")[0] + String(parts[1])), url.path == "/auth/callback" else {
                    self.respond(connection, status: "404 Not Found", text: "Not found"); return
                }
                self.respond(connection, status: "200 OK", text: "Return to TermGPT to finish connecting. You may close this browser tab.")
                if self.callback == nil {
                    self.callback = url
                    self.continuation?.resume(returning: url); self.continuation = nil
                    self.listener?.cancel(); self.timeout?.cancel()
                }
            }
        }
    }
    private func respond(_ connection: NWConnection, status: String, text: String) {
        let body = Data(text.utf8)
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: \(body.count)\r\n\r\n"
        connection.send(content: Data(response.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
    func wait() async throws -> URL {
        if let callback { return callback }
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { c in
                continuation = c
                timeout = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 300_000_000_000) } catch { return }
                    self?.cancel()
                }
            }
        }, onCancel: { Task { @MainActor in self.cancel() } })
    }
    func cancel() {
        timeout?.cancel(); timeout = nil; listener?.cancel(); listener = nil
        continuation?.resume(throwing: CancellationError()); continuation = nil
        connections.forEach { $0.cancel() }; connections.removeAll()
    }
}

struct ChatGPTModel: Identifiable, Equatable {
    var id: String
    var name: String
}
@MainActor final class ChatGPTAccount: ObservableObject {
    @Published private(set) var vault = ChatGPTVault()
    @Published private(set) var connecting = false
    @Published private(set) var loadingAccount = true
    @Published private(set) var models: [ChatGPTModel] = []
    @Published var message = ""
    @Published var welcome = false
    private var loginTask: Task<Void, Never>?
    private var loopback: OAuthLoopback?
    private var refreshTask: Task<ChatGPTRegistration, Error>?
    private var modelClient: String?
    var account: ChatGPTRegistration? { vault.registrations.first { $0.clientID == vault.selected } }
    var connected: Bool { account?.connected == true }
    init() {
        let load = Task.detached(priority: .userInitiated) { try ChatGPTConfigurationStore.load() }
        Task {
            do { vault = try await load.value } catch { message = error.localizedDescription }
            loadingAccount = false
        }
    }
    func connect(newAccount: Bool = false) {
        guard !connecting, !loadingAccount else { return }
        connecting = true; message = "正在等待浏览器授权…"
        loginTask = Task {
            let loop = OAuthLoopback(); loopback = loop
            defer { loop.cancel(); loopback = nil; connecting = false; loginTask = nil }
            do {
                try ChatGPTConfigurationStore.save(vault) // Persist host identity before first sign-in.
                let previous = newAccount ? nil : account
                let state = try ChatGPTOAuth.random(), nonce = try ChatGPTOAuth.random(), verifier = try ChatGPTOAuth.random()
                let redirect = try await loop.start()
                let url = ChatGPTOAuth.authorize(clientID: previous?.clientID ?? "dynamic_agent_client", hostID: vault.hostID, redirect: redirect, state: state, nonce: nonce, verifier: verifier)
                guard NSWorkspace.shared.open(url) else { throw AppError.message("无法打开系统浏览器") }
                let callback = try await loop.wait()
                let authorization = try ChatGPTOAuth.callback(callback, state: state, registeredClient: previous?.clientID)
                // Save issued registration even if code exchange requires a retry.
                if !vault.registrations.contains(where: { $0.clientID == authorization.client }) {
                    vault.registrations.append(ChatGPTRegistration(clientID: authorization.client)); if vault.selected == nil { vault.selected = authorization.client }; try ChatGPTConfigurationStore.save(vault)
                }
                let tokens = try await tokenRequest(["grant_type": "authorization_code", "client_id": authorization.client, "code": authorization.code, "code_verifier": verifier, "redirect_uri": redirect, "resource": ChatGPTOAuth.resource])
                guard let idToken = tokens["id_token"] as? String else { throw AppError.message("登录未返回 ID token") }
                let claims = try await validatedIDToken(idToken, client: authorization.client, nonce: nonce)
                if let previous, !previous.subject.isEmpty, claims["sub"] as? String != previous.subject { throw AppError.message("返回的 ChatGPT 身份与已选账户不匹配") }
                var registration = try tokenRecord(tokens, client: authorization.client)
                registration.subject = claims["sub"] as! String; registration.email = claims["email"] as? String ?? ""; registration.plan = ChatGPTOAuth.planName(claims)
                guard registration.connected else { throw AppError.message("账户已验证，但尚未授权 ChatGPT plan usage。请重新连接并允许套餐使用。") }
                replace(registration); vault.selected = registration.clientID; try ChatGPTConfigurationStore.save(vault)
                message = "已连接"; models = []; modelClient = nil
                if !vault.welcomeShown { welcome = true }
                await refreshModels()
                NSApp.activate(ignoringOtherApps: true)
            } catch is CancellationError { message = "连接已取消" }
            catch { message = error.localizedDescription }
        }
    }
    func cancelLogin() { loginTask?.cancel(); loopback?.cancel() }
    func acknowledgeWelcome() { welcome = false; vault.welcomeShown = true; do { try ChatGPTConfigurationStore.save(vault) } catch { message = error.localizedDescription } }
    func select(_ client: String) {
        guard !connecting else { return }
        refreshTask?.cancel(); refreshTask = nil; vault.selected = client; models = []; modelClient = nil
        do { try ChatGPTConfigurationStore.save(vault) } catch { message = error.localizedDescription }
        Task { await refreshModels() }
    }
    private func replace(_ record: ChatGPTRegistration) {
        if let i = vault.registrations.firstIndex(where: { $0.clientID == record.clientID }) { vault.registrations[i] = record } else { vault.registrations.append(record) }
    }
    private func tokenRequest(_ fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: ChatGPTOAuth.issuer + "/api/accounts/oauth/token")!)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"); request.httpBody = ChatGPTOAuth.form(fields)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AppError.message("ChatGPT 令牌交换失败，请重新连接") }
        return object
    }
    private func tokenRecord(_ tokens: [String: Any], client: String) throws -> ChatGPTRegistration {
        guard let access = tokens["access_token"] as? String, !access.isEmpty, let scope = tokens["scope"] as? String, let expires = tokens["expires_in"] as? Double, expires > 0 else { throw AppError.message("ChatGPT 凭据响应不完整") }
        return ChatGPTRegistration(clientID: client, accessToken: access, refreshToken: tokens["refresh_token"] as? String ?? "", idToken: tokens["id_token"] as? String ?? "", scope: scope, expiresAt: Date().addingTimeInterval(expires))
    }
    private func discovery() async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(from: URL(string: ChatGPTOAuth.issuer + "/.well-known/openid-configuration")!)
        guard (response as? HTTPURLResponse)?.statusCode == 200, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["issuer"] as? String == ChatGPTOAuth.issuer else { throw AppError.message("无法确认 OpenAI 登录服务") }
        return object
    }
    private func officialURL(_ value: Any?) throws -> URL {
        guard let string = value as? String, let url = URL(string: string), url.scheme == "https", url.host == "auth.openai.com", url.user == nil, url.password == nil else { throw AppError.message("登录服务返回不可信地址") }; return url
    }
    private func validatedIDToken(_ token: String, client: String, nonce: String) async throws -> [String: Any] {
        let discovery = try await discovery()
        let (data, response) = try await URLSession.shared.data(from: officialURL(discovery["jwks_uri"]))
        guard (response as? HTTPURLResponse)?.statusCode == 200, let jwks = try JSONSerialization.jsonObject(with: data) as? [String: Any], let keys = jwks["keys"] as? [[String: Any]] else { throw AppError.message("无法获取登录签名密钥") }
        return try OIDCSignature.verify(token, keys: keys, client: client, nonce: nonce)
    }
    func validAccount() async throws -> ChatGPTRegistration {
        guard let old = account, old.connected else { throw AppError.message("请在设置中 Continue with ChatGPT") }
        if old.expiresAt.timeIntervalSinceNow > 90 { return old }
        if let refreshTask { return try await refreshTask.value }
        let task = Task { [self] () throws -> ChatGPTRegistration in
            guard !old.refreshToken.isEmpty else { throw AppError.message("ChatGPT 登录已过期，请重新连接") }
            let response = try await tokenRequest(["grant_type": "refresh_token", "client_id": old.clientID, "refresh_token": old.refreshToken, "resource": ChatGPTOAuth.resource])
            var updated = try tokenRecord(response, client: old.clientID)
            guard !updated.refreshToken.isEmpty, updated.connected else { throw AppError.message("ChatGPT 套餐权限已失效，请重新连接") }
            updated.subject = old.subject; updated.email = old.email; updated.plan = old.plan
            if updated.idToken.isEmpty { updated.idToken = old.idToken }
            try Task.checkCancellation()
            guard vault.selected == old.clientID, account?.refreshToken == old.refreshToken else { throw CancellationError() }
            replace(updated); try ChatGPTConfigurationStore.save(vault); return updated
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }
    func refreshModels() async {
        do {
            let active = try await validAccount()
            var request = URLRequest(url: URL(string: ChatGPTOAuth.resource + "/models")!); request.timeoutInterval = 30
            request.setValue("Bearer \(active.accessToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any], let rows = obj["models"] as? [[String: Any]] else { throw AppError.message("无法获取 ChatGPT 可用模型，请刷新或重新连接") }
            guard vault.selected == active.clientID else { return }
            models = rows.compactMap { row in guard row["visibility"] as? String == "list", let slug = row["slug"] as? String else { return nil }; return ChatGPTModel(id: slug, name: row["display_name"] as? String ?? slug) }
            modelClient = active.clientID
            message = models.isEmpty ? "当前账户未返回可选模型" : "已连接"
        } catch { message = error.localizedDescription }
    }
    func stream(messages: [Message], model: String, update: @escaping (String) async -> Void) async throws {
        let active = try await validAccount()
        if models.isEmpty || modelClient != active.clientID { await refreshModels() }
        let selected = model.isEmpty ? models.first?.id : models.first { $0.id == model }?.id
        guard let selected else { throw AppError.message("尚未取得当前账户的可用模型，请在设置中刷新模型") }
        var request = URLRequest(url: URL(string: ChatGPTOAuth.resource + "/responses")!)
        request.httpMethod = "POST"; request.timeoutInterval = 120
        request.setValue("Bearer \(active.accessToken)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let instructions = messages.filter { $0.role == "system" }.map(\.content).joined(separator: "\n")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": selected, "store": false, "stream": true, "instructions": instructions, "input": messages.filter { $0.role != "system" }.map { ["role": $0.role, "content": $0.content] }])
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 429 { throw AppError.message("ChatGPT 使用额度已到限制，请在 Settings → Usage 查看并管理用量") }
            throw AppError.message("ChatGPT 请求失败（HTTP \(status)），请检查登录或套餐授权")
        }
        var completed = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:"), let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces).data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            switch object["type"] as? String {
            case "response.output_text.delta": if let delta = object["delta"] as? String { await update(delta) }
            case "response.completed": completed = true
            case "response.failed", "response.incomplete", "error": throw AppError.message("ChatGPT 返回未完成的响应，请重新尝试")
            default: break
            }
        }
        guard completed else { throw AppError.message("ChatGPT 响应连接中断，回复尚未完成") }
    }
    func disconnect() async {
        cancelLogin(); refreshTask?.cancel(); refreshTask = nil
        guard var current = account else { return }
        var revoked = false
        if !current.refreshToken.isEmpty {
            for attempt in 0..<2 {
                do {
                    let discovery = try await discovery()
                    var request = URLRequest(url: try officialURL(discovery["revocation_endpoint"]))
                    request.httpMethod = "POST"; request.timeoutInterval = 15; request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                    request.httpBody = ChatGPTOAuth.form(["token": current.refreshToken, "token_type_hint": "refresh_token", "client_id": current.clientID])
                    let (_, response) = try await URLSession.shared.data(for: request)
                    if (response as? HTTPURLResponse)?.statusCode == 200 { revoked = true; break }
                } catch { }
                if attempt == 0 { try? await Task.sleep(nanoseconds: 500_000_000) }
            }
        }
        current.accessToken = ""; current.refreshToken = ""; current.idToken = ""; current.scope = ""; current.expiresAt = .distantPast
        replace(current); models = []; modelClient = nil
        do { try ChatGPTConfigurationStore.save(vault); message = revoked ? "已断开连接" : "本机已断开；远端撤销未确认，可在 ChatGPT Settings 中移除应用访问。" } catch { message = "配置清除失败，请重试：\(error.localizedDescription)" }
    }
}

// Verify the signature before interpreting identity, email, plan, or nonce claims.
enum OIDCSignature {
    static func der(_ tag: UInt8, _ bytes: Data) -> Data {
        let length: [UInt8]
        if bytes.count < 128 { length = [UInt8(bytes.count)] }
        else {
            var size = bytes.count, encoded = [UInt8]()
            while size > 0 { encoded.insert(UInt8(size & 255), at: 0); size >>= 8 }
            length = [0x80 | UInt8(encoded.count)] + encoded
        }
        return Data([tag] + length) + bytes
    }
    static func integer(_ bytes: Data) -> Data {
        var b = bytes; while b.count > 1 && b.first == 0 { b.removeFirst() }
        if let first = b.first, first & 0x80 != 0 { b.insert(0, at: 0) }
        return der(0x02, b)
    }
    static func verify(_ token: String, keys: [[String: Any]], client: String, nonce: String) throws -> [String: Any] {
        let pieces = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard pieces.count == 3, let header = try JSONSerialization.jsonObject(with: ChatGPTOAuth.decode(pieces[0])) as? [String: Any], let kid = header["kid"] as? String,
              let jwk = keys.first(where: { $0["kid"] as? String == kid }), jwk["use"] as? String == nil || jwk["use"] as? String == "sig" else { throw AppError.message("登录签名密钥不匹配") }
        let algorithm = header["alg"] as? String
        let keyData: Data, attributes: [String: Any], signature: Data, verification: SecKeyAlgorithm
        if algorithm == "RS256", jwk["kty"] as? String == "RSA", let n = jwk["n"] as? String, let e = jwk["e"] as? String {
            keyData = der(0x30, integer(try ChatGPTOAuth.decode(n)) + integer(try ChatGPTOAuth.decode(e)))
            attributes = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeyClass as String: kSecAttrKeyClassPublic]
            signature = try ChatGPTOAuth.decode(pieces[2]); verification = .rsaSignatureMessagePKCS1v15SHA256
        } else if algorithm == "ES256", jwk["kty"] as? String == "EC", jwk["crv"] as? String == "P-256", let x = jwk["x"] as? String, let y = jwk["y"] as? String {
            let xd = try ChatGPTOAuth.decode(x), yd = try ChatGPTOAuth.decode(y), sig = try ChatGPTOAuth.decode(pieces[2])
            guard xd.count == 32, yd.count == 32, sig.count == 64 else { throw AppError.message("登录签名格式无效") }
            keyData = Data([0x04]) + xd + yd
            attributes = [kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom, kSecAttrKeyClass as String: kSecAttrKeyClassPublic, kSecAttrKeySizeInBits as String: 256]
            signature = der(0x30, integer(Data(sig.prefix(32))) + integer(Data(sig.suffix(32)))); verification = .ecdsaSignatureMessageX962SHA256
        } else { throw AppError.message("不支持或不可信的登录签名算法") }
        guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, nil), SecKeyVerifySignature(key, verification, Data((pieces[0] + "." + pieces[1]).utf8) as CFData, signature as CFData, nil) else { throw AppError.message("ChatGPT 身份签名校验失败") }
        guard let claims = try JSONSerialization.jsonObject(with: ChatGPTOAuth.decode(pieces[1])) as? [String: Any] else { throw AppError.message("登录身份内容无效") }
        try ChatGPTOAuth.validateClaims(claims, client: client, nonce: nonce)
        return claims
    }
}
