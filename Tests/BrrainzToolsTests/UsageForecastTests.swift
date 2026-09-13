import Foundation
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

}
