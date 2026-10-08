import AppKit
import Foundation

// OpenSSH owns this helper's stdout pipe. Passwords never enter argv or environment.
let env = ProcessInfo.processInfo.environment
let chinese = env["TERMGPT_UI_LANGUAGE"] == "chinese"
// Close authentication UI if its owning SSH process is canceled.
let owner = getppid()
let ownerMonitor = DispatchSource.makeTimerSource(queue: .main)
ownerMonitor.schedule(deadline: .now() + 1, repeating: 1)
ownerMonitor.setEventHandler { if getppid() != owner || kill(owner, 0) != 0 { exit(1) } }
ownerMonitor.resume()
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
let passwordPrompt = prompt.lowercased().contains("password") && !prompt.lowercased().contains("passphrase")
if passwordPrompt, let id = env["TERMGPT_SSH_BOOKMARK_ID"], UUID(uuidString: id) != nil {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TermGPT/credentials.json")
    if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
       attributes[.type] as? FileAttributeType == .typeRegular,
       let permissions = attributes[.posixPermissions] as? NSNumber, permissions.intValue & 0o077 == 0,
       let data = try? Data(contentsOf: url),
       let configuration = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       (configuration["schemaVersion"] as? Int ?? 1) == 1,
       let passwords = configuration["sshPasswords"] as? [String: String], let password = passwords[id] {
        print(password); exit(0)
    }
}
// Non-PTY SFTP can request a password, key passphrase or interactive challenge.
// Manually entered secrets are sent only to OpenSSH's pipe and never persisted.
guard env["TERMGPT_SFTP_AUTH"] == "1" else { exit(1) }
_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory); NSApp.activate(ignoringOtherApps: true)
let alert = NSAlert()
alert.messageText = chinese ? "SFTP 登录验证" : "SFTP Authentication"
alert.informativeText = prompt
let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
alert.accessoryView = field
alert.addButton(withTitle: chinese ? "连接" : "Connect")
alert.addButton(withTitle: chinese ? "取消" : "Cancel")
alert.window.initialFirstResponder = field
if alert.runModal() == .alertFirstButtonReturn { print(field.stringValue); exit(0) }
exit(1)
