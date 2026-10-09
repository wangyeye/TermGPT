import SwiftUI
import WebKit

final class WebSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let view = WKWebView(frame: .zero)
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
    @State private var input = ""
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { browser.view.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!browser.canGoBack).help(L("后退"))
                Button { browser.view.goForward() } label: { Image(systemName: "chevron.right") }.disabled(!browser.canGoForward).help(L("前进"))
                Button { browser.view.reload() } label: { Image(systemName: "arrow.clockwise") }.help(L("刷新"))
                TextField("URL", text: $input).textFieldStyle(.roundedBorder).onSubmit {
                    do { try browser.open(input) } catch { browser.error = error.localizedDescription }
                }
                if browser.loading { ProgressView().controlSize(.small) }
            }.padding(8)
            if !browser.error.isEmpty { Text(browser.error).foregroundStyle(.red).font(.caption).padding(8).textSelection(.enabled) }
            Divider()
            WebHost(browser: browser)
        }.onAppear { input = browser.address }.onChange(of: browser.address) { input = $0 }
    }
}
