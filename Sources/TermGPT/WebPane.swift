import SwiftUI
import WebKit
import CryptoKit
import Security

final class WebSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let view: WKWebView = {
        let configuration = WKWebViewConfiguration()
        // Public macOS 15 property, accessed dynamically for older SDK builds.
        if configuration.responds(to: NSSelectorFromString("setWritingToolsBehavior:")) {
            configuration.setValue(-1, forKey: "writingToolsBehavior")
        }
        // Apply to dynamic fields and subframes as well as the initial document.
        let script = """
        (() => {
          const disable = element => {
            if (!(element instanceof Element)) return;
            for (const [name, value] of Object.entries({spellcheck:'false', autocorrect:'off', autocapitalize:'off'})) {
              if (element.getAttribute(name) !== value) element.setAttribute(name, value);
            }
          };
          const scan = root => {
            if (root.matches?.('input, textarea, [contenteditable]')) disable(root);
            root.querySelectorAll?.('input, textarea, [contenteditable]').forEach(disable);
          };
          const observer = new MutationObserver(records => {
            for (const record of records) {
              if (record.type === 'attributes') scan(record.target);
              record.addedNodes.forEach(scan);
            }
          });
          observer.observe(document, {subtree:true, childList:true, attributes:true,
            attributeFilter:['contenteditable', 'spellcheck', 'autocorrect', 'autocapitalize']});
          document.addEventListener('focusin', event => event.composedPath().forEach(disable), true);
          scan(document);
        })();
        """
        configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        return WKWebView(frame: .zero, configuration: configuration)
    }()
    @Published var address = ""
    @Published var loading = false
    @Published var error = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    var changed: (() -> Void)?
    private var observations: [NSKeyValueObservation] = []
    private var closed = false
    private let passwordAutofill = WebPasswordAutofill()
    private var trustedCertificates: [String: String] = [:]
    override init() {
        super.init()
        passwordAutofill.browser = self
        view.configuration.userContentController.addScriptMessageHandler(passwordAutofill, contentWorld: .page, name: WebPasswordAutofill.handler)
        view.configuration.userContentController.addUserScript(WKUserScript(source: WebPasswordAutofill.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        view.navigationDelegate = self; view.uiDelegate = self
        observations = [
            view.observe(\.isLoading, options: [.new]) { [weak self] _, _ in self?.update() },
            view.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in self?.update() },
            view.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in self?.update() },
            view.observe(\.url, options: [.new]) { [weak self] _, _ in self?.update() }
        ]
    }
    func open(_ value: String) throws {
        let url = try Bookmark(host: value, connectionKind: .web).webAddress()
        guard !closed else { return }
        error = ""; address = url.absoluteString
        view.load(URLRequest(url: url))
    }
    private func update() {
        guard !closed else { return }
        loading = view.isLoading; canGoBack = view.canGoBack; canGoForward = view.canGoForward
        if let url = view.url { address = url.absoluteString }
        changed?()
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let value = navigationAction.request.url?.absoluteString ?? ""
        decisionHandler(!closed && (try? Bookmark(host: value, connectionKind: .web).webAddress()) != nil ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard !closed else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        let method = challenge.protectionSpace.authenticationMethod
        if method == NSURLAuthenticationMethodServerTrust, let trust = challenge.protectionSpace.serverTrust {
            if SecTrustEvaluateWithError(trust, nil) {
                completionHandler(.performDefaultHandling, nil); return
            }
            guard let certificate = SecTrustGetCertificateAtIndex(trust, 0) else {
                completionHandler(.cancelAuthenticationChallenge, nil); return
            }
            let fingerprint = SHA256.hash(data: SecCertificateCopyData(certificate) as Data).map { String(format: "%02x", $0) }.joined(separator: ":")
            let host = challenge.protectionSpace.host.lowercased()
            let key = "https://\(host):\(challenge.protectionSpace.port)"
            if trustedCertificates[key] == fingerprint || (try? CredentialStore.shared.read().webCertificates[key]) == fingerprint {
                completionHandler(.useCredential, URLCredential(trust: trust)); return
            }
            let alert = NSAlert()
            alert.messageText = L("验证网页服务器证书")
            alert.informativeText = L("无法验证服务器证书。请核对服务器身份。始终信任会保存此主机和端口的证书指纹，证书变更时重新询问。")
                + "\n\n" + key + "\n" + (SecCertificateCopySubjectSummary(certificate) as String? ?? "") + "\nSHA-256: " + fingerprint
            alert.addButton(withTitle: L("仅本次信任")); alert.addButton(withTitle: L("始终信任")); alert.addButton(withTitle: L("取消"))
            let result = alert.runModal()
            guard !closed, result == .alertFirstButtonReturn || result == .alertSecondButtonReturn else {
                completionHandler(.cancelAuthenticationChallenge, nil); return
            }
            trustedCertificates[key] = fingerprint
            if result == .alertSecondButtonReturn {
                do { try CredentialStore.shared.update { $0.webCertificates[key] = fingerprint } }
                catch { self.error = L("保存证书信任失败") }
            }
            completionHandler(.useCredential, URLCredential(trust: trust)); return
        }
        guard method == NSURLAuthenticationMethodHTTPBasic || method == NSURLAuthenticationMethodHTTPDigest else {
            completionHandler(.performDefaultHandling, nil); return
        }
        let space = challenge.protectionSpace
        // Include scheme, port, realm and method so credentials never cross origins.
        let key = String(data: try! JSONEncoder().encode([space.protocol ?? "", space.host.lowercased(), String(space.port), space.realm ?? "", method]), encoding: .utf8)!
        let saved = try? CredentialStore.shared.read().webPasswords[key]
        if challenge.previousFailureCount == 0, let saved {
            completionHandler(.useCredential, URLCredential(user: saved.username, password: saved.password, persistence: .forSession))
            return
        }
        let alert = NSAlert()
        alert.messageText = L("网页身份验证")
        alert.informativeText = challenge.protectionSpace.host + "\n" + (challenge.protectionSpace.realm ?? "")
            + (challenge.previousFailureCount > 0 ? "\n" + L("用户名或密码不正确，请重试") : "")
        alert.addButton(withTitle: L("登录")); alert.addButton(withTitle: L("取消"))
        let fields = NSStackView()
        fields.orientation = .vertical; fields.spacing = 10
        let username = NSTextField(string: saved?.username ?? challenge.proposedCredential?.user ?? "")
        username.placeholderString = L("用户名")
        let password = NSSecureTextField(string: "")
        password.placeholderString = L("密码")
        fields.addArrangedSubview(username); fields.addArrangedSubview(password)
        let remember = NSButton(checkboxWithTitle: L("保存密码"), target: nil, action: nil)
        remember.state = saved == nil ? .off : .on
        fields.addArrangedSubview(remember)
        fields.frame = NSRect(x: 0, y: 0, width: 300, height: 90)
        username.widthAnchor.constraint(equalToConstant: 300).isActive = true
        password.widthAnchor.constraint(equalToConstant: 300).isActive = true
        alert.accessoryView = fields
        alert.window.initialFirstResponder = username
        if alert.runModal() == .alertFirstButtonReturn, !closed {
            do {
                try CredentialStore.shared.update {
                    if remember.state == .on { $0.webPasswords[key] = WebCredential(username: username.stringValue, password: password.stringValue) }
                    else { $0.webPasswords.removeValue(forKey: key) }
                }
            } catch { self.error = L("保存网页密码失败") }
            completionHandler(.useCredential, URLCredential(user: username.stringValue, password: password.stringValue, persistence: .forSession))
        } else { completionHandler(.cancelAuthenticationChallenge, nil) }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url { try? open(url.absoluteString) }
        return nil
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        guard !closed else { completionHandler(nil); return }
        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? L("网页身份验证")
        alert.informativeText = prompt
        alert.addButton(withTitle: L("好")); alert.addButton(withTitle: L("取消"))
        let isPassword = prompt.range(of: "password|passphrase|密码|口令", options: [.regularExpression, .caseInsensitive]) != nil
        let origin = WebPasswordAutofill.origin(frame.request.url)
        let key = "prompt:" + (origin ?? "") + ":" + prompt
        let canRemember = isPassword && frame.isMainFrame && origin != nil && origin == WebPasswordAutofill.origin(view.url)
        let saved = canRemember ? (try? CredentialStore.shared.read().webPasswords[key]) : nil
        let input: NSTextField = isPassword ? NSSecureTextField(string: saved?.password ?? defaultText ?? "") : NSTextField(string: defaultText ?? "")
        input.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        let fields = NSStackView(); fields.orientation = .vertical; fields.spacing = 10
        fields.addArrangedSubview(input)
        input.widthAnchor.constraint(equalToConstant: 300).isActive = true
        let remember = NSButton(checkboxWithTitle: L("保存密码并自动填充"), target: nil, action: nil)
        remember.state = saved == nil ? .off : .on
        if canRemember { fields.addArrangedSubview(remember) }
        fields.frame = NSRect(x: 0, y: 0, width: 300, height: canRemember ? 58 : 24)
        alert.accessoryView = fields; alert.window.initialFirstResponder = input
        guard let window = webView.window else { completionHandler(nil); return }
        alert.beginSheetModal(for: window) { [self] result in
        if result == .alertFirstButtonReturn && !closed {
            if canRemember {
                do { try CredentialStore.shared.update {
                    if remember.state == .on { $0.webPasswords[key] = WebCredential(username: "", password: input.stringValue) }
                    else { $0.webPasswords.removeValue(forKey: key) }
                } } catch { self.error = L("保存网页密码失败") }
            }
            completionHandler(input.stringValue)
        } else { completionHandler(nil) }
        }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { error = ""; update() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { update() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError failure: Error) { failed(failure) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError failure: Error) { failed(failure) }
    private func failed(_ failure: Error) {
        guard !closed, (failure as NSError).code != NSURLErrorCancelled else { return }
        error = failure.localizedDescription; update()
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { error = L("网页进程已退出，请刷新重试"); update() }
    func close() {
        closed = true; changed = nil; observations.removeAll()
        view.configuration.userContentController.removeScriptMessageHandler(forName: WebPasswordAutofill.handler, contentWorld: .page)
        view.stopLoading(); view.navigationDelegate = nil; view.uiDelegate = nil
    }
}
struct WebHost: NSViewRepresentable {
    let browser: WebSession
    func makeNSView(context: Context) -> WKWebView { browser.view }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
struct WebPane: View {
    @ObservedObject var browser: WebSession
    let showAddressBar: Bool
    @State private var input = ""
    var body: some View {
        VStack(spacing: 0) {
            if showAddressBar {
            HStack {
                Button { browser.view.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!browser.canGoBack).help(L("后退"))
                Button { browser.view.goForward() } label: { Image(systemName: "chevron.right") }.disabled(!browser.canGoForward).help(L("前进"))
                Button { browser.view.reload() } label: { Image(systemName: "arrow.clockwise") }.help(L("刷新"))
                TextField("URL", text: $input).textFieldStyle(.roundedBorder).onSubmit {
                    do { try browser.open(input) } catch { browser.error = error.localizedDescription }
                }
                if browser.loading { ProgressView().controlSize(.small) }
            }.padding(8)
            Divider()
            }
            if !browser.error.isEmpty { Text(browser.error).foregroundStyle(.red).font(.caption).padding(8).textSelection(.enabled) }
            WebHost(browser: browser).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.onAppear { input = browser.address }.onChange(of: browser.address) { input = $0 }
    }
}
