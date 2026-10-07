import XCTest
@testable import TermGPT

final class CredentialStoreTests: XCTestCase {
    func testJSONCredentialsPreserveOtherProvidersAndRestrictPermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CredentialStore(directory: directory), id = UUID()
        XCTAssertEqual(try store.read().apiKey, "")
        var vault = ChatGPTVault()
        vault.registrations = [ChatGPTRegistration(clientID: "fixture-client", accessToken: "fixture-token-not-real")]
        vault.selected = "fixture-client"
        try store.update { $0.chatGPT = vault; $0.apiKey = "fixture-api-not-real" }
        try SSHPasswordStore.write("fixture-password-not-real", id: id, store: store)
        let persisted = try store.read()
        XCTAssertEqual(persisted.chatGPT?.selected, "fixture-client")
        XCTAssertEqual(persisted.chatGPT?.registrations.first?.accessToken, "fixture-token-not-real")
        XCTAssertEqual(persisted.apiKey, "fixture-api-not-real")
        let file = try FileManager.default.attributesOfItem(atPath: store.url.path)
        let folder = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((file[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((folder[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: store.url)) as? [String: Any]
        XCTAssertEqual((object?["sshPasswords"] as? [String: String])?[id.uuidString], "fixture-password-not-real")
        try SSHPasswordStore.remove(id: id, store: store)
        XCTAssertNil(try SSHPasswordStore.read(id: id, store: store))
        XCTAssertEqual(try store.read().apiKey, "fixture-api-not-real")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["credentials.json"])
    }
    func testMalformedConfigurationIsNotOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CredentialStore(directory: directory)
        try store.update { $0.apiKey = "fixture" }
        let broken = Data("{broken".utf8)
        try broken.write(to: store.url)
        XCTAssertThrowsError(try store.update { $0.apiKey = "replacement" })
        XCTAssertEqual(try Data(contentsOf: store.url), broken)
    }
    func testPartialConfigurationAndFutureSchema() throws {
        let partial = try JSONDecoder().decode(CredentialConfiguration.self, from: Data("{}".utf8))
        XCTAssertEqual(partial.apiKey, ""); XCTAssertTrue(partial.sshPasswords.isEmpty)
        XCTAssertThrowsError(try JSONDecoder().decode(CredentialConfiguration.self, from: Data(#"{"schemaVersion":99}"#.utf8)))
    }
}
