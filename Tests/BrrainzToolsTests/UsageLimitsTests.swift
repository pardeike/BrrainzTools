import Foundation
import XCTest
@testable import BrrainzTools

final class UsageLimitsTests: XCTestCase {
    func testProviderSelectionAndHelp() throws {
        for arguments in [["usage"], ["usage", "all"], ["usage", "codex"], ["usage", "claude"]] {
            guard case .usageLimits(let providers) = try parse(arguments: arguments) else {
                return XCTFail("Expected usage command")
            }
            XCTAssertEqual(providers.count, arguments.count == 1 || arguments.last == "all" ? 2 : 1)
            XCTAssertFalse(try parse(arguments: arguments).shouldSynchronizeAgentSupport)
        }
        guard case .showHelpText(let help) = try parse(arguments: ["usage", "--help"]) else {
            return XCTFail("Expected help")
        }
        XCTAssertTrue(help.contains("brrainztools usage"))
        XCTAssertThrowsError(try parse(arguments: ["usage", "unknown"]))
        XCTAssertThrowsError(try parse(arguments: ["usage", "codex", "claude"]))
    }

    func testCodexWindowsAndAdditionalLimits() throws {
        let data = Data(#"{"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":24,"limit_window_seconds":18000,"reset_at":1800000000,"reset_after_seconds":900}},"additional_rate_limits":[{"limit_name":"model","rate_limit":{"secondary_window":{"used_percent":105,"limit_window_seconds":604800}}}]}"#.utf8)
        let result = try parseUsageData(data, provider: .codex)
        XCTAssertEqual(result.plan, "pro")
        XCTAssertEqual(result.windows.count, 2)
        XCTAssertEqual(result.windows[0].remainingPercent, 76)
        XCTAssertEqual(result.windows[0].resetsAt, "2027-01-15T08:00:00Z")
        XCTAssertEqual(result.windows[1].name, "model.secondary")
        XCTAssertEqual(result.windows[1].remainingPercent, 0)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result.windows[0])) as! [String: Any]
        XCTAssertEqual(json["remainingPercent"] as? Double, 76)
    }

    func testClaudeWindowsAndModelLimits() throws {
        let data = Data(#"{"five_hour":{"utilization":12.5,"resets_at":"2026-09-07T00:00:00Z"},"seven_day":{"utilization":100,"locked_reason":"limit"},"seven_day_sonnet":{"utilization":5},"seven_day_opus":null,"extra_usage":{"utilization":99}}"#.utf8)
        let result = try parseUsageData(data, provider: .claude)
        XCTAssertEqual(result.windows.map(\.name), ["five_hour", "seven_day", "seven_day_sonnet"])
        XCTAssertEqual(result.windows[0].remainingPercent, 87.5)
        XCTAssertEqual(result.windows[1].lockedReason, "limit")
    }

    func testMissingOrMalformedLimitsAreNotReportedAsZeroUsage() {
        for provider in UsageProvider.allCases {
            for json in ["{}", "null", "not json"] {
                XCTAssertThrowsError(try parseUsageData(Data(json.utf8), provider: provider))
            }
        }
        for json in [#"{"five_hour":{"utilization":true}}"#, #"{"five_hour":{"utilization":-1}}"#] {
            XCTAssertThrowsError(try parseUsageData(Data(json.utf8), provider: .claude))
        }
    }

    func testHTTPFailuresAndPartialReport() {
        XCTAssertTrue(usageHTTPError(401).contains("Authentication"))
        XCTAssertTrue(usageHTTPError(429).contains("Wait"))
        XCTAssertTrue(usageHTTPError(503).contains("503"))
        let result = UsageReport(providers: [ProviderUsage(provider: .claude, source: UsageProvider.claude.endpoint,
                                                         checkedAt: "now", status: "unavailable", plan: nil,
                                                         windows: [], error: "Missing credential")])
        XCTAssertFalse(result.succeeded)
    }
}
