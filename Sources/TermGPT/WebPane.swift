import SwiftUI
import WebKit

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
    override init() {
        super.init()
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
            WebHost(browser: browser)
        }.onAppear { input = browser.address }.onChange(of: browser.address) { input = $0 }
    }
}
