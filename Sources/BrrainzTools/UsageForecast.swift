import Foundation
import CryptoKit

// Read-only subset of TokenCoffee's persisted QuotaSample. No credentials or cloud tokens.
struct QuotaSample: Codable, Sendable {
    let capturedAt: Date
    let limitId: String
    let limitName: String?
    let weeklyUsedPercent: Double
    let weeklyWindowMinutes: Int?
    let weeklyResetsAt: Date?
    let planType: String?
}

struct UsageForecastScenario: Encodable {
    let usedPercentAtReset: Double
    let reaches100At: String?

    enum CodingKeys: String, CodingKey { case usedPercentAtReset, reaches100At }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(usedPercentAtReset, forKey: .usedPercentAtReset)
        // Explicit null means no crossing before reset, not missing evidence.
        try values.encode(reaches100At, forKey: .reaches100At)
    }
}

struct UsageForecast: Encodable {
    var status: String
    let historySource = "tokencoffee"
    let method = "tokencoffee-e1b47ee-v3"
    let historyContractVersion = UsageHistoryContract.version
    // TokenCoffee's current sample format has no account identifier.
    var accountMatch = "unverified"
    var reason: String?
    var latestSampleAt: String?
    var newestStoredSampleAt: String?
    var rejectedSampleCount: Int?
    var lastSuccessfulSyncAt: String?
    var syncCaughtUp: Bool?
    var sampleCount: Int?
    var historySpanSeconds: Double?
    var recentRatePercentPointsPerHour: Double?
    var recentRateSpanSeconds: Double?
    var optimistic: UsageForecastScenario?
    var pessimistic: UsageForecastScenario?
}

struct TokenCoffeeHistory {
    let samples: [QuotaSample]
    let lastSuccessfulSyncAt: Date?
    let syncCaughtUp: Bool?

    static func load(directory: URL, filename: String = "quota-samples.jsonl", syncFile: URL? = nil) throws -> TokenCoffeeHistory {
        let file = directory.appendingPathComponent(filename)
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 32 * 1024 * 1024 else { throw UsageFailure(message: "TokenCoffee history exceeds 32 MB.") }
        let data = try Data(contentsOf: file)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Reject a damaged snapshot rather than turning discarded observations into idle time.
        let samples = try data.split(separator: 0x0A).map { try decoder.decode(QuotaSample.self, from: Data($0)) }
        struct SyncState: Decodable {
            let lastSuccessfulSyncAt: Date?
            let isCaughtUp: Bool?
        }
        let sync = try? decoder.decode(SyncState.self, from: Data(contentsOf:
            syncFile ?? directory.appendingPathComponent("quota-cloud-sync-state.json")))
        return TokenCoffeeHistory(samples: samples, lastSuccessfulSyncAt: sync?.lastSuccessfulSyncAt,
                                  syncCaughtUp: sync?.isCaughtUp)
    }
}

func tokenCoffeeDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                          environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
    if let override = environment["BRRAINZTOOLS_TOKENCOFFEE_DIRECTORY"], !override.isEmpty {
        return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
    }
    let relative = "Library/Application Support/TokenCoffee"
    let container = home.appendingPathComponent("Library/Containers/com.pardeike.TokenCoffee")
    if FileManager.default.fileExists(atPath: container.path) {
        // Do not fall back to an obsolete development store when macOS denies
        // access to the installed app's sandbox, or before its first sync.
        return container.appendingPathComponent("Data/" + relative)
    }
    return home.appendingPathComponent(relative)
}

// TokenCoffee 77bc2b4 stores each account and scope separately.
private struct TokenCoffeeAccounts: Decodable {
    struct Account: Decodable {
        let id: UUID
        let provider: String
        let identity: String?
    }
    let accounts: [Account]
}

func tokenCoffeeScope(_ window: UsageWindow, provider: UsageProvider) -> String? {
    guard window.windowSeconds == 604800 else { return nil }
    if provider == .codex { return ["primary", "secondary"].contains(window.name) ? "general" : nil }
    if window.name == "seven_day" { return "general" }
    return window.name.hasPrefix("model:") || window.name.hasPrefix("model-name:") ? window.name : nil
}

func addTokenCoffeeForecasts(to windows: [UsageWindow], plan: String?, now: Date,
                             directory: URL = tokenCoffeeDirectory(), provider: UsageProvider = .codex,
                             accountIdentity: String? = nil,
                             environment: [String: String] = ProcessInfo.processInfo.environment) -> [UsageWindow] {
    guard windows.contains(where: { tokenCoffeeScope($0, provider: provider) != nil }) else { return windows }
    let root = directory.appendingPathComponent("multi-account")
    let registryFile = root.appendingPathComponent("accounts.json")
    let linked = FileManager.default.fileExists(atPath: registryFile.path)
    let registry = try? JSONDecoder().decode(TokenCoffeeAccounts.self, from: Data(contentsOf: registryFile))
    let selection = environment["BRRAINZTOOLS_TOKENCOFFEE_" + provider.rawValue.uppercased() + "_ACCOUNT"]
    let accounts = registry?.accounts.filter { account in
        guard account.provider.lowercased() == provider.rawValue else { return false }
        if let selection, UUID(uuidString: selection) != account.id { return false }
        if let accountIdentity { return account.identity == accountIdentity }
        return true
    } ?? []
    return windows.map { window in
        guard let scope = tokenCoffeeScope(window, provider: provider) else { return window }
        var result = window
        guard !(provider == .claude || linked || selection != nil) || accountIdentity != nil else {
            result.forecast = UsageForecast(status: "unavailable", reason: "account_identity_unverified")
            return result
        }
        var history: TokenCoffeeHistory?
        if linked || provider == .claude || selection != nil {
            guard accounts.count == 1, let account = accounts.first else {
                result.forecast = UsageForecast(status: "unavailable", reason:
                    registry == nil ? "account_registry_unreadable" : accounts.isEmpty ? "no_matching_account" : "ambiguous_account")
                return result
            }
            let filename = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined() + ".jsonl"
            let accountKey = SHA256.hash(data: Data((account.provider + ":" + (account.identity ?? account.id.uuidString)).utf8))
                .map { String(format: "%02x", $0) }.joined()
            let syncKey = SHA256.hash(data: Data((accountKey + ":" + scope).utf8))
                .map { String(format: "%02x", $0) }.joined()
            let syncFiles = ["Development", "Production"].map {
                root.appendingPathComponent("cloud-state/" + $0 + "/" + syncKey + ".json")
            }.filter { FileManager.default.fileExists(atPath: $0.path) }
            // Do not attribute sync state from an ambiguous CloudKit environment.
            history = try? TokenCoffeeHistory.load(directory: root.appendingPathComponent("diagram-history")
                .appendingPathComponent(account.id.uuidString), filename: filename,
                syncFile: syncFiles.count == 1 ? syncFiles[0] : nil)
            result.forecast = makeUsageForecast(window: window, plan: plan, history: history, now: now,
                limitID: provider == .codex ? "codex" : scope)
            if let accountIdentity, account.identity == accountIdentity { result.forecast?.accountMatch = "verified" }
        } else {
            history = try? TokenCoffeeHistory.load(directory: directory)
            result.forecast = makeUsageForecast(window: window, plan: plan, history: history, now: now)
        }
        return result
    }
}

func makeUsageForecast(window: UsageWindow, plan: String?, history: TokenCoffeeHistory?, now: Date, limitID: String = "codex") -> UsageForecast {
    var result = UsageForecast(status: "unavailable")
    let formatter = ISO8601DateFormatter()
    guard let resetString = window.resetsAt, let reset = usageResetDate(resetString), reset > now else {
        result.reason = "missing_or_expired_reset"
        return result
    }
    if window.usedPercent >= 100 {
        result.status = "exhausted"
        let observed = UsageForecastScenario(usedPercentAtReset: window.usedPercent,
                                            reaches100At: formatter.string(from: now))
        result.optimistic = observed
        result.pessimistic = observed
        return result
    }
    guard let history else {
        result.reason = "history_unreadable"
        return result
    }
    result.lastSuccessfulSyncAt = history.lastSuccessfulSyncAt.map(formatter.string)
    result.syncCaughtUp = history.syncCaughtUp
    result.newestStoredSampleAt = history.samples.map(\.capturedAt).max().map(formatter.string)
    let start = reset.addingTimeInterval(-604800)
    let candidates = history.samples.filter {
        $0.limitId == limitID && $0.weeklyWindowMinutes == 10080 &&
        UsageHistoryContract.matchesReset($0.weeklyResetsAt, live: reset) &&
        (plan == nil || $0.planType == plan) && $0.capturedAt >= start && $0.capturedAt <= now
    }.sorted {
        $0.capturedAt == $1.capturedAt ? $0.weeklyUsedPercent < $1.weeklyUsedPercent : $0.capturedAt < $1.capturedAt
    }
    result.rejectedSampleCount = history.samples.count - candidates.count
    // Multiple devices may observe the same second. Keep the highest observation.
    var samples: [QuotaSample] = []
    for sample in candidates {
        if samples.last?.capturedAt == sample.capturedAt { samples.removeLast() }
        samples.append(sample)
    }
    result.sampleCount = samples.count
    guard let first = samples.first, let latest = samples.last else {
        result.reason = "no_matching_history"
        return result
    }
    result.latestSampleAt = formatter.string(from: latest.capturedAt)
    result.historySpanSeconds = latest.capturedAt.timeIntervalSince(first.capturedAt)
    guard samples.allSatisfy({ $0.weeklyUsedPercent.isFinite && $0.weeklyUsedPercent >= 0 }),
          latest.weeklyUsedPercent <= window.usedPercent,
          zip(samples, samples.dropFirst()).allSatisfy({ $0.weeklyUsedPercent <= $1.weeklyUsedPercent }) else {
        result.reason = "history_usage_mismatch"
        return result
    }
    guard now.timeIntervalSince(latest.capturedAt) <= 30 * 60 else {
        result.status = "stale_history"
        result.reason = history.samples.contains { $0.capturedAt > latest.capturedAt && $0.capturedAt <= now
            && now.timeIntervalSince($0.capturedAt) <= 30 * 60 }
            ? "fresh_samples_do_not_match" : "no_recent_samples"
        return result
    }
    guard samples.count >= 3, latest.capturedAt.timeIntervalSince(first.capturedAt) >= 60 * 60 else {
        result.status = "insufficient_history"
        return result
    }
    // A measured trailing rate, including idle time. Do not extend it across an
    // unobserved stale gap, or derive an angle from an arbitrary chart scale.
    let rateStart = samples.last(where: { $0.capturedAt <= now.addingTimeInterval(-3600) }) ?? first
    let rateSpan = now.timeIntervalSince(rateStart.capturedAt)
    result.recentRateSpanSeconds = rateSpan
    result.recentRatePercentPointsPerHour = (window.usedPercent - rateStart.weeklyUsedPercent) * 3600 / rateSpan
    guard let forecast = QuotaForecastKitAdapter.makeCycleRunForecast(
        current: window.usedPercent, startDate: start, resetDate: reset, now: now, samples: samples
    ) else {
        result.status = "insufficient_history"
        result.reason = "no_observed_usage_increase"
        return result
    }
    result.status = "ok"
    result.optimistic = UsageForecastScenario(
        usedPercentAtReset: forecast.lowProjectedWeeklyUsedPercentAtReset,
        reaches100At: forecastCrossing(forecast.lowLineSegments).map(formatter.string))
    result.pessimistic = UsageForecastScenario(
        usedPercentAtReset: forecast.highProjectedWeeklyUsedPercentAtReset,
        reaches100At: forecastCrossing(forecast.highLineSegments).map(formatter.string))
    return result
}

func forecastCrossing(_ segments: [QuotaForecastLineSegment]) -> Date? {
    for segment in segments {
        if segment.startUsedPercent >= 100 { return segment.startDate }
        if segment.endUsedPercent >= 100, segment.endUsedPercent > segment.startUsedPercent {
            let fraction = (100 - segment.startUsedPercent) / (segment.endUsedPercent - segment.startUsedPercent)
            return segment.startDate.addingTimeInterval(fraction * segment.endDate.timeIntervalSince(segment.startDate))
        }
    }
    return nil
}
