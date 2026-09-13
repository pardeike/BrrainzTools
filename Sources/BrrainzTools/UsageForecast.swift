import Foundation

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
    let method = "tokencoffee-e1b47ee-v1"
    // TokenCoffee's current sample format has no account identifier.
    let accountMatch = "unverified"
    var reason: String?
    var latestSampleAt: String?
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

    static func load(directory: URL) throws -> TokenCoffeeHistory {
        let file = directory.appendingPathComponent("quota-samples.jsonl")
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
            directory.appendingPathComponent("quota-cloud-sync-state.json")))
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

func addTokenCoffeeForecasts(to windows: [UsageWindow], plan: String?, now: Date,
                             directory: URL = tokenCoffeeDirectory()) -> [UsageWindow] {
    // Only TokenCoffee's account-wide weekly history is supported. A provider may
    // call this primary or secondary; duration, not position, identifies the window.
    let supported: (UsageWindow) -> Bool = {
        ["primary", "secondary"].contains($0.name) && $0.windowSeconds == 604800
    }
    guard windows.contains(where: supported) else { return windows }
    let history = try? TokenCoffeeHistory.load(directory: directory)
    return windows.map { window in
        guard supported(window) else { return window }
        var result = window
        result.forecast = makeUsageForecast(window: window, plan: plan, history: history, now: now)
        return result
    }
}

func makeUsageForecast(window: UsageWindow, plan: String?, history: TokenCoffeeHistory?, now: Date) -> UsageForecast {
    var result = UsageForecast(status: "unavailable")
    let formatter = ISO8601DateFormatter()
    guard let resetString = window.resetsAt, let reset = formatter.date(from: resetString), reset > now else {
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
    let start = reset.addingTimeInterval(-604800)
    let candidates = history.samples.filter {
        $0.limitId == "codex" && $0.weeklyWindowMinutes == 10080 &&
        $0.weeklyResetsAt.map { abs($0.timeIntervalSince(reset)) <= 1 } == true &&
        (plan == nil || $0.planType == plan) && $0.capturedAt >= start && $0.capturedAt <= now
    }.sorted {
        $0.capturedAt == $1.capturedAt ? $0.weeklyUsedPercent < $1.weeklyUsedPercent : $0.capturedAt < $1.capturedAt
    }
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
