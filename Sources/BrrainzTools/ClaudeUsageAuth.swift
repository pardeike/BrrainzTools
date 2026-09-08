import CryptoKit
import Darwin
import Foundation

// Public OAuth client and endpoints used by the installed Claude Code 2.1.236.
// Request only profile access, which is used by the subscription usage endpoint.
let claudeUsageClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
let claudeUsageRedirect = "https://platform.claude.com/oauth/code/callback"
let claudeUsageTokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!

struct ClaudeUsageCredential: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Double // Unix seconds

    func needsRefresh(now: Date = Date()) -> Bool {
        expiresAt <= now.timeIntervalSince1970 + 60
    }
}

struct ClaudeUsageAuthFile: Codable {
    let claude: ClaudeUsageCredential
}

struct ClaudeUsagePendingLogin: Codable {
    let verifier: String
    let state: String
    let createdAt: Date
}

struct ClaudeUsageLoginResult: Encodable {
    let status: String
    let authorizationURL: String?
    let instruction: String
}

struct ClaudeUsageTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Double
    let scope: String?

    func credential(previousRefreshToken: String? = nil, now: Date = Date()) throws -> ClaudeUsageCredential {
        guard !access_token.isEmpty, expires_in.isFinite, expires_in > 0,
              let refresh = refresh_token ?? previousRefreshToken, !refresh.isEmpty else {
            throw UsageFailure(message: "Claude returned an incomplete OAuth credential. Run 'brrainztools usage claude login' again.")
        }
        if let scope, !scope.split(separator: " ").contains("user:profile") {
            throw UsageFailure(message: "Claude did not grant profile access required for usage polling.")
        }
        return ClaudeUsageCredential(accessToken: access_token, refreshToken: refresh,
                                     expiresAt: now.timeIntervalSince1970 + expires_in)
    }
}

func claudeUsageAuthDirectory() -> URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".brrainztools", isDirectory: true)
}

func claudeUsageChallenge(_ verifier: String) -> String {
    Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

func claudeUsageAuthorizationURL(_ pending: ClaudeUsagePendingLogin) -> URL {
    var url = URLComponents(string: "https://claude.com/cai/oauth/authorize")!
    url.queryItems = [
        URLQueryItem(name: "code", value: "true"),
        URLQueryItem(name: "client_id", value: claudeUsageClientID),
        URLQueryItem(name: "response_type", value: "code"),
        URLQueryItem(name: "redirect_uri", value: claudeUsageRedirect),
        URLQueryItem(name: "scope", value: "user:profile"),
        URLQueryItem(name: "code_challenge", value: claudeUsageChallenge(pending.verifier)),
        URLQueryItem(name: "code_challenge_method", value: "S256"),
        URLQueryItem(name: "state", value: pending.state),
    ]
    return url.url!
}

// Private directory plus exclusive, non-following lock protects the credential and
// serializes rotating refresh tokens across separate polling processes.
func lockClaudeUsageAuth(directory: URL) throws -> Int32 {
    let manager = FileManager.default
    try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
    let attributes = try manager.attributesOfItem(atPath: directory.path)
    guard attributes[.type] as? FileAttributeType == .typeDirectory,
          (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
        throw UsageFailure(message: "Claude auth directory must be a directory owned by the current user, not a symlink.")
    }
    try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    let fd = open(directory.appendingPathComponent("auth.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
    guard fd >= 0 else { throw UsageFailure(message: "Could not open Claude auth lock.") }
    guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
        close(fd)
        throw UsageFailure(message: "Another process is updating Claude authentication. Poll again after it finishes.")
    }
    return fd
}

func writeClaudeUsageSecret<T: Encodable>(_ value: T, to url: URL) throws {
    // The containing directory is already mode 0700 and exclusively locked.
    try JSONEncoder().encode(value).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}

func readClaudeUsageSecret<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard attributes[.type] as? FileAttributeType == .typeRegular,
          (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
          let mode = attributes[.posixPermissions] as? NSNumber, mode.intValue & 0o077 == 0 else {
        throw UsageFailure(message: "Claude auth file must be a regular file owned by you with permissions 0600.")
    }
    do { return try JSONDecoder().decode(type, from: Data(contentsOf: url)) }
    catch { throw UsageFailure(message: "Claude auth file is invalid. Run 'brrainztools usage claude login' again.") }
}

func claudeUsageAuthorizationCode(_ input: String, pending: ClaudeUsagePendingLogin, now: Date = Date()) throws -> String {
    guard now.timeIntervalSince(pending.createdAt) >= 0, now.timeIntervalSince(pending.createdAt) < 1800 else {
        throw UsageFailure(message: "Pending Claude login expired. Run 'brrainztools usage claude login' again.")
    }
    let parts = input.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "#", omittingEmptySubsequences: false)
    guard parts.count == 2, !parts[0].isEmpty, parts[1] == pending.state else {
        throw UsageFailure(message: "Expected the complete code#state from the browser for this login.")
    }
    return String(parts[0])
}

func exchangeClaudeUsageToken(_ body: [String: String], session: URLSession) async throws -> ClaudeUsageTokenResponse {
    var request = URLRequest(url: claudeUsageTokenURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(body)
    let data: Data
    let response: URLResponse
    do { (data, response) = try await session.data(for: request) }
    catch { throw UsageFailure(message: "Could not reach Claude OAuth endpoint. Try again later.") }
    guard let http = response as? HTTPURLResponse else { throw UsageFailure(message: "Invalid Claude OAuth response.") }
    guard http.statusCode == 200 else {
        throw UsageFailure(message: http.statusCode == 429
            ? "Claude OAuth endpoint rate-limited the request (HTTP 429). Wait before trying again."
            : "Claude OAuth request failed (HTTP \(http.statusCode)). Run 'brrainztools usage claude login' if authorization expired or was revoked.")
    }
    do { return try JSONDecoder().decode(ClaudeUsageTokenResponse.self, from: data) }
    catch { throw UsageFailure(message: "Claude returned malformed OAuth data.") }
}

func claudeUsageSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 20
    config.timeoutIntervalForResource = 20
    return URLSession(configuration: config)
}

func handleClaudeUsageLogin(complete: Bool) async throws -> ClaudeUsageLoginResult {
    let directory = claudeUsageAuthDirectory()
    let fd = try lockClaudeUsageAuth(directory: directory)
    defer { close(fd) }
    let pendingURL = directory.appendingPathComponent("claude-login.json")
    if !complete {
        func randomString() -> String {
            Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let pending = ClaudeUsagePendingLogin(verifier: randomString(), state: randomString(), createdAt: Date())
        try writeClaudeUsageSecret(pending, to: pendingURL)
        return ClaudeUsageLoginResult(status: "authorization_required", authorizationURL: claudeUsageAuthorizationURL(pending).absoluteString,
                                      instruction: "Open authorizationURL in your browser. Then run 'brrainztools usage claude login --complete' and paste the browser's code#state into stdin.")
    }
    guard FileManager.default.fileExists(atPath: pendingURL.path) else {
        throw UsageFailure(message: "No pending Claude login. Run 'brrainztools usage claude login' first.")
    }
    let pending = try readClaudeUsageSecret(ClaudeUsagePendingLogin.self, from: pendingURL)
    // Input is never a command argument, log field, or part of the JSON result.
    FileHandle.standardError.write(Data("Paste the browser's code#state and press Return:\n".utf8))
    let code = try claudeUsageAuthorizationCode(readLine() ?? "", pending: pending)
    let session = claudeUsageSession()
    defer { session.invalidateAndCancel() }
    let response = try await exchangeClaudeUsageToken([
        "grant_type": "authorization_code", "code": code, "state": pending.state,
        "redirect_uri": claudeUsageRedirect, "client_id": claudeUsageClientID,
        "code_verifier": pending.verifier,
    ], session: session)
    try writeClaudeUsageSecret(ClaudeUsageAuthFile(claude: response.credential()), to: directory.appendingPathComponent("auth.json"))
    try FileManager.default.removeItem(at: pendingURL)
    return ClaudeUsageLoginResult(status: "authenticated", authorizationURL: nil,
                                  instruction: "Credential saved to ~/.brrainztools/auth.json. Run 'brrainztools usage claude'.")
}

func loadClaudeUsageToken(directory: URL = claudeUsageAuthDirectory(), session: URLSession) async throws -> String {
    let fd = try lockClaudeUsageAuth(directory: directory)
    defer { close(fd) }
    let url = directory.appendingPathComponent("auth.json")
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw UsageFailure(message: "No file-based Claude usage login. Run 'brrainztools usage claude login'. Keychain and API keys are not used.")
    }
    let credential = try readClaudeUsageSecret(ClaudeUsageAuthFile.self, from: url).claude
    guard !credential.accessToken.isEmpty, !credential.refreshToken.isEmpty else {
        throw UsageFailure(message: "Incomplete Claude usage credential. Run 'brrainztools usage claude login'.")
    }
    if !credential.needsRefresh() { return credential.accessToken }
    let response = try await exchangeClaudeUsageToken([
        "grant_type": "refresh_token", "refresh_token": credential.refreshToken,
        "client_id": claudeUsageClientID, "scope": "user:profile",
    ], session: session)
    let refreshed = try response.credential(previousRefreshToken: credential.refreshToken)
    try writeClaudeUsageSecret(ClaudeUsageAuthFile(claude: refreshed), to: url)
    return refreshed.accessToken
}
