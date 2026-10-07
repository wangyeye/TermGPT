import AppKit
import Foundation
import Security

// OpenSSH owns this helper's stdout pipe. Passwords never enter argv or environment.
let env = ProcessInfo.processInfo.environment
let prompt = CommandLine.arguments.dropFirst().joined(separator: " ")
if env["SSH_ASKPASS_PROMPT"] == "confirm" {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = "确认 SSH 主机指纹"
    alert.informativeText = prompt
    alert.addButton(withTitle: "信任并连接")
    alert.addButton(withTitle: "取消")
    print(alert.runModal() == .alertFirstButtonReturn ? "yes" : "no")
    exit(0)
}
guard prompt.lowercased().contains("password"), !prompt.lowercased().contains("passphrase"),
      let id = env["TERMGPT_SSH_BOOKMARK_ID"], UUID(uuidString: id) != nil else { exit(1) }
let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "local.TermGPT.ssh-password", kSecAttrAccount as String: id,
    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
var result: CFTypeRef?
guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data, let password = String(data: data, encoding: .utf8) else { exit(1) }
print(password)
