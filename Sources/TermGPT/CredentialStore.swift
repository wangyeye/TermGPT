import Foundation
import Darwin

struct WebCredential: Codable { var username: String; var password: String }

// Local JSON configuration. Never included in exports, release packages or logs.
struct CredentialConfiguration: Codable {
    var schemaVersion = 1
    var chatGPT: ChatGPTVault?
    var apiKey = ""
    var sshPasswords: [String: String] = [:]
    var rdpCertificates: [String: RDPCertificatePin] = [:]
    var webPasswords: [String: WebCredential] = [:]
    init() {}
    enum CodingKeys: String, CodingKey { case schemaVersion, chatGPT, apiKey, sshPasswords, rdpCertificates, webPasswords }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard schemaVersion == 1 else { throw AppError.message("配置文件版本不受支持") }
        chatGPT = try c.decodeIfPresent(ChatGPTVault.self, forKey: .chatGPT)
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        sshPasswords = try c.decodeIfPresent([String: String].self, forKey: .sshPasswords) ?? [:]
        rdpCertificates = try c.decodeIfPresent([String: RDPCertificatePin].self, forKey: .rdpCertificates) ?? [:]
        webPasswords = try c.decodeIfPresent([String: WebCredential].self, forKey: .webPasswords) ?? [:]
    }
}
final class CredentialStore: @unchecked Sendable {
    static let shared = CredentialStore(directory: DiskStore.directory)
    let directory: URL
    var url: URL { directory.appendingPathComponent("credentials.json") }
    private let lock = NSLock()
    init(directory: URL) { self.directory = directory }
    func read() throws -> CredentialConfiguration {
        lock.lock(); defer { lock.unlock() }
        return try readUnlocked()
    }
    func update(_ mutate: (inout CredentialConfiguration) throws -> Void) throws {
        lock.lock(); defer { lock.unlock() }
        var configuration = try readUnlocked()
        try mutate(&configuration)
        try prepareDirectory()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        var template = Array(directory.appendingPathComponent(".credentials.XXXXXX").path.utf8CString)
        let descriptor = mkstemp(&template) // Creates the temporary file with mode 0600.
        guard descriptor >= 0 else { throw AppError.message("无法保存本机 JSON 配置") }
        let temporary = String(cString: template)
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close(); unlink(temporary) }
        try handle.write(contentsOf: data); try handle.synchronize(); try handle.close()
        guard rename(temporary, url.path) == 0 else { throw AppError.message("无法保存本机 JSON 配置") }
    }
    private func prepareDirectory() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: directory.path) {
            let attributes = try fm.attributesOfItem(atPath: directory.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw AppError.message("本机配置目录无效") }
        } else {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
    private func readUnlocked() throws -> CredentialConfiguration {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return CredentialConfiguration() }
        try prepareDirectory()
        let attributes = try fm.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw AppError.message("本机配置文件无效") }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        do { return try JSONDecoder().decode(CredentialConfiguration.self, from: Data(contentsOf: url)) }
        catch { throw AppError.message("本机 JSON 配置无法读取，请检查文件格式；原文件未覆盖") }
    }
}
enum APIKeyStore {
    static func read() throws -> String { try CredentialStore.shared.read().apiKey }
    static func write(_ key: String) throws { try CredentialStore.shared.update { $0.apiKey = key } }
}
enum ChatGPTConfigurationStore {
    static func load() throws -> ChatGPTVault { try CredentialStore.shared.read().chatGPT ?? ChatGPTVault() }
    static func save(_ vault: ChatGPTVault) throws { try CredentialStore.shared.update { $0.chatGPT = vault } }
}
