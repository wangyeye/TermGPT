import AppKit
import Foundation

// OpenSSH owns this helper's stdout pipe. Passwords never enter argv or environment.
let env = ProcessInfo.processInfo.environment
let chinese = env["TERMGPT_UI_LANGUAGE"] == "chinese"
let prompt = CommandLine.arguments.dropFirst().joined(separator: " ")
if env["SSH_ASKPASS_PROMPT"] == "confirm" {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = chinese ? "确认 SSH 主机指纹" : "Verify SSH Host Fingerprint"
    alert.informativeText = prompt
    alert.addButton(withTitle: chinese ? "信任并连接" : "Trust and Connect")
    alert.addButton(withTitle: chinese ? "取消" : "Cancel")
    print(alert.runModal() == .alertFirstButtonReturn ? "yes" : "no")
    exit(0)
}
guard prompt.lowercased().contains("password"), !prompt.lowercased().contains("passphrase"),
      let id = env["TERMGPT_SSH_BOOKMARK_ID"], UUID(uuidString: id) != nil else { exit(1) }
let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TermGPT/credentials.json")
guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
      attributes[.type] as? FileAttributeType == .typeRegular,
      let permissions = attributes[.posixPermissions] as? NSNumber, permissions.intValue & 0o077 == 0,
      let data = try? Data(contentsOf: url),
      let configuration = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      (configuration["schemaVersion"] as? Int ?? 1) == 1,
      let passwords = configuration["sshPasswords"] as? [String: String], let password = passwords[id] else { exit(1) }
print(password)
