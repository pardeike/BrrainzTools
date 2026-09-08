import Foundation

let usageLimitsHelpText = """
Usage:
  brrainztools usage [codex|claude|all]
  brrainztools usage claude login
  brrainztools usage claude login --complete

Fetch live subscription limits. Codex uses its existing file-based login.
Claude uses ~/.brrainztools/auth.json; run the login command to authorize once.
The login command returns a browser URL; --complete reads code#state from stdin.
Claude tokens refresh automatically. No Keychain access or API keys.
Defaults to all. JSON data.providers contains status, windows, and any error.
Percentages describe account allowance, not token counts. Reset times are UTC.
Each request times out after 20 seconds. Polling never opens login or permission prompts.
Exit 0 when all requested providers succeed; exit 1 if any are unavailable.
Provider failures remain in the JSON result on stdout, including partial results.
"""

enum UsageProvider: String, CaseIterable, Sendable, Codable {
    case codex, claude

    var endpoint: URL {
        URL(string: self == .codex
            ? "https://chatgpt.com/backend-api/wham/usage"
            : "https://api.anthropic.com/api/oauth/usage")!
    }
}

struct UsageWindow: Encodable {
    let name: String
    let usedPercent: Double
    var remainingPercent: Double { max(0, 100 - usedPercent) }
    let windowSeconds: Double?
    let resetsAt: String?
    let resetsInSeconds: Double?
    let lockedReason: String?

    enum CodingKeys: String, CodingKey {
        case name, usedPercent, remainingPercent, windowSeconds, resetsAt, resetsInSeconds, lockedReason
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(usedPercent, forKey: .usedPercent)
        try container.encode(remainingPercent, forKey: .remainingPercent)
        try container.encodeIfPresent(windowSeconds, forKey: .windowSeconds)
        try container.encodeIfPresent(resetsAt, forKey: .resetsAt)
        try container.encodeIfPresent(resetsInSeconds, forKey: .resetsInSeconds)
        try container.encodeIfPresent(lockedReason, forKey: .lockedReason)
    }
}

struct ProviderUsage: Encodable {
    let provider: UsageProvider
    let source: URL
    let checkedAt: String
    let status: String
    let plan: String?
    let windows: [UsageWindow]
    let error: String?
}

struct UsageReport: Encodable {
    let providers: [ProviderUsage]
    var succeeded: Bool { providers.allSatisfy { $0.status == "ok" } }
}

struct UsageFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct UsageCredential: Decodable {
    struct Tokens: Decodable {
        let access_token: String?
        let account_id: String?
    }
    let tokens: Tokens?
    let access_token: String?
    let account_id: String?
}

private func usageCredential(_ provider: UsageProvider, session: URLSession) async throws -> (token: String, account: String?) {
    if provider == .claude { return (try await loadClaudeUsageToken(session: session), nil) }
    let home = FileManager.default.homeDirectoryForCurrentUser
    let environment = ProcessInfo.processInfo.environment
    let directory = environment["CODEX_HOME"]
        .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        ?? home.appendingPathComponent(".codex")
    let file = directory.appendingPathComponent("auth.json")
    if let data = try? Data(contentsOf: file),
       let credential = try? JSONDecoder().decode(UsageCredential.self, from: data) {
        let token = credential.tokens?.access_token ?? credential.access_token
        if let token, !token.isEmpty {
            return (token, credential.tokens?.account_id ?? credential.account_id)
        }
    }
    throw UsageFailure(message: "No readable Codex OAuth credential. Run 'codex login'.")
}

private struct CodexUsage: Decodable {
    struct Window: Decodable {
        let used_percent: Double
        let limit_window_seconds: Double?
        let reset_at: Double?
        let reset_after_seconds: Double?
    }
    struct Limit: Decodable {
        let primary_window: Window?
        let secondary_window: Window?
    }
    struct Additional: Decodable {
        let limit_name: String?
        let metered_feature: String?
        let rate_limit: Limit?
    }
    let plan_type: String?
    let rate_limit: Limit?
    let additional_rate_limits: [Additional]?
}

private struct ClaudeWindow: Decodable {
    let utilization: Double?
    let resets_at: String?
    let locked_reason: String?
}

func parseUsageData(_ data: Data, provider: UsageProvider) throws -> (plan: String?, windows: [UsageWindow]) {
    var windows: [UsageWindow] = []
    var plan: String?
    if provider == .codex {
        let response = try JSONDecoder().decode(CodexUsage.self, from: data)
        plan = response.plan_type
        func append(_ limit: CodexUsage.Limit?, prefix: String) {
            for (name, value) in [("primary", limit?.primary_window), ("secondary", limit?.secondary_window)] {
                guard let value, value.used_percent.isFinite, value.used_percent >= 0 else { continue }
                windows.append(UsageWindow(
                    name: prefix + name, usedPercent: value.used_percent,
                    windowSeconds: value.limit_window_seconds,
                    resetsAt: value.reset_at.map { ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: $0)) },
                    resetsInSeconds: value.reset_after_seconds, lockedReason: nil))
            }
        }
        append(response.rate_limit, prefix: "")
        for additional in response.additional_rate_limits ?? [] {
            append(additional.rate_limit, prefix: (additional.limit_name ?? additional.metered_feature ?? "additional") + ".")
        }
    } else {
        // Only decode allowance windows; unrelated objects such as extra_usage are not percentages.
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        for key in object.keys.sorted() where key == "five_hour" || key.hasPrefix("seven_day") {
            guard let object = object[key] as? [String: Any] else { continue }
            let value = try JSONDecoder().decode(ClaudeWindow.self, from: JSONSerialization.data(withJSONObject: object))
            guard let used = value.utilization, used.isFinite, used >= 0 else { continue }
            windows.append(UsageWindow(name: key, usedPercent: used,
                                       windowSeconds: key == "five_hour" ? 18000 : 604800,
                                       resetsAt: value.resets_at, resetsInSeconds: nil, lockedReason: value.locked_reason))
        }
    }
    guard !windows.isEmpty else { throw UsageFailure(message: "Provider returned no usable allowance windows.") }
    return (plan, windows)
}

func usageHTTPError(_ status: Int) -> String {
    switch status {
    case 401: "Authentication expired or rejected. Sign in again with the provider CLI."
    case 403: "Provider denied access to subscription usage (HTTP 403)."
    case 429: "Usage query rate-limited (HTTP 429). Wait before polling again."
    default: "Usage endpoint returned HTTP \(status)."
    }
}

func pollUsage(_ providers: [UsageProvider]) async -> UsageReport {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 20
    configuration.timeoutIntervalForResource = 20
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    var results: [ProviderUsage] = []
    for provider in providers {
        var plan: String?
        var windows: [UsageWindow] = []
        var failure: String?
        do {
            let credential = try await usageCredential(provider, session: session)
            var request = URLRequest(url: provider.endpoint)
            request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
            if provider == .codex {
                request.setValue(credential.account, forHTTPHeaderField: "chatgpt-account-id")
                request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
                request.setValue("codex_cli_rs", forHTTPHeaderField: "User-Agent")
            } else {
                request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
                request.setValue("brrainztools", forHTTPHeaderField: "User-Agent")
            }
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw UsageFailure(message: "Invalid HTTP response.")
            }
            guard response.statusCode == 200 else { throw UsageFailure(message: usageHTTPError(response.statusCode)) }
            (plan, windows) = try parseUsageData(data, provider: provider)
        } catch let error as UsageFailure {
            failure = error.message
        } catch is DecodingError {
            failure = "Provider returned malformed usage data."
        } catch let error as URLError {
            failure = error.code == .timedOut ? "Usage request timed out." : "Could not reach usage endpoint."
        } catch {
            // Never print raw provider bodies, credential data, or arbitrary error details.
            failure = "Could not read provider usage data."
        }
        results.append(ProviderUsage(provider: provider, source: provider.endpoint,
                                     checkedAt: ISO8601DateFormatter().string(from: Date()),
                                     status: failure == nil ? "ok" : "unavailable",
                                     plan: plan, windows: windows, error: failure))
    }
    return UsageReport(providers: results)
}
