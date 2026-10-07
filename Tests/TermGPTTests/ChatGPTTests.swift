import XCTest
import CryptoKit
@testable import TermGPT
final class ChatGPTTests: XCTestCase {
    func testPKCEAndAuthorization() throws {
        XCTAssertEqual(ChatGPTOAuth.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertNotEqual(try ChatGPTOAuth.random(), try ChatGPTOAuth.random())
        let url = ChatGPTOAuth.authorize(clientID: "dynamic_agent_client", hostID: "urn:uuid:test", redirect: "http://127.0.0.1:1234/auth/callback", state: "state", nonce: "nonce", verifier: "verifier")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "agent_name_hint" }?.value, "TermGPT")
        XCTAssertEqual(items.first { $0.name == "scope" }?.value, ChatGPTOAuth.scope)
    }
    func testCallbackRejectsInvalidStateDuplicatesAndClient() throws {
        let base = "http://127.0.0.1:1234/auth/callback?code=fixture&state=ok"
        XCTAssertEqual(try ChatGPTOAuth.callback(URL(string: base + "&client_id=issued")!, state: "ok", registeredClient: nil).client, "issued")
        XCTAssertEqual(try ChatGPTOAuth.callback(URL(string: base)!, state: "ok", registeredClient: "issued").client, "issued")
        for value in [base, base + "&client_id=dynamic_agent_client", base + "&state=ok&client_id=issued", base.replacingOccurrences(of: "state=ok", with: "state=bad") + "&client_id=issued", base.replacingOccurrences(of: "127.0.0.1", with: "evil.example") + "&client_id=issued"] {
            XCTAssertThrowsError(try ChatGPTOAuth.callback(URL(string: value)!, state: "ok", registeredClient: nil))
        }
        XCTAssertThrowsError(try ChatGPTOAuth.callback(URL(string: base + "&client_id=other")!, state: "ok", registeredClient: "issued"))
    }
    func testSignedIdentityAndTamperRejection() throws {
        let key = P256.Signing.PrivateKey()
        let publicKey = key.publicKey.x963Representation
        let jwk: [String: Any] = ["kid": "test", "kty": "EC", "crv": "P-256", "x": ChatGPTOAuth.base64url(Data(publicKey[1..<33])), "y": ChatGPTOAuth.base64url(Data(publicKey[33..<65]))]
        let header = ChatGPTOAuth.base64url(try JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": "test"]))
        var claims: [String: Any] = ["iss": ChatGPTOAuth.issuer, "aud": "client", "nonce": "nonce", "sub": "subject", "exp": Date().timeIntervalSince1970 + 3600]
        func payload() throws -> String { ChatGPTOAuth.base64url(try JSONSerialization.data(withJSONObject: claims)) }
        let message = try header + "." + payload()
        let sig = ChatGPTOAuth.base64url(try key.signature(for: Data(message.utf8)).rawRepresentation)
        XCTAssertEqual(try OIDCSignature.verify(message + "." + sig, keys: [jwk], client: "client", nonce: "nonce")["sub"] as? String, "subject")
        XCTAssertThrowsError(try OIDCSignature.verify(message + "." + sig, keys: [jwk], client: "client", nonce: "wrong"))
        claims["sub"] = "tampered"
        XCTAssertThrowsError(try OIDCSignature.verify(header + "." + payload() + "." + sig, keys: [jwk], client: "client", nonce: "nonce"))
        claims["exp"] = Date().timeIntervalSince1970 - 1
        XCTAssertThrowsError(try ChatGPTOAuth.validateClaims(claims, client: "client", nonce: "nonce"))
    }
    func testPreferenceMigrationAndNoInventedPlan() throws {
        XCTAssertEqual(Preferences().provider, .chatGPT)
        let empty = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertEqual(empty.provider, .chatGPT)
        let old = try JSONDecoder().decode(Preferences.self, from: Data(#"{"model":"local-model","endpoint":"http://127.0.0.1:11434/v1"}"#.utf8))
        XCTAssertEqual(old.provider, .openAI)
        XCTAssertEqual(old.model, "local-model")
        XCTAssertNil(ChatGPTOAuth.planName([:]))
        XCTAssertEqual(ChatGPTOAuth.planName(["chatgpt_plan_type": "plus"]), "ChatGPT Plus")
        XCTAssertFalse(ChatGPTOAuth.permitted("openid profile"))
        XCTAssertTrue(ChatGPTOAuth.permitted(ChatGPTOAuth.scope))
    }
    @MainActor func testLoopbackCallbackTransport() async throws {
        let loop = OAuthLoopback()
        let redirect = try await loop.start()
        defer { loop.cancel() }
        let url = URL(string: redirect + "?code=fixture&state=test&client_id=issued")!
        let request = Task { try await URLSession.shared.data(from: url) }
        let callback = try await loop.wait()
        XCTAssertEqual(callback, url)
        let (_, response) = try await request.value
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }
}
