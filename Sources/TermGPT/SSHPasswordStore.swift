import Foundation

enum SSHPasswordStore {
    static func read(id: UUID, store: CredentialStore = .shared) throws -> String? { try store.read().sshPasswords[id.uuidString] }
    static func write(_ password: String, id: UUID, store: CredentialStore = .shared) throws {
        try store.update { $0.sshPasswords[id.uuidString] = password }
    }
    static func remove(id: UUID, store: CredentialStore = .shared) throws {
        try store.update { $0.sshPasswords.removeValue(forKey: id.uuidString); $0.rdpCertificates.removeValue(forKey: id.uuidString) }
    }
}
