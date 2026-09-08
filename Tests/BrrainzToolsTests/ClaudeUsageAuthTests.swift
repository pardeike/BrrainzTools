import Darwin
import Foundation
import XCTest
@testable import BrrainzTools

private final class OAuthStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class ClaudeUsageAuthTests: XCTestCase, @unchecked Sendable {
    func testLoginParsing() throws {
        for (args, complete) in [(["usage", "claude", "login"], false), (["usage", "claude", "login", "--complete"], true)] {
            guard case .claudeUsageLogin(let actual) = try parse(arguments: args) else { return XCTFail() }
            XCTAssertEqual(actual, complete)
        }
        XCTAssertThrowsError(try parse(arguments: ["usage", "claude", "login", "secret"]))
    }

    func testPKCEAndLeastPrivilegeAuthorization() throws {
        // RFC 7636 published test vector.
        XCTAssertEqual(claudeUsageChallenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let pending = ClaudeUsagePendingLogin(verifier: "secret-verifier", state: "state", createdAt: Date())
        let url = claudeUsageAuthorizationURL(pending)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "scope" }?.value, "user:profile")
        XCTAssertFalse(url.absoluteString.contains(pending.verifier))
        XCTAssertEqual(try claudeUsageAuthorizationCode("code#state\n", pending: pending), "code")
        XCTAssertThrowsError(try claudeUsageAuthorizationCode("code#wrong", pending: pending))
        XCTAssertThrowsError(try claudeUsageAuthorizationCode("code", pending: pending))
        XCTAssertThrowsError(try claudeUsageAuthorizationCode("code#state", pending: pending, now: Date().addingTimeInterval(1900)))
    }

    func testPrivateStorageAndExclusiveLock() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fd = try lockClaudeUsageAuth(directory: directory)
        defer { close(fd) }
        XCTAssertThrowsError(try lockClaudeUsageAuth(directory: directory))
        let url = directory.appendingPathComponent("auth.json")
        let auth = ClaudeUsageAuthFile(claude: ClaudeUsageCredential(accessToken: "test-access", refreshToken: "test-refresh", expiresAt: 100))
        try writeClaudeUsageSecret(auth, to: url)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual(try readClaudeUsageSecret(ClaudeUsageAuthFile.self, from: url).claude.accessToken, "test-access")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        XCTAssertThrowsError(try readClaudeUsageSecret(ClaudeUsageAuthFile.self, from: url))
        let symlink = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: url)
        XCTAssertThrowsError(try readClaudeUsageSecret(ClaudeUsageAuthFile.self, from: symlink))
    }

    func testTokenValidationAndRefreshMargin() throws {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(ClaudeUsageCredential(accessToken: "a", refreshToken: "r", expiresAt: 1060).needsRefresh(now: now))
        XCTAssertFalse(ClaudeUsageCredential(accessToken: "a", refreshToken: "r", expiresAt: 1061).needsRefresh(now: now))
        let response = ClaudeUsageTokenResponse(access_token: "new", refresh_token: nil, expires_in: 600, scope: "user:profile")
        XCTAssertEqual(try response.credential(previousRefreshToken: "old", now: now).expiresAt, 1600)
        XCTAssertThrowsError(try response.credential())
        XCTAssertThrowsError(try ClaudeUsageTokenResponse(access_token: "new", refresh_token: "r", expires_in: 600, scope: "user:inference").credential())
    }

    func testRefreshPersistsRotationAndFailurePreservesFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fd = try lockClaudeUsageAuth(directory: directory)
        close(fd)
        let file = directory.appendingPathComponent("auth.json")
        let original = ClaudeUsageAuthFile(claude: ClaudeUsageCredential(accessToken: "old-access", refreshToken: "old-refresh", expiresAt: 1))
        try writeClaudeUsageSecret(original, to: file)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OAuthStub.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); OAuthStub.handler = nil }
        OAuthStub.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url, claudeUsageTokenURL)
            return (200, Data(#"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600,"scope":"user:profile"}"#.utf8))
        }
        let token = try await loadClaudeUsageToken(directory: directory, session: session)
        XCTAssertEqual(token, "new-access")
        XCTAssertEqual(try readClaudeUsageSecret(ClaudeUsageAuthFile.self, from: file).claude.refreshToken, "new-refresh")
        OAuthStub.handler = { _ in XCTFail("Fresh token must not make a refresh request"); return (500, Data()) }
        let cached = try await loadClaudeUsageToken(directory: directory, session: session)
        XCTAssertEqual(cached, "new-access")
        try writeClaudeUsageSecret(original, to: file)
        let before = try Data(contentsOf: file)
        OAuthStub.handler = { _ in (429, Data("private server response must not appear in errors".utf8)) }
        do {
            _ = try await loadClaudeUsageToken(directory: directory, session: session)
            XCTFail("Expected refresh failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("429"))
            XCTAssertFalse(error.localizedDescription.contains("private server response"))
        }
        XCTAssertEqual(try Data(contentsOf: file), before)
    }
}
