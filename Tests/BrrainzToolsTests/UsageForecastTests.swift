import Foundation
import CryptoKit
import XCTest
@testable import BrrainzTools

final class UsageForecastTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var reset: Date { now.addingTimeInterval(3 * 86400) }
    private func window(name: String = "primary", used: Double = 40, seconds: Double = 604800) -> UsageWindow {
        UsageWindow(name: name, usedPercent: used, windowSeconds: seconds,
                    resetsAt: ISO8601DateFormatter().string(from: reset), resetsInSeconds: nil, lockedReason: nil)
    }
    private func samples() -> [QuotaSample] {
        (0...48).map { index in
            QuotaSample(capturedAt: now.addingTimeInterval(Double(index - 48) * 1800), limitId: "codex",
                        limitName: nil, weeklyUsedPercent: 16 + Double(index) / 2,
                        weeklyWindowMinutes: 10080, weeklyResetsAt: reset, planType: "pro")
        }
    }
    private func history(_ samples: [QuotaSample]? = nil) -> TokenCoffeeHistory {
        TokenCoffeeHistory(samples: samples ?? self.samples(), lastSuccessfulSyncAt: now, syncCaughtUp: true)
    }
    private func forecast(_ samples: [QuotaSample]? = nil, used: Double = 40) -> UsageForecast {
        makeUsageForecast(window: window(used: used), plan: "pro", history: history(samples), now: now)
    }

    func testForecastMatchesTokenCoffeeAdjustedCurvesAndMeasuredRate() throws {
        let result = forecast()
        let reference = try XCTUnwrap(QuotaForecastKitAdapter.makeCycleRunForecast(
            current: 40, startDate: reset.addingTimeInterval(-604800), resetDate: reset, now: now, samples: samples()))
        XCTAssertEqual(result.status, "ok")
        XCTAssertEqual(result.optimistic?.usedPercentAtReset, reference.lowProjectedWeeklyUsedPercentAtReset)
        XCTAssertEqual(result.pessimistic?.usedPercentAtReset, reference.highProjectedWeeklyUsedPercentAtReset)
        XCTAssertEqual(result.optimistic?.reaches100At,
                       forecastCrossing(reference.lowLineSegments).map(ISO8601DateFormatter().string))
        XCTAssertEqual(result.recentRatePercentPointsPerHour, 1)
        XCTAssertEqual(result.recentRateSpanSeconds, 3600)
        XCTAssertEqual(result.accountMatch, "unverified")
        XCTAssertEqual(result.sampleCount, 49)
    }

    func testCrossingInterpolatesAndDoesNotExtrapolatePastReset() throws {
        func segment(_ from: Double, _ to: Double) -> QuotaForecastLineSegment {
            QuotaForecastLineSegment(startDate: now, endDate: now.addingTimeInterval(3600),
                                     startUsedPercent: from, endUsedPercent: to, kind: .projectedActivity)
        }
        XCTAssertEqual(forecastCrossing([segment(90, 110)]), now.addingTimeInterval(1800))
        XCTAssertEqual(forecastCrossing([segment(90, 100)]), now.addingTimeInterval(3600))
        XCTAssertEqual(forecastCrossing([segment(100, 100)]), now)
        XCTAssertNil(forecastCrossing([segment(90, 99)]))
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            UsageForecastScenario(usedPercentAtReset: 80, reaches100At: nil))) as! [String: Any]
        XCTAssertTrue(json["reaches100At"] is NSNull)
    }

    func testMissingStaleSparseAndFlatHistoryDoNotInventPredictions() {
        XCTAssertEqual(makeUsageForecast(window: window(), plan: "pro", history: nil, now: now).reason, "history_unreadable")
        XCTAssertEqual(forecast(Array(samples().dropLast(2))).status, "stale_history")
        XCTAssertEqual(forecast(Array(samples().suffix(2))).status, "insufficient_history")
        let flat = samples().map { sample in
            QuotaSample(capturedAt: sample.capturedAt, limitId: "codex", limitName: nil,
                        weeklyUsedPercent: 40, weeklyWindowMinutes: 10080, weeklyResetsAt: reset, planType: "pro")
        }
        XCTAssertEqual(forecast(flat).reason, "no_observed_usage_increase")
        XCTAssertNil(forecast(flat).optimistic)
    }

    func testMismatchedResetPlanAndDecreasesAreRejected() {
        let wrongReset = samples().map { sample in
            QuotaSample(capturedAt: sample.capturedAt, limitId: "codex", limitName: nil,
                        weeklyUsedPercent: sample.weeklyUsedPercent, weeklyWindowMinutes: 10080,
                        weeklyResetsAt: reset.addingTimeInterval(-604800), planType: "pro")
        }
        XCTAssertEqual(forecast(wrongReset).reason, "no_matching_history")
        XCTAssertEqual(makeUsageForecast(window: window(), plan: "plus", history: history(), now: now).reason,
                       "no_matching_history")
        XCTAssertEqual(forecast(used: 39).reason, "history_usage_mismatch")
        var decreased = samples()
        let old = decreased[20]
        decreased[20] = QuotaSample(capturedAt: old.capturedAt, limitId: "codex", limitName: nil,
                                   weeklyUsedPercent: 0, weeklyWindowMinutes: 10080, weeklyResetsAt: reset, planType: "pro")
        XCTAssertEqual(forecast(decreased).reason, "history_usage_mismatch")
    }

    func testAlreadyExhaustedNeedsNoHistoryAndExpiredWindowDoesNotForecast() {
        let result = makeUsageForecast(window: window(used: 100), plan: "pro", history: nil, now: now)
        XCTAssertEqual(result.status, "exhausted")
        XCTAssertEqual(result.optimistic?.reaches100At, ISO8601DateFormatter().string(from: now))
        XCTAssertEqual(makeUsageForecast(window: window(), plan: "pro", history: history(), now: reset).reason,
                       "missing_or_expired_reset")
    }

    func testReadOnlyFileIntegrationAndWindowSelection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = Data()
        for sample in samples() { data.append(try encoder.encode(sample)); data.append(10) }
        let file = directory.appendingPathComponent("quota-samples.jsonl")
        try data.write(to: file)
        try Data(#"{"lastSuccessfulSyncAt":"2027-01-15T07:59:00Z","isCaughtUp":true}"#.utf8)
            .write(to: directory.appendingPathComponent("quota-cloud-sync-state.json"))
        let windows = [window(), window(name: "secondary"), window(name: "Spark.secondary"), window(seconds: 18000)]
        let output = addTokenCoffeeForecasts(to: windows, plan: "pro", now: now, directory: directory)
        XCTAssertEqual(output[0].forecast?.status, "ok")
        XCTAssertEqual(output[1].forecast?.status, "ok")
        XCTAssertNil(output[2].forecast)
        XCTAssertNil(output[3].forecast)
        XCTAssertEqual(output[0].forecast?.syncCaughtUp, true)
        XCTAssertEqual(try Data(contentsOf: file), data)
        try Data("broken\n".utf8).write(to: file)
        let broken = addTokenCoffeeForecasts(to: windows, plan: "pro", now: now, directory: directory)
        XCTAssertEqual(broken[0].forecast?.reason, "history_unreadable")
        XCTAssertEqual(broken[0].usedPercent, 40)
    }

    func testDuplicatesAndForeignLimitsDoNotChangeForecast() {
        var input = samples() + samples()
        input.append(QuotaSample(capturedAt: now, limitId: "spark", limitName: nil, weeklyUsedPercent: 99,
                                 weeklyWindowMinutes: 10080, weeklyResetsAt: reset, planType: "pro"))
        input.append(QuotaSample(capturedAt: now.addingTimeInterval(60), limitId: "codex", limitName: nil,
                                 weeklyUsedPercent: 99, weeklyWindowMinutes: 10080, weeklyResetsAt: reset, planType: "pro"))
        XCTAssertEqual(forecast(input).sampleCount, 49)
        XCTAssertEqual(forecast(input).optimistic?.usedPercentAtReset, forecast().optimistic?.usedPercentAtReset)
    }
    func testSandboxSelectionDoesNotFallBackToOldDevelopmentHistory() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let container = home.appendingPathComponent("Library/Containers/com.pardeike.TokenCoffee")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        XCTAssertEqual(tokenCoffeeDirectory(home: home, environment: [:]),
                       container.appendingPathComponent("Data/Library/Application Support/TokenCoffee"))
        XCTAssertEqual(tokenCoffeeDirectory(home: home, environment: ["BRRAINZTOOLS_TOKENCOFFEE_DIRECTORY": "/tmp/explicit"]),
                       URL(fileURLWithPath: "/tmp/explicit", isDirectory: true))
    }

    func testLinkedClaudeHistoryIsPartitionedByAccountAndScope() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("multi-account")
        let account = UUID()
        let historyDirectory = root.appendingPathComponent("diagram-history/" + account.uuidString)
        try FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        func registry(_ ids: [UUID]) throws {
            let object = ["accounts": ids.map { ["id": $0.uuidString, "provider": "Claude", "identity": $0 == account ? "live-claude" : "other-claude"] }]
            try JSONSerialization.data(withJSONObject: object).write(to: root.appendingPathComponent("accounts.json"))
        }
        try registry([account])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        for scope in ["general", "model:fable"] {
            var data = Data()
            for sample in samples() {
                data.append(try encoder.encode(QuotaSample(capturedAt: sample.capturedAt, limitId: scope,
                    limitName: nil, weeklyUsedPercent: sample.weeklyUsedPercent, weeklyWindowMinutes: 10080,
                    weeklyResetsAt: reset, planType: nil)))
                data.append(10)
            }
            let filename = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
            try data.write(to: historyDirectory.appendingPathComponent(filename + ".jsonl"))
        }
        let windows = [window(name: "seven_day"), window(name: "model:fable"),
                       window(name: "five_hour", seconds: 18000), window(name: "seven_day_sonnet")]
        func read(_ environment: [String: String] = [:]) -> [UsageWindow] {
            addTokenCoffeeForecasts(to: windows, plan: nil, now: now, directory: directory,
                                   provider: .claude, accountIdentity: "live-claude", environment: environment)
        }
        XCTAssertEqual(read()[0].forecast?.status, "ok")
        XCTAssertEqual(read()[1].forecast?.status, "ok")
        XCTAssertEqual(read()[0].forecast?.accountMatch, "verified")
        XCTAssertNil(read()[2].forecast)
        XCTAssertNil(read()[3].forecast)
        let otherAccount = UUID()
        try registry([account, otherAccount])
        XCTAssertEqual(read()[0].forecast?.status, "ok", "Identity selects the correct account automatically")
        XCTAssertEqual(read(["BRRAINZTOOLS_TOKENCOFFEE_CLAUDE_ACCOUNT": account.uuidString])[0].forecast?.status, "ok")
        XCTAssertEqual(read(["BRRAINZTOOLS_TOKENCOFFEE_CLAUDE_ACCOUNT": otherAccount.uuidString])[0].forecast?.reason, "no_matching_account")
        let unverified = addTokenCoffeeForecasts(to: windows, plan: nil, now: now, directory: directory,
            provider: .claude, environment: ["BRRAINZTOOLS_TOKENCOFFEE_CLAUDE_ACCOUNT": account.uuidString])
        XCTAssertEqual(unverified[0].forecast?.reason, "account_identity_unverified")
        XCTAssertNil(unverified[0].forecast?.optimistic)
        XCTAssertEqual(read(["BRRAINZTOOLS_TOKENCOFFEE_CLAUDE_ACCOUNT": UUID().uuidString])[0].forecast?.reason, "no_matching_account")
        let codex = addTokenCoffeeForecasts(to: [window()], plan: "pro", now: now, directory: directory,
                                           accountIdentity: "different", environment: [:])
        XCTAssertEqual(codex[0].forecast?.reason, "no_matching_account")
        let codexRegistry = ["accounts": [["id": account.uuidString, "provider": "Codex", "identity": "live-account"]]]
        try JSONSerialization.data(withJSONObject: codexRegistry).write(to: root.appendingPathComponent("accounts.json"))
        var codexData = Data()
        for sample in samples() { codexData.append(try encoder.encode(sample)); codexData.append(10) }
        let general = SHA256.hash(data: Data("general".utf8)).map { String(format: "%02x", $0) }.joined()
        try codexData.write(to: historyDirectory.appendingPathComponent(general + ".jsonl"))
        let verified = addTokenCoffeeForecasts(to: [window()], plan: "pro", now: now, directory: directory,
            accountIdentity: "live-account", environment: [:])
        XCTAssertEqual(verified[0].forecast?.status, "ok")
        XCTAssertEqual(verified[0].forecast?.accountMatch, "verified")
        let unknownCodex = addTokenCoffeeForecasts(to: [window()], plan: "pro", now: now, directory: directory,
            environment: [:])
        XCTAssertEqual(unknownCodex[0].forecast?.reason, "account_identity_unverified")
        let mismatch = addTokenCoffeeForecasts(to: [window()], plan: "pro", now: now, directory: directory,
            accountIdentity: "wrong-account", environment: ["BRRAINZTOOLS_TOKENCOFFEE_CODEX_ACCOUNT": account.uuidString])
        XCTAssertEqual(mismatch[0].forecast?.reason, "no_matching_account")
    }

    func testFractionalResetMatchesRoundedTokenCoffeeHistory() {
        let base = window()
        let fractional = UsageWindow(name: base.name, usedPercent: base.usedPercent, windowSeconds: base.windowSeconds,
            resetsAt: ISO8601DateFormatter().string(from: reset.addingTimeInterval(-2)).replacingOccurrences(of: "Z", with: ".672Z"), resetsInSeconds: nil, lockedReason: nil)
        XCTAssertEqual(makeUsageForecast(window: fractional, plan: "pro", history: history(), now: now).status, "ok")
    }

    func testFreshRejectedSamplesAreDistinguishedFromStoppedCollection() {
        let old = Array(samples().dropLast(2))
        let stopped = forecast(old)
        XCTAssertEqual(stopped.status, "stale_history")
        XCTAssertEqual(stopped.reason, "no_recent_samples")
        let foreign = QuotaSample(capturedAt: now, limitId: "codex", limitName: nil,
            weeklyUsedPercent: 40, weeklyWindowMinutes: 10080, weeklyResetsAt: reset.addingTimeInterval(6), planType: "pro")
        let mismatched = forecast(old + [foreign])
        XCTAssertEqual(mismatched.status, "stale_history")
        XCTAssertEqual(mismatched.reason, "fresh_samples_do_not_match")
        XCTAssertEqual(mismatched.newestStoredSampleAt, ISO8601DateFormatter().string(from: now))
        XCTAssertEqual(mismatched.latestSampleAt, ISO8601DateFormatter().string(from: old.last!.capturedAt))
        XCTAssertEqual(mismatched.rejectedSampleCount, 1)
        XCTAssertNil(mismatched.optimistic)
    }

}
