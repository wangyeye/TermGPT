import AppKit
import WebKit

/// Only top-level pages can access credentials for their own exact web origin.
final class WebPasswordAutofill: NSObject, WKScriptMessageHandlerWithReply {
    static let handler = "termGPTLogin"
    static let script = """
    (() => {
      const bridge = window.webkit.messageHandlers.termGPTLogin;
      let pending = false;
      const fields = () => {
        const passwords = [...document.querySelectorAll('input[type="password"]')].filter(e => e.getClientRects().length && !e.disabled);
        if (passwords.length !== 1 || passwords[0].autocomplete === 'new-password') return null;
        const password = passwords[0];
        const root = password.form || document;
        const users = [...root.querySelectorAll('input')].filter(e => e.getClientRects().length && !e.disabled && ['text','email',''].includes(e.type));
        const username = users.find(e => e.autocomplete === 'username') || users.find(e => /user|login|email|account/i.test(e.name + e.id + e.placeholder)) || users[0];
        return username ? {username, password} : null;
      };
      const set = (field, value) => {
        Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(field, value);
        field.dispatchEvent(new Event('input', {bubbles:true}));
        field.dispatchEvent(new Event('change', {bubbles:true}));
      };
      const fill = async () => {
        const pair = fields();
        if (!pair || pending || pair.password.value) return;
        pending = true;
        try {
          const saved = await bridge.postMessage({action:'load'});
          if (saved && pair.username.isConnected && pair.password.isConnected && (!pair.username.value || pair.username.value === saved.username) && !pair.password.value) {
            set(pair.username, saved.username); set(pair.password, saved.password);
          }
        } catch (_) {} finally { pending = false; }
      };
      const remember = event => {
        if (!event.isTrusted) return;
        const pair = fields();
        if (!pair || !pair.username.value || !pair.password.value) return;
        bridge.postMessage({action:'save', username:pair.username.value, password:pair.password.value}).catch(() => {});
      };
      document.addEventListener('submit', remember, true);
      document.addEventListener('click', event => {
        const button = event.target.closest?.('button, input[type="submit"], input[type="button"], input[type="image"], [role="button"]');
        const label = button && [button.textContent, button.value, button.id, button.name, button.getAttribute('aria-label')].join('').replace(/\\s+/g, '');
        if (button && (button.type === 'submit' || /login|signin|登录|登入|登陆/i.test(label))) remember(event);
      }, true);
      document.addEventListener('keydown', event => { if (event.key === 'Enter' && event.target.matches?.('input')) remember(event); }, true);
      new MutationObserver(fill).observe(document, {subtree:true, childList:true});
      document.addEventListener('DOMContentLoaded', fill); document.addEventListener('focusin', fill); fill();
    })();
    """
    weak var browser: WebSession?
    private var asking = false
    private var offered: [String: WebCredential] = [:]
    static func origin(_ url: URL?) -> String? {
        guard let url, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), let host = url.host?.lowercased() else { return nil }
        return "\(scheme)://\(host):\(url.port ?? (scheme == "https" ? 443 : 80))"
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let browser, message.frameInfo.isMainFrame,
              let origin = Self.origin(message.frameInfo.request.url), origin == Self.origin(browser.view.url),
              let body = message.body as? [String: Any], let action = body["action"] as? String else {
            replyHandler(nil, "Unavailable"); return
        }
        let key = "form:" + origin
        do {
            let saved = try CredentialStore.shared.read().webPasswords[key]
            if action == "load" {
                replyHandler(saved.map { ["username": $0.username, "password": $0.password] }, nil); return
            }
            guard action == "save", let username = body["username"] as? String, let password = body["password"] as? String,
                  !username.isEmpty, !password.isEmpty, username.utf8.count < 4096, password.utf8.count < 16384 else {
                replyHandler(nil, "Invalid request"); return
            }
            if asking || (saved?.username == username && saved?.password == password) { replyHandler(nil, nil); return }
            if offered[key]?.username == username && offered[key]?.password == password { replyHandler(nil, nil); return }
            offered[key] = WebCredential(username: username, password: password)
            guard let window = browser.view.window else { replyHandler(nil, "Unavailable"); return }
            asking = true
            let alert = NSAlert()
            alert.messageText = L("保存网页登录信息？")
            alert.informativeText = L("是否保存此网站的用户名和密码，下次访问时自动填充？") + "\n\n" + origin
            alert.addButton(withTitle: L("保存并自动填充")); alert.addButton(withTitle: L("不保存"))
            alert.beginSheetModal(for: window) { [self] result in
                defer { asking = false }
                do {
                    if result == .alertFirstButtonReturn {
                        try CredentialStore.shared.update { $0.webPasswords[key] = WebCredential(username: username, password: password) }
                    }
                    replyHandler(nil, nil)
                } catch { replyHandler(nil, "Local credential storage unavailable") }
            }
        } catch { replyHandler(nil, "Local credential storage unavailable") }
    }
}
