import XCTest
@testable import TermGPT

final class ConfigurationBackupTests: XCTestCase {
    private func state() -> SavedState {
        SavedState(savedNotes: [SavedNote(title: "Fixture note", content: "Fixture text")], savedCommands: [SavedCommand(name: "Fixture command", command: "echo fixture")], bookmarks: [Bookmark(name: "Fixture", host: "example.test")], folders: [], chats: [], preferences: Preferences())
    }
    func testPlainBackupRoundTripWithoutCredentials() throws {
        let backup = ConfigurationBackup(state: state(), credentials: nil)
        let data = try ConfigurationBackupCodec.encode(backup)
        XCTAssertFalse(try ConfigurationBackupCodec.isEncrypted(data))
        let restored = try ConfigurationBackupCodec.decode(data)
        XCTAssertEqual(restored.state.bookmarks.first?.host, "example.test")
        XCTAssertEqual(restored.state.savedNotes?.first?.content, "Fixture text")
        XCTAssertEqual(restored.state.savedCommands?.first?.command, "echo fixture")
        XCTAssertNil(restored.credentials)
    }
    func testEncryptedCredentialsRoundTripExcludesAccountTokens() throws {
        var credentials = CredentialConfiguration()
        credentials.apiKey = "fixture-api-not-real"
        credentials.sshPasswords[UUID().uuidString] = "fixture-password-not-real"
        credentials.chatGPT = ChatGPTVault()
        let backup = ConfigurationBackup(state: state(), credentials: credentials)
        XCTAssertThrowsError(try ConfigurationBackupCodec.encode(backup))
        XCTAssertThrowsError(try ConfigurationBackupCodec.encode(backup, password: "short"))
        let data = try ConfigurationBackupCodec.encode(backup, password: "fixture-backup-passphrase")
        XCTAssertTrue(try ConfigurationBackupCodec.isEncrypted(data))
        let restored = try ConfigurationBackupCodec.decode(data, password: "fixture-backup-passphrase")
        XCTAssertEqual(restored.credentials?.apiKey, credentials.apiKey)
        XCTAssertEqual(restored.credentials?.sshPasswords, credentials.sshPasswords)
        XCTAssertNil(restored.credentials?.chatGPT)
        XCTAssertThrowsError(try ConfigurationBackupCodec.decode(data))
        XCTAssertThrowsError(try ConfigurationBackupCodec.decode(data, password: "wrong-passphrase"))
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var ciphertext = try XCTUnwrap(Data(base64Encoded: envelope["content"] as? String ?? ""))
        ciphertext[ciphertext.count - 1] ^= 1
        envelope["content"] = ciphertext.base64EncodedString()
        XCTAssertThrowsError(try ConfigurationBackupCodec.decode(JSONSerialization.data(withJSONObject: envelope), password: "fixture-backup-passphrase"))
    }
    func testUnsupportedAndDuplicateBackupsRejected() throws {
        var value = state(); value.bookmarks.append(value.bookmarks[0])
        XCTAssertThrowsError(try ConfigurationBackupCodec.decode(ConfigurationBackupCodec.encode(ConfigurationBackup(state: value, credentials: nil))))
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: ConfigurationBackupCodec.encode(ConfigurationBackup(state: state(), credentials: nil))) as? [String: Any])
        envelope["version"] = 999
        XCTAssertThrowsError(try ConfigurationBackupCodec.decode(JSONSerialization.data(withJSONObject: envelope)))
        XCTAssertThrowsError(try ConfigurationBackupCodec.decode(Data("not a backup".utf8)))
    }
    func testBackupFileUsesPrivatePermissions() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("fixture.termgptbackup")
        let data = try ConfigurationBackupCodec.encode(ConfigurationBackup(state: state(), credentials: nil))
        try ConfigurationBackupCodec.write(data, to: file)
        XCTAssertEqual(try Data(contentsOf: file), data)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
}
