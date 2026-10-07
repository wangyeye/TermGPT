import Foundation
import Security
enum SSHPasswordStore {
    static let service = "local.TermGPT.ssh-password"
    static func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString]
    }
    static func read(id: UUID) throws -> String? {
        var q = query(id); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw AppError.message("无法读取 SSH Keychain：\(status)") }
        return value
    }
    static func write(_ password: String, id: UUID) throws {
        let q = query(id), values = [kSecValueData as String: Data(password.utf8)]
        var status = SecItemUpdate(q as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(q.merging(values) { _, value in value } as CFDictionary, nil) }
        guard status == errSecSuccess else { throw AppError.message("无法保存 SSH Keychain：\(status)") }
    }
    static func remove(id: UUID) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AppError.message("无法删除 SSH Keychain：\(status)") }
    }
}
