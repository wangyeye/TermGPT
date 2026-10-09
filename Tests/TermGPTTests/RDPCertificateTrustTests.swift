import XCTest
@testable import TermGPT

final class RDPCertificateTrustTests: XCTestCase {
    func testTrustIsPersistedAndBoundToEndpointAndFingerprint() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CredentialStore(directory: directory), id = UUID()
        let certificate = RemoteCertificate(host: "fixture.example", subject: "fixture", issuer: "fixture", fingerprint: String(repeating: "ab", count: 32))
        try SSHPasswordStore.write("fixture-password", id: id, store: store)
        try RDPCertificateTrust.remember(id: id, host: "fixture.example", port: 3389, certificate: certificate, store: store)
        let reopened = CredentialStore(directory: directory)
        XCTAssertTrue(try RDPCertificateTrust.matches(id: id, host: "FIXTURE.EXAMPLE", port: 3389, certificate: certificate, store: reopened))
        XCTAssertFalse(try RDPCertificateTrust.matches(id: id, host: "fixture.example", port: 3390, certificate: certificate, store: reopened))
        XCTAssertFalse(try RDPCertificateTrust.matches(id: id, host: "other.example", port: 3389, certificate: certificate, store: reopened))
        let changed = RemoteCertificate(host: certificate.host, subject: "fixture", issuer: "fixture", fingerprint: String(repeating: "cd", count: 32))
        XCTAssertFalse(try RDPCertificateTrust.matches(id: id, host: certificate.host, port: 3389, certificate: changed, store: reopened))
        let invalid = RemoteCertificate(host: certificate.host, subject: "fixture", issuer: "fixture", fingerprint: "invalid")
        XCTAssertThrowsError(try RDPCertificateTrust.remember(id: id, host: certificate.host, port: 3389, certificate: invalid, store: store))
        XCTAssertEqual(try SSHPasswordStore.read(id: id, store: store), "fixture-password")
        try SSHPasswordStore.remove(id: id, store: store)
        XCTAssertTrue(try store.read().rdpCertificates.isEmpty)
    }
}
