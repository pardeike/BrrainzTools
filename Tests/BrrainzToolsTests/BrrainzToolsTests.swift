import CoreGraphics
import Foundation
import Vision
import XCTest
@testable import BrrainzTools

final class BrrainzToolsTests: XCTestCase {
    func testFindAppParsing() throws {
        let behavior = try parse(arguments: ["--find-app", "RimWorld"])

        guard case .findApps(let command) = behavior else {
            return XCTFail("Expected find-app behavior.")
        }

        XCTAssertEqual(command.query, "RimWorld")
    }

    func testVersionParsing() throws {
        let behavior = try parse(arguments: ["--version"])

        guard case .showVersion = behavior else {
            return XCTFail("Expected version behavior.")
        }
    }

    func testVersionRejectsMixedArguments() {
        XCTAssertThrowsError(
            try parse(arguments: ["--version", "--raw"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--version"))
        }
    }

    func testSubcommandHelpParsing() throws {
        let behavior = try parse(arguments: ["capture", "--help"])

        guard case .showHelpText(let text) = behavior else {
            return XCTFail("Expected focused help behavior.")
        }

        XCTAssertTrue(text.contains("brrainztools capture"))

        let doctorBehavior = try parse(arguments: ["doctor", "--help"])
        guard case .showHelpText(let doctorText) = doctorBehavior else {
            return XCTFail("Expected doctor help behavior.")
        }

        XCTAssertTrue(doctorText.contains("brrainztools doctor"))
    }

    func testActionSubcommandHelpParsing() throws {
        for arguments in [
            ["ax", "scroll", "--help"],
            ["ax", "--app", "Terminal", "scroll", "0,-120", "--help"],
            ["ax", "get", "-h"],
        ] {
            let behavior = try parse(arguments: arguments)
            guard case .showHelpText(let text) = behavior else {
                return XCTFail("Expected AX help for \(arguments).")
            }
            XCTAssertTrue(text.contains("brrainztools ax"))
        }

        let menuBehavior = try parse(arguments: ["menu", "press-item", "--help"])
        guard case .showHelpText(let menuText) = menuBehavior else {
            return XCTFail("Expected menu help.")
        }
        XCTAssertTrue(menuText.contains("brrainztools menu"))
    }

    func testCaptureSubcommandForwardsToLegacyCaptureParser() throws {
        let behavior = try parse(arguments: ["capture", "1", "2", "3", "4", "--raw"])

        guard case .capture(let command) = behavior else {
            return XCTFail("Expected capture behavior.")
        }

        XCTAssertEqual(command.region?.x, 1)
        XCTAssertTrue(command.rawOutput)
    }

    func testCaptureSubcommandDefaultsAppOnlyToFrontmostWindowCapture() throws {
        let behavior = try parse(arguments: ["capture", "--app", "Finder", "--output", "/tmp/finder.png"])

        guard case .capture(let command) = behavior else {
            return XCTFail("Expected capture behavior.")
        }

        XCTAssertNil(command.region)
        XCTAssertEqual(command.outputURL.path, "/tmp/finder.png")
        guard case .frontmost? = command.windowSelection else {
            return XCTFail("Expected frontmost app-window capture.")
        }
    }

    func testCaptureSubcommandRejectsNonCaptureModes() {
        XCTAssertThrowsError(
            try parse(arguments: ["capture", "--app", "Finder", "--list-windows"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("windows"))
        }
    }

    func testAppsAndDisplaysSubcommands() throws {
        let appsBehavior = try parse(arguments: ["apps", "Terminal"])

        guard case .findApps(let command) = appsBehavior else {
            return XCTFail("Expected find-app behavior.")
        }

        XCTAssertEqual(command.query, "Terminal")

        let displaysBehavior = try parse(arguments: ["displays"])
        guard case .listDisplays = displaysBehavior else {
            return XCTFail("Expected display list behavior.")
        }
    }

    func testWindowsSubcommandModes() throws {
        let visibleBehavior = try parse(arguments: ["windows", "--app", "Terminal", "--visible"])
        guard case .listVisibleWindows = visibleBehavior else {
            return XCTFail("Expected visible-window list behavior.")
        }

        let accessibilityBehavior = try parse(arguments: ["windows", "--app", "Terminal", "--ax"])
        guard case .inspectAccessibility(let command) = accessibilityBehavior else {
            return XCTFail("Expected accessibility window list behavior.")
        }

        guard case .listWindows = command.mode else {
            return XCTFail("Expected accessibility window list mode.")
        }
    }

    func testAXSubcommandActions() throws {
        let treeBehavior = try parse(arguments: [
            "ax",
            "--app", "Terminal",
            "tree",
            "--depth", "2",
        ])

        guard case .inspectAccessibility(let treeCommand) = treeBehavior else {
            return XCTFail("Expected accessibility behavior.")
        }

        guard case .listElements = treeCommand.mode else {
            return XCTFail("Expected tree mode.")
        }

        XCTAssertEqual(treeCommand.treeDepth, 2)

        let getBehavior = try parse(arguments: [
            "ax",
            "--app", "Terminal",
            "get",
            "--path", "0.1",
        ])

        guard case .inspectAccessibility(let getCommand) = getBehavior else {
            return XCTFail("Expected accessibility behavior.")
        }

        guard case .getElement(let selector) = getCommand.mode else {
            return XCTFail("Expected get mode.")
        }

        XCTAssertEqual(selector.path, "0.1")
    }

    func testAXSubcommandRejectsUnknownAction() {
        XCTAssertThrowsError(
            try parse(arguments: ["ax", "--app", "Finder", "tre"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("Unknown `ax` action `tre`"))
        }
    }

    func testMenuAndAsciiSubcommands() throws {
        let pressBehavior = try parse(arguments: [
            "menu",
            "--app", "Drafty",
            "press",
        ])

        guard case .menuBar(let pressCommand) = pressBehavior else {
            return XCTFail("Expected menu-bar press behavior.")
        }

        guard case .pressItem = pressCommand.mode else {
            return XCTFail("Expected menu-bar press mode.")
        }

        let menuBehavior = try parse(arguments: [
            "menu",
            "--app", "Drafty",
            "press-item",
            "Quick Tasks",
            "--menu-bar-index", "0",
        ])

        guard case .menuBar(let command) = menuBehavior else {
            return XCTFail("Expected menu-bar behavior.")
        }

        guard case .pressMenuItem(let selection) = command.mode else {
            return XCTFail("Expected press-item mode.")
        }

        XCTAssertEqual(selection.query, "Quick Tasks")

        let asciiBehavior = try parse(arguments: ["ascii", "/tmp/screenshot.png", "--ocr-only"])
        guard case .asciiArt(let asciiCommand) = asciiBehavior else {
            return XCTFail("Expected ascii behavior.")
        }

        XCTAssertEqual(asciiCommand.imageURL.path, "/tmp/screenshot.png")
        XCTAssertEqual(asciiCommand.outputMode, .ocrOnly)
    }

    func testMenuSubcommandRejectsUnknownAction() {
        XCTAssertThrowsError(
            try parse(arguments: ["menu", "--app", "Finder", "pres"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("Unknown `menu` action `pres`"))
        }
    }

    func testDoctorParsing() throws {
        let subcommandBehavior = try parse(arguments: ["doctor"])
        guard case .doctor = subcommandBehavior else {
            return XCTFail("Expected doctor behavior.")
        }

        let flagBehavior = try parse(arguments: ["--doctor"])
        guard case .doctor = flagBehavior else {
            return XCTFail("Expected doctor behavior.")
        }
    }

    func testDoctorRejectsMixedArguments() {
        XCTAssertThrowsError(
            try parse(arguments: ["doctor", "--app", "Terminal"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("doctor"))
        }

        XCTAssertThrowsError(
            try parse(arguments: ["--doctor", "--app", "Terminal"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--doctor"))
        }
    }

    func testClipboardParsing() throws {
        let readBehavior = try parse(arguments: ["clipboard"])
        guard case .clipboard(let readCommand) = readBehavior else {
            return XCTFail("Expected clipboard behavior.")
        }
        XCTAssertNil(readCommand.setText)

        let setBehavior = try parse(arguments: ["clipboard", "--set", "hello"])
        guard case .clipboard(let setCommand) = setBehavior else {
            return XCTFail("Expected clipboard behavior.")
        }
        XCTAssertEqual(setCommand.setText, "hello")
    }

    func testClipboardParsingRejectsUnexpectedArguments() {
        XCTAssertThrowsError(
            try parse(arguments: ["clipboard", "--bad"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("clipboard"))
        }
    }

    func testRevealParsing() throws {
        let behavior = try parse(arguments: ["reveal", "./README.md"])

        guard case .revealFile(let command) = behavior else {
            return XCTFail("Expected reveal-file behavior.")
        }

        XCTAssertEqual(command.path, "./README.md")
    }

    func testRevealHelpParsing() throws {
        for arguments in [
            ["reveal", "--help"],
            ["reveal", "-h"],
        ] {
            let behavior = try parse(arguments: arguments)
            guard case .showHelpText(let text) = behavior else {
                return XCTFail("Expected reveal help for \(arguments).")
            }

            XCTAssertTrue(text.contains("brrainztools reveal PATH"))
        }
    }

    func testRevealParsingRejectsMissingEmptyOrMultiplePaths() {
        for arguments in [
            ["reveal"],
            ["reveal", ""],
            ["reveal", "one", "two"],
        ] {
            XCTAssertThrowsError(
                try parse(arguments: arguments)
            ) { error in
                XCTAssertTrue(String(describing: error).contains("reveal"))
                XCTAssertTrue(String(describing: error).contains("PATH"))
            }
        }
    }

    func testRevealResolvesRelativePathAndRequestsFinderSelection() throws {
        let expectedURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/usage.md")
            .standardizedFileURL
        var existenceCheckPath: String?
        var revealedURLs: [URL] = []

        let json = try reveal(
            using: RevealCommand(path: "docs/usage.md"),
            fileExists: {
                existenceCheckPath = $0
                return true
            },
            revealURLs: {
                revealedURLs = $0
            }
        )

        XCTAssertEqual(existenceCheckPath, expectedURL.path)
        XCTAssertEqual(revealedURLs, [expectedURL])
        XCTAssertEqual(json, try encodeJSON(RevealResponse(path: expectedURL.path)))
    }

    func testRevealRejectsMissingPathBeforeRequestingFinderSelection() {
        let rawPath = "~/missing-brrainztools-test-file"
        let expectedPath = (rawPath as NSString).expandingTildeInPath
        var existenceCheckPath: String?
        var revealWasRequested = false

        XCTAssertThrowsError(
            try reveal(
                using: RevealCommand(path: rawPath),
                fileExists: {
                    existenceCheckPath = $0
                    return false
                },
                revealURLs: { _ in revealWasRequested = true }
            )
        ) { error in
            guard let error = error as? BrrainzToolsError else {
                return XCTFail("Expected BrrainzToolsError.")
            }

            XCTAssertEqual(error.kind, "pathNotFound")
            XCTAssertEqual(error.exitCode, 66)
            XCTAssertTrue(error.localizedDescription.contains("missing-brrainztools-test-file"))
        }

        XCTAssertEqual(existenceCheckPath, expectedPath)
        XCTAssertFalse(revealWasRequested)
    }

    func testOpenFileParsingUsesDefaultApplication() throws {
        let behavior = try parse(arguments: ["open-file", "./README.md"])

        guard case .openFile(let command) = behavior else {
            return XCTFail("Expected open-file behavior.")
        }

        XCTAssertEqual(command.path, "./README.md")
        XCTAssertNil(command.applicationTarget)
        XCTAssertFalse(command.waitForWindow)
        XCTAssertTrue(command.promptForAccessibility)
        XCTAssertEqual(command.timeout, 5.0, accuracy: 0.001)
    }

    func testOpenFileParsingSupportsTargetedAppAndWait() throws {
        let behavior = try parse(arguments: [
            "--open-file",
            "~/Documents/Review.markreview",
            "--app", "/tmp/MarkReview.app",
            "--wait-window",
            "--no-prompt",
            "--timeout", "2.5",
        ])

        guard case .openFile(let command) = behavior else {
            return XCTFail("Expected open-file behavior.")
        }

        XCTAssertEqual(command.path, "~/Documents/Review.markreview")
        XCTAssertEqual(command.applicationTarget, .path("/tmp/MarkReview.app"))
        XCTAssertTrue(command.waitForWindow)
        XCTAssertFalse(command.promptForAccessibility)
        XCTAssertEqual(command.timeout, 2.5, accuracy: 0.001)
    }

    func testOpenFileHelpParsing() throws {
        for arguments in [
            ["open-file", "--help"],
            ["open-file", "-h"],
            ["--open-file", "--help"],
        ] {
            let behavior = try parse(arguments: arguments)
            guard case .showHelpText(let text) = behavior else {
                return XCTFail("Expected open-file help for \(arguments).")
            }

            XCTAssertTrue(text.contains("brrainztools open-file PATH"))
            XCTAssertTrue(text.contains("--app PATH|BUNDLE_ID"))
        }
    }

    func testOpenFileParsingRejectsIncompleteOrConflictingArguments() {
        for arguments in [
            ["open-file"],
            ["open-file", ""],
            ["open-file", "one", "two"],
            ["open-file", "document.md", "--app"],
            ["open-file", "document.md", "--app", "--wait-window"],
            ["open-file", "document.md", "--app", "One.app", "--app", "Two.app"],
            ["open-file", "document.md", "--no-prompt"],
        ] {
            XCTAssertThrowsError(
                try parse(arguments: arguments)
            ) { error in
                XCTAssertTrue(String(describing: error).contains("open-file"))
            }
        }
    }

    func testOpenFileResolvesPathAndRequestsDocumentHandoff() throws {
        let expectedURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/usage.md")
            .standardizedFileURL
        let target = LaunchTarget.path("/tmp/Test Document App.app")
        var statusPath: String?
        var openedURL: URL?
        var openedTarget: LaunchTarget?

        let json = try openFile(
            using: OpenFileCommand(
                path: "docs/usage.md",
                applicationTarget: target,
                waitForWindow: false,
                promptForAccessibility: true,
                timeout: 5
            ),
            pathStatus: {
                statusPath = $0
                return (true, false)
            },
            openDocument: { url, applicationTarget in
                openedURL = url
                openedTarget = applicationTarget
                return (
                    AutomationApplication(
                        name: "Test Document App",
                        bundleIdentifier: "com.example.document-app",
                        processID: 321
                    ),
                    "applicationBundle"
                )
            }
        )

        XCTAssertEqual(statusPath, expectedURL.path)
        XCTAssertEqual(openedURL, expectedURL)
        XCTAssertEqual(openedTarget, target)

        let data = try XCTUnwrap(json.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["path"] as? String, expectedURL.path)
        XCTAssertEqual(object["applicationTarget"] as? String, "/tmp/Test Document App.app")
        XCTAssertEqual(object["method"] as? String, "applicationBundle")
        XCTAssertEqual(object["waitForWindow"] as? Bool, false)
        let application = try XCTUnwrap(object["application"] as? [String: Any])
        XCTAssertEqual(application["name"] as? String, "Test Document App")
        XCTAssertEqual(application["bundleIdentifier"] as? String, "com.example.document-app")
        XCTAssertEqual(application["processID"] as? Int, 321)
    }

    func testOpenFileRejectsMissingPathOrDirectoryBeforeHandoff() {
        for status in [(false, false), (true, true)] {
            var openWasRequested = false

            XCTAssertThrowsError(
                try openFile(
                    using: OpenFileCommand(
                        path: "missing-or-directory.md",
                        applicationTarget: nil,
                        waitForWindow: false,
                        promptForAccessibility: true,
                        timeout: 5
                    ),
                    pathStatus: { _ in status },
                    openDocument: { _, _ in
                        openWasRequested = true
                        return (
                            AutomationApplication(name: "Unexpected", bundleIdentifier: "", processID: 1),
                            "defaultApplication"
                        )
                    }
                )
            ) { error in
                guard let error = error as? BrrainzToolsError else {
                    return XCTFail("Expected BrrainzToolsError.")
                }

                XCTAssertEqual(error.kind, status.0 ? "openFailed" : "pathNotFound")
                XCTAssertEqual(error.exitCode, status.0 ? 70 : 66)
            }

            XCTAssertFalse(openWasRequested)
        }
    }

    func testActivateApplicationParsing() throws {
        let behavior = try parse(arguments: ["activate", "--app", "Terminal"])

        guard case .activateApplication(let command) = behavior else {
            return XCTFail("Expected activate application behavior.")
        }

        guard case .name(let name) = command.applicationSelector else {
            return XCTFail("Expected name application selector.")
        }

        XCTAssertEqual(name, "Terminal")
    }

    func testActivateApplicationParsingSupportsPID() throws {
        let behavior = try parse(arguments: ["activate", "--pid", "123"])

        guard case .activateApplication(let command) = behavior else {
            return XCTFail("Expected activate application behavior.")
        }

        guard case .processID(let processID) = command.applicationSelector else {
            return XCTFail("Expected pid application selector.")
        }

        XCTAssertEqual(processID, 123)
    }

    func testActivateApplicationRejectsMissingSelector() {
        XCTAssertThrowsError(
            try parse(arguments: ["activate"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("activate"))
            XCTAssertTrue(String(describing: error).contains("--app"))
        }
    }

    func testActivateApplicationRejectsMixedArguments() {
        XCTAssertThrowsError(
            try parse(arguments: ["activate", "--app", "Terminal", "--list-windows"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("activate"))
        }
    }

    func testLaunchApplicationParsingBundleIdentifier() throws {
        let behavior = try parse(arguments: ["launch", "com.apple.TextEdit"])

        guard case .launchApplication(let command) = behavior else {
            return XCTFail("Expected launch application behavior.")
        }

        XCTAssertEqual(command.target, .bundleIdentifier("com.apple.TextEdit"))
        XCTAssertEqual(command.arguments, [])
        XCTAssertFalse(command.waitForWindow)
        XCTAssertTrue(command.promptForAccessibility)
        XCTAssertEqual(command.timeout, 5.0, accuracy: 0.001)
    }

    func testLaunchApplicationParsingPathWaitAndArguments() throws {
        let behavior = try parse(arguments: [
            "launch",
            ".build/debug/MyDebugApp",
            "--wait-window",
            "--timeout", "2.5",
            "--args", "--fixture", "smoke", "--flag",
        ])

        guard case .launchApplication(let command) = behavior else {
            return XCTFail("Expected launch application behavior.")
        }

        XCTAssertEqual(command.target, .path(".build/debug/MyDebugApp"))
        XCTAssertEqual(command.arguments, ["--fixture", "smoke", "--flag"])
        XCTAssertTrue(command.waitForWindow)
        XCTAssertTrue(command.promptForAccessibility)
        XCTAssertEqual(command.timeout, 2.5, accuracy: 0.001)
    }

    func testLaunchApplicationParsingSupportsNoPrompt() throws {
        let behavior = try parse(arguments: [
            "launch",
            "com.apple.TextEdit",
            "--wait-window",
            "--no-prompt",
        ])

        guard case .launchApplication(let command) = behavior else {
            return XCTFail("Expected launch application behavior.")
        }

        XCTAssertTrue(command.waitForWindow)
        XCTAssertFalse(command.promptForAccessibility)
    }

    func testLaunchApplicationRejectsMissingTarget() {
        XCTAssertThrowsError(
            try parse(arguments: ["launch", "--wait-window"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("launch"))
            XCTAssertTrue(String(describing: error).contains("PATH"))
        }
    }

    func testLaunchApplicationRejectsNoPromptWithoutWaitWindow() {
        XCTAssertThrowsError(
            try parse(arguments: ["launch", "com.apple.TextEdit", "--no-prompt"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--no-prompt"))
            XCTAssertTrue(String(describing: error).contains("--wait-window"))
        }
    }

    func testLaunchApplicationRejectsUnexpectedFlagBeforeArgs() {
        XCTAssertThrowsError(
            try parse(arguments: ["launch", "com.apple.TextEdit", "--bad"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("launch"))
        }
    }

    func testQuitApplicationParsing() throws {
        let behavior = try parse(arguments: ["quit", "--app", "Terminal"])

        guard case .quitApplication(let command) = behavior else {
            return XCTFail("Expected quit application behavior.")
        }

        guard case .name(let name) = command.applicationSelector else {
            return XCTFail("Expected name application selector.")
        }

        XCTAssertEqual(name, "Terminal")
        XCTAssertFalse(command.force)
        XCTAssertFalse(command.waitForTermination)
        XCTAssertEqual(command.timeout, 5.0, accuracy: 0.001)
    }

    func testQuitApplicationParsingSupportsForceAndPID() throws {
        let behavior = try parse(arguments: ["quit", "--pid", "123", "--force"])

        guard case .quitApplication(let command) = behavior else {
            return XCTFail("Expected quit application behavior.")
        }

        guard case .processID(let processID) = command.applicationSelector else {
            return XCTFail("Expected pid application selector.")
        }

        XCTAssertEqual(processID, 123)
        XCTAssertTrue(command.force)
        XCTAssertFalse(command.waitForTermination)
    }

    func testQuitApplicationParsingSupportsWaitAndTimeout() throws {
        let behavior = try parse(arguments: [
            "quit",
            "--wait",
            "--app", "Terminal",
            "--timeout", "2.5",
            "--force",
        ])

        guard case .quitApplication(let command) = behavior else {
            return XCTFail("Expected quit application behavior.")
        }

        XCTAssertTrue(command.force)
        XCTAssertTrue(command.waitForTermination)
        XCTAssertEqual(command.timeout, 2.5, accuracy: 0.001)
    }

    func testQuitApplicationRejectsTimeoutWithoutWait() {
        XCTAssertThrowsError(
            try parse(arguments: ["quit", "--app", "Terminal", "--timeout", "2.5"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--timeout"))
            XCTAssertTrue(String(describing: error).contains("--wait"))
        }
    }

    func testQuitApplicationRejectsInvalidWaitTimeout() {
        XCTAssertThrowsError(
            try parse(arguments: ["quit", "--app", "Terminal", "--wait", "--timeout", "never"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--timeout"))
            XCTAssertTrue(String(describing: error).contains("positive"))
        }
    }

    func testQuitApplicationRejectsMissingSelector() {
        XCTAssertThrowsError(
            try parse(arguments: ["quit", "--force"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("quit"))
            XCTAssertTrue(String(describing: error).contains("--app"))
        }
    }

    func testQuitApplicationRejectsMixedArguments() {
        XCTAssertThrowsError(
            try parse(arguments: ["quit", "--app", "Terminal", "--list-windows"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("quit"))
        }
    }

    func testWaitForApplicationTerminationReturnsAfterObservedExit() {
        var currentTime = 0.0
        var checks = 0
        var sleepDurations: [TimeInterval] = []

        let terminated = waitForApplicationTermination(
            timeout: 1,
            pollInterval: 0.05,
            now: { Date(timeIntervalSinceReferenceDate: currentTime) },
            sleep: {
                sleepDurations.append($0)
                currentTime += $0
            },
            isTerminated: {
                checks += 1
                return checks == 3
            }
        )

        XCTAssertTrue(terminated)
        XCTAssertEqual(checks, 3)
        XCTAssertEqual(sleepDurations, [0.05, 0.05])
    }

    func testWaitForApplicationTerminationStopsAtTimeout() {
        var currentTime = 0.0
        var checks = 0
        var sleepDurations: [TimeInterval] = []

        let terminated = waitForApplicationTermination(
            timeout: 0.12,
            pollInterval: 0.05,
            now: { Date(timeIntervalSinceReferenceDate: currentTime) },
            sleep: {
                sleepDurations.append($0)
                currentTime += $0
            },
            isTerminated: {
                checks += 1
                return false
            }
        )

        XCTAssertFalse(terminated)
        XCTAssertEqual(checks, 4)
        XCTAssertEqual(sleepDurations.count, 3)
        XCTAssertEqual(sleepDurations.reduce(0, +), 0.12, accuracy: 0.001)
    }

    func testListDisplaysParsing() throws {
        let behavior = try parse(arguments: ["--list-displays"])

        guard case .listDisplays = behavior else {
            return XCTFail("Expected list displays behavior.")
        }
    }

    func testListDisplaysRejectsMixedArguments() {
        XCTAssertThrowsError(
            try parse(arguments: ["--list-displays", "--app", "Terminal"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--list-displays"))
        }
    }

    func testDisplayCaptureParsingSupportsDisplayID() throws {
        let behavior = try parse(arguments: [
            "--display", "42",
            "--output", "/tmp/display.jpg",
            "--timeout", "1.5",
            "--format", "jpeg",
            "--quality", "0.6",
            "--max-dimension", "800",
            "--with-ocr",
            "--ascii-language", "sv-SE",
        ])

        guard case .capture(let command) = behavior else {
            return XCTFail("Expected capture behavior.")
        }

        XCTAssertNil(command.region)
        XCTAssertNil(command.applicationSelector)
        XCTAssertEqual(command.displaySelection, .displayID(42))
        XCTAssertEqual(command.outputURL.path, "/tmp/display.jpg")
        XCTAssertEqual(command.screenCaptureTimeout, 1.5, accuracy: 0.001)
        XCTAssertEqual(command.imageOutput.format, .jpeg)
        XCTAssertEqual(command.imageOutput.jpegQuality, 0.6, accuracy: 0.001)
        XCTAssertEqual(command.imageOutput.maxDimension, 800)

        let textOutput = try XCTUnwrap(command.textOutput)
        XCTAssertEqual(textOutput.outputMode, .ocrOnly)
        XCTAssertEqual(textOutput.recognitionLanguages, ["sv-SE"])
    }

    func testDisplayCaptureParsingSupportsAllDisplays() throws {
        let behavior = try parse(arguments: ["--all-displays", "--raw"])

        guard case .capture(let command) = behavior else {
            return XCTFail("Expected capture behavior.")
        }

        XCTAssertNil(command.region)
        XCTAssertEqual(command.displaySelection, .allDisplays)
        XCTAssertTrue(command.rawOutput)
    }

    func testDisplayCaptureRejectsMixedModes() {
        XCTAssertThrowsError(
            try parse(arguments: ["--display", "42", "--all-displays"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--display"))
        }

        XCTAssertThrowsError(
            try parse(arguments: ["1", "2", "3", "4", "--display", "42"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("Display capture"))
        }

        XCTAssertThrowsError(
            try parse(arguments: ["--all-displays", "--app", "Terminal"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("Display capture"))
        }

        XCTAssertThrowsError(
            try parse(arguments: ["--display", "42", "--list-windows"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("Display capture"))
        }
    }

    func testPassiveCommandsDoNotSynchronizeAgentSupport() throws {
        XCTAssertFalse(try parse(arguments: []).shouldSynchronizeAgentSupport)
        XCTAssertFalse(try parse(arguments: ["--help"]).shouldSynchronizeAgentSupport)
        XCTAssertFalse(try parse(arguments: ["--version"]).shouldSynchronizeAgentSupport)
        XCTAssertFalse(try parse(arguments: ["doctor"]).shouldSynchronizeAgentSupport)
        XCTAssertFalse(try parse(arguments: ["clipboard"]).shouldSynchronizeAgentSupport)
        XCTAssertFalse(try parse(arguments: ["--list-displays"]).shouldSynchronizeAgentSupport)
    }

    func testOperationalCommandsSynchronizeAgentSupport() throws {
        XCTAssertTrue(try parse(arguments: ["--find-app", "RimWorld"]).shouldSynchronizeAgentSupport)
        XCTAssertTrue(try parse(arguments: ["reveal", "./README.md"]).shouldSynchronizeAgentSupport)
        XCTAssertTrue(try parse(arguments: ["open-file", "./README.md"]).shouldSynchronizeAgentSupport)
        XCTAssertTrue(try parse(arguments: ["activate", "--app", "Terminal"]).shouldSynchronizeAgentSupport)
        XCTAssertTrue(try parse(arguments: ["quit", "--app", "Terminal"]).shouldSynchronizeAgentSupport)
    }

    func testAsciiArtParsing() throws {
        let behavior = try parse(arguments: [
            "--ascii", "/tmp/screenshot.png",
            "--ascii-width", "100",
            "--ascii-max-height", "40",
            "--ascii-invert",
            "--ascii-no-ocr",
        ])

        guard case .asciiArt(let command) = behavior else {
            return XCTFail("Expected ascii-art behavior.")
        }

        XCTAssertEqual(command.imageURL.path, "/tmp/screenshot.png")
        XCTAssertEqual(command.style, .layout)
        XCTAssertEqual(command.width, 100)
        XCTAssertEqual(command.maxHeight, 40)
        XCTAssertTrue(command.invert)
        XCTAssertFalse(command.includeOCR)
        XCTAssertEqual(command.recognitionLanguages, [])
        XCTAssertEqual(command.outputMode, .report)
    }

    func testAsciiArtParsingUsesDefaults() throws {
        let behavior = try parse(arguments: ["--ascii", "/tmp/screenshot.png"])

        guard case .asciiArt(let command) = behavior else {
            return XCTFail("Expected ascii-art behavior.")
        }

        XCTAssertEqual(command.style, .layout)
        XCTAssertEqual(command.width, 160)
        XCTAssertEqual(command.maxHeight, 100)
        XCTAssertFalse(command.invert)
        XCTAssertTrue(command.includeOCR)
        XCTAssertEqual(command.recognitionLanguages, [])
        XCTAssertEqual(command.outputMode, .report)
    }

    func testAsciiArtParsingSupportsOCROnlyMode() throws {
        let behavior = try parse(arguments: [
            "--ascii", "/tmp/screenshot.png",
            "--ocr-only",
        ])

        guard case .asciiArt(let command) = behavior else {
            return XCTFail("Expected ascii-art behavior.")
        }

        XCTAssertEqual(command.outputMode, .ocrOnly)
        XCTAssertTrue(command.includeOCR)
    }

    func testOCROnlyRejectsDisabledOCR() {
        XCTAssertThrowsError(
            try parse(arguments: ["--ascii", "/tmp/screenshot.png", "--ocr-only", "--ascii-no-ocr"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--ocr-only"))
        }
    }

    func testAsciiArtParsingSupportsOCRLanguageList() throws {
        let behavior = try parse(arguments: [
            "--ascii", "/tmp/screenshot.png",
            "--ascii-language", "de-DE, sv-SE",
        ])

        guard case .asciiArt(let command) = behavior else {
            return XCTFail("Expected ascii-art behavior.")
        }

        XCTAssertEqual(command.recognitionLanguages, ["de-DE", "sv-SE"])
    }

    func testAsciiLanguageRejectsEmptyItems() {
        XCTAssertThrowsError(
            try parse(arguments: ["--ascii", "/tmp/screenshot.png", "--ascii-language", "de-DE,"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--ascii-language"))
        }
    }

    func testAsciiArtParsingSupportsToneStyleDefaults() throws {
        let behavior = try parse(arguments: ["--ascii", "/tmp/screenshot.png", "--ascii-style", "tone"])

        guard case .asciiArt(let command) = behavior else {
            return XCTFail("Expected ascii-art behavior.")
        }

        XCTAssertEqual(command.style, .tone)
        XCTAssertEqual(command.width, 120)
        XCTAssertEqual(command.maxHeight, 80)
    }

    func testVisibleWindowCaptureParsing() throws {
        let behavior = try parse(arguments: [
            "--app", "RimWorld",
            "--visible-window",
            "--output", "/tmp/rimworld.png",
            "--timeout", "0.75",
            "--raw",
        ])

        guard case .captureVisibleWindow(let command) = behavior else {
            return XCTFail("Expected visible-window capture behavior.")
        }

        guard case .name(let name) = command.applicationSelector else {
            return XCTFail("Expected name application selector.")
        }

        XCTAssertEqual(name, "RimWorld")
        XCTAssertNil(command.windowSelection)
        XCTAssertEqual(command.outputURL.path, "/tmp/rimworld.png")
        XCTAssertEqual(command.screenCaptureTimeout, 0.75, accuracy: 0.001)
        XCTAssertTrue(command.rawOutput)
    }

    func testRectangleCaptureParsingSupportsRawOutput() throws {
        let behavior = try parse(arguments: [
            "1",
            "2",
            "3",
            "4",
            "--raw",
        ])

        guard case .capture(let command) = behavior else {
            return XCTFail("Expected capture behavior.")
        }

        XCTAssertTrue(command.rawOutput)
    }

    func testRectangleCaptureParsingSupportsWithAscii() throws {
        let behavior = try parse(arguments: [
            "1",
            "2",
            "3",
            "4",
            "--with-ascii",
            "--ascii-width", "80",
            "--ascii-max-height", "40",
            "--ascii-language", "sv-SE",
            "--ascii-no-ocr",
        ])

        guard case .capture(let command) = behavior else {
            return XCTFail("Expected capture behavior.")
        }

        let textOutput = try XCTUnwrap(command.textOutput)
        XCTAssertEqual(textOutput.outputMode, .report)
        XCTAssertEqual(textOutput.width, 80)
        XCTAssertEqual(textOutput.maxHeight, 40)
        XCTAssertEqual(textOutput.recognitionLanguages, ["sv-SE"])
        XCTAssertFalse(textOutput.includeOCR)
    }

    func testRectangleCaptureParsingSupportsWithOCR() throws {
        let behavior = try parse(arguments: [
            "1",
            "2",
            "3",
            "4",
            "--with-ocr",
            "--ascii-language", "de-DE",
        ])

        guard case .capture(let command) = behavior else {
            return XCTFail("Expected capture behavior.")
        }

        let textOutput = try XCTUnwrap(command.textOutput)
        XCTAssertEqual(textOutput.outputMode, .ocrOnly)
        XCTAssertEqual(textOutput.recognitionLanguages, ["de-DE"])
    }

    func testRectangleCaptureParsingSupportsImageOutputOptions() throws {
        let behavior = try parse(arguments: [
            "1",
            "2",
            "3",
            "4",
            "--format", "jpeg",
            "--quality", "0.7",
            "--max-dimension", "1200",
        ])

        guard case .capture(let command) = behavior else {
            return XCTFail("Expected capture behavior.")
        }

        XCTAssertEqual(command.imageOutput.format, .jpeg)
        XCTAssertEqual(command.imageOutput.jpegQuality, 0.7, accuracy: 0.001)
        XCTAssertEqual(command.imageOutput.maxDimension, 1200)
        XCTAssertEqual(command.outputURL.pathExtension, "jpg")
    }

    func testImageOutputOptionsRejectNonCaptureModesAndInvalidQuality() {
        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--list-windows", "--format", "jpeg"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--format"))
        }

        XCTAssertThrowsError(
            try parse(arguments: ["1", "2", "3", "4", "--quality", "0.7"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--quality"))
        }

        XCTAssertThrowsError(
            try parse(arguments: ["1", "2", "3", "4", "--format", "jpeg", "--quality", "1.5"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--quality"))
        }
    }

    func testRawOutputRejectsStructuredModes() {
        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--list-windows", "--raw"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--raw"))
        }
    }

    func testCaptureTextOptionsRejectRawAndNonCaptureModes() {
        XCTAssertThrowsError(
            try parse(arguments: ["1", "2", "3", "4", "--with-ascii", "--raw"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--raw"))
        }

        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--with-ascii"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--with-ascii"))
        }
    }

    func testWithOCRRejectsRenderOnlyAsciiOptions() {
        XCTAssertThrowsError(
            try parse(arguments: ["1", "2", "3", "4", "--with-ocr", "--ascii-width", "80"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--with-ocr"))
        }
    }

    func testExplicitPIDParsing() throws {
        let behavior = try parse(arguments: [
            "--pid", "12345",
            "--list-windows",
        ])

        guard case .listWindows(let command) = behavior else {
            return XCTFail("Expected list-windows behavior.")
        }

        guard case .processID(let processID) = command.applicationSelector else {
            return XCTFail("Expected pid application selector.")
        }

        XCTAssertEqual(processID, 12345)
    }

    func testAppNameParsingForNumericNames() throws {
        let behavior = try parse(arguments: [
            "--app-name", "2048",
            "--list-windows",
        ])

        guard case .listWindows(let command) = behavior else {
            return XCTFail("Expected list-windows behavior.")
        }

        guard case .name(let name) = command.applicationSelector else {
            return XCTFail("Expected name application selector.")
        }

        XCTAssertEqual(name, "2048")
    }

    func testNumericAppParsingKeepsPIDCompatibility() throws {
        let behavior = try parse(arguments: [
            "--app", "2048",
            "--list-windows",
        ])

        guard case .listWindows(let command) = behavior else {
            return XCTFail("Expected list-windows behavior.")
        }

        guard case .processID(let processID) = command.applicationSelector else {
            return XCTFail("Expected pid application selector.")
        }

        XCTAssertEqual(processID, 2048)
    }

    func testAppSelectorParsingRejectsMixedSelectors() {
        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--pid", "12345"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--app"))
            XCTAssertTrue(String(describing: error).contains("--pid"))
        }
    }

    func testPIDParsingRejectsNonPositiveValues() {
        XCTAssertThrowsError(
            try parse(arguments: ["--pid", "0", "--list-windows"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--pid"))
        }
    }

    func testApplicationSearchScoreRanksExactPathStemAndContainsMatches() {
        let cases: [(texts: [String], query: String, score: Int?)] = [
            (["Terminal"], "terminal", 0),
            (["/Applications/Utilities/Terminal.app"], "Terminal", 1),
            (["com.apple.Terminal"], "apple.term", 10),
            (["Terminal", "/Applications/Utilities/Terminal.app"], "Terminal", 0),
            (["Terminal"], "Safari", nil),
            (["Terminal"], "  ", nil),
        ]

        for testCase in cases {
            XCTAssertEqual(
                applicationSearchScore(for: testCase.texts, query: testCase.query),
                testCase.score,
                "query: \(testCase.query), texts: \(testCase.texts)"
            )
        }
    }

    func testWindowlessApplicationMessageIncludesRecoveryHintsAndBundleWhenAvailable() {
        let message = windowlessApplicationMessage(
            name: "Drafty",
            bundleIdentifier: "com.example.Drafty",
            processID: -12345,
            windowKind: "visible",
            modeDescription: "`--visible-window` only targets visible app windows."
        )

        XCTAssertTrue(message.contains("`Drafty` was found (pid -12345, com.example.Drafty)"))
        XCTAssertTrue(message.contains("macOS exposed no visible windows"))
        XCTAssertTrue(message.contains("`--visible-window` only targets visible app windows."))
        XCTAssertTrue(message.contains("Use `--list-menu-bar-items` and `--capture-menu`"))
        XCTAssertTrue(message.contains("rectangle capture (`brrainztools X Y WIDTH HEIGHT`)"))
    }

    func testWindowlessApplicationMessageOmitsEmptyBundleIdentifier() {
        let message = windowlessApplicationMessage(
            name: "Untitled",
            bundleIdentifier: "",
            processID: -12345,
            windowKind: "accessibility app",
            modeDescription: "Accessibility modes operate inside app windows."
        )

        XCTAssertTrue(message.contains("`Untitled` was found (pid -12345)"))
        XCTAssertFalse(message.contains("pid -12345, )"))
    }

    func testScreenCaptureTimeoutParsing() throws {
        let behavior = try parse(arguments: [
            "--app", "Terminal",
            "--timeout", "0.25",
        ])

        guard case .listWindows(let command) = behavior else {
            return XCTFail("Expected list-windows behavior.")
        }

        XCTAssertEqual(command.screenCaptureTimeout, 0.25, accuracy: 0.001)
    }

    func testAccessibilityWindowListParsing() throws {
        let behavior = try parse(arguments: [
            "--app", "Terminal",
            "--list-accessibility-windows",
        ])

        guard case .inspectAccessibility(let command) = behavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        guard case .name(let name) = command.applicationSelector else {
            return XCTFail("Expected name application selector.")
        }

        guard case .listWindows = command.mode else {
            return XCTFail("Expected accessibility window list mode.")
        }

        XCTAssertEqual(name, "Terminal")
        XCTAssertNil(command.windowSelection)
        XCTAssertTrue(command.promptForAccessibility)
    }

    func testAccessibilityWindowListAliasParsing() throws {
        let behavior = try parse(arguments: [
            "--app", "Terminal",
            "--list-ax-windows",
        ])

        guard case .inspectAccessibility(let command) = behavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        guard case .listWindows = command.mode else {
            return XCTFail("Expected accessibility window list mode.")
        }
    }

    func testNoPromptParsingSupportsAccessibilityAndMenuBarModes() throws {
        let accessibilityBehavior = try parse(arguments: [
            "--app", "Terminal",
            "--list-elements",
            "--no-prompt",
        ])

        guard case .inspectAccessibility(let accessibilityCommand) = accessibilityBehavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        XCTAssertFalse(accessibilityCommand.promptForAccessibility)

        let menuBarBehavior = try parse(arguments: [
            "--app", "Drafty",
            "--list-menu-bar-items",
            "--no-prompt",
        ])

        guard case .menuBar(let menuBarCommand) = menuBarBehavior else {
            return XCTFail("Expected menu-bar behavior.")
        }

        XCTAssertFalse(menuBarCommand.promptForAccessibility)
    }

    func testNoPromptRejectsNonAccessibilityModes() {
        XCTAssertThrowsError(
            try parse(arguments: ["1", "2", "3", "4", "--no-prompt"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--no-prompt"))
        }

        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--list-windows", "--no-prompt"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--no-prompt"))
        }
    }

    func testAccessibilityElementListParsingUsesTreeDefaults() throws {
        let behavior = try parse(arguments: [
            "--app", "Terminal",
            "--list-elements",
        ])

        guard case .inspectAccessibility(let command) = behavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        guard case .listElements = command.mode else {
            return XCTFail("Expected element list mode.")
        }

        XCTAssertEqual(command.treeDepth, 4)
        XCTAssertEqual(command.treeChildLimit, 25)
        XCTAssertEqual(command.treeRoleFilter, [])
        XCTAssertFalse(command.treeInteractiveOnly)
        XCTAssertFalse(command.treeFlat)
    }

    func testAccessibilityElementListParsingSupportsTreeLimits() throws {
        let behavior = try parse(arguments: [
            "--app", "Terminal",
            "--list-elements",
            "--depth", "2",
            "--max-children", "10",
            "--roles", "AXButton, AXTextField",
            "--interactive",
            "--flat",
        ])

        guard case .inspectAccessibility(let command) = behavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        guard case .listElements = command.mode else {
            return XCTFail("Expected element list mode.")
        }

        XCTAssertEqual(command.treeDepth, 2)
        XCTAssertEqual(command.treeChildLimit, 10)
        XCTAssertEqual(command.treeRoleFilter, ["AXButton", "AXTextField"])
        XCTAssertTrue(command.treeInteractiveOnly)
        XCTAssertTrue(command.treeFlat)
    }

    func testAccessibilityGetElementParsing() throws {
        let behavior = try parse(arguments: [
            "--app", "Terminal",
            "--get",
            "--role", "AXTextField",
            "--title", "Name",
            "--identifier", "name-field",
        ])

        guard case .inspectAccessibility(let command) = behavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        guard case .getElement(let selector) = command.mode else {
            return XCTFail("Expected accessibility get mode.")
        }

        XCTAssertEqual(selector.role, "AXTextField")
        XCTAssertEqual(selector.title, "Name")
        XCTAssertEqual(selector.identifier, "name-field")
        XCTAssertNil(selector.path)
        XCTAssertNil(selector.subrole)
        XCTAssertNil(selector.elementDescription)
    }

    func testAccessibilityGetElementParsingSupportsPathSelector() throws {
        let behavior = try parse(arguments: [
            "--app", "Terminal",
            "--get",
            "--path", "0.3.1",
        ])

        guard case .inspectAccessibility(let command) = behavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        guard case .getElement(let selector) = command.mode else {
            return XCTFail("Expected accessibility get mode.")
        }

        XCTAssertEqual(selector.path, "0.3.1")
    }

    func testAccessibilityPathSelectorRejectsInvalidOrMixedSelectors() {
        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--get", "--path", "1.2"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--path"))
            XCTAssertTrue(String(describing: error).contains("0"))
        }

        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--get", "--path", "0.1", "--role", "AXButton"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--path"))
            XCTAssertTrue(String(describing: error).contains("--role"))
        }
    }

    func testAccessibilityGetElementAliasParsing() throws {
        let behavior = try parse(arguments: [
            "--app", "Terminal",
            "--frontmost-window",
            "--get-element",
            "--description", "Search field",
        ])

        guard case .inspectAccessibility(let command) = behavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        guard case .getElement(let selector) = command.mode else {
            return XCTFail("Expected accessibility get mode.")
        }

        guard case .frontmost = command.windowSelection else {
            return XCTFail("Expected frontmost window selection.")
        }

        XCTAssertEqual(selector.elementDescription, "Search field")
    }

    func testAccessibilityWaitForElementParsingUsesTimeout() throws {
        let behavior = try parse(arguments: [
            "--app", "Terminal",
            "--wait-for-element",
            "--role", "AXButton",
            "--title", "Done",
            "--timeout", "2.5",
        ])

        guard case .inspectAccessibility(let command) = behavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        guard case .waitForElement(let selector) = command.mode else {
            return XCTFail("Expected accessibility wait-for-element mode.")
        }

        XCTAssertEqual(command.timeout, 2.5, accuracy: 0.001)
        XCTAssertEqual(selector.role, "AXButton")
        XCTAssertEqual(selector.title, "Done")
    }

    func testAccessibilityWaitForWindowParsingUsesTimeout() throws {
        let behavior = try parse(arguments: [
            "--app", "Terminal",
            "--wait-for-window", "server logs",
            "--timeout", "3.25",
        ])

        guard case .inspectAccessibility(let command) = behavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        guard case .waitForWindow(let title) = command.mode else {
            return XCTFail("Expected accessibility wait-for-window mode.")
        }

        XCTAssertEqual(command.timeout, 3.25, accuracy: 0.001)
        XCTAssertEqual(title, "server logs")
        XCTAssertNil(command.windowSelection)
    }

    func testAccessibilityWaitForWindowRejectsEmptyTitle() {
        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--wait-for-window", "  "])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--wait-for-window"))
        }
    }

    func testAccessibilityWaitForWindowRejectsMixedAccessibilityMode() {
        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--wait-for-window", "server logs", "--press-at", "1,1"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--wait-for-window"))
            XCTAssertTrue(String(describing: error).contains("--press-at"))
        }
    }

    func testAccessibilityWaitForWindowRejectsSeparateWindowSelection() {
        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--window-name", "server logs", "--wait-for-window", "server logs"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--wait-for-window"))
            XCTAssertTrue(String(describing: error).contains("--window-name"))
        }
    }

    func testAccessibilityWaitForElementRequiresSelector() {
        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--wait-for-element"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--wait-for-element"))
        }
    }

    func testAccessibilityWaitForElementRejectsMixedAccessibilityMode() {
        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--wait-for-element", "--role", "AXButton", "--press-at", "1,1"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--wait-for-element"))
            XCTAssertTrue(String(describing: error).contains("--press-at"))
        }
    }

    func testAccessibilitySetValueParsing() throws {
        let behavior = try parse(arguments: [
            "--app", "Terminal",
            "--set-value", "Andreas",
            "--role", "AXTextField",
            "--title", "Name",
        ])

        guard case .inspectAccessibility(let command) = behavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        guard case .setValue(let selector, let value) = command.mode else {
            return XCTFail("Expected accessibility set-value mode.")
        }

        XCTAssertEqual(value, "Andreas")
        XCTAssertEqual(selector.role, "AXTextField")
        XCTAssertEqual(selector.title, "Name")
    }

    func testAccessibilitySetValuePreservesEmptyString() throws {
        let behavior = try parse(arguments: [
            "--app", "Terminal",
            "--set-value", "",
            "--role", "AXTextField",
        ])

        guard case .inspectAccessibility(let command) = behavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        guard case .setValue(let selector, let value) = command.mode else {
            return XCTFail("Expected accessibility set-value mode.")
        }

        XCTAssertEqual(value, "")
        XCTAssertEqual(selector.role, "AXTextField")
    }

    func testAccessibilitySetValueRequiresSelector() {
        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--set-value", "Andreas"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--set-value"))
        }
    }

    func testAccessibilitySetValueRejectsMixedAccessibilityMode() {
        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--set-value", "Andreas", "--role", "AXTextField", "--get"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--set-value"))
            XCTAssertTrue(String(describing: error).contains("--get"))
        }
    }

    func testAccessibilityTypeTextParsing() throws {
        let behavior = try parse(arguments: [
            "--app", "Terminal",
            "--type", "hello",
        ])

        guard case .inspectAccessibility(let command) = behavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        guard case .typeText(let text) = command.mode else {
            return XCTFail("Expected type text mode.")
        }

        XCTAssertEqual(text, "hello")
    }

    func testAccessibilityKeyChordParsing() throws {
        let behavior = try parse(arguments: [
            "--app", "Terminal",
            "--key", "cmd+shift+s",
        ])

        guard case .inspectAccessibility(let command) = behavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        guard case .keyChord(let chord) = command.mode else {
            return XCTFail("Expected key chord mode.")
        }

        XCTAssertEqual(chord.rawValue, "cmd+shift+s")
        XCTAssertEqual(chord.keyName, "s")
        XCTAssertEqual(chord.keyCode, 1)
        XCTAssertEqual(chord.modifiers, [.command, .shift])
    }

    func testAccessibilityKeyChordRejectsUnsupportedKey() {
        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--key", "cmd+notakey"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--key"))
            XCTAssertTrue(String(describing: error).contains("notakey"))
        }
    }

    func testAccessibilityKeyboardInputRejectsMixedModesAndWindowSelection() {
        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--type", "hello", "--key", "return"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--type"))
            XCTAssertTrue(String(describing: error).contains("--key"))
        }

        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--window-name", "server logs", "--type", "hello"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--type"))
            XCTAssertTrue(String(describing: error).contains("--window-name"))
        }
    }

    func testAccessibilityMouseClickParsing() throws {
        let behavior = try parse(arguments: [
            "--app", "Terminal",
            "--click", "12,34",
            "--right",
            "--double",
        ])

        guard case .inspectAccessibility(let command) = behavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        guard case .click(let click) = command.mode else {
            return XCTFail("Expected mouse click mode.")
        }

        XCTAssertEqual(click.point.x, 12)
        XCTAssertEqual(click.point.y, 34)
        XCTAssertEqual(click.button, .right)
        XCTAssertEqual(click.clickCount, 2)
    }

    func testAccessibilityMouseDragAndScrollParsing() throws {
        let dragBehavior = try parse(arguments: [
            "--app", "Terminal",
            "--drag", "10,20,30,40",
        ])

        guard case .inspectAccessibility(let dragCommand) = dragBehavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        guard case .drag(let drag) = dragCommand.mode else {
            return XCTFail("Expected mouse drag mode.")
        }

        XCTAssertEqual(drag.start.x, 10)
        XCTAssertEqual(drag.start.y, 20)
        XCTAssertEqual(drag.end.x, 30)
        XCTAssertEqual(drag.end.y, 40)

        let scrollBehavior = try parse(arguments: [
            "--app", "Terminal",
            "--scroll", "-5,12",
        ])

        guard case .inspectAccessibility(let scrollCommand) = scrollBehavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        guard case .scroll(let delta, let selector) = scrollCommand.mode else {
            return XCTFail("Expected mouse scroll mode.")
        }

        XCTAssertEqual(delta.x, -5)
        XCTAssertEqual(delta.y, 12)
        XCTAssertNil(selector)
    }

    func testAccessibilityScrollParsingSupportsElementSelectors() throws {
        let pathBehavior = try parse(arguments: [
            "ax",
            "--app", "Terminal",
            "scroll", "0,-240",
            "--path", "0.3.1",
        ])

        guard case .inspectAccessibility(let pathCommand) = pathBehavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        guard case .scroll(let pathDelta, let pathSelector?) = pathCommand.mode else {
            return XCTFail("Expected targeted mouse scroll mode.")
        }

        XCTAssertEqual(pathDelta.x, 0)
        XCTAssertEqual(pathDelta.y, -240)
        XCTAssertEqual(pathSelector.path, "0.3.1")
        XCTAssertNil(pathSelector.role)

        let roleBehavior = try parse(arguments: [
            "--app", "Terminal",
            "--scroll", "0,120",
            "--role", "AXScrollArea",
        ])

        guard case .inspectAccessibility(let roleCommand) = roleBehavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        guard case .scroll(_, let roleSelector?) = roleCommand.mode else {
            return XCTFail("Expected selector-targeted mouse scroll mode.")
        }

        XCTAssertNil(roleSelector.path)
        XCTAssertEqual(roleSelector.role, "AXScrollArea")
    }

    func testAccessibilityMouseActionsRejectInvalidCombinations() {
        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--right"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--right"))
            XCTAssertTrue(String(describing: error).contains("--click"))
        }

        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--click", "1,2", "--drag", "1,2,3,4"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--click"))
            XCTAssertTrue(String(describing: error).contains("--drag"))
        }

        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--scroll", "0,0"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--scroll"))
            XCTAssertTrue(String(describing: error).contains("non-zero"))
        }
    }

    func testAccessibilityGetElementRequiresSelector() {
        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--get"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--get"))
        }
    }

    func testAccessibilitySelectorFieldsRequireGetOrPressMode() {
        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--title", "Done"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--get"))
            XCTAssertTrue(String(describing: error).contains("--wait-for-element"))
            XCTAssertTrue(String(describing: error).contains("--set-value"))
            XCTAssertTrue(String(describing: error).contains("--scroll"))
            XCTAssertTrue(String(describing: error).contains("--press"))
        }
    }

    func testVisibleCenterPointClipsTargetToSelectedWindow() {
        let window = CGRect(x: 100, y: 200, width: 300, height: 400)

        XCTAssertEqual(
            visibleCenterPoint(
                of: CGRect(x: 150, y: 250, width: 100, height: 80),
                within: window
            ),
            CGPoint(x: 200, y: 290)
        )
        XCTAssertEqual(
            visibleCenterPoint(
                of: CGRect(x: 350, y: 550, width: 100, height: 100),
                within: window
            ),
            CGPoint(x: 375, y: 575)
        )
        XCTAssertNil(
            visibleCenterPoint(
                of: CGRect(x: 0, y: 0, width: 50, height: 50),
                within: window
            )
        )
        XCTAssertNil(
            visibleCenterPoint(
                of: CGRect(x: 150, y: 250, width: 0, height: 80),
                within: window
            )
        )
    }

    func testAccessibilityGetElementRejectsMixedAccessibilityMode() {
        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--get", "--role", "AXButton", "--press-at", "1,1"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--get"))
            XCTAssertTrue(String(describing: error).contains("--press-at"))
        }
    }

    func testAccessibilityTreeLimitOptionsRequireElementListMode() {
        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--depth", "2", "--interactive"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--list-elements"))
            XCTAssertTrue(String(describing: error).contains("--interactive"))
        }
    }

    func testAccessibilityTreeLimitOptionsRejectOutOfRangeValues() {
        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--list-elements", "--depth", "13"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--depth"))
        }

        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--list-elements", "--max-children", "0"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--max-children"))
        }

        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--list-elements", "--roles", "AXButton,"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--roles"))
        }
    }

    func testRaiseWindowParsingWithIndex() throws {
        let behavior = try parse(arguments: [
            "--app", "Terminal",
            "--window-index", "2",
            "--raise-window",
        ])

        guard case .inspectAccessibility(let command) = behavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        guard case .index(let index) = command.windowSelection else {
            return XCTFail("Expected window index selection.")
        }

        guard case .raiseWindow = command.mode else {
            return XCTFail("Expected raise-window mode.")
        }

        XCTAssertEqual(index, 2)
    }

    func testRaiseWindowAliasParsingWithName() throws {
        let behavior = try parse(arguments: [
            "--app", "Terminal",
            "--window-name", "server logs",
            "--raise",
        ])

        guard case .inspectAccessibility(let command) = behavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        guard case .name(let name) = command.windowSelection else {
            return XCTFail("Expected window-name selection.")
        }

        guard case .raiseWindow = command.mode else {
            return XCTFail("Expected raise-window mode.")
        }

        XCTAssertEqual(name, "server logs")
    }

    func testCloseWindowParsingWithName() throws {
        let behavior = try parse(arguments: [
            "--app", "Terminal",
            "--window-name", "server logs",
            "--close-window",
        ])

        guard case .inspectAccessibility(let command) = behavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        guard case .name(let name) = command.windowSelection else {
            return XCTFail("Expected window-name selection.")
        }

        guard case .closeWindow = command.mode else {
            return XCTFail("Expected close-window mode.")
        }

        XCTAssertEqual(name, "server logs")
    }

    func testCloseWindowRejectsMixedAccessibilityMode() {
        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--close-window", "--raise-window"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--close-window"))
            XCTAssertTrue(String(describing: error).contains("--raise-window"))
        }
    }

    func testMinimizeWindowParsingWithIndex() throws {
        let behavior = try parse(arguments: [
            "--app", "Terminal",
            "--window-index", "1",
            "--minimize-window",
        ])

        guard case .inspectAccessibility(let command) = behavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        guard case .index(let index) = command.windowSelection else {
            return XCTFail("Expected window-index selection.")
        }

        guard case .minimizeWindow = command.mode else {
            return XCTFail("Expected minimize-window mode.")
        }

        XCTAssertEqual(index, 1)
    }

    func testMinimizeWindowRejectsMixedAccessibilityMode() {
        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--minimize-window", "--close-window"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--minimize-window"))
            XCTAssertTrue(String(describing: error).contains("--close-window"))
        }
    }

    func testMoveWindowParsingAllowsNegativeCoordinates() throws {
        let behavior = try parse(arguments: [
            "--app", "Terminal",
            "--window-name", "server logs",
            "--move-window", "-120,80",
        ])

        guard case .inspectAccessibility(let command) = behavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        guard case .moveWindow(let position) = command.mode else {
            return XCTFail("Expected move-window mode.")
        }

        XCTAssertEqual(position.x, -120)
        XCTAssertEqual(position.y, 80)
    }

    func testResizeWindowParsing() throws {
        let behavior = try parse(arguments: [
            "--app", "Terminal",
            "--window-index", "1",
            "--resize-window", "900,600",
        ])

        guard case .inspectAccessibility(let command) = behavior else {
            return XCTFail("Expected accessibility inspection behavior.")
        }

        guard case .resizeWindow(let size) = command.mode else {
            return XCTFail("Expected resize-window mode.")
        }

        XCTAssertEqual(size.width, 900)
        XCTAssertEqual(size.height, 600)
    }

    func testResizeWindowRejectsNonPositiveDimensions() {
        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--resize-window", "900,0"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--resize-window"))
        }
    }

    func testMoveAndResizeWindowRejectMixedAccessibilityMode() {
        XCTAssertThrowsError(
            try parse(arguments: ["--app", "Terminal", "--move-window", "10,20", "--resize-window", "900,600"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--move-window"))
            XCTAssertTrue(String(describing: error).contains("--resize-window"))
        }
    }

    func testAsciiArtRejectsMixedModes() {
        XCTAssertThrowsError(
            try parse(arguments: ["--ascii", "/tmp/screenshot.png", "--app", "Terminal"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--ascii"))
        }
    }

    func testAsciiArtRejectsInvalidDimensions() {
        XCTAssertThrowsError(
            try parse(arguments: ["--ascii", "/tmp/screenshot.png", "--ascii-width", "15"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--ascii-width"))
        }

        XCTAssertThrowsError(
            try parse(arguments: ["--ascii", "/tmp/screenshot.png", "--ascii-max-height", "7"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--ascii-max-height"))
        }
    }

    func testAsciiArtRejectsInvalidStyle() {
        XCTAssertThrowsError(
            try parse(arguments: ["--ascii", "/tmp/screenshot.png", "--ascii-style", "photo"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--ascii-style"))
        }
    }

    func testAsciiArtOptionsRequireAsciiMode() {
        XCTAssertThrowsError(
            try parse(arguments: ["--ascii-width", "100"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--ascii"))
        }

        XCTAssertThrowsError(
            try parse(arguments: ["--ascii-language", "sv-SE"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--ascii"))
        }

        XCTAssertThrowsError(
            try parse(arguments: ["--ocr-only"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--ascii"))
        }
    }

    func testPressMenuItemParsing() throws {
        let behavior = try parse(arguments: [
            "--app", "Drafty",
            "--menu-bar-index", "0",
            "--press-menu-item", "Quick Tasks",
        ])

        guard case .menuBar(let command) = behavior else {
            return XCTFail("Expected menu-bar behavior.")
        }

        guard case .name(let name) = command.applicationSelector else {
            return XCTFail("Expected name application selector.")
        }

        guard case .index(let index) = command.selection else {
            return XCTFail("Expected menu-bar index selection.")
        }

        guard case .pressMenuItem(let selection) = command.mode else {
            return XCTFail("Expected child menu item press mode.")
        }

        XCTAssertEqual(name, "Drafty")
        XCTAssertEqual(index, 0)
        XCTAssertEqual(selection.query, "Quick Tasks")
        XCTAssertTrue(command.promptForAccessibility)
        XCTAssertNil(command.outputURL)
    }

    func testPressMenuItemRejectsOutput() {
        XCTAssertThrowsError(
            try parse(arguments: [
                "--app", "Drafty",
                "--menu-bar-index", "0",
                "--press-menu-item", "Quick Tasks",
                "--output", "/tmp/menu.png",
            ])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--press-menu-item"))
        }
    }

    func testAccessibilityWindowListRejectsWindowSelection() {
        XCTAssertThrowsError(
            try parse(arguments: [
                "--app", "Terminal",
                "--window-index", "0",
                "--list-accessibility-windows",
            ])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--list-accessibility-windows"))
        }
    }

    func testRaiseWindowRejectsOutput() {
        XCTAssertThrowsError(
            try parse(arguments: [
                "--app", "Terminal",
                "--window-index", "0",
                "--raise-window",
                "--output", "/tmp/window.png",
            ])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("Accessibility inspection and actions"))
        }
    }

    func testFindAppRejectsMixedModes() {
        XCTAssertThrowsError(
            try parse(arguments: ["--find-app", "RimWorld", "--app", "Terminal"])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("--find-app"))
        }
    }

    func testScreenRegionCapturePreflightsBeforeRunningDisplayCapture() async throws {
        let outputURL = URL(fileURLWithPath: "/tmp/brrainztools-unit-test.png")
        var events: [String] = []

        try await captureScreenRegion(
            region: CaptureRegion(x: 1, y: 2, width: 3, height: 4),
            outputURL: outputURL,
            ensureAccess: {
                events.append("preflight")
            },
            runCapture: { region, url in
                events.append("capture")
                XCTAssertEqual(region.rectangleArgument, "1,2,3,4")
                XCTAssertEqual(url, outputURL)
            },
            fileExists: { path in
                events.append("file-exists")
                XCTAssertEqual(path, outputURL.path)
                return true
            }
        )

        XCTAssertEqual(events, ["preflight", "capture", "file-exists"])
    }

    func testScreenRegionCaptureDoesNotRunDisplayCaptureWhenPreflightFails() async {
        let outputURL = URL(fileURLWithPath: "/tmp/brrainztools-unit-test.png")
        var events: [String] = []

        await XCTAssertThrowsErrorAsync({
            try await captureScreenRegion(
                region: CaptureRegion(x: 1, y: 2, width: 3, height: 4),
                outputURL: outputURL,
                ensureAccess: {
                    events.append("preflight")
                    throw BrrainzToolsError.capturePermissionDenied
                },
                runCapture: { _, _ in
                    XCTFail("display capture should not run after preflight failure.")
                },
                fileExists: { _ in
                    XCTFail("capture output should not be checked after preflight failure.")
                    return false
                }
            )
        }) { error in
            guard case BrrainzToolsError.capturePermissionDenied = error else {
                return XCTFail("Expected capturePermissionDenied, got \(error).")
            }
        }

        XCTAssertEqual(events, ["preflight"])
    }

    func testEncodeJSONUsesCompactSortedKeys() throws {
        let json = try encodeJSON(
            JSONFixture(
                z: "last",
                a: "first",
                nested: JSONNestedFixture(b: 2, a: 1)
            )
        )

        XCTAssertEqual(json, #"{"a":"first","nested":{"a":1,"b":2},"z":"last"}"#)
        XCTAssertFalse(json.contains("\n"))
    }

    func testSuccessEnvelopeEncodingWrapsModePayloads() throws {
        XCTAssertEqual(
            try dataEnvelopeJSON(mode: "doctor", dataJSON: #"{"screenRecording":true}"#, version: "1.2.3"),
            #"{"data":{"screenRecording":true},"mode":"doctor","ok":true,"version":"1.2.3"}"#
        )

        XCTAssertEqual(
            try outputEnvelopeJSON(mode: "capture", output: "/tmp/region.png", version: "1.2.3"),
            #"{"mode":"capture","ok":true,"output":"/tmp/region.png","version":"1.2.3"}"#
        )

        XCTAssertEqual(
            try reportEnvelopeJSON(mode: "ascii", report: "layout\ntext", version: "1.2.3"),
            #"{"mode":"ascii","ok":true,"report":"layout\ntext","version":"1.2.3"}"#
        )

        XCTAssertEqual(
            try outputReportEnvelopeJSON(mode: "capture", output: "/tmp/region.png", report: "image\nreport", version: "1.2.3"),
            #"{"mode":"capture","ok":true,"output":"/tmp/region.png","report":"image\nreport","version":"1.2.3"}"#
        )

        XCTAssertEqual(
            try outputDataEnvelopeJSON(mode: "capture", output: "/tmp/region.png", dataJSON: #"{"blocks":[]}"#, version: "1.2.3"),
            #"{"data":{"blocks":[]},"mode":"capture","ok":true,"output":"/tmp/region.png","version":"1.2.3"}"#
        )
    }

    func testErrorEnvelopeEncodingIncludesKindMessageAndExitCode() throws {
        XCTAssertEqual(
            try errorEnvelopeJSON(error: .ambiguousWindow("Choose one."), version: "1.2.3"),
            #"{"error":{"exitCode":65,"kind":"ambiguousWindow","message":"Choose one."},"ok":false,"version":"1.2.3"}"#
        )
    }

    func testBrrainzToolsErrorExitCodesDistinguishActionableFailureFamilies() {
        let expectations: [(BrrainzToolsError, Int32)] = [
            (.invalidArguments("bad flag"), 64),
            (.invalidInteger(flag: "--width", value: "wide"), 64),
            (.invalidRegion("bad rectangle"), 64),
            (.ambiguousApplication("two apps"), 65),
            (.ambiguousWindow("two windows"), 65),
            (.applicationNotFound("missing app"), 66),
            (.windowNotFound("missing window"), 66),
            (.pathNotFound("missing path"), 66),
            (.capturePermissionDenied, 69),
            (.accessibilityPermissionDenied, 69),
            (.openFailed("open failed"), 70),
            (.launchFailed("launch failed"), 70),
            (.captureFailed("capture failed"), 70),
            (.accessibilityQueryFailed("query failed"), 70),
            (.encodeFailed("encoding failed"), 70),
            (.operationTimedOut("too slow"), 75),
        ]

        for (error, expectedExitCode) in expectations {
            XCTAssertEqual(error.exitCode, expectedExitCode, String(describing: error))
        }
    }

    func testTextRecognitionRequestUsesExplicitLanguagesOnlyWhenProvided() {
        var requestWithDefaultLanguages = RecognizeTextRequest()
        requestWithDefaultLanguages.recognitionLanguages = [Locale.Language(identifier: "fr-FR")]
        configureTextRecognitionRequest(&requestWithDefaultLanguages, recognitionLanguages: [])

        XCTAssertEqual(requestWithDefaultLanguages.recognitionLevel, .accurate)
        XCTAssertTrue(requestWithDefaultLanguages.usesLanguageCorrection)
        XCTAssertTrue(requestWithDefaultLanguages.automaticallyDetectsLanguage)
        XCTAssertEqual(requestWithDefaultLanguages.recognitionLanguages, [])

        var requestWithExplicitLanguages = RecognizeTextRequest()
        configureTextRecognitionRequest(&requestWithExplicitLanguages, recognitionLanguages: ["de-DE", "sv-SE"])

        XCTAssertEqual(requestWithExplicitLanguages.recognitionLevel, .accurate)
        XCTAssertTrue(requestWithExplicitLanguages.usesLanguageCorrection)
        XCTAssertFalse(requestWithExplicitLanguages.automaticallyDetectsLanguage)
        XCTAssertEqual(
            requestWithExplicitLanguages.recognitionLanguages,
            [Locale.Language(identifier: "de-DE"), Locale.Language(identifier: "sv-SE")]
        )
    }

    func testAccessibilityElementResponseEncodesStateAttributes() throws {
        let response = AccessibilityElementResponse(
            path: nil,
            role: "AXCheckBox",
            subrole: nil,
            title: "Enable Sync",
            description: nil,
            identifier: "sync",
            value: "1",
            enabled: true,
            focused: false,
            selected: true,
            frame: nil,
            actions: ["AXPress"],
            childCount: 0,
            truncated: nil,
            children: nil
        )

        XCTAssertEqual(
            try encodeJSON(response),
            #"{"actions":["AXPress"],"childCount":0,"enabled":true,"focused":false,"identifier":"sync","role":"AXCheckBox","selected":true,"title":"Enable Sync","value":"1"}"#
        )
    }

    func testAXMutationInvokesActionOnceAndAcceptsObservedPostcondition() {
        let attributeUnsupported = AXError(rawValue: -25205)!
        var mutationCount = 0
        var postconditionCheckCount = 0
        var sleepCount = 0

        let outcome = performAXMutationOnce(
            perform: {
                mutationCount += 1
                return attributeUnsupported
            },
            verifyPostcondition: {
                postconditionCheckCount += 1
                return postconditionCheckCount == 3
            },
            postconditionChecks: 4,
            pollInterval: 0.05,
            sleep: { _ in sleepCount += 1 }
        )

        XCTAssertTrue(outcome.accepted)
        XCTAssertEqual(outcome.error.rawValue, -25205)
        XCTAssertTrue(outcome.postconditionSatisfied)
        XCTAssertEqual(mutationCount, 1)
        XCTAssertEqual(postconditionCheckCount, 3)
        XCTAssertEqual(sleepCount, 2)
    }

    func testAXMutationSuccessDoesNotPollOrRepeatAction() {
        var mutationCount = 0
        var postconditionCheckCount = 0
        var sleepCount = 0

        let outcome = performAXMutationOnce(
            perform: {
                mutationCount += 1
                return .success
            },
            verifyPostcondition: {
                postconditionCheckCount += 1
                return false
            },
            sleep: { _ in sleepCount += 1 }
        )

        XCTAssertTrue(outcome.accepted)
        XCTAssertFalse(outcome.postconditionSatisfied)
        XCTAssertEqual(mutationCount, 1)
        XCTAssertEqual(postconditionCheckCount, 0)
        XCTAssertEqual(sleepCount, 0)
    }

    func testAXMutationRejectsUnverifiedFailureWithoutRepeatingAction() {
        let cannotComplete = AXError(rawValue: -25204)!
        var mutationCount = 0
        var postconditionCheckCount = 0
        var sleepCount = 0

        let outcome = performAXMutationOnce(
            perform: {
                mutationCount += 1
                return cannotComplete
            },
            verifyPostcondition: {
                postconditionCheckCount += 1
                return false
            },
            postconditionChecks: 3,
            sleep: { _ in sleepCount += 1 }
        )

        XCTAssertFalse(outcome.accepted)
        XCTAssertEqual(mutationCount, 1)
        XCTAssertEqual(postconditionCheckCount, 3)
        XCTAssertEqual(sleepCount, 2)
    }

    func testAXErrorFormattingIncludesSymbolicAndRawValues() {
        let attributeUnsupported = AXError(rawValue: -25205)!
        let cannotComplete = AXError(rawValue: -25204)!

        XCTAssertEqual(
            formatAXError(attributeUnsupported),
            "kAXErrorAttributeUnsupported (-25205)"
        )
        XCTAssertEqual(
            formatAXError(cannotComplete),
            "kAXErrorCannotComplete (-25204)"
        )
    }

    func testAlternateMenuActionRequiresOriginalReachableContext() {
        XCTAssertTrue(
            shouldAttemptAlternateMenuAction(
                primaryAccepted: false,
                menuStillVisible: true,
                itemStillReachable: true,
                supportsAlternateAction: true
            )
        )
        XCTAssertFalse(
            shouldAttemptAlternateMenuAction(
                primaryAccepted: true,
                menuStillVisible: true,
                itemStillReachable: true,
                supportsAlternateAction: true
            )
        )
        XCTAssertFalse(
            shouldAttemptAlternateMenuAction(
                primaryAccepted: false,
                menuStillVisible: false,
                itemStillReachable: true,
                supportsAlternateAction: true
            )
        )
        XCTAssertFalse(
            shouldAttemptAlternateMenuAction(
                primaryAccepted: false,
                menuStillVisible: true,
                itemStillReachable: false,
                supportsAlternateAction: true
            )
        )
        XCTAssertFalse(
            shouldAttemptAlternateMenuAction(
                primaryAccepted: false,
                menuStillVisible: true,
                itemStillReachable: true,
                supportsAlternateAction: false
            )
        )
    }

    func testAccessibilityResponseFallsBackAfterTargetInvalidation() throws {
        let snapshot = AccessibilityElementResponse(
            path: nil,
            role: "AXButton",
            subrole: "AXCloseButton",
            title: "Close",
            description: nil,
            identifier: nil,
            value: nil,
            enabled: true,
            focused: nil,
            selected: nil,
            frame: JSONRect(CGRect(x: 10, y: 20, width: 14, height: 14)),
            actions: ["AXPress"],
            childCount: 0,
            truncated: nil,
            children: nil
        )
        let invalidated = AccessibilityElementResponse(
            path: nil,
            role: nil,
            subrole: nil,
            title: nil,
            description: nil,
            identifier: nil,
            value: nil,
            enabled: nil,
            focused: nil,
            selected: nil,
            frame: nil,
            actions: nil,
            childCount: 0,
            truncated: nil,
            children: []
        )

        let selected = preferredAccessibilityElementResponse(
            refreshed: invalidated,
            fallback: snapshot
        )

        XCTAssertEqual(
            try encodeJSON(selected),
            #"{"actions":["AXPress"],"childCount":0,"enabled":true,"frame":{"height":14,"width":14,"x":10,"y":20},"role":"AXButton","subrole":"AXCloseButton","title":"Close"}"#
        )
    }

    func testAXGeometryPostconditionsUseOnePointTolerance() {
        XCTAssertTrue(
            axPointMatches(
                CGPoint(x: 100.75, y: -20.5),
                expected: CGPoint(x: 100, y: -20)
            )
        )
        XCTAssertFalse(
            axPointMatches(
                CGPoint(x: 101.01, y: -20),
                expected: CGPoint(x: 100, y: -20)
            )
        )
        XCTAssertTrue(
            axSizeMatches(
                CGSize(width: 799.25, height: 600.5),
                expected: CGSize(width: 800, height: 600)
            )
        )
        XCTAssertFalse(
            axSizeMatches(
                CGSize(width: 798.9, height: 600),
                expected: CGSize(width: 800, height: 600)
            )
        )
    }

    func testReportedAXActionsOmitsShowMenuOnlyNoise() throws {
        XCTAssertEqual(reportedAXActions([kAXShowMenuAction as String]), [])
        XCTAssertEqual(reportedAXActions([kAXPressAction as String]), [kAXPressAction as String])
        XCTAssertEqual(
            reportedAXActions([kAXShowMenuAction as String, kAXPressAction as String]),
            [kAXShowMenuAction as String, kAXPressAction as String]
        )

        let showMenuOnlyActions = reportedAXActions([kAXShowMenuAction as String])
        let response = AccessibilityElementResponse(
            path: nil,
            role: "AXStaticText",
            subrole: nil,
            title: "Decorative",
            description: nil,
            identifier: nil,
            value: nil,
            enabled: nil,
            focused: nil,
            selected: nil,
            frame: nil,
            actions: showMenuOnlyActions.isEmpty ? nil : showMenuOnlyActions,
            childCount: 0,
            truncated: nil,
            children: nil
        )

        XCTAssertEqual(
            try encodeJSON(response),
            #"{"childCount":0,"role":"AXStaticText","title":"Decorative"}"#
        )
    }

    func testAgentSupportExcludesCodexOnlyFilesFromClaudeSkill() {
        let prefixes: Set<String> = ["agents/"]

        XCTAssertTrue(isExcludedRelativePath("agents", prefixes: prefixes))
        XCTAssertTrue(isExcludedRelativePath("agents/openai.yaml", prefixes: prefixes))
        XCTAssertFalse(isExcludedRelativePath("SKILL.md", prefixes: prefixes))
        XCTAssertFalse(isExcludedRelativePath("references/usage.md", prefixes: prefixes))
    }

    func testUpdatedAgentsContentsReplacesLegacyRegionshotManagedBlock() {
        let existingContents = """
        # User Environment Notes

        <!-- regionshot-managed:start -->
        - Use the `regionshot` skill and the `regionshot` command on PATH.
        - Prefer `regionshot --help` for exact command syntax.
        <!-- regionshot-managed:end -->

        # Unrelated user notes

        - keep me
        """
        let managedBlock = """
        <!-- brrainztools-managed:start -->
        - Use the `brrainztools` skill and the `brrainztools` command on PATH.
        <!-- brrainztools-managed:end -->
        """

        let updatedContents = updatedAgentsContents(
            from: existingContents,
            managedBlock: managedBlock,
            legacyPointerBody: "- Use the `brrainztools` skill and the `brrainztools` command on PATH."
        )

        XCTAssertFalse(updatedContents.contains("regionshot"))
        XCTAssertEqual(
            updatedContents.components(separatedBy: "<!-- brrainztools-managed:start -->").count,
            2,
            "Expected exactly one managed block."
        )
        XCTAssertTrue(updatedContents.contains("- keep me"))
        XCTAssertTrue(updatedContents.contains("- Use the `brrainztools` skill and the `brrainztools` command on PATH."))
    }

    func testUpdatedAgentsContentsMigrationIsIdempotent() {
        let existingContents = """
        # User Environment Notes

        <!-- regionshot-managed:start -->
        - Use the `regionshot` skill.
        <!-- regionshot-managed:end -->
        """
        let managedBlock = """
        <!-- brrainztools-managed:start -->
        - Use the `brrainztools` skill.
        <!-- brrainztools-managed:end -->
        """
        let pointerBody = "- Use the `brrainztools` skill."

        let migratedContents = updatedAgentsContents(
            from: existingContents,
            managedBlock: managedBlock,
            legacyPointerBody: pointerBody
        )
        let remigratedContents = updatedAgentsContents(
            from: migratedContents,
            managedBlock: managedBlock,
            legacyPointerBody: pointerBody
        )

        XCTAssertEqual(migratedContents, remigratedContents)
        XCTAssertFalse(migratedContents.contains("regionshot"))
    }

    func testUpdatedAgentsContentsRemovesDuplicatedLegacyBlocks() {
        let legacyBlock = """
        <!-- regionshot-managed:start -->
        - Use the `regionshot` skill.
        <!-- regionshot-managed:end -->
        """
        let existingContents = """
        # User Environment Notes

        \(legacyBlock)

        \(legacyBlock)
        """
        let managedBlock = """
        <!-- brrainztools-managed:start -->
        - Use the `brrainztools` skill.
        <!-- brrainztools-managed:end -->
        """

        let updatedContents = updatedAgentsContents(
            from: existingContents,
            managedBlock: managedBlock,
            legacyPointerBody: "- Use the `brrainztools` skill."
        )

        XCTAssertFalse(updatedContents.contains("regionshot"))
        XCTAssertEqual(
            updatedContents.components(separatedBy: "<!-- brrainztools-managed:start -->").count,
            2,
            "Expected exactly one managed block."
        )
    }

    func testStringifyAXAttributeValueNormalizesCommonStateValues() {
        XCTAssertEqual(stringifyAXAttributeValue("  Hello\nWorld  "), "Hello World")
        XCTAssertEqual(stringifyAXAttributeValue(NSAttributedString(string: "Styled")), "Styled")
        XCTAssertEqual(stringifyAXAttributeValue(true), "true")
        XCTAssertEqual(stringifyAXAttributeValue(false), "false")
        XCTAssertEqual(stringifyAXAttributeValue(NSNumber(value: 42)), "42")
        XCTAssertEqual(stringifyAXAttributeValue(URL(string: "file:///tmp/example.txt")!), "file:///tmp/example.txt")
        XCTAssertNil(stringifyAXAttributeValue(["unsupported"]))
    }

    func testDoctorStatusEncodesPermissionAndHostState() throws {
        let response = doctorStatus(
            screenRecordingAccess: { true },
            accessibilityTrusted: { false },
            version: { "1.2.3" },
            hostProcess: {
                DoctorHostProcess(
                    processID: 42,
                    name: "iTerm2",
                    bundleIdentifier: "com.googlecode.iterm2"
                )
            }
        )

        XCTAssertEqual(
            try encodeJSON(response),
            #"{"accessibility":false,"hostProcess":{"bundleIdentifier":"com.googlecode.iterm2","name":"iTerm2","processID":42},"screenRecording":true,"version":"1.2.3"}"#
        )
    }

    func testClipboardResponseEncodesReadAndSetState() throws {
        XCTAssertEqual(
            try encodeJSON(ClipboardResponse(action: "read", text: "hello")),
            #"{"action":"read","text":"hello"}"#
        )

        XCTAssertEqual(
            try encodeJSON(ClipboardResponse(action: "read", text: nil)),
            #"{"action":"read"}"#
        )
    }

    func testDisplayListResponseEncodesDisplayGeometry() throws {
        let response = DisplayListResponse(
            displays: [
                DisplayEntry(
                    id: 42,
                    frame: JSONRect(CGRect(x: -100, y: 20, width: 800, height: 600)),
                    pixelWidth: 1600,
                    pixelHeight: 1200,
                    scale: 2,
                    isMain: true
                ),
            ]
        )

        XCTAssertEqual(
            try encodeJSON(response),
            #"{"displays":[{"frame":{"height":600,"width":800,"x":-100,"y":20},"id":42,"isMain":true,"pixelHeight":1200,"pixelWidth":1600,"scale":2}]}"#
        )
    }

    func testDisplayFrameCaptureRegionRoundsOutwardAndUnionsFrames() throws {
        let region = try captureRegionForDisplayFrames([
            CGRect(x: -10.4, y: 5.2, width: 100.1, height: 50.1),
            CGRect(x: 90.2, y: -4.8, width: 20.1, height: 10.1),
        ])

        XCTAssertEqual(region.x, -11)
        XCTAssertEqual(region.y, -5)
        XCTAssertEqual(region.width, 122)
        XCTAssertEqual(region.height, 61)
    }

    func testDisplayFrameCaptureRegionRejectsEmptyDisplaySet() {
        XCTAssertThrowsError(
            try captureRegionForDisplayFrames([])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("No active displays"))
        }
    }

    func testBrrainzToolsVersionPrefersEnvironmentOverride() {
        let version = brrainzToolsVersion(
            environment: ["BRRAINZTOOLS_VERSION": " 2.0.0 \n"],
            executableDirectory: URL(fileURLWithPath: "/tmp/bin", isDirectory: true),
            currentDirectoryURL: URL(fileURLWithPath: "/tmp/repo", isDirectory: true),
            readTextFile: { _ in "1.0.0" },
            gitDescribe: { _ in "v1.0.0" }
        )

        XCTAssertEqual(version, "2.0.0")
    }

    func testBrrainzToolsVersionReadsInstalledSupportFile() {
        let executableDirectory = URL(fileURLWithPath: "/tmp/bin", isDirectory: true)
        var gitDescribeWasCalled = false
        var requestedURLs: [URL] = []

        let version = brrainzToolsVersion(
            environment: [:],
            executableDirectory: executableDirectory,
            currentDirectoryURL: URL(fileURLWithPath: "/tmp/repo", isDirectory: true),
            readTextFile: { url in
                requestedURLs.append(url)
                return "1.2.3\nignored"
            },
            gitDescribe: { _ in
                gitDescribeWasCalled = true
                return "v1.0.0"
            }
        )

        XCTAssertEqual(version, "1.2.3")
        XCTAssertEqual(
            requestedURLs,
            [
                executableDirectory
                    .appendingPathComponent(".brrainztools-support", isDirectory: true)
                    .appendingPathComponent("VERSION"),
            ]
        )
        XCTAssertFalse(gitDescribeWasCalled)
    }

    func testBrrainzToolsVersionUsesGitDescribeOnlyForBrrainzToolsRepository() {
        let repositoryURL = URL(fileURLWithPath: "/tmp/BrrainzTools", isDirectory: true)
        var requestedGitDescribeURLs: [URL] = []

        let gitVersion = brrainzToolsVersion(
            environment: [:],
            executableDirectory: nil,
            currentDirectoryURL: repositoryURL.appendingPathComponent("docs", isDirectory: true),
            readTextFile: { url in
                if url.path == repositoryURL.appendingPathComponent("Package.swift").path {
                    return #"let package = Package(name: "BrrainzTools")"#
                }

                return nil
            },
            gitDescribe: { url in
                requestedGitDescribeURLs.append(url)
                return "v1.0.0-4-gabcdef"
            }
        )

        XCTAssertEqual(gitVersion, "v1.0.0-4-gabcdef")
        XCTAssertEqual(requestedGitDescribeURLs, [repositoryURL])
    }

    func testBrrainzToolsVersionIgnoresForeignRepositoryGitDescribe() {
        var gitDescribeWasCalled = false

        let fallbackVersion = brrainzToolsVersion(
            environment: [:],
            executableDirectory: nil,
            currentDirectoryURL: URL(fileURLWithPath: "/tmp/DecompilerServer", isDirectory: true),
            readTextFile: { url in
                if url.path == "/tmp/DecompilerServer/Package.swift" {
                    return #"let package = Package(name: "DecompilerServer")"#
                }

                return nil
            },
            gitDescribe: { _ in
                gitDescribeWasCalled = true
                return "v1.3.6-2-g248d20d"
            }
        )

        XCTAssertEqual(fallbackVersion, "v2.0.0")
        XCTAssertFalse(gitDescribeWasCalled)
    }

    func testVisibleWindowCatalogFiltersToNormalVisibleWindows() {
        let snapshots = [
            WindowSnapshot(
                windowID: 10,
                ownerPID: 100,
                title: "Menu",
                bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
                layer: 20,
                alpha: 1
            ),
            WindowSnapshot(
                windowID: 11,
                ownerPID: 100,
                title: "Front",
                bounds: CGRect(x: 10, y: 20, width: 300, height: 200),
                layer: 0,
                alpha: 1
            ),
            WindowSnapshot(
                windowID: 14,
                ownerPID: 100,
                title: "Floating Panel",
                bounds: CGRect(x: 12, y: 24, width: 300, height: 120),
                layer: 3,
                alpha: 1
            ),
            WindowSnapshot(
                windowID: 12,
                ownerPID: 100,
                title: "Transparent",
                bounds: CGRect(x: 20, y: 30, width: 300, height: 200),
                layer: 0,
                alpha: 0
            ),
            WindowSnapshot(
                windowID: 13,
                ownerPID: 200,
                title: "Other",
                bounds: CGRect(x: 30, y: 40, width: 300, height: 200),
                layer: 0,
                alpha: 1
            ),
        ]

        let windows = visibleWindows(for: 100, snapshots: snapshots)

        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].index, 0)
        XCTAssertEqual(windows[0].windowID, 11)
        XCTAssertEqual(windows[0].title, "Front")
        XCTAssertEqual(windows[1].index, 1)
        XCTAssertEqual(windows[1].windowID, 14)
        XCTAssertEqual(windows[1].title, "Floating Panel")
    }

    func testAsciiRendererPreservesTopToBottomOrientation() throws {
        let image = try makeGrayscaleImage(
            width: 2,
            height: 4,
            pixels: [
                0, 0,
                0, 0,
                255, 255,
                255, 255,
            ]
        )

        let rendered = try renderAsciiArt(
            from: image,
            options: AsciiArtOptions(width: 2, maxHeight: 2, invert: false)
        )
        let lines = rendered.text.components(separatedBy: "\n")

        XCTAssertEqual(rendered.width, 2)
        XCTAssertEqual(rendered.height, 2)
        XCTAssertEqual(lines, ["@@", "  "])
    }

    func testCaptureCanvasPreservesImageOrientation() throws {
        let sourceImage = try makeGrayscaleImage(
            width: 4,
            height: 4,
            pixels: [
                0, 0, 255, 255,
                0, 0, 255, 255,
                255, 255, 0, 0,
                255, 255, 0, 0,
            ]
        )
        let canvas = try makeCaptureCanvas(size: CGSize(width: 4, height: 4))
        canvas.interpolationQuality = .none
        canvas.draw(sourceImage, in: CGRect(x: 0, y: 0, width: 4, height: 4))

        guard let compositedImage = canvas.makeImage() else {
            return XCTFail("Expected the capture canvas to produce an image.")
        }

        let rendered = try renderAsciiArt(
            from: compositedImage,
            options: AsciiArtOptions(width: 4, maxHeight: 2, invert: false)
        )

        XCTAssertEqual(rendered.text.components(separatedBy: "\n"), ["@@  ", "  @@"])
    }

    func testAsciiRendererCanInvertLightness() throws {
        let image = try makeGrayscaleImage(
            width: 2,
            height: 4,
            pixels: [
                0, 0,
                0, 0,
                255, 255,
                255, 255,
            ]
        )

        let rendered = try renderAsciiArt(
            from: image,
            options: AsciiArtOptions(width: 2, maxHeight: 2, invert: true)
        )

        XCTAssertEqual(rendered.text.components(separatedBy: "\n"), ["  ", "@@"])
    }

    func testAsciiLayoutOverlaysOCRText() throws {
        let image = try makeGrayscaleImage(width: 80, height: 40, pixels: Array(repeating: 255, count: 80 * 40))
        let rendered = try renderAsciiLayout(
            from: image,
            options: AsciiLayoutOptions(width: 40, maxHeight: 10),
            textBlocks: [
                OCRTextBlock(
                    text: "Finder Window",
                    confidence: 0.9,
                    bounds: CGRect(x: 10, y: 8, width: 32, height: 8)
                ),
            ]
        )

        XCTAssertTrue(rendered.text.contains("Finder Window"))
    }

    func testAsciiLayoutWrapsLongOCRText() throws {
        let image = try makeGrayscaleImage(width: 80, height: 40, pixels: Array(repeating: 255, count: 80 * 40))
        let rendered = try renderAsciiLayout(
            from: image,
            options: AsciiLayoutOptions(width: 24, maxHeight: 10),
            textBlocks: [
                OCRTextBlock(
                    text: "This is a very long Finder row",
                    confidence: 0.9,
                    bounds: CGRect(x: 48, y: 10, width: 16, height: 8)
                ),
            ]
        )

        XCTAssertTrue(rendered.text.contains("This is"))
        XCTAssertTrue(rendered.text.contains("Finder row"))
    }

    func testAsciiLayoutDrawsSparseEdges() throws {
        let image = try makeGrayscaleImage(
            width: 20,
            height: 20,
            pixels: borderedPixels(width: 20, height: 20)
        )
        let rendered = try renderAsciiLayout(
            from: image,
            options: AsciiLayoutOptions(width: 20, maxHeight: 10),
            textBlocks: []
        )

        XCTAssertTrue(rendered.text.contains("-") || rendered.text.contains("|") || rendered.text.contains("+"))
    }

    func testOCRFormattingSortsBlocksForReadingOrder() {
        let formatted = formatOCRTextBlocks([
            OCRTextBlock(
                text: "Bottom",
                confidence: 0.8,
                bounds: CGRect(x: 10, y: 100, width: 60, height: 14)
            ),
            OCRTextBlock(
                text: "Top \"Menu\"",
                confidence: 0.93,
                bounds: CGRect(x: 5, y: 10, width: 40, height: 8)
            ),
        ])

        XCTAssertEqual(
            formatted.components(separatedBy: "\n"),
            [
                "ocr:",
                "- [x=5 y=10 w=40 h=8 confidence=0.93] \"Top \\\"Menu\\\"\"",
                "- [x=10 y=100 w=60 h=14 confidence=0.80] \"Bottom\"",
            ]
        )
    }

    func testOCROnlyResponseFormatsSortedJSONBlocks() throws {
        let json = try formatOCROnlyResponse(
            imagePath: "/tmp/screenshot.png",
            imageWidth: 200,
            imageHeight: 100,
            ocrStatus: .blocks([
                OCRTextBlock(
                    text: "Bottom",
                    confidence: 0.8,
                    bounds: CGRect(x: 10, y: 100, width: 60, height: 14)
                ),
                OCRTextBlock(
                    text: "Top",
                    confidence: 0.93,
                    bounds: CGRect(x: 5, y: 10, width: 40, height: 8)
                ),
            ])
        )

        XCTAssertEqual(
            json,
            #"{"blocks":[{"bounds":{"height":8,"width":40,"x":5,"y":10},"confidence":0.93,"text":"Top"},{"bounds":{"height":14,"width":60,"x":10,"y":100},"confidence":0.8,"text":"Bottom"}],"image":{"height":100,"path":"/tmp/screenshot.png","width":200}}"#
        )
    }

    func testAsciiReportFormatsDisabledOCR() {
        let report = formatAsciiArtReport(
            imagePath: "/tmp/screenshot.png",
            imageWidth: 200,
            imageHeight: 100,
            style: .layout,
            rendered: RenderedAsciiArt(width: 4, height: 1, text: "@@  "),
            ocrStatus: .disabled
        )

        let expected = [
            "image: /tmp/screenshot.png",
            "size: 200x100 px",
            "layout: 4x1 chars",
            "@@  ",
            "",
            "ocr: disabled",
        ].joined(separator: "\n")

        XCTAssertEqual(report, expected)
    }

    func testMenuBarWindowCloseStopsAfterEscapeClosesWindow() {
        var attempts: [MenuBarWindowCloseAttempt] = []

        closeMenuBarWindowSurface(processID: 123, windowID: 456) { attempt in
            attempts.append(attempt)
            return true
        }

        XCTAssertEqual(attempts, [.pressEscape(processID: 123, windowID: 456)])
    }

    func testMenuBarWindowCloseRepressesItemOnlyAfterEscapeFails() {
        var attempts: [MenuBarWindowCloseAttempt] = []

        closeMenuBarWindowSurface(processID: 123, windowID: 456) { attempt in
            attempts.append(attempt)
            return attempt == .pressMenuBarItem(windowID: 456)
        }

        XCTAssertEqual(
            attempts,
            [
                .pressEscape(processID: 123, windowID: 456),
                .pressMenuBarItem(windowID: 456),
            ]
        )
    }

    func testSelectMenuBarItemDefaultsToSingleExtrasItem() throws {
        let catalog = menuBarCatalog(
            items: [
                menuBarItem(index: 0, source: "main-menu", title: "File"),
                menuBarItem(index: 1, source: "extras", title: nil),
            ]
        )

        let selected = try selectMenuBarItem(from: catalog, using: nil)

        XCTAssertEqual(selected.index, 1)
        XCTAssertEqual(selected.source, "extras")
    }

    func testSelectMenuBarItemDefaultsToOnlyItem() throws {
        let catalog = menuBarCatalog(items: [menuBarItem(index: 0, source: "main-menu", title: "File")])

        let selected = try selectMenuBarItem(from: catalog, using: nil)

        XCTAssertEqual(selected.index, 0)
    }

    func testSelectMenuBarItemPrefersExactNameMatch() throws {
        let catalog = menuBarCatalog(
            items: [
                menuBarItem(index: 0, source: "extras", title: "Drafty Helper"),
                menuBarItem(index: 1, source: "extras", title: "Drafty"),
            ]
        )

        let selected = try selectMenuBarItem(from: catalog, using: .name("drafty"))

        XCTAssertEqual(selected.index, 1)
    }

    func testSelectMenuBarItemMatchesDescriptionAndIdentifier() throws {
        let catalog = menuBarCatalog(
            items: [
                menuBarItem(index: 0, source: "extras", title: nil, description: "Quick Tasks"),
                menuBarItem(index: 1, source: "extras", title: nil, identifier: "com.example.settings"),
            ]
        )

        let descriptionMatch = try selectMenuBarItem(from: catalog, using: .name("quick"))
        let identifierMatch = try selectMenuBarItem(from: catalog, using: .name("settings"))

        XCTAssertEqual(descriptionMatch.index, 0)
        XCTAssertEqual(identifierMatch.index, 1)
    }

    func testSelectMenuBarItemReportsAmbiguousPartialMatches() {
        let catalog = menuBarCatalog(
            items: [
                menuBarItem(index: 0, source: "extras", title: "Drafty"),
                menuBarItem(index: 1, source: "extras", title: "Drafty Helper"),
            ]
        )

        XCTAssertThrowsError(
            try selectMenuBarItem(from: catalog, using: .name("draft"))
        ) { error in
            XCTAssertTrue(String(describing: error).contains("More than one menu-bar item"))
            XCTAssertTrue(String(describing: error).contains("[0]"))
            XCTAssertTrue(String(describing: error).contains("[1]"))
        }
    }

    func testSelectMenuBarItemReportsMissingIndex() {
        let catalog = menuBarCatalog(items: [menuBarItem(index: 0, source: "extras", title: "Drafty")])

        XCTAssertThrowsError(
            try selectMenuBarItem(from: catalog, using: .index(2))
        ) { error in
            XCTAssertTrue(String(describing: error).contains("No menu-bar item at index 2"))
        }
    }

    func testWaitForStableMenuBarSurfaceFrameReturnsFirstRepeatedFrame() {
        let first = CGRect(x: 10, y: 20, width: 100, height: 50)
        let moving = CGRect(x: 10, y: 24, width: 100, height: 50)
        let stable = CGRect(x: 10, y: 28, width: 100, height: 50)
        var frames: [CGRect?] = [moving, stable, stable, first]
        var observedPollIntervals: [TimeInterval] = []

        let result = waitForStableMenuBarSurfaceFrame(
            initialFrame: first,
            timeout: 10,
            pollInterval: 0.05,
            now: { Date(timeIntervalSinceReferenceDate: 0) },
            sleep: { observedPollIntervals.append($0) },
            readFrame: { frames.removeFirst() }
        )

        XCTAssertEqual(result, stable)
        XCTAssertEqual(observedPollIntervals, [0.05, 0.05])
    }

    func testWaitForStableMenuBarSurfaceFrameReturnsLatestFrameOnTimeout() {
        let first = CGRect(x: 10, y: 20, width: 100, height: 50)
        let second = CGRect(x: 10, y: 24, width: 100, height: 50)
        let third = CGRect(x: 10, y: 28, width: 100, height: 50)
        var frames: [CGRect?] = [first, nil, .zero, second, third]
        var currentTime = 0.0

        let result = waitForStableMenuBarSurfaceFrame(
            initialFrame: nil,
            timeout: 0.045,
            pollInterval: 0,
            now: {
                defer { currentTime += 0.01 }
                return Date(timeIntervalSinceReferenceDate: currentTime)
            },
            sleep: { _ in },
            readFrame: { frames.isEmpty ? nil : frames.removeFirst() }
        )

        XCTAssertEqual(result, third)
    }

    func testTimeoutReturnsFailureWithoutWaitingForOperation() async throws {
        let start = Date()

        do {
            let _: Int = try await withTimeout(
                seconds: 0.05,
                timeoutMessage: { "timed out" },
                operation: {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    return 1
                }
            )
            XCTFail("Expected timeout.")
        } catch BrrainzToolsError.operationTimedOut(let message) {
            XCTAssertEqual(message, "timed out")
            XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
        }
    }

    func testTimeoutReturnsSuccessfulOperation() async throws {
        let value: Int = try await withTimeout(
            seconds: 1,
            timeoutMessage: { "timed out" },
            operation: { 42 }
        )

        XCTAssertEqual(value, 42)
    }
}

private func makeGrayscaleImage(width: Int, height: Int, pixels: [UInt8]) throws -> CGImage {
    XCTAssertEqual(pixels.count, width * height)

    var rgba: [UInt8] = []
    rgba.reserveCapacity(width * height * 4)

    for pixel in pixels {
        rgba.append(pixel)
        rgba.append(pixel)
        rgba.append(pixel)
        rgba.append(255)
    }

    guard
        let data = CFDataCreate(nil, rgba, rgba.count),
        let provider = CGDataProvider(data: data),
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    else {
        throw BrrainzToolsError.captureFailed("Failed to create test image.")
    }

    return image
}

private func borderedPixels(width: Int, height: Int) -> [UInt8] {
    (0..<height).flatMap { row in
        (0..<width).map { column in
            row == 0 || row == height - 1 || column == 0 || column == width - 1 ? UInt8(0) : UInt8(255)
        }
    }
}

private func menuBarCatalog(items: [MenuBarCatalogItem]) -> MenuBarItemCatalog {
    MenuBarItemCatalog(
        application: AutomationApplication(
            name: "Drafty",
            bundleIdentifier: "com.example.Drafty",
            processID: 123
        ),
        items: items
    )
}

private func menuBarItem(
    index: Int,
    source: String,
    title: String?,
    description: String? = nil,
    identifier: String? = nil
) -> MenuBarCatalogItem {
    MenuBarCatalogItem(
        index: index,
        source: source,
        role: kAXMenuBarItemRole as String,
        subrole: nil,
        title: title,
        description: description,
        identifier: identifier,
        frame: CGRect(x: index * 20, y: 0, width: 18, height: 20),
        actions: [kAXPressAction as String],
        childCount: 0,
        element: AXUIElementCreateApplication(123)
    )
}

private func XCTAssertThrowsErrorAsync<T>(
    _ operation: () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await operation()
        XCTFail("Expected error to be thrown.", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}

private struct JSONFixture: Encodable {
    let z: String
    let a: String
    let nested: JSONNestedFixture
}

private struct JSONNestedFixture: Encodable {
    let b: Int
    let a: Int
}
