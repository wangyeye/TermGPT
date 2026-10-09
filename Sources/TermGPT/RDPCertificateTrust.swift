import Foundation

struct RDPCertificatePin: Codable, Equatable {
    let host: String
    let port: Int
    let fingerprint: String
}

enum RDPCertificateTrust {
    private static func pin(host: String, port: Int, certificate: RemoteCertificate) throws -> RDPCertificatePin {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let fingerprint = certificate.fingerprint.replacingOccurrences(of: ":", with: "").lowercased()
        guard !normalizedHost.isEmpty, normalizedHost == certificate.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              (1...65535).contains(port), fingerprint.utf8.count == 64,
              fingerprint.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw AppError.message("无法保存证书信任，请重试")
        }
        return RDPCertificatePin(host: normalizedHost, port: port, fingerprint: fingerprint)
    }
    static func matches(id: UUID, host: String, port: Int, certificate: RemoteCertificate, store: CredentialStore = .shared) throws -> Bool {
        guard let candidate = try? pin(host: host, port: port, certificate: certificate) else { return false }
        return try store.read().rdpCertificates[id.uuidString] == candidate
    }
    static func remember(id: UUID, host: String, port: Int, certificate: RemoteCertificate, store: CredentialStore = .shared) throws {
        let candidate = try pin(host: host, port: port, certificate: certificate)
        try store.update { $0.rdpCertificates[id.uuidString] = candidate }
    }
}
