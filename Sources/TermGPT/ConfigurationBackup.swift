import Foundation
import CryptoKit
import Security
import CommonCrypto

struct ConfigurationBackup: Codable {
    var format = "TermGPT.configuration"
    var version = 1
    var createdAt = Date()
    var state: SavedState
    var credentials: CredentialConfiguration?
}
private struct BackupEnvelope: Codable {
    var format = "TermGPT.backup"
    var version = 1
    var encrypted: Bool
    var salt: Data?
    var content: Data
}
enum ConfigurationBackupCodec {
    static let maximumSize = 64 * 1024 * 1024
    private static func key(password: String, salt: Data) throws -> SymmetricKey {
        guard !password.isEmpty, salt.count == 16 else { throw AppError.message(L("请输入备份密码")) }
        let passwordBytes = Array(password.utf8)
        var bytes = [UInt8](repeating: 0, count: 32)
        let outputCount = bytes.count
        let result = passwordBytes.withUnsafeBytes { passwordBuffer in
            salt.withUnsafeBytes { saltBuffer in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), passwordBuffer.baseAddress?.assumingMemoryBound(to: Int8.self), passwordBytes.count, saltBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 310_000, &bytes, outputCount)
            }
        }
        guard result == kCCSuccess else { throw AppError.message(L("备份加密失败")) }
        return SymmetricKey(data: bytes)
    }
    static func encode(_ backup: ConfigurationBackup, password: String? = nil) throws -> Data {
        guard backup.credentials == nil || password != nil else { throw AppError.message(L("包含密码的备份必须加密")) }
        var portable = backup
        portable.credentials?.chatGPT = nil
        let content = try JSONEncoder().encode(portable)
        let envelope: BackupEnvelope
        if let password {
            guard password.count >= 8 else { throw AppError.message(L("备份密码至少需要 8 个字符")) }
            var salt = Data(count: 16)
            let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
            guard status == errSecSuccess else { throw AppError.message(L("备份加密失败")) }
            let sealed = try AES.GCM.seal(content, using: key(password: password, salt: salt), authenticating: Data("TermGPT.backup.v1".utf8))
            envelope = BackupEnvelope(encrypted: true, salt: salt, content: sealed.combined!)
        } else { envelope = BackupEnvelope(encrypted: false, content: content) }
        return try JSONEncoder().encode(envelope)
    }
    static func isEncrypted(_ data: Data) throws -> Bool { try envelope(data).encrypted }
    private static func envelope(_ data: Data) throws -> BackupEnvelope {
        guard data.count <= maximumSize else { throw AppError.message(L("备份文件过大")) }
        let value: BackupEnvelope
        do { value = try JSONDecoder().decode(BackupEnvelope.self, from: data) }
        catch { throw AppError.message(L("不是有效的 TermGPT 备份")) }
        guard value.format == "TermGPT.backup", value.version == 1 else { throw AppError.message(L("备份版本不受支持")) }
        return value
    }
    static func decode(_ data: Data, password: String? = nil) throws -> ConfigurationBackup {
        let value = try envelope(data)
        let content: Data
        if value.encrypted {
            guard let password, let salt = value.salt else { throw AppError.message(L("请输入备份密码")) }
            do { content = try AES.GCM.open(AES.GCM.SealedBox(combined: value.content), using: key(password: password, salt: salt), authenticating: Data("TermGPT.backup.v1".utf8)) }
            catch { throw AppError.message(L("备份密码错误或文件已损坏")) }
        } else { content = value.content }
        let backup = try JSONDecoder().decode(ConfigurationBackup.self, from: content)
        guard backup.format == "TermGPT.configuration", backup.version == 1, value.encrypted || backup.credentials == nil else { throw AppError.message(L("不是有效的 TermGPT 备份")) }
        guard backup.state.preferences.fontSize.isFinite, (10...24).contains(backup.state.preferences.fontSize) else { throw AppError.message(L("备份设置无效")) }
        guard Set(backup.state.bookmarks.map(\.id)).count == backup.state.bookmarks.count, Set(backup.state.chats.map(\.id)).count == backup.state.chats.count else { throw AppError.message(L("备份包含重复项目")) }
        return backup
    }
    static func write(_ data: Data, to url: URL) throws {
        guard data.count <= maximumSize else { throw AppError.message(L("备份文件过大")) }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
