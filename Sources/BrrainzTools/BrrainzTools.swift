import Darwin
import AppKit
import ApplicationServices
import CoreGraphics
import Dispatch
import Foundation
import ImageIO
@preconcurrency import ScreenCaptureKit
import UniformTypeIdentifiers
import Vision

@main
struct BrrainzTools {
    static func main() async {
        do {
            let behavior = try parse(arguments: Array(CommandLine.arguments.dropFirst()))
            if behavior.shouldSynchronizeAgentSupport {
                synchronizeAgentSupportIfAvailable()
            }

            switch behavior {
            case .showHelp:
                print(usageText)
            case .showHelpText(let text):
                print(text)
            case .showVersion:
                print(try basicEnvelopeJSON(mode: "version"))
            case .doctor:
                let json = try encodeJSON(currentDoctorStatus())
                print(try dataEnvelopeJSON(mode: "doctor", dataJSON: json))
            case .clipboard(let command):
                let json = try handleClipboard(using: command)
                print(try dataEnvelopeJSON(mode: "clipboard", dataJSON: json))
            case .revealFile(let command):
                let json = try reveal(using: command)
                print(try dataEnvelopeJSON(mode: "reveal", dataJSON: json))
            case .openFile(let command):
                let json = try openFile(using: command)
                print(try dataEnvelopeJSON(mode: "open-file", dataJSON: json))
            case .listDisplays:
                let json = try listDisplays()
                print(try dataEnvelopeJSON(mode: "displays", dataJSON: json))
            case .activateApplication(let command):
                let json = try activate(using: command)
                print(try dataEnvelopeJSON(mode: "activate", dataJSON: json))
            case .launchApplication(let command):
                let json = try launch(using: command)
                print(try dataEnvelopeJSON(mode: "launch", dataJSON: json))
            case .quitApplication(let command):
                let json = try quit(using: command)
                print(try dataEnvelopeJSON(mode: "quit", dataJSON: json))
            case .findApps(let command):
                let json = try findApps(using: command)
                print(try dataEnvelopeJSON(mode: "find-app", dataJSON: json))
            case .asciiArt(let command):
                let text = try await asciiArtReport(using: command)
                if command.rawOutput {
                    print(text)
                } else if command.outputMode == .ocrOnly {
                    print(try dataEnvelopeJSON(mode: "ocr", dataJSON: text))
                } else {
                    print(try reportEnvelopeJSON(mode: "ascii", report: text))
                }
            case .capture(let command):
                try await capture(using: command)
                if command.rawOutput {
                    print(command.outputURL.path)
                } else {
                    print(try await captureOutputEnvelopeJSON(
                        mode: "capture",
                        outputURL: command.outputURL,
                        textOutput: command.textOutput
                    ))
                }
            case .captureVisibleWindow(let command):
                try await captureVisibleWindow(using: command)
                if command.rawOutput {
                    print(command.outputURL.path)
                } else {
                    print(try await captureOutputEnvelopeJSON(
                        mode: "visible-window",
                        outputURL: command.outputURL,
                        textOutput: command.textOutput
                    ))
                }
            case .listWindows(let command):
                let json = try await listWindows(using: command)
                print(try dataEnvelopeJSON(mode: "windows", dataJSON: json))
            case .listVisibleWindows(let command):
                let json = try listVisibleWindows(using: command)
                print(try dataEnvelopeJSON(mode: "visible-windows", dataJSON: json))
            case .inspectAccessibility(let command):
                let json = try await inspectAccessibility(using: command)
                print(try dataEnvelopeJSON(mode: "accessibility", dataJSON: json))
            case .menuBar(let command):
                let result = try await handleMenuBar(using: command)
                if command.mode.isCapture {
                    if command.rawOutput {
                        print(result)
                    } else {
                        print(try await captureOutputEnvelopeJSON(
                            mode: "menu.capture",
                            outputURL: URL(fileURLWithPath: result),
                            textOutput: command.textOutput
                        ))
                    }
                } else {
                    print(try dataEnvelopeJSON(mode: command.mode.envelopeMode, dataJSON: result))
                }
            }
        } catch let error as BrrainzToolsError {
            let json = (try? errorEnvelopeJSON(error: error)) ?? fallbackErrorEnvelopeJSON(
                kind: error.kind,
                message: error.localizedDescription,
                exitCode: error.exitCode
            )
            writeStandardError(json + "\n")
            Darwin.exit(error.exitCode)
        } catch {
            let json = fallbackErrorEnvelopeJSON(
                kind: "unexpectedError",
                message: error.localizedDescription,
                exitCode: 1
            )
            writeStandardError(json + "\n")
            Darwin.exit(1)
        }
    }
}

enum CommandBehavior: Sendable {
    case showHelp
    case showHelpText(String)
    case showVersion
    case doctor
    case clipboard(ClipboardCommand)
    case revealFile(RevealCommand)
    case openFile(OpenFileCommand)
    case listDisplays
    case activateApplication(ActivateApplicationCommand)
    case launchApplication(LaunchApplicationCommand)
    case quitApplication(QuitApplicationCommand)
    case findApps(FindAppsCommand)
    case asciiArt(AsciiArtCommand)
    case capture(CaptureCommand)
    case captureVisibleWindow(VisibleWindowCaptureCommand)
    case listWindows(ListWindowsCommand)
    case listVisibleWindows(VisibleWindowsCommand)
    case inspectAccessibility(AccessibilityCommand)
    case menuBar(MenuBarCommand)

    var shouldSynchronizeAgentSupport: Bool {
        switch self {
        case .showHelp, .showHelpText, .showVersion, .doctor, .clipboard, .listDisplays:
            return false
        case .revealFile, .openFile, .activateApplication, .launchApplication, .quitApplication, .findApps, .asciiArt, .capture, .captureVisibleWindow, .listWindows, .listVisibleWindows, .inspectAccessibility, .menuBar:
            return true
        }
    }
}

struct ActivateApplicationCommand: Sendable {
    let applicationSelector: ApplicationSelector
}

struct LaunchApplicationCommand: Sendable {
    let target: LaunchTarget
    let arguments: [String]
    let waitForWindow: Bool
    let promptForAccessibility: Bool
    let timeout: TimeInterval
}

struct QuitApplicationCommand: Sendable {
    let applicationSelector: ApplicationSelector
    let force: Bool
    let waitForTermination: Bool
    let timeout: TimeInterval
}

struct CaptureCommand: Sendable {
    let region: CaptureRegion?
    let displaySelection: DisplayCaptureSelection?
    let outputURL: URL
    let applicationSelector: ApplicationSelector?
    let windowSelection: WindowSelection?
    let windowCrop: WindowCropRect?
    let screenCaptureTimeout: TimeInterval
    let rawOutput: Bool
    let textOutput: CaptureTextOptions?
    let imageOutput: ImageOutputOptions
}

enum DisplayCaptureSelection: Equatable, Sendable {
    case displayID(CGDirectDisplayID)
    case allDisplays
}

struct FindAppsCommand: Sendable {
    let query: String
}

struct ClipboardCommand: Sendable {
    let setText: String?
}

struct RevealCommand: Sendable {
    let path: String
}

struct OpenFileCommand: Sendable {
    let path: String
    let applicationTarget: LaunchTarget?
    let waitForWindow: Bool
    let promptForAccessibility: Bool
    let timeout: TimeInterval
}

struct AsciiArtCommand: Sendable {
    let imageURL: URL
    let style: AsciiArtStyle
    let outputMode: AsciiOutputMode
    let width: Int
    let maxHeight: Int
    let invert: Bool
    let includeOCR: Bool
    let recognitionLanguages: [String]
    let rawOutput: Bool
}

struct ListWindowsCommand: Sendable {
    let applicationSelector: ApplicationSelector
    let screenCaptureTimeout: TimeInterval
}

struct VisibleWindowsCommand: Sendable {
    let applicationSelector: ApplicationSelector
}

struct VisibleWindowCaptureCommand: Sendable {
    let applicationSelector: ApplicationSelector
    let windowSelection: WindowSelection?
    let windowCrop: WindowCropRect?
    let outputURL: URL
    let screenCaptureTimeout: TimeInterval
    let rawOutput: Bool
    let textOutput: CaptureTextOptions?
    let imageOutput: ImageOutputOptions
}

struct AccessibilityCommand: Sendable {
    let applicationSelector: ApplicationSelector
    let windowSelection: WindowSelection?
    let mode: AccessibilityMode
    let promptForAccessibility: Bool
    let treeDepth: Int
    let treeChildLimit: Int
    let treeRoleFilter: Set<String>
    let treeInteractiveOnly: Bool
    let treeFlat: Bool
    let timeout: TimeInterval
}

struct MenuBarCommand: Sendable {
    let applicationSelector: ApplicationSelector
    let selection: MenuBarSelection?
    let mode: MenuBarMode
    let promptForAccessibility: Bool
    let outputURL: URL?
    let screenCaptureTimeout: TimeInterval
    let rawOutput: Bool
    let textOutput: CaptureTextOptions?
    let imageOutput: ImageOutputOptions
}

struct MenuChildSelection: Sendable {
    let query: String
}

struct CaptureTextOptions: Sendable {
    let outputMode: AsciiOutputMode
    let style: AsciiArtStyle
    let width: Int
    let maxHeight: Int
    let invert: Bool
    let includeOCR: Bool
    let recognitionLanguages: [String]
}

struct ImageOutputOptions: Sendable {
    let format: ImageOutputFormat
    let jpegQuality: Double
    let maxDimension: Int?
}

enum ImageOutputFormat: String, Sendable {
    case png
    case jpeg

    var fileExtension: String {
        switch self {
        case .png:
            return "png"
        case .jpeg:
            return "jpg"
        }
    }

    var typeIdentifier: String {
        switch self {
        case .png:
            return UTType.png.identifier
        case .jpeg:
            return UTType.jpeg.identifier
        }
    }

    var displayName: String {
        switch self {
        case .png:
            return "PNG"
        case .jpeg:
            return "JPEG"
        }
    }
}

struct AccessibilitySelector: Sendable {
    let path: String?
    let role: String?
    let subrole: String?
    let title: String?
    let identifier: String?
    let elementDescription: String?

    var isEmpty: Bool {
        path == nil &&
        role == nil &&
        subrole == nil &&
        title == nil &&
        identifier == nil &&
        elementDescription == nil
    }

    var hasNonPathFields: Bool {
        role != nil ||
        subrole != nil ||
        title != nil ||
        identifier != nil ||
        elementDescription != nil
    }
}

struct CaptureRegion: Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    var rectangleArgument: String {
        "\(x),\(y),\(width),\(height)"
    }

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct WindowCropRect: Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct WindowPoint: Sendable {
    let x: Int
    let y: Int

    var point: CGPoint {
        CGPoint(x: x, y: y)
    }
}

struct WindowDrag: Sendable {
    let start: WindowPoint
    let end: WindowPoint
}

struct ScrollDelta: Sendable {
    let x: Int32
    let y: Int32
}

struct MouseClick: Sendable {
    let point: WindowPoint
    let button: MouseButton
    let clickCount: Int
}

enum MouseButton: String, Sendable {
    case left
    case right
}

struct WindowPosition: Sendable {
    let x: Int
    let y: Int

    var point: CGPoint {
        CGPoint(x: x, y: y)
    }
}

struct WindowSize: Sendable {
    let width: Int
    let height: Int

    var size: CGSize {
        CGSize(width: width, height: height)
    }
}

enum KeyModifier: String, Sendable {
    case command
    case shift
    case option
    case control
    case function

    var eventFlag: CGEventFlags {
        switch self {
        case .command:
            return .maskCommand
        case .shift:
            return .maskShift
        case .option:
            return .maskAlternate
        case .control:
            return .maskControl
        case .function:
            return .maskSecondaryFn
        }
    }
}

struct KeyChord: Sendable {
    let rawValue: String
    let keyName: String
    let keyCode: CGKeyCode
    let modifiers: [KeyModifier]

    var modifierNames: [String] {
        modifiers.map(\.rawValue)
    }

    var eventFlags: CGEventFlags {
        var flags = CGEventFlags()
        for modifier in modifiers {
            flags.insert(modifier.eventFlag)
        }
        return flags
    }
}

struct AsciiArtOptions: Sendable {
    let width: Int
    let maxHeight: Int
    let invert: Bool
}

struct AsciiLayoutOptions: Sendable {
    let width: Int
    let maxHeight: Int
}

struct RenderedAsciiArt: Sendable {
    let width: Int
    let height: Int
    let text: String
}

struct OCRTextBlock: Sendable {
    let text: String
    let confidence: Float
    let bounds: CGRect
}

enum AsciiArtStyle: String, Sendable {
    case layout
    case tone
}

enum AsciiOutputMode: Sendable, Equatable {
    case report
    case ocrOnly
}

enum ApplicationSelector: Sendable {
    case processID(pid_t)
    case name(String)

    init(rawValue: String) {
        if let processID = Int32(rawValue) {
            self = .processID(processID)
        } else {
            self = .name(rawValue)
        }
    }

    var label: String {
        switch self {
        case .processID(let processID):
            return "pid \(processID)"
        case .name(let name):
            return name
        }
    }

    var commandArgument: String {
        switch self {
        case .processID(let processID):
            return "\(processID)"
        case .name(let name):
            return name
        }
    }
}

enum LaunchTarget: Equatable, Sendable {
    case path(String)
    case bundleIdentifier(String)

    var rawValue: String {
        switch self {
        case .path(let path):
            return path
        case .bundleIdentifier(let bundleIdentifier):
            return bundleIdentifier
        }
    }
}

enum WindowSelection: Sendable {
    case frontmost
    case index(Int)
    case name(String)
}

enum AccessibilityMode: Sendable {
    case listWindows
    case listElements
    case elementAt(WindowPoint)
    case waitForWindow(String)
    case getElement(AccessibilitySelector)
    case waitForElement(AccessibilitySelector)
    case setValue(AccessibilitySelector, String)
    case typeText(String)
    case keyChord(KeyChord)
    case click(MouseClick)
    case drag(WindowDrag)
    case scroll(ScrollDelta, AccessibilitySelector?)
    case pressAt(WindowPoint)
    case pressElement(AccessibilitySelector)
    case raiseWindow
    case closeWindow
    case minimizeWindow
    case moveWindow(WindowPosition)
    case resizeWindow(WindowSize)
}

enum MenuBarMode: Sendable {
    case listItems
    case tree(MenuTreeOptions)
    case pressItem
    case pressMenuItem(MenuChildSelection)
    case captureMenu

    var envelopeMode: String {
        switch self {
        case .listItems:
            return "menu.items"
        case .tree:
            return "menu.tree"
        case .pressItem:
            return "menu.press"
        case .pressMenuItem:
            return "menu.press-item"
        case .captureMenu:
            return "menu.capture"
        }
    }

    var isCapture: Bool {
        if case .captureMenu = self {
            return true
        }

        return false
    }
}

struct MenuTreeOptions: Sendable {
    let depth: Int
    let childLimit: Int
}

enum MenuBarSelection: Sendable {
    case index(Int)
    case name(String)
}

private struct ParsedArguments {
    let region: CaptureRegion?
    let values: [String: String]
    let flags: Set<String>
}

private struct DisplayCapturePlan {
    let display: SCDisplay
    let intersectionRect: CGRect
    let pointPixelScale: CGFloat
}

private struct AppWindowCatalog {
    let application: SCRunningApplication
    let windows: [CatalogWindow]
}

private struct VisibleWindowCatalog {
    let application: AutomationApplication
    let windows: [VisibleCatalogWindow]
}

struct AutomationApplication {
    let name: String
    let bundleIdentifier: String
    let processID: pid_t
}

private struct CatalogWindow {
    let index: Int
    let windowID: CGWindowID
    let title: String?
    let frame: CGRect
    let layer: Int
    let isOnScreen: Bool
    let isActive: Bool
    let scWindow: SCWindow
}

struct VisibleCatalogWindow {
    let index: Int
    let windowID: CGWindowID
    let title: String?
    let frame: CGRect
    let layer: Int
}

private struct AccessibilityWindowCatalog {
    let application: AutomationApplication
    let frontmostApplication: AutomationApplication?
    let isFrontmostApplication: Bool
    let windows: [AccessibilityCatalogWindow]
}

private struct WaitedAccessibilityWindow {
    let catalog: AccessibilityWindowCatalog
    let window: AccessibilityCatalogWindow
}

private struct LaunchedApplication {
    let application: AutomationApplication
    let method: String
}

private final class OpenApplicationResult: @unchecked Sendable {
    var application: NSRunningApplication?
    var error: Error?
}

struct MenuBarItemCatalog {
    let application: AutomationApplication
    let items: [MenuBarCatalogItem]
}

private struct AccessibilityCatalogWindow {
    let index: Int
    let title: String?
    let frame: CGRect
    let isFocused: Bool
    let isMain: Bool
    let isFrontmostApplication: Bool
    let isFrontmostWindow: Bool
    let actions: [String]
    let element: AXUIElement
}

struct MenuBarCatalogItem {
    let index: Int
    let source: String
    let role: String?
    let subrole: String?
    let title: String?
    let description: String?
    let identifier: String?
    let frame: CGRect?
    let actions: [String]
    let childCount: Int
    let element: AXUIElement
}

struct WindowSnapshot {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let title: String?
    let bounds: CGRect
    let layer: Int
    let alpha: Double
}

enum MenuBarWindowCloseAttempt: Equatable, Sendable {
    case pressEscape(processID: pid_t, windowID: CGWindowID)
    case pressMenuBarItem(windowID: CGWindowID)
}

private struct RunningApplicationSearchResponse: Encodable {
    let query: String
    let matches: [RunningApplicationEntry]
}

struct DoctorResponse: Encodable {
    let screenRecording: Bool
    let accessibility: Bool
    let version: String
    let hostProcess: DoctorHostProcess
}

struct DoctorHostProcess: Encodable, Equatable {
    let processID: Int32
    let name: String
    let bundleIdentifier: String?
}

struct ClipboardResponse: Encodable {
    let action: String
    let text: String?
}

struct RevealResponse: Encodable {
    let path: String
}

private struct OpenFileResponse: Encodable {
    let path: String
    let applicationTarget: String?
    let method: String
    let application: WindowListApplication
    let waitForWindow: Bool
    let window: AccessibilityWindowEntry?
}

struct DisplayListResponse: Encodable {
    let displays: [DisplayEntry]
}

struct DisplayEntry: Encodable {
    let id: UInt32
    let frame: JSONRect
    let pixelWidth: Int
    let pixelHeight: Int
    let scale: Double
    let isMain: Bool
}

private struct ActivateApplicationResponse: Encodable {
    let application: WindowListApplication
    let activationRequestAccepted: Bool
}

private struct LaunchApplicationResponse: Encodable {
    let target: String
    let method: String
    let arguments: [String]
    let application: WindowListApplication
    let waitForWindow: Bool
    let window: AccessibilityWindowEntry?
}

private struct QuitApplicationResponse: Encodable {
    let application: WindowListApplication
    let force: Bool
    let terminationRequestAccepted: Bool
    let waitForTermination: Bool
    let terminated: Bool
}

private struct BasicEnvelope: Encodable {
    let mode: String
    let ok: Bool
    let version: String
}

private struct OutputEnvelope: Encodable {
    let mode: String
    let ok: Bool
    let output: String
    let version: String
}

private struct ReportEnvelope: Encodable {
    let mode: String
    let ok: Bool
    let report: String
    let version: String
}

private struct OutputReportEnvelope: Encodable {
    let mode: String
    let ok: Bool
    let output: String
    let report: String
    let version: String
}

private struct ErrorEnvelope: Encodable {
    let error: ErrorEntry
    let ok: Bool
    let version: String
}

private struct ErrorEntry: Encodable {
    let kind: String
    let message: String
    let exitCode: Int32
}

private struct RunningApplicationEntry: Encodable {
    let index: Int
    let processID: Int32
    let name: String
    let bundleIdentifier: String
    let activationPolicy: String
    let bundlePath: String?
    let executablePath: String?
    let visibleWindowCount: Int
}

private struct WindowListResponse: Encodable {
    let application: WindowListApplication
    let windows: [WindowListEntry]
}

private struct WindowListApplication: Encodable {
    let name: String
    let bundleIdentifier: String
    let processID: Int32
}

private struct WindowListEntry: Encodable {
    let index: Int
    let windowID: UInt32
    let title: String?
    let frame: JSONRect
    let layer: Int
    let isOnScreen: Bool
    let isActive: Bool
}

struct OCROnlyResponse: Encodable {
    let image: OCRImageEntry
    let blocks: [OCRTextBlockEntry]
    let error: String?
}

struct OCRImageEntry: Encodable {
    let path: String
    let width: Int
    let height: Int
}

struct OCRTextBlockEntry: Encodable {
    let text: String
    let confidence: Float
    let bounds: JSONRect
}

private struct VisibleWindowListResponse: Encodable {
    let application: WindowListApplication
    let captureSemantics: String
    let windows: [VisibleWindowEntry]
}

private struct VisibleWindowEntry: Encodable {
    let index: Int
    let windowID: UInt32
    let title: String?
    let frame: JSONRect
    let layer: Int
}

struct JSONRect: Encodable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }
}

private struct JSONPoint: Encodable {
    let x: Double
    let y: Double

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }
}

private struct JSONSize: Encodable {
    let width: Double
    let height: Double

    init(_ size: CGSize) {
        width = size.width
        height = size.height
    }
}

private struct AccessibilityTreeResponse: Encodable {
    let application: WindowListApplication
    let window: AccessibilityWindowEntry
    let tree: AccessibilityElementResponse
}

private struct AccessibilityFlatTreeResponse: Encodable {
    let application: WindowListApplication
    let window: AccessibilityWindowEntry
    let elements: [AccessibilityElementResponse]
}

private struct AccessibilityWindowListResponse: Encodable {
    let application: WindowListApplication
    let frontmostApplication: WindowListApplication?
    let frontnessSemantics: String
    let windows: [AccessibilityWindowEntry]
}

private struct AccessibilityWaitForWindowResponse: Encodable {
    let application: WindowListApplication
    let frontmostApplication: WindowListApplication?
    let mode: String
    let title: String
    let window: AccessibilityWindowEntry
}

private struct AccessibilityHitResponse: Encodable {
    let application: WindowListApplication
    let window: AccessibilityWindowEntry
    let point: JSONPoint
    let screenPoint: JSONPoint
    let hit: AccessibilityElementResponse
    let ancestors: [AccessibilityElementResponse]
}

private struct AccessibilitySelectorResponse: Encodable {
    let path: String?
    let role: String?
    let subrole: String?
    let title: String?
    let identifier: String?
    let description: String?
}

private struct AccessibilityGetResponse: Encodable {
    let application: WindowListApplication
    let window: AccessibilityWindowEntry
    let mode: String
    let selector: AccessibilitySelectorResponse
    let matched: AccessibilityElementResponse
    let ancestors: [AccessibilityElementResponse]
}

private struct AccessibilitySetValueResponse: Encodable {
    let application: WindowListApplication
    let window: AccessibilityWindowEntry
    let mode: String
    let attribute: String
    let value: String
    let selector: AccessibilitySelectorResponse
    let matched: AccessibilityElementResponse
    let ancestors: [AccessibilityElementResponse]
}

private struct KeyboardInputResponse: Encodable {
    let application: WindowListApplication
    let mode: String
    let text: String?
    let chord: String?
    let key: String?
    let modifiers: [String]?
    let activationRequestAccepted: Bool
}

private struct AccessibilityPressResponse: Encodable {
    let application: WindowListApplication
    let window: AccessibilityWindowEntry
    let mode: String
    let action: String
    let selector: AccessibilitySelectorResponse?
    let point: JSONPoint?
    let screenPoint: JSONPoint?
    let matched: AccessibilityElementResponse
    let pressed: AccessibilityElementResponse
    let ancestors: [AccessibilityElementResponse]
}

private struct MouseActionResponse: Encodable {
    let application: WindowListApplication
    let window: AccessibilityWindowEntry
    let mode: String
    let selector: AccessibilitySelectorResponse?
    let matched: AccessibilityElementResponse?
    let button: String?
    let clickCount: Int?
    let point: JSONPoint?
    let screenPoint: JSONPoint?
    let endPoint: JSONPoint?
    let screenEndPoint: JSONPoint?
    let deltaX: Int32?
    let deltaY: Int32?
    let activationRequestAccepted: Bool
    let windowRaiseAttempted: Bool
}

private struct AccessibilityRaiseWindowResponse: Encodable {
    let application: WindowListApplication
    let frontmostApplication: WindowListApplication?
    let window: AccessibilityWindowEntry
    let action: String
    let activationRequestAccepted: Bool
}

private struct AccessibilityCloseWindowResponse: Encodable {
    let application: WindowListApplication
    let window: AccessibilityWindowEntry
    let action: String
    let target: AccessibilityElementResponse
}

private struct AccessibilityMinimizeWindowResponse: Encodable {
    let application: WindowListApplication
    let window: AccessibilityWindowEntry
    let action: String
    let target: AccessibilityElementResponse
}

private struct AccessibilityMoveWindowResponse: Encodable {
    let application: WindowListApplication
    let window: AccessibilityWindowEntry
    let attribute: String
    let position: JSONPoint
    let updatedFrame: JSONRect?
}

private struct AccessibilityResizeWindowResponse: Encodable {
    let application: WindowListApplication
    let window: AccessibilityWindowEntry
    let attribute: String
    let size: JSONSize
    let updatedFrame: JSONRect?
}

private struct AccessibilityWindowEntry: Encodable {
    let index: Int
    let title: String?
    let frame: JSONRect
    let isFocused: Bool
    let isMain: Bool
    let isFrontmostApplication: Bool
    let isFrontmostWindow: Bool
    let actions: [String]
}

struct AccessibilityElementResponse: Encodable {
    let path: String?
    let role: String?
    let subrole: String?
    let title: String?
    let description: String?
    let identifier: String?
    let value: String?
    let enabled: Bool?
    let focused: Bool?
    let selected: Bool?
    let frame: JSONRect?
    let actions: [String]?
    let childCount: Int?
    let truncated: Bool?
    let children: [AccessibilityElementResponse]?
}

private struct MenuBarListResponse: Encodable {
    let application: WindowListApplication
    let items: [MenuBarItemEntry]
}

private struct MenuTreeResponse: Encodable {
    let application: WindowListApplication
    let items: [MenuTreeNode]
}

struct MenuTreeNode: Encodable {
    let path: String
    let index: Int?
    let source: String?
    let role: String?
    let subrole: String?
    let title: String?
    let description: String?
    let identifier: String?
    let enabled: Bool?
    let checked: Bool?
    let mark: String?
    let shortcut: MenuShortcut?
    let frame: JSONRect?
    let actions: [String]
    let childCount: Int
    let truncated: Bool?
    let children: [MenuTreeNode]?
}

struct MenuShortcut: Encodable, Equatable {
    let character: String?
    let virtualKey: Int?
    let glyph: Int?
    let modifierMask: UInt32?
    let modifiers: [String]?
}

private struct MenuBarPressResponse: Encodable {
    let application: WindowListApplication
    let item: MenuBarItemEntry
    let action: String
    let menu: AccessibilityElementResponse?
}

private struct MenuBarChildPressResponse: Encodable {
    let application: WindowListApplication
    let item: MenuBarItemEntry
    let action: String
    let menuItem: AccessibilityElementResponse
    let ancestors: [AccessibilityElementResponse]
}

private struct MenuBarItemEntry: Encodable {
    let index: Int
    let source: String
    let role: String?
    let subrole: String?
    let title: String?
    let description: String?
    let identifier: String?
    let frame: JSONRect?
    let actions: [String]
    let childCount: Int
}

private enum MenuBarSurface {
    case menu(AXUIElement)
    case window(WindowSnapshot)

    var frame: CGRect? {
        switch self {
        case .menu(let element):
            return copyAXFrame(from: element)
        case .window(let snapshot):
            return snapshot.bounds
        }
    }

    var kind: String {
        switch self {
        case .menu:
            return "AX menu"
        case .window:
            return "popover window"
        }
    }
}

private struct AccessibilityElementCandidate {
    let element: AXUIElement
    let depth: Int
    let role: String?
    let subrole: String?
    let title: String?
    let description: String?
    let identifier: String?
    let frame: CGRect?
    let actions: [String]
}

struct AXMutationOutcome {
    let error: AXError
    let postconditionSatisfied: Bool

    var accepted: Bool {
        error == .success || postconditionSatisfied
    }
}

func performAXMutationOnce(
    perform: () -> AXError,
    verifyPostcondition: (() -> Bool)? = nil,
    postconditionChecks: Int = 16,
    pollInterval: TimeInterval = 0.05,
    sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
) -> AXMutationOutcome {
    let error = perform()
    guard error != .success, let verifyPostcondition else {
        return AXMutationOutcome(error: error, postconditionSatisfied: false)
    }

    let checkCount = max(1, postconditionChecks)
    for checkIndex in 0..<checkCount {
        if verifyPostcondition() {
            return AXMutationOutcome(error: error, postconditionSatisfied: true)
        }

        if checkIndex < checkCount - 1 {
            sleep(pollInterval)
        }
    }

    return AXMutationOutcome(error: error, postconditionSatisfied: false)
}

func axErrorName(_ error: AXError) -> String {
    switch error.rawValue {
    case 0:
        return "kAXErrorSuccess"
    case -25200:
        return "kAXErrorFailure"
    case -25201:
        return "kAXErrorIllegalArgument"
    case -25202:
        return "kAXErrorInvalidUIElement"
    case -25203:
        return "kAXErrorInvalidUIElementObserver"
    case -25204:
        return "kAXErrorCannotComplete"
    case -25205:
        return "kAXErrorAttributeUnsupported"
    case -25206:
        return "kAXErrorActionUnsupported"
    case -25207:
        return "kAXErrorNotificationUnsupported"
    case -25208:
        return "kAXErrorNotImplemented"
    case -25209:
        return "kAXErrorNotificationAlreadyRegistered"
    case -25210:
        return "kAXErrorNotificationNotRegistered"
    case -25211:
        return "kAXErrorAPIDisabled"
    case -25212:
        return "kAXErrorNoValue"
    case -25213:
        return "kAXErrorParameterizedAttributeUnsupported"
    case -25214:
        return "kAXErrorNotEnoughPrecision"
    default:
        return "AXError"
    }
}

func formatAXError(_ error: AXError) -> String {
    "\(axErrorName(error)) (\(error.rawValue))"
}

func shouldAttemptAlternateMenuAction(
    primaryAccepted: Bool,
    menuStillVisible: Bool,
    itemStillReachable: Bool,
    supportsAlternateAction: Bool
) -> Bool {
    !primaryAccepted &&
    menuStillVisible &&
    itemStillReachable &&
    supportsAlternateAction
}

private struct RunningApplicationMatch {
    let application: NSRunningApplication
    let score: Int
    let visibleWindowCount: Int
    let activationRank: Int
}

enum BrrainzToolsError: LocalizedError, Sendable {
    case invalidArguments(String)
    case invalidInteger(flag: String, value: String)
    case invalidRegion(String)
    case capturePermissionDenied
    case accessibilityPermissionDenied
    case applicationNotFound(String)
    case ambiguousApplication(String)
    case windowNotFound(String)
    case ambiguousWindow(String)
    case pathNotFound(String)
    case openFailed(String)
    case launchFailed(String)
    case captureFailed(String)
    case operationTimedOut(String)
    case accessibilityQueryFailed(String)
    case encodeFailed(String)

    var kind: String {
        switch self {
        case .invalidArguments:
            return "invalidArguments"
        case .invalidInteger:
            return "invalidInteger"
        case .invalidRegion:
            return "invalidRegion"
        case .capturePermissionDenied:
            return "capturePermissionDenied"
        case .accessibilityPermissionDenied:
            return "accessibilityPermissionDenied"
        case .applicationNotFound:
            return "applicationNotFound"
        case .ambiguousApplication:
            return "ambiguousApplication"
        case .windowNotFound:
            return "windowNotFound"
        case .ambiguousWindow:
            return "ambiguousWindow"
        case .pathNotFound:
            return "pathNotFound"
        case .openFailed:
            return "openFailed"
        case .launchFailed:
            return "launchFailed"
        case .captureFailed:
            return "captureFailed"
        case .operationTimedOut:
            return "operationTimedOut"
        case .accessibilityQueryFailed:
            return "accessibilityQueryFailed"
        case .encodeFailed:
            return "encodeFailed"
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return message
        case .invalidInteger(let flag, let value):
            return "Expected an integer for \(flag), got `\(value)`."
        case .invalidRegion(let message):
            return message
        case .capturePermissionDenied:
            return "Screen Recording permission is required for app/window inspection and capture. Grant access and run the command again."
        case .accessibilityPermissionDenied:
            return "Accessibility permission is required for accessibility inspection and actions. Grant access and run the command again."
        case .applicationNotFound(let message):
            return message
        case .ambiguousApplication(let message):
            return message
        case .windowNotFound(let message):
            return message
        case .ambiguousWindow(let message):
            return message
        case .pathNotFound(let message):
            return message
        case .openFailed(let message):
            return message
        case .launchFailed(let message):
            return message
        case .captureFailed(let message):
            return message
        case .operationTimedOut(let message):
            return message
        case .accessibilityQueryFailed(let message):
            return message
        case .encodeFailed(let message):
            return message
        }
    }

    var exitCode: Int32 {
        switch self {
        case .invalidArguments, .invalidInteger, .invalidRegion:
            return 64
        case .ambiguousApplication, .ambiguousWindow:
            return 65
        case .applicationNotFound, .windowNotFound, .pathNotFound:
            return 66
        case .capturePermissionDenied, .accessibilityPermissionDenied:
            return 69
        case .openFailed, .launchFailed, .captureFailed, .accessibilityQueryFailed, .encodeFailed:
            return 70
        case .operationTimedOut:
            return 75
        }
    }
}

private let defaultScreenCaptureKitTimeout: TimeInterval = 5.0
private let defaultApplicationTerminationTimeout: TimeInterval = 5.0
private let defaultLayoutAsciiWidth = 160
private let defaultLayoutAsciiMaxHeight = 100
private let defaultToneAsciiWidth = 120
private let defaultToneAsciiMaxHeight = 80
private let asciiWidthRange = 16...240
private let asciiMaxHeightRange = 8...240
private let defaultImageOutputOptions = ImageOutputOptions(format: .png, jpegQuality: 0.8, maxDimension: nil)
private let imageMaxDimensionRange = 16...16384
private let maximumVisibleAppWindowLayer = 10
private let defaultAccessibilityTreeDepth = 4
private let defaultAccessibilityTreeChildLimit = 25
private let accessibilityTreeDepthRange = 0...12
private let accessibilityTreeChildLimitRange = 1...200
private let defaultMenuTreeDepth = accessibilityTreeDepthRange.upperBound
private let defaultMenuTreeChildLimit = accessibilityTreeChildLimitRange.upperBound

private let usageText = """
brrainztools = macOS desktop automation, inspection, and capture tool for agents and scripts.

Usage:
  brrainztools <subcommand> [options]

Subcommands:
  capture   pixel capture: regions, app windows, visible windows, displays
  apps      find running apps
  windows   list ScreenCaptureKit, visible, or AX windows
  ax        AX tree/get/press/input/window actions
  menu      menu-bar list/tree/press/press-item/capture
  ascii     image to ASCII/OCR text
  open-file open a document through macOS Launch Services
  reveal    select a file or directory in Finder
  displays | doctor | clipboard
  launch | activate | quit

Legacy flag-first forms are still accepted.
Run `brrainztools <subcommand> --help` for focused help.
"""

private let captureHelpText = """
Usage:
  brrainztools capture X Y WIDTH HEIGHT [options]
  brrainztools capture --x X --y Y --width WIDTH --height HEIGHT [options]
  brrainztools capture --display DISPLAY_ID [options]
  brrainztools capture --all-displays [options]
  brrainztools capture --app APP [--frontmost-window | --window-index N | --window-name TITLE] [options]
  brrainztools capture --app APP --visible-window [--window-index N | --window-name TITLE | --frontmost-window] [options]

Options:
  --output FILE
  --timeout SECONDS
  --format png|jpeg
  --quality 0...1
  --max-dimension N
  --window-crop X,Y,W,H
  --with-ascii | --with-ocr
  --raw
"""

private let appsHelpText = """
Usage:
  brrainztools apps QUERY

Find running apps by name, bundle id, path, or pid. Equivalent legacy form:
  brrainztools --find-app QUERY
"""

private let windowsHelpText = """
Usage:
  brrainztools windows --app APP
  brrainztools windows --app APP --visible
  brrainztools windows --app APP --ax

Modes:
  default    ScreenCaptureKit app windows
  --visible currently visible app windows from the window stack
  --ax      Accessibility windows
"""

private let axHelpText = """
Usage:
  brrainztools ax --app APP ACTION [selectors/options]

Actions:
  windows
  tree
  get
  wait-for-window TITLE
  wait-for-element
  set-value TEXT
  type TEXT
  key CHORD
  press
  press-at X,Y
  element-at X,Y
  click X,Y [--right] [--double]
  drag X1,Y1,X2,Y2
  scroll DX,DY [selectors]
  raise
  close
  minimize
  move X,Y
  resize W,H

Selectors/options:
  --path PATH
  --role ROLE
  --subrole SUBROLE
  --title TITLE
  --identifier ID
  --description TEXT
  --window-index N | --window-name TITLE | --frontmost-window
  --depth N --max-children N --roles ROLE[,ROLE...] --interactive --flat
  --timeout SECONDS
  --no-prompt

Element selectors apply to get, wait-for-element, set-value, scroll, and press.
"""

private let menuHelpText = """
Usage:
  brrainztools menu --app APP list
  brrainztools menu --app APP tree [--depth N] [--max-children N] [--menu-bar-index N | --menu-bar-item TEXT]
  brrainztools menu --app APP press [--menu-bar-index N | --menu-bar-item TEXT]
  brrainztools menu --app APP press-item TEXT [--menu-bar-index N | --menu-bar-item TEXT]
  brrainztools menu --app APP capture [--menu-bar-index N | --menu-bar-item TEXT] [capture options]

Capture options:
  --output FILE
  --timeout SECONDS
  --format png|jpeg
  --quality 0...1
  --max-dimension N
  --with-ascii | --with-ocr
  --raw
  --no-prompt

`tree` recursively inspects the exposed menu hierarchy without opening menus,
pressing items, or activating the selected app.
"""

private let asciiHelpText = """
Usage:
  brrainztools ascii IMAGE [options]

Options:
  --ascii-style layout|tone
  --ascii-width N
  --ascii-max-height N
  --ascii-language CODE[,CODE...]
  --ascii-invert
  --ascii-no-ocr
  --ocr-only
  --raw
"""

private let displaysHelpText = """
Usage:
  brrainztools displays
  brrainztools capture --display DISPLAY_ID [capture options]
  brrainztools capture --all-displays [capture options]

`brrainztools displays` returns active display ids, point frames, pixel sizes,
scale, and main-display status.
"""

private let doctorHelpText = """
Usage:
  brrainztools doctor

Checks Screen Recording and Accessibility permission status without prompting,
and reports the host process that macOS permissions apply to.
"""

private let clipboardHelpText = """
Usage:
  brrainztools clipboard
  brrainztools clipboard --set TEXT

Reads or sets plain text on the general pasteboard.
"""

private let revealHelpText = """
Usage:
  brrainztools reveal PATH

Opens Finder and selects the file or directory at PATH. Relative paths and `~`
are resolved before Finder is asked to reveal the item.
"""

private let openFileHelpText = """
Usage:
  brrainztools open-file PATH [--app PATH|BUNDLE_ID] [--wait-window [--no-prompt]] [--timeout SECONDS]
  brrainztools --open-file PATH [--app PATH|BUNDLE_ID] [--wait-window [--no-prompt]] [--timeout SECONDS]

Asks macOS to open PATH as a document, using its default app unless `--app`
specifies an app bundle path or bundle id. `--wait-window` waits for the app's
first Accessibility window.
"""

private let launchHelpText = """
Usage:
  brrainztools launch PATH|BUNDLE_ID [--wait-window [--no-prompt]] [--timeout SECONDS] [--args ARG ...]

Starts an app bundle, bundle id, or executable path. `--wait-window` waits for
the launched app's first Accessibility window.
"""

private let activateHelpText = """
Usage:
  brrainztools activate --app APP
  brrainztools activate --app-name NAME
  brrainztools activate --pid PID

Activates a running app.
"""

private let quitHelpText = """
Usage:
  brrainztools quit --app APP [--force] [--wait [--timeout SECONDS]]
  brrainztools quit --app-name NAME [--force] [--wait [--timeout SECONDS]]
  brrainztools quit --pid PID [--force] [--wait [--timeout SECONDS]]

Asks a running app to terminate; `--force` force-terminates it. `--wait`
returns only after termination is observed, or fails when `--timeout` expires.
"""

private let agentSupportSkillName = "brrainztools"
private let agentSupportDirectoryName = "AgentSupport"
private let managedAgentInstructionsStartMarker = "<!-- brrainztools-managed:start -->"
private let managedAgentInstructionsEndMarker = "<!-- brrainztools-managed:end -->"
private let agentSupportDebugEnvironmentKey = "BRRAINZTOOLS_DEBUG_AGENT_SYNC"
// Artifacts written by pre-rename RegionShot installs; the sync path removes them wherever it runs.
private let legacyAgentSupportSkillName = "regionshot"
private let legacyManagedAgentInstructionsStartMarker = "<!-- regionshot-managed:start -->"
private let legacyManagedAgentInstructionsEndMarker = "<!-- regionshot-managed:end -->"
private let brrainzToolsFallbackVersion = "v2.1.0"
private let brrainzToolsVersionEnvironmentKey = "BRRAINZTOOLS_VERSION"
private let brrainzToolsSupportDirectoryName = ".brrainztools-support"
private let brrainzToolsSupportVersionFilename = "VERSION"

private let cachedBrrainzToolsVersion: String = brrainzToolsVersion(
    environment: ProcessInfo.processInfo.environment,
    executableDirectory: currentExecutableURL()?.deletingLastPathComponent(),
    currentDirectoryURL: URL(
        fileURLWithPath: FileManager.default.currentDirectoryPath,
        isDirectory: true
    ),
    readTextFile: readTextFileIfPresent,
    gitDescribe: gitDescribeVersion
)

private func currentBrrainzToolsVersion() -> String {
    cachedBrrainzToolsVersion
}

func brrainzToolsVersion(
    environment: [String: String],
    executableDirectory: URL?,
    currentDirectoryURL: URL,
    readTextFile: (URL) -> String?,
    gitDescribe: (URL) -> String?
) -> String {
    if let environmentVersion = normalizedVersion(environment[brrainzToolsVersionEnvironmentKey]) {
        return environmentVersion
    }

    if
        let executableDirectory,
        let supportVersion = normalizedVersion(
            readTextFile(
                executableDirectory
                    .appendingPathComponent(brrainzToolsSupportDirectoryName, isDirectory: true)
                    .appendingPathComponent(brrainzToolsSupportVersionFilename)
            )
        )
    {
        return supportVersion
    }

    if
        let repositoryURL = brrainzToolsRepositoryRoot(
            containing: currentDirectoryURL,
            readTextFile: readTextFile
        ),
        let gitVersion = normalizedVersion(gitDescribe(repositoryURL))
    {
        return gitVersion
    }

    return brrainzToolsFallbackVersion
}

private func brrainzToolsRepositoryRoot(
    containing currentDirectoryURL: URL,
    readTextFile: (URL) -> String?
) -> URL? {
    var candidate = currentDirectoryURL.standardizedFileURL

    while true {
        let manifestURL = candidate.appendingPathComponent("Package.swift")
        if
            let manifest = readTextFile(manifestURL),
            packageManifestDeclaresBrrainzTools(manifest)
        {
            return candidate
        }

        let parent = candidate.deletingLastPathComponent()
        if parent.path == candidate.path {
            return nil
        }

        candidate = parent
    }
}

private func packageManifestDeclaresBrrainzTools(_ manifest: String) -> Bool {
    manifest.range(
        of: #"name\s*:\s*"BrrainzTools""#,
        options: .regularExpression
    ) != nil
}

private func normalizedVersion(_ rawValue: String?) -> String? {
    guard let rawValue else {
        return nil
    }

    let version = rawValue
        .components(separatedBy: .newlines)
        .first?
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard let version, !version.isEmpty else {
        return nil
    }

    return version
}

private func readTextFileIfPresent(at url: URL) -> String? {
    try? String(contentsOf: url, encoding: .utf8)
}

private func gitDescribeVersion(repositoryURL: URL) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = [
        "-C",
        repositoryURL.path,
        "describe",
        "--tags",
        "--always",
        "--dirty",
    ]

    let standardOutput = Pipe()
    let standardError = Pipe()
    process.standardOutput = standardOutput
    process.standardError = standardError

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return nil
    }

    guard process.terminationStatus == 0 else {
        return nil
    }

    return String(
        decoding: standardOutput.fileHandleForReading.readDataToEndOfFile(),
        as: UTF8.self
    )
}

private func currentDoctorStatus() -> DoctorResponse {
    doctorStatus(
        screenRecordingAccess: { CGPreflightScreenCaptureAccess() },
        accessibilityTrusted: { AXIsProcessTrusted() },
        version: currentBrrainzToolsVersion,
        hostProcess: currentHostProcess
    )
}

func doctorStatus(
    screenRecordingAccess: () -> Bool,
    accessibilityTrusted: () -> Bool,
    version: () -> String,
    hostProcess: () -> DoctorHostProcess
) -> DoctorResponse {
    DoctorResponse(
        screenRecording: screenRecordingAccess(),
        accessibility: accessibilityTrusted(),
        version: version(),
        hostProcess: hostProcess()
    )
}

private func currentHostProcess() -> DoctorHostProcess {
    let parentProcessID = getppid()
    let runningApplication = NSRunningApplication(processIdentifier: parentProcessID)

    return DoctorHostProcess(
        processID: parentProcessID,
        name: runningApplication?.localizedName ?? "pid \(parentProcessID)",
        bundleIdentifier: runningApplication?.bundleIdentifier
    )
}

func handleClipboard(using command: ClipboardCommand) throws -> String {
    let pasteboard = NSPasteboard.general

    if let setText = command.setText {
        pasteboard.clearContents()
        guard pasteboard.setString(setText, forType: .string) else {
            throw BrrainzToolsError.captureFailed("Failed to write text to the clipboard.")
        }

        return try encodeJSON(ClipboardResponse(action: "set", text: setText))
    }

    return try encodeJSON(
        ClipboardResponse(
            action: "read",
            text: pasteboard.string(forType: .string)
        )
    )
}

func reveal(
    using command: RevealCommand,
    fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
    revealURLs: ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) }
) throws -> String {
    let url = fileURL(from: command.path)

    guard fileExists(url.path) else {
        throw BrrainzToolsError.pathNotFound("No file or directory exists at `\(url.path)`.")
    }

    revealURLs([url])
    return try encodeJSON(RevealResponse(path: url.path))
}

func openFile(
    using command: OpenFileCommand,
    pathStatus: (String) -> (exists: Bool, isDirectory: Bool) = { path in
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return (exists, isDirectory.boolValue)
    },
    openDocument: (URL, LaunchTarget?) throws -> (application: AutomationApplication, method: String) = { url, target in
        let opened = try openDocument(at: url, with: target)
        return (opened.application, opened.method)
    }
) throws -> String {
    let url = fileURL(from: command.path)
    let status = pathStatus(url.path)

    guard status.exists else {
        throw BrrainzToolsError.pathNotFound("No file exists at `\(url.path)`.")
    }

    guard !status.isDirectory else {
        throw BrrainzToolsError.openFailed("Open-file path `\(url.path)` is a directory, not a document.")
    }

    let opened = try openDocument(url, command.applicationTarget)
    let waitedWindow: AccessibilityWindowEntry?

    if command.waitForWindow {
        try ensureAccessibilityAccess(prompt: command.promptForAccessibility)
        let waited = try waitForAnyAccessibilityWindow(
            selector: .processID(opened.application.processID),
            timeout: command.timeout
        )
        waitedWindow = accessibilityWindowEntry(for: waited.window)
    } else {
        waitedWindow = nil
    }

    return try encodeJSON(
        OpenFileResponse(
            path: url.path,
            applicationTarget: command.applicationTarget?.rawValue,
            method: opened.method,
            application: windowListApplication(for: opened.application),
            waitForWindow: command.waitForWindow,
            window: waitedWindow
        )
    )
}

func listDisplays() throws -> String {
    try encodeJSON(DisplayListResponse(displays: currentDisplayEntries()))
}

func activate(using command: ActivateApplicationCommand) throws -> String {
    let application = try resolveAutomationApplication(selector: command.applicationSelector)
    let accepted = activateApplication(application)
    return try encodeJSON(
        ActivateApplicationResponse(
            application: windowListApplication(for: application),
            activationRequestAccepted: accepted
        )
    )
}

func launch(using command: LaunchApplicationCommand) throws -> String {
    let launched = try launchApplication(target: command.target, arguments: command.arguments)
    let waitedWindow: AccessibilityWindowEntry?

    if command.waitForWindow {
        try ensureAccessibilityAccess(prompt: command.promptForAccessibility)
        let waited = try waitForAnyAccessibilityWindow(
            selector: .processID(launched.application.processID),
            timeout: command.timeout
        )
        waitedWindow = accessibilityWindowEntry(for: waited.window)
    } else {
        waitedWindow = nil
    }

    return try encodeJSON(
        LaunchApplicationResponse(
            target: command.target.rawValue,
            method: launched.method,
            arguments: command.arguments,
            application: windowListApplication(for: launched.application),
            waitForWindow: command.waitForWindow,
            window: waitedWindow
        )
    )
}

func quit(using command: QuitApplicationCommand) throws -> String {
    let application = try resolveAutomationApplication(selector: command.applicationSelector)
    let runningApplication = NSRunningApplication(processIdentifier: application.processID)
    let accepted = command.force
        ? (runningApplication?.forceTerminate() ?? false)
        : (runningApplication?.terminate() ?? false)
    var terminated = applicationHasTerminated(
        runningApplication,
        processID: application.processID
    )

    if command.waitForTermination, !terminated {
        terminated = waitForApplicationTermination(
            timeout: command.timeout,
            isTerminated: {
                applicationHasTerminated(
                    runningApplication,
                    processID: application.processID
                )
            }
        )

        guard terminated else {
            let requestKind = command.force ? "force-termination" : "termination"
            let acceptance = accepted ? "accepted" : "did not accept"
            let recovery = command.force
                ? "Retry with a longer `--timeout` if the process needs more time to exit."
                : "Retry with `--force --wait` or a longer `--timeout`."
            throw BrrainzToolsError.operationTimedOut(
                "`\(application.name)` (pid \(application.processID)) did not terminate within \(formatSeconds(command.timeout)); macOS \(acceptance) the \(requestKind) request. \(recovery)"
            )
        }
    }

    return try encodeJSON(
        QuitApplicationResponse(
            application: windowListApplication(for: application),
            force: command.force,
            terminationRequestAccepted: accepted,
            waitForTermination: command.waitForTermination,
            terminated: terminated
        )
    )
}

private func applicationHasTerminated(
    _ runningApplication: NSRunningApplication?,
    processID: pid_t
) -> Bool {
    if runningApplication?.isTerminated == true {
        return true
    }

    if let currentApplication = NSRunningApplication(processIdentifier: processID) {
        return currentApplication.isTerminated
    }

    errno = 0
    return Darwin.kill(processID, 0) != 0 && errno == ESRCH
}

func waitForApplicationTermination(
    timeout: TimeInterval,
    pollInterval: TimeInterval = 0.05,
    now: () -> Date = Date.init,
    sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
    isTerminated: () -> Bool
) -> Bool {
    let deadline = now().addingTimeInterval(timeout)

    while true {
        if isTerminated() {
            return true
        }

        let remaining = deadline.timeIntervalSince(now())
        guard remaining > 0 else {
            return false
        }

        sleep(min(pollInterval, remaining))
    }
}

private func launchApplication(target: LaunchTarget, arguments: [String]) throws -> LaunchedApplication {
    switch target {
    case .bundleIdentifier(let bundleIdentifier):
        guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw BrrainzToolsError.applicationNotFound("No application bundle matches bundle id `\(bundleIdentifier)`.")
        }

        let application = try openApplication(at: applicationURL, arguments: arguments)
        return LaunchedApplication(application: automationApplication(from: application), method: "bundleIdentifier")

    case .path(let path):
        let url = fileURL(from: path)
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw BrrainzToolsError.applicationNotFound("No application or executable exists at `\(url.path)`.")
        }

        if isDirectory.boolValue {
            guard url.pathExtension.lowercased() == "app" else {
                throw BrrainzToolsError.launchFailed("Launch path `\(url.path)` is a directory, not an app bundle or executable.")
            }

            let application = try openApplication(at: url, arguments: arguments)
            return LaunchedApplication(application: automationApplication(from: application), method: "applicationBundle")
        }

        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw BrrainzToolsError.launchFailed("Launch path `\(url.path)` is not executable.")
        }

        let process = Process()
        process.executableURL = url
        process.arguments = arguments
        if let nullDevice = FileHandle(forWritingAtPath: "/dev/null") {
            process.standardOutput = nullDevice
            process.standardError = nullDevice
        }

        do {
            try process.run()
        } catch {
            throw BrrainzToolsError.launchFailed("Failed to launch executable `\(url.path)`: \(error.localizedDescription)")
        }

        let processID = process.processIdentifier
        let application = NSRunningApplication(processIdentifier: processID)
            .map(automationApplication(from:)) ??
            AutomationApplication(name: url.lastPathComponent, bundleIdentifier: "", processID: processID)

        return LaunchedApplication(application: application, method: "executable")
    }
}

private func openDocument(at documentURL: URL, with applicationTarget: LaunchTarget?) throws -> LaunchedApplication {
    let configuration = NSWorkspace.OpenConfiguration()
    let result = OpenApplicationResult()
    let semaphore = DispatchSemaphore(value: 0)
    let method: String

    if let applicationTarget {
        let resolved = try resolveApplicationURL(for: applicationTarget)
        method = resolved.method
        NSWorkspace.shared.open(
            [documentURL],
            withApplicationAt: resolved.url,
            configuration: configuration
        ) { application, error in
            result.application = application
            result.error = error
            semaphore.signal()
        }
    } else {
        method = "defaultApplication"
        NSWorkspace.shared.open(documentURL, configuration: configuration) { application, error in
            result.application = application
            result.error = error
            semaphore.signal()
        }
    }

    guard semaphore.wait(timeout: .now() + 10) == .success else {
        throw BrrainzToolsError.operationTimedOut(
            "macOS did not return open status for `\(documentURL.path)` within 10 seconds."
        )
    }

    if let error = result.error {
        throw BrrainzToolsError.openFailed(
            "Failed to open `\(documentURL.path)`: \(error.localizedDescription)"
        )
    }

    guard let application = result.application else {
        throw BrrainzToolsError.openFailed(
            "macOS did not return the application handling `\(documentURL.path)`."
        )
    }

    return LaunchedApplication(
        application: automationApplication(from: application),
        method: method
    )
}

private func resolveApplicationURL(for target: LaunchTarget) throws -> (url: URL, method: String) {
    switch target {
    case .bundleIdentifier(let bundleIdentifier):
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw BrrainzToolsError.applicationNotFound(
                "No application bundle matches bundle id `\(bundleIdentifier)`."
            )
        }
        return (url, "bundleIdentifier")

    case .path(let path):
        let url = fileURL(from: path)
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw BrrainzToolsError.applicationNotFound(
                "No application bundle exists at `\(url.path)`."
            )
        }
        guard isDirectory.boolValue, url.pathExtension.lowercased() == "app" else {
            throw BrrainzToolsError.openFailed(
                "Open-file app path `\(url.path)` is not an app bundle."
            )
        }
        return (url, "applicationBundle")
    }
}

private func openApplication(at applicationURL: URL, arguments: [String]) throws -> NSRunningApplication {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.arguments = arguments

    let result = OpenApplicationResult()
    let semaphore = DispatchSemaphore(value: 0)

    NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { application, error in
        result.application = application
        result.error = error
        semaphore.signal()
    }

    guard semaphore.wait(timeout: .now() + 10) == .success else {
        throw BrrainzToolsError.operationTimedOut("macOS did not return launch status for `\(applicationURL.path)` within 10 seconds.")
    }

    if let error = result.error {
        throw BrrainzToolsError.launchFailed("Failed to launch `\(applicationURL.path)`: \(error.localizedDescription)")
    }

    guard let application = result.application else {
        throw BrrainzToolsError.launchFailed("macOS did not return a running application for `\(applicationURL.path)`.")
    }

    return application
}

func currentDisplayEntries() -> [DisplayEntry] {
    activeDisplayIDs()
        .map(displayEntry(for:))
        .sorted(by: displayEntrySort)
}

private func activeDisplayFrames() -> [(id: CGDirectDisplayID, frame: CGRect)] {
    activeDisplayIDs().map { displayID in
        (id: displayID, frame: CGDisplayBounds(displayID))
    }
}

private func activeDisplayIDs() -> [CGDirectDisplayID] {
    var displayCount: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
        return []
    }

    var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
    let error = displayIDs.withUnsafeMutableBufferPointer { buffer in
        CGGetActiveDisplayList(displayCount, buffer.baseAddress, &displayCount)
    }

    guard error == .success else {
        return []
    }

    return Array(displayIDs.prefix(Int(displayCount)))
}

private func displayEntry(for displayID: CGDirectDisplayID) -> DisplayEntry {
    let frame = CGDisplayBounds(displayID)
    let displayMode = CGDisplayCopyDisplayMode(displayID)
    let pixelWidth = displayMode.map { Int($0.pixelWidth) } ?? Int(CGDisplayPixelsWide(displayID))
    let pixelHeight = displayMode.map { Int($0.pixelHeight) } ?? Int(CGDisplayPixelsHigh(displayID))
    let scale = frame.width > 0 ? Double(pixelWidth) / Double(frame.width) : 1

    return DisplayEntry(
        id: displayID,
        frame: JSONRect(frame),
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        scale: scale,
        isMain: displayID == CGMainDisplayID()
    )
}

private func displayEntrySort(_ left: DisplayEntry, _ right: DisplayEntry) -> Bool {
    if left.isMain != right.isMain {
        return left.isMain && !right.isMain
    }

    if left.frame.y != right.frame.y {
        return left.frame.y < right.frame.y
    }

    if left.frame.x != right.frame.x {
        return left.frame.x < right.frame.x
    }

    return left.id < right.id
}

private func synchronizeAgentSupportIfAvailable() {
    do {
        try installOrUpdateAgentSupportIfAvailable()
    } catch {
        let environment = ProcessInfo.processInfo.environment
        if environment[agentSupportDebugEnvironmentKey] == "1" {
            writeStandardError("warning: failed to sync BrrainzTools agent support files: \(error.localizedDescription)\n")
        }
    }
}

private func installOrUpdateAgentSupportIfAvailable() throws {
    guard let supportSourceDirectory = findAgentSupportDirectory() else {
        return
    }

    let skillSourceDirectory = supportSourceDirectory
        .appendingPathComponent("skills", isDirectory: true)
        .appendingPathComponent(agentSupportSkillName, isDirectory: true)
    let pointerSourceURL = supportSourceDirectory.appendingPathComponent("AGENTS.pointer.md")

    let fileManager = FileManager.default
    guard
        fileManager.fileExists(atPath: skillSourceDirectory.appendingPathComponent("SKILL.md").path),
        fileManager.fileExists(atPath: pointerSourceURL.path)
    else {
        return
    }

    let codexHomeDirectory = fileManager.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex", isDirectory: true)
    let codexSkillDestinationDirectory = codexHomeDirectory
        .appendingPathComponent("skills", isDirectory: true)
        .appendingPathComponent(agentSupportSkillName, isDirectory: true)
    let agentsDestinationURL = codexHomeDirectory.appendingPathComponent("AGENTS.md")

    let claudeHomeDirectory = fileManager.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude", isDirectory: true)
    let claudeSkillDestinationDirectory = claudeHomeDirectory
        .appendingPathComponent("skills", isDirectory: true)
        .appendingPathComponent(agentSupportSkillName, isDirectory: true)
    let claudeDestinationURL = claudeHomeDirectory.appendingPathComponent("CLAUDE.md")

    removeLegacySkillDirectories(under: [codexHomeDirectory, claudeHomeDirectory])

    try syncDirectoryIfNeeded(from: skillSourceDirectory, to: codexSkillDestinationDirectory)
    try syncDirectoryIfNeeded(
        from: skillSourceDirectory,
        to: claudeSkillDestinationDirectory,
        excludingRelativePathPrefixes: ["agents/"]
    )

    let pointerBody = try String(contentsOf: pointerSourceURL, encoding: .utf8)
    try upsertManagedAgentInstructions(pointerBody, at: agentsDestinationURL)
    try upsertManagedAgentInstructions(pointerBody, at: claudeDestinationURL)
}

private func removeLegacySkillDirectories(under agentHomeDirectories: [URL]) {
    let fileManager = FileManager.default

    for agentHomeDirectory in agentHomeDirectories {
        let legacySkillDirectory = agentHomeDirectory
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent(legacyAgentSupportSkillName, isDirectory: true)

        if fileManager.fileExists(atPath: legacySkillDirectory.path) {
            try? fileManager.removeItem(at: legacySkillDirectory)
        }
    }
}

private func findAgentSupportDirectory() -> URL? {
    let fileManager = FileManager.default

    for candidate in agentSupportCandidates() {
        let standardizedCandidate = candidate.standardizedFileURL
        guard fileManager.fileExists(atPath: standardizedCandidate.path) else {
            continue
        }

        let skillDirectory = standardizedCandidate
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent(agentSupportSkillName, isDirectory: true)
        let skillFileURL = skillDirectory.appendingPathComponent("SKILL.md")
        let pointerFileURL = standardizedCandidate.appendingPathComponent("AGENTS.pointer.md")

        if fileManager.fileExists(atPath: skillFileURL.path), fileManager.fileExists(atPath: pointerFileURL.path) {
            return standardizedCandidate
        }
    }

    return nil
}

private func agentSupportCandidates() -> [URL] {
    var candidates: [URL] = []

    if let executableDirectory = currentExecutableURL()?.deletingLastPathComponent() {
        appendInstalledAgentSupportDirectories(startingAt: executableDirectory, to: &candidates)
        appendAncestorAgentSupportDirectories(startingAt: executableDirectory, to: &candidates)
    }

    let currentDirectory = URL(
        fileURLWithPath: FileManager.default.currentDirectoryPath,
        isDirectory: true
    )
    appendAncestorAgentSupportDirectories(startingAt: currentDirectory, to: &candidates)

    var deduplicated: [URL] = []
    var seenPaths: Set<String> = []
    for candidate in candidates {
        let path = candidate.standardizedFileURL.path
        if seenPaths.insert(path).inserted {
            deduplicated.append(candidate.standardizedFileURL)
        }
    }

    return deduplicated
}

private func appendInstalledAgentSupportDirectories(startingAt directory: URL, to candidates: inout [URL]) {
    let supportDirectory = directory.appendingPathComponent(brrainzToolsSupportDirectoryName, isDirectory: true)
    candidates.append(supportDirectory.appendingPathComponent(agentSupportDirectoryName, isDirectory: true))
}

private func appendAncestorAgentSupportDirectories(startingAt directory: URL, to candidates: inout [URL]) {
    var currentPath = directory.standardizedFileURL.path

    while true {
        let currentDirectoryURL = URL(fileURLWithPath: currentPath, isDirectory: true)
        candidates.append(currentDirectoryURL.appendingPathComponent(agentSupportDirectoryName, isDirectory: true))

        let parentPath = (currentPath as NSString).deletingLastPathComponent
        if parentPath.isEmpty || parentPath == currentPath {
            break
        }

        currentPath = parentPath
    }
}

private func currentExecutableURL() -> URL? {
    var size: UInt32 = 0
    _ = _NSGetExecutablePath(nil, &size)

    var buffer = [CChar](repeating: 0, count: Int(size))
    guard _NSGetExecutablePath(&buffer, &size) == 0 else {
        return nil
    }

    let executablePathBytes = buffer
        .prefix { $0 != 0 }
        .map { UInt8(bitPattern: $0) }
    let executablePath = String(decoding: executablePathBytes, as: UTF8.self)

    return URL(fileURLWithPath: executablePath)
        .resolvingSymlinksInPath()
        .standardizedFileURL
}

private func syncDirectoryIfNeeded(
    from sourceDirectory: URL,
    to destinationDirectory: URL,
    excludingRelativePathPrefixes: Set<String> = []
) throws {
    let fileManager = FileManager.default

    if try directoriesMatch(
        sourceDirectory,
        destinationDirectory,
        excludingRelativePathPrefixes: excludingRelativePathPrefixes
    ) {
        return
    }

    try fileManager.createDirectory(
        at: destinationDirectory.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    if fileManager.fileExists(atPath: destinationDirectory.path) {
        try fileManager.removeItem(at: destinationDirectory)
    }

    try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

    for relativePath in try regularFiles(in: sourceDirectory)
        where !isExcludedRelativePath(relativePath, prefixes: excludingRelativePathPrefixes) {
        let sourceFileURL = sourceDirectory.appendingPathComponent(relativePath)
        let destinationFileURL = destinationDirectory.appendingPathComponent(relativePath)
        try fileManager.createDirectory(
            at: destinationFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: sourceFileURL, to: destinationFileURL)
    }
}

private func directoriesMatch(
    _ sourceDirectory: URL,
    _ destinationDirectory: URL,
    excludingRelativePathPrefixes: Set<String> = []
) throws -> Bool {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false

    guard fileManager.fileExists(atPath: destinationDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        return false
    }

    let sourceFiles = try regularFiles(in: sourceDirectory)
        .filter { !isExcludedRelativePath($0, prefixes: excludingRelativePathPrefixes) }
    let destinationFiles = try regularFiles(in: destinationDirectory)
    guard sourceFiles == destinationFiles else {
        return false
    }

    for relativePath in sourceFiles {
        let sourceFileURL = sourceDirectory.appendingPathComponent(relativePath)
        let destinationFileURL = destinationDirectory.appendingPathComponent(relativePath)

        if !fileManager.contentsEqual(atPath: sourceFileURL.path, andPath: destinationFileURL.path) {
            return false
        }
    }

    return true
}

func isExcludedRelativePath(_ relativePath: String, prefixes: Set<String>) -> Bool {
    prefixes.contains { prefix in
        let directoryName = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
        return relativePath == directoryName || relativePath.hasPrefix(prefix)
    }
}

private func regularFiles(in directory: URL) throws -> [String] {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    let directoryPathPrefix = directory.standardizedFileURL.path + "/"
    var files: [String] = []

    for case let fileURL as URL in enumerator {
        let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
        guard resourceValues.isRegularFile == true else {
            continue
        }

        let filePath = fileURL.standardizedFileURL.path
        if filePath.hasPrefix(directoryPathPrefix) {
            files.append(String(filePath.dropFirst(directoryPathPrefix.count)))
        }
    }

    return files.sorted()
}

private func upsertManagedAgentInstructions(_ pointerBody: String, at agentsURL: URL) throws {
    let trimmedPointerBody = pointerBody.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedPointerBody.isEmpty else {
        return
    }

    let managedBlock = """
    \(managedAgentInstructionsStartMarker)
    \(trimmedPointerBody)
    \(managedAgentInstructionsEndMarker)
    """

    let fileManager = FileManager.default
    let existingContents = (try? String(contentsOf: agentsURL, encoding: .utf8)) ?? ""
    let updatedContents = updatedAgentsContents(
        from: existingContents,
        managedBlock: managedBlock,
        legacyPointerBody: trimmedPointerBody
    )

    guard updatedContents != existingContents else {
        return
    }

    try fileManager.createDirectory(
        at: agentsURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try updatedContents.write(to: agentsURL, atomically: true, encoding: .utf8)
}

func updatedAgentsContents(
    from existingContents: String,
    managedBlock: String,
    legacyPointerBody: String
) -> String {
    let existingContents = removingLegacyManagedAgentInstructions(from: existingContents)
    let normalizedExistingContents = normalizeManagedText(existingContents)
    let legacyStandaloneContents = normalizeManagedText("""
    # User Environment Notes

    \(legacyPointerBody)
    """)

    if normalizedExistingContents.isEmpty || normalizedExistingContents == legacyStandaloneContents {
        return """
        # User Environment Notes

        \(managedBlock)
        """
    }

    if let managedRange = managedAgentsRange(in: existingContents) {
        var updatedContents = existingContents
        updatedContents.replaceSubrange(managedRange, with: managedBlock)
        return ensureTrailingNewline(in: updatedContents)
    }

    return ensureTrailingNewline(in: existingContents) + "\n\(managedBlock)\n"
}

private func removingLegacyManagedAgentInstructions(from contents: String) -> String {
    var updatedContents = contents

    while
        let startRange = updatedContents.range(of: legacyManagedAgentInstructionsStartMarker),
        let endRange = updatedContents.range(
            of: legacyManagedAgentInstructionsEndMarker,
            range: startRange.upperBound..<updatedContents.endIndex
        )
    {
        updatedContents.removeSubrange(startRange.lowerBound..<endRange.upperBound)
    }

    guard updatedContents != contents else {
        return contents
    }

    return updatedContents.replacingOccurrences(
        of: #"\n{3,}"#,
        with: "\n\n",
        options: .regularExpression
    )
}

private func managedAgentsRange(in contents: String) -> Range<String.Index>? {
    guard let startRange = contents.range(of: managedAgentInstructionsStartMarker) else {
        return nil
    }

    guard let endRange = contents.range(of: managedAgentInstructionsEndMarker, range: startRange.upperBound..<contents.endIndex) else {
        return nil
    }

    return startRange.lowerBound..<endRange.upperBound
}

private func normalizeManagedText(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\r\n", with: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func ensureTrailingNewline(in value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "" : trimmed + "\n"
}

func parse(arguments: [String]) throws -> CommandBehavior {
    guard !arguments.isEmpty else {
        return .showHelp
    }

    if let subcommandBehavior = try parseSubcommand(arguments: arguments) {
        return subcommandBehavior
    }

    if arguments.first == "doctor" {
        guard arguments.count == 1 else {
            throw BrrainzToolsError.invalidArguments("`doctor` does not accept additional arguments.")
        }
        return .doctor
    }

    if arguments.first == "clipboard" {
        return .clipboard(try parseClipboardCommand(arguments: Array(arguments.dropFirst())))
    }

    if arguments.first == "reveal" {
        return .revealFile(try parseRevealCommand(arguments: Array(arguments.dropFirst())))
    }

    if arguments.first == "open-file" || arguments.first == "--open-file" {
        if isHelpRequest(Array(arguments.dropFirst())) {
            return .showHelpText(openFileHelpText)
        }
        return .openFile(try parseOpenFileCommand(arguments: Array(arguments.dropFirst())))
    }

    if arguments.first == "activate" {
        return .activateApplication(try parseActivateApplicationCommand(arguments: Array(arguments.dropFirst())))
    }

    if arguments.first == "launch" {
        return .launchApplication(try parseLaunchApplicationCommand(arguments: Array(arguments.dropFirst())))
    }

    if arguments.first == "quit" {
        return .quitApplication(try parseQuitApplicationCommand(arguments: Array(arguments.dropFirst())))
    }

    let parsed = try parseRawArguments(arguments)

    if parsed.flags.contains("--help") || parsed.flags.contains("-h") {
        return .showHelp
    }

    if parsed.flags.contains("--version") {
        let hasOtherFlag = parsed.flags.contains { $0 != "--version" }
        if parsed.region != nil || !parsed.values.isEmpty || hasOtherFlag {
            throw BrrainzToolsError.invalidArguments("`--version` cannot be combined with other arguments.")
        }
        return .showVersion
    }

    if parsed.flags.contains("--doctor") {
        let hasOtherFlag = parsed.flags.contains { $0 != "--doctor" }
        if parsed.region != nil || !parsed.values.isEmpty || hasOtherFlag {
            throw BrrainzToolsError.invalidArguments("`--doctor` cannot be combined with other arguments.")
        }
        return .doctor
    }

    if parsed.flags.contains("--list-displays") {
        let hasOtherFlag = parsed.flags.contains { $0 != "--list-displays" }
        if parsed.region != nil || !parsed.values.isEmpty || hasOtherFlag {
            throw BrrainzToolsError.invalidArguments("`--list-displays` cannot be combined with other arguments.")
        }
        return .listDisplays
    }

    let applicationSelector = try parseApplicationSelector(values: parsed.values)
    let displaySelection = try parseDisplayCaptureSelection(parsed)
    let findAppQuery = normalizedArgumentValue(parsed.values["--find-app"])
    let windowSelection = try parseWindowSelection(parsed)
    let windowCrop = try parseWindowCrop(parsed.values["--window-crop"])
    let screenCaptureTimeout = try parseTimeout(parsed.values["--timeout"])
    let wantsWindowList = parsed.flags.contains("--list-windows")
    let wantsVisibleWindowList = parsed.flags.contains("--list-visible-windows")
    let wantsVisibleWindowCapture = parsed.flags.contains("--visible-window")
    let wantsMenuBarList = parsed.flags.contains("--list-menu-bar-items")
    let wantsMenuBarTree = parsed.flags.contains("--menu-tree")
    let wantsCaptureMenu = parsed.flags.contains("--capture-menu")
    let pressMenuItemQuery = normalizedArgumentValue(parsed.values["--press-menu-item"])
    let menuBarSelection = try parseMenuBarSelection(parsed)
    let wantsAccessibilityWindowList = parsed.flags.contains("--list-accessibility-windows") ||
        parsed.flags.contains("--list-ax-windows")
    let wantsElementList = parsed.flags.contains("--list-elements")
    let waitForWindowTitle = normalizedArgumentValue(parsed.values["--wait-for-window"])
    let wantsAccessibilityWaitForWindow = parsed.values["--wait-for-window"] != nil
    let elementTreeDepth = try parseBoundedIntegerOption(
        parsed.values["--depth"],
        flag: "--depth",
        defaultValue: defaultAccessibilityTreeDepth,
        allowedRange: accessibilityTreeDepthRange
    )
    let elementTreeChildLimit = try parseBoundedIntegerOption(
        parsed.values["--max-children"],
        flag: "--max-children",
        defaultValue: defaultAccessibilityTreeChildLimit,
        allowedRange: accessibilityTreeChildLimitRange
    )
    let elementTreeRoleFilter = try parseAccessibilityRoles(parsed.values["--roles"])
    let wantsElementTreeInteractiveOnly = parsed.flags.contains("--interactive")
    let wantsElementTreeFlat = parsed.flags.contains("--flat")
    let wantsAccessibilityGet = parsed.flags.contains("--get") || parsed.flags.contains("--get-element")
    let wantsAccessibilityWaitForElement = parsed.flags.contains("--wait-for-element")
    let setValueText = parsed.values["--set-value"]
    let wantsAccessibilitySetValue = setValueText != nil
    let typeText = parsed.values["--type"]
    let wantsAccessibilityTypeText = typeText != nil
    let keyChord = try parseKeyChord(parsed.values["--key"])
    let wantsAccessibilityKeyChord = parsed.values["--key"] != nil
    let wantsPress = parsed.flags.contains("--press") || parsed.flags.contains("--press-element")
    let wantsExplicitMenuBarPress = parsed.flags.contains("--menu-bar-press")
    let wantsMenuBarPress = wantsExplicitMenuBarPress || (wantsPress && menuBarSelection != nil)
    let wantsAccessibilityPress = wantsPress && !wantsMenuBarPress
    let wantsRaiseWindow = parsed.flags.contains("--raise-window") || parsed.flags.contains("--raise")
    let wantsCloseWindow = parsed.flags.contains("--close-window")
    let wantsMinimizeWindow = parsed.flags.contains("--minimize-window")
    let windowPosition = try parseWindowPosition(parsed.values["--move-window"], flag: "--move-window")
    let windowSize = try parseWindowSize(parsed.values["--resize-window"], flag: "--resize-window")
    let clickPoint = try parseWindowPoint(parsed.values["--click"], flag: "--click")
    let drag = try parseWindowDrag(parsed.values["--drag"], flag: "--drag")
    let scrollDelta = try parseScrollDelta(parsed.values["--scroll"], flag: "--scroll")
    let wantsRightClick = parsed.flags.contains("--right")
    let wantsDoubleClick = parsed.flags.contains("--double")
    let elementPoint = try parseWindowPoint(parsed.values["--element-at"], flag: "--element-at")
    let pressPoint = try parseWindowPoint(parsed.values["--press-at"], flag: "--press-at")
    let selector = parseAccessibilitySelector(from: parsed.values)
    try validateAccessibilitySelector(selector)
    let outputPath = parsed.values["--output"]
    let asciiImagePath = normalizedArgumentValue(parsed.values["--ascii"])
    let asciiStyle = try parseAsciiStyle(parsed.values["--ascii-style"])
    let asciiRecognitionLanguages = try parseOCRLanguages(parsed.values["--ascii-language"])
    let wantsAsciiInvert = parsed.flags.contains("--ascii-invert")
    let wantsAsciiNoOCR = parsed.flags.contains("--ascii-no-ocr")
    let wantsOCROnly = parsed.flags.contains("--ocr-only")
    let wantsRawOutput = parsed.flags.contains("--raw")
    let wantsWithAscii = parsed.flags.contains("--with-ascii")
    let wantsWithOCR = parsed.flags.contains("--with-ocr")
    let wantsNoPrompt = parsed.flags.contains("--no-prompt")
    let imageOutput = try parseImageOutputOptions(
        formatValue: parsed.values["--format"],
        qualityValue: parsed.values["--quality"],
        maxDimensionValue: parsed.values["--max-dimension"]
    )
    let asciiDefaultWidth = asciiStyle == .layout ? defaultLayoutAsciiWidth : defaultToneAsciiWidth
    let asciiDefaultMaxHeight = asciiStyle == .layout ? defaultLayoutAsciiMaxHeight : defaultToneAsciiMaxHeight
    let hasAsciiRenderOption = parsed.values["--ascii-width"] != nil ||
        parsed.values["--ascii-max-height"] != nil ||
        parsed.values["--ascii-style"] != nil ||
        wantsAsciiInvert ||
        wantsAsciiNoOCR
    let hasAsciiOption = hasAsciiRenderOption ||
        parsed.values["--ascii-language"] != nil ||
        wantsOCROnly
    let hasImageOutputOption = parsed.values["--format"] != nil ||
        parsed.values["--quality"] != nil ||
        parsed.values["--max-dimension"] != nil

    if parsed.values["--find-app"] != nil, findAppQuery == nil {
        throw BrrainzToolsError.invalidArguments("`--find-app` requires a non-empty search string.")
    }

    if parsed.values["--ascii"] != nil, asciiImagePath == nil {
        throw BrrainzToolsError.invalidArguments("`--ascii` requires a non-empty image path.")
    }

    if parsed.values["--press-menu-item"] != nil, pressMenuItemQuery == nil {
        throw BrrainzToolsError.invalidArguments("`--press-menu-item` requires a non-empty child menu item title, description, or identifier.")
    }

    if wantsAccessibilityWaitForWindow, waitForWindowTitle == nil {
        throw BrrainzToolsError.invalidArguments("`--wait-for-window` requires a non-empty window title.")
    }

    if wantsAccessibilityTypeText, normalizedArgumentValue(typeText) == nil {
        throw BrrainzToolsError.invalidArguments("`--type` requires non-empty text.")
    }

    if (wantsRightClick || wantsDoubleClick), clickPoint == nil {
        throw BrrainzToolsError.invalidArguments("`--right` and `--double` require `--click X,Y`.")
    }

    if let asciiImagePath {
        let allowedValueKeys: Set<String> = ["--ascii", "--ascii-width", "--ascii-max-height", "--ascii-style", "--ascii-language"]
        let allowedFlagKeys: Set<String> = ["--help", "-h", "--ascii-invert", "--ascii-no-ocr", "--ocr-only", "--raw"]
        let hasOtherValue = parsed.values.keys.contains { !allowedValueKeys.contains($0) }
        let hasOtherFlag = parsed.flags.contains { !allowedFlagKeys.contains($0) }

        if parsed.region != nil || hasOtherValue || hasOtherFlag {
            throw BrrainzToolsError.invalidArguments("`--ascii` cannot be combined with capture, app/window, menu-bar, Accessibility, `--find-app`, or `--output` modes.")
        }

        if wantsOCROnly, wantsAsciiNoOCR {
            throw BrrainzToolsError.invalidArguments("`--ocr-only` cannot be combined with `--ascii-no-ocr`.")
        }

        return .asciiArt(
            AsciiArtCommand(
                imageURL: try inputURL(from: asciiImagePath),
                style: asciiStyle,
                outputMode: wantsOCROnly ? .ocrOnly : .report,
                width: try parseAsciiDimension(
                    parsed.values["--ascii-width"],
                    flag: "--ascii-width",
                    defaultValue: asciiDefaultWidth,
                    allowedRange: asciiWidthRange
                ),
                maxHeight: try parseAsciiDimension(
                    parsed.values["--ascii-max-height"],
                    flag: "--ascii-max-height",
                    defaultValue: asciiDefaultMaxHeight,
                    allowedRange: asciiMaxHeightRange
                ),
                invert: wantsAsciiInvert,
                includeOCR: !wantsAsciiNoOCR,
                recognitionLanguages: asciiRecognitionLanguages,
                rawOutput: wantsRawOutput
            )
        )
    }

    if hasAsciiOption {
        if !wantsWithAscii, !wantsWithOCR {
            throw BrrainzToolsError.invalidArguments("`--ascii-style`, `--ascii-width`, `--ascii-max-height`, `--ascii-language`, `--ascii-invert`, `--ascii-no-ocr`, and `--ocr-only` require `--ascii IMAGE`, `--with-ascii`, or `--with-ocr`.")
        }
    }

    if wantsWithAscii, wantsWithOCR {
        throw BrrainzToolsError.invalidArguments("Choose only one of `--with-ascii` or `--with-ocr`.")
    }

    if wantsWithOCR, hasAsciiRenderOption || wantsOCROnly {
        throw BrrainzToolsError.invalidArguments("`--with-ocr` can only be combined with `--ascii-language`; rendering options require `--with-ascii`.")
    }

    if wantsWithAscii, wantsOCROnly {
        throw BrrainzToolsError.invalidArguments("`--ocr-only` requires `--ascii IMAGE`; use `--with-ocr` for capture modes.")
    }

    if let findAppQuery {
        let hasOtherValue = parsed.values.keys.contains(where: { key in key != "--find-app" })
        let hasOtherFlag = parsed.flags.contains(where: { flag in flag != "--help" && flag != "-h" })

        if parsed.region != nil || hasOtherValue || hasOtherFlag {
            throw BrrainzToolsError.invalidArguments("`--find-app` cannot be combined with other command flags or rectangle coordinates.")
        }

        return .findApps(FindAppsCommand(query: findAppQuery))
    }

    var accessibilityModeCount = 0
    if wantsAccessibilityWindowList { accessibilityModeCount += 1 }
    if wantsElementList { accessibilityModeCount += 1 }
    if elementPoint != nil { accessibilityModeCount += 1 }
    if wantsAccessibilityWaitForWindow { accessibilityModeCount += 1 }
    if wantsAccessibilityGet { accessibilityModeCount += 1 }
    if wantsAccessibilityWaitForElement { accessibilityModeCount += 1 }
    if wantsAccessibilitySetValue { accessibilityModeCount += 1 }
    if wantsAccessibilityTypeText { accessibilityModeCount += 1 }
    if wantsAccessibilityKeyChord { accessibilityModeCount += 1 }
    if clickPoint != nil { accessibilityModeCount += 1 }
    if drag != nil { accessibilityModeCount += 1 }
    if scrollDelta != nil { accessibilityModeCount += 1 }
    if wantsAccessibilityPress { accessibilityModeCount += 1 }
    if pressPoint != nil { accessibilityModeCount += 1 }
    if wantsRaiseWindow { accessibilityModeCount += 1 }
    if wantsCloseWindow { accessibilityModeCount += 1 }
    if wantsMinimizeWindow { accessibilityModeCount += 1 }
    if windowPosition != nil { accessibilityModeCount += 1 }
    if windowSize != nil { accessibilityModeCount += 1 }

    if accessibilityModeCount > 1 {
        throw BrrainzToolsError.invalidArguments("Choose only one of `--list-accessibility-windows`, `--list-elements`, `--element-at`, `--wait-for-window`, `--get`/`--get-element`, `--wait-for-element`, `--set-value`, `--type`, `--key`, `--click`, `--drag`, `--scroll`, `--press`/`--press-element`, `--press-at`, `--raise-window`, `--close-window`, `--minimize-window`, `--move-window`, or `--resize-window`.")
    }

    let menuBarModeCount = [
        wantsMenuBarList ? 1 : 0,
        wantsMenuBarTree ? 1 : 0,
        wantsMenuBarPress ? 1 : 0,
        pressMenuItemQuery != nil ? 1 : 0,
        wantsCaptureMenu ? 1 : 0,
    ].reduce(0, +)

    if menuBarModeCount > 1 {
        throw BrrainzToolsError.invalidArguments("Choose only one of `--list-menu-bar-items`, `--menu-tree`, menu-bar `--press`, `--press-menu-item`, or `--capture-menu`.")
    }

    let visibleWindowModeCount = [
        wantsVisibleWindowList ? 1 : 0,
        wantsVisibleWindowCapture ? 1 : 0,
    ].reduce(0, +)

    if visibleWindowModeCount > 1 {
        throw BrrainzToolsError.invalidArguments("Choose only one of `--list-visible-windows` or `--visible-window`.")
    }

    let accessibilityMode: AccessibilityMode?
    if wantsAccessibilityWindowList {
        accessibilityMode = .listWindows
    } else if wantsElementList {
        accessibilityMode = .listElements
    } else if let elementPoint {
        accessibilityMode = .elementAt(elementPoint)
    } else if let waitForWindowTitle {
        accessibilityMode = .waitForWindow(waitForWindowTitle)
    } else if wantsAccessibilityGet {
        accessibilityMode = .getElement(selector)
    } else if wantsAccessibilityWaitForElement {
        accessibilityMode = .waitForElement(selector)
    } else if let setValueText {
        accessibilityMode = .setValue(selector, setValueText)
    } else if let typeText {
        accessibilityMode = .typeText(typeText)
    } else if let keyChord {
        accessibilityMode = .keyChord(keyChord)
    } else if let clickPoint {
        accessibilityMode = .click(
            MouseClick(
                point: clickPoint,
                button: wantsRightClick ? .right : .left,
                clickCount: wantsDoubleClick ? 2 : 1
            )
        )
    } else if let drag {
        accessibilityMode = .drag(drag)
    } else if let scrollDelta {
        accessibilityMode = .scroll(scrollDelta, selector.isEmpty ? nil : selector)
    } else if wantsAccessibilityPress {
        accessibilityMode = .pressElement(selector)
    } else if let pressPoint {
        accessibilityMode = .pressAt(pressPoint)
    } else if wantsRaiseWindow {
        accessibilityMode = .raiseWindow
    } else if wantsCloseWindow {
        accessibilityMode = .closeWindow
    } else if wantsMinimizeWindow {
        accessibilityMode = .minimizeWindow
    } else if let windowPosition {
        accessibilityMode = .moveWindow(windowPosition)
    } else if let windowSize {
        accessibilityMode = .resizeWindow(windowSize)
    } else {
        accessibilityMode = nil
    }

    let menuBarMode: MenuBarMode?
    if wantsMenuBarList {
        menuBarMode = .listItems
    } else if wantsMenuBarTree {
        menuBarMode = .tree(
            MenuTreeOptions(
                depth: parsed.values["--depth"] == nil ? defaultMenuTreeDepth : elementTreeDepth,
                childLimit: parsed.values["--max-children"] == nil ? defaultMenuTreeChildLimit : elementTreeChildLimit
            )
        )
    } else if wantsMenuBarPress {
        menuBarMode = .pressItem
    } else if let pressMenuItemQuery {
        menuBarMode = .pressMenuItem(MenuChildSelection(query: pressMenuItemQuery))
    } else if wantsCaptureMenu {
        menuBarMode = .captureMenu
    } else {
        menuBarMode = nil
    }

    let rawCapturesRectangle = (parsed.region != nil || displaySelection != nil) && accessibilityMode == nil && menuBarMode == nil && !wantsWindowList && !wantsVisibleWindowList
    let rawCapturesAppWindow = applicationSelector != nil && windowSelection != nil && accessibilityMode == nil && menuBarMode == nil && !wantsWindowList && !wantsVisibleWindowList && !wantsVisibleWindowCapture
    let captureTextIsSupported = wantsCaptureMenu || wantsVisibleWindowCapture || rawCapturesRectangle || rawCapturesAppWindow
    let rawIsSupported = captureTextIsSupported
    if wantsRawOutput, !rawIsSupported {
        throw BrrainzToolsError.invalidArguments("`--raw` is only supported for capture output, `--capture-menu`, and `--ascii IMAGE`.")
    }

    if wantsRawOutput, wantsWithAscii || wantsWithOCR {
        throw BrrainzToolsError.invalidArguments("`--raw` cannot be combined with `--with-ascii` or `--with-ocr`; raw output can only print the legacy path.")
    }

    if (wantsWithAscii || wantsWithOCR), !captureTextIsSupported {
        throw BrrainzToolsError.invalidArguments("`--with-ascii` and `--with-ocr` require a capture mode.")
    }

    if hasImageOutputOption, !captureTextIsSupported {
        throw BrrainzToolsError.invalidArguments("`--format`, `--quality`, and `--max-dimension` require a capture mode.")
    }

    if imageOutput.format != .jpeg, parsed.values["--quality"] != nil {
        throw BrrainzToolsError.invalidArguments("`--quality` requires `--format jpeg`.")
    }

    let captureTextOutput: CaptureTextOptions?
    if wantsWithAscii || wantsWithOCR {
        captureTextOutput = CaptureTextOptions(
            outputMode: wantsWithOCR ? .ocrOnly : .report,
            style: asciiStyle,
            width: try parseAsciiDimension(
                parsed.values["--ascii-width"],
                flag: "--ascii-width",
                defaultValue: asciiDefaultWidth,
                allowedRange: asciiWidthRange
            ),
            maxHeight: try parseAsciiDimension(
                parsed.values["--ascii-max-height"],
                flag: "--ascii-max-height",
                defaultValue: asciiDefaultMaxHeight,
                allowedRange: asciiMaxHeightRange
            ),
            invert: wantsAsciiInvert,
            includeOCR: !wantsAsciiNoOCR,
            recognitionLanguages: asciiRecognitionLanguages
        )
    } else {
        captureTextOutput = nil
    }

    if displaySelection != nil {
        if parsed.region != nil {
            throw BrrainzToolsError.invalidArguments("Display capture cannot be combined with rectangle coordinates.")
        }

        if applicationSelector != nil {
            throw BrrainzToolsError.invalidArguments("Display capture cannot be combined with app selectors (`--app`, `--app-name`, or `--pid`).")
        }

        if windowSelection != nil || windowCrop != nil {
            throw BrrainzToolsError.invalidArguments("Display capture cannot be combined with app window selection or `--window-crop`.")
        }

        if wantsWindowList || wantsVisibleWindowList || wantsVisibleWindowCapture || accessibilityMode != nil || menuBarMode != nil {
            throw BrrainzToolsError.invalidArguments("Display capture cannot be combined with app/window listing, visible-window, menu-bar, or Accessibility modes.")
        }
    }

    if wantsNoPrompt, accessibilityMode == nil, menuBarMode == nil {
        throw BrrainzToolsError.invalidArguments("`--no-prompt` is only supported for Accessibility, menu-bar, and `launch --wait-window` commands.")
    }

    if windowSelection != nil, applicationSelector == nil {
        throw BrrainzToolsError.invalidArguments("Window selection requires an app selector (`--app`, `--app-name`, or `--pid`).")
    }

    if windowCrop != nil, applicationSelector == nil {
        throw BrrainzToolsError.invalidArguments("`--window-crop` requires an app selector (`--app`, `--app-name`, or `--pid`) and a specific window selection.")
    }

    if wantsWindowList, applicationSelector == nil {
        throw BrrainzToolsError.invalidArguments("`--list-windows` requires an app selector (`--app`, `--app-name`, or `--pid`).")
    }

    if wantsVisibleWindowList, applicationSelector == nil {
        throw BrrainzToolsError.invalidArguments("`--list-visible-windows` requires an app selector (`--app`, `--app-name`, or `--pid`).")
    }

    if wantsVisibleWindowCapture, applicationSelector == nil {
        throw BrrainzToolsError.invalidArguments("`--visible-window` requires an app selector (`--app`, `--app-name`, or `--pid`).")
    }

    if menuBarMode != nil, applicationSelector == nil {
        throw BrrainzToolsError.invalidArguments("Menu-bar inspection and actions require an app selector (`--app`, `--app-name`, or `--pid`).")
    }

    if accessibilityMode != nil, applicationSelector == nil {
        throw BrrainzToolsError.invalidArguments("Accessibility inspection and actions require an app selector (`--app`, `--app-name`, or `--pid`).")
    }

    if wantsAccessibilityWindowList, windowSelection != nil {
        throw BrrainzToolsError.invalidArguments("`--list-accessibility-windows` cannot be combined with `--frontmost-window`, `--window-index`, or `--window-name`.")
    }

    if wantsAccessibilityWaitForWindow, windowSelection != nil {
        throw BrrainzToolsError.invalidArguments("`--wait-for-window` cannot be combined with `--frontmost-window`, `--window-index`, or `--window-name`; pass the expected title as the `--wait-for-window` value.")
    }

    if (wantsAccessibilityTypeText || wantsAccessibilityKeyChord), windowSelection != nil {
        throw BrrainzToolsError.invalidArguments("`--type` and `--key` cannot be combined with `--frontmost-window`, `--window-index`, or `--window-name`; keyboard input is posted to the selected app.")
    }

    let hasTreeBoundsOption = parsed.values["--depth"] != nil ||
        parsed.values["--max-children"] != nil
    let hasElementTreeFilter = parsed.values["--roles"] != nil ||
        wantsElementTreeInteractiveOnly ||
        wantsElementTreeFlat
    if
        (hasTreeBoundsOption || hasElementTreeFilter),
        !wantsElementList,
        !wantsMenuBarTree
    {
        throw BrrainzToolsError.invalidArguments("`--depth`, `--max-children`, `--roles`, `--interactive`, and `--flat` require `--list-elements`; `menu tree`/`--menu-tree` also accepts `--depth` and `--max-children`.")
    }

    if hasElementTreeFilter, !wantsElementList {
        throw BrrainzToolsError.invalidArguments("`--roles`, `--interactive`, and `--flat` require `ax tree` or `--list-elements`.")
    }

    if wantsWindowList, windowSelection != nil {
        throw BrrainzToolsError.invalidArguments("`--list-windows` cannot be combined with `--frontmost-window`, `--window-index`, or `--window-name`.")
    }

    if wantsWindowList, accessibilityMode != nil {
        throw BrrainzToolsError.invalidArguments("`--list-windows` cannot be combined with accessibility inspection or action flags.")
    }

    if wantsWindowList, menuBarMode != nil {
        throw BrrainzToolsError.invalidArguments("`--list-windows` cannot be combined with menu-bar inspection or action flags.")
    }

    if wantsWindowList, windowCrop != nil {
        throw BrrainzToolsError.invalidArguments("`--list-windows` cannot be combined with `--window-crop`.")
    }

    if wantsWindowList, parsed.region != nil {
        throw BrrainzToolsError.invalidArguments("`--list-windows` cannot be combined with rectangle coordinates.")
    }

    if wantsWindowList, outputPath != nil {
        throw BrrainzToolsError.invalidArguments("`--list-windows` returns JSON data and does not use `--output`.")
    }

    if wantsWindowList, wantsVisibleWindowCapture || wantsVisibleWindowList {
        throw BrrainzToolsError.invalidArguments("`--list-windows` cannot be combined with visible-window modes.")
    }

    if wantsVisibleWindowList, parsed.region != nil {
        throw BrrainzToolsError.invalidArguments("`--list-visible-windows` cannot be combined with rectangle coordinates.")
    }

    if wantsVisibleWindowList, windowSelection != nil {
        throw BrrainzToolsError.invalidArguments("`--list-visible-windows` cannot be combined with `--frontmost-window`, `--window-index`, or `--window-name`.")
    }

    if wantsVisibleWindowList, windowCrop != nil {
        throw BrrainzToolsError.invalidArguments("`--list-visible-windows` cannot be combined with `--window-crop`.")
    }

    if wantsVisibleWindowList, outputPath != nil {
        throw BrrainzToolsError.invalidArguments("`--list-visible-windows` returns JSON data and does not use `--output`.")
    }

    if wantsVisibleWindowList, accessibilityMode != nil || menuBarMode != nil {
        throw BrrainzToolsError.invalidArguments("`--list-visible-windows` cannot be combined with menu-bar or Accessibility modes.")
    }

    if wantsVisibleWindowCapture, parsed.region != nil {
        throw BrrainzToolsError.invalidArguments("`--visible-window` cannot be combined with rectangle coordinates.")
    }

    if wantsVisibleWindowCapture, accessibilityMode != nil || menuBarMode != nil || wantsWindowList {
        throw BrrainzToolsError.invalidArguments("`--visible-window` cannot be combined with ScreenCaptureKit window listing, menu-bar modes, or Accessibility modes.")
    }

    if menuBarMode != nil, parsed.region != nil {
        throw BrrainzToolsError.invalidArguments("Menu-bar inspection and actions cannot be combined with rectangle coordinates.")
    }

    if menuBarMode != nil, windowSelection != nil {
        throw BrrainzToolsError.invalidArguments("Menu-bar inspection and actions cannot be combined with `--frontmost-window`, `--window-index`, or `--window-name`.")
    }

    if menuBarMode != nil, windowCrop != nil {
        throw BrrainzToolsError.invalidArguments("Menu-bar inspection and actions cannot be combined with `--window-crop`.")
    }

    if menuBarMode != nil, accessibilityMode != nil {
        throw BrrainzToolsError.invalidArguments("Menu-bar inspection and actions cannot be combined with window Accessibility inspection or action flags.")
    }

    if wantsMenuBarList, menuBarSelection != nil {
        throw BrrainzToolsError.invalidArguments("`--list-menu-bar-items` cannot be combined with `--menu-bar-index` or `--menu-bar-item`.")
    }

    if wantsMenuBarList, outputPath != nil {
        throw BrrainzToolsError.invalidArguments("`--list-menu-bar-items` returns JSON data and does not use `--output`.")
    }

    if wantsMenuBarTree, outputPath != nil {
        throw BrrainzToolsError.invalidArguments("`--menu-tree` returns JSON data and does not use `--output`.")
    }

    if wantsMenuBarPress, outputPath != nil {
        throw BrrainzToolsError.invalidArguments("Menu-bar `--press` returns JSON data and does not use `--output`.")
    }

    if wantsMenuBarPress, !selector.isEmpty {
        throw BrrainzToolsError.invalidArguments("Menu-bar `--press` cannot be combined with selector fields. Use `--menu-bar-index` or `--menu-bar-item` to select a menu-bar item.")
    }

    if pressMenuItemQuery != nil, outputPath != nil {
        throw BrrainzToolsError.invalidArguments("`--press-menu-item` returns JSON data and does not use `--output`.")
    }

    if pressMenuItemQuery != nil, !selector.isEmpty {
        throw BrrainzToolsError.invalidArguments("`--press-menu-item` cannot be combined with selector fields. Pass the child menu item title, description, or identifier as the `--press-menu-item` value.")
    }

    if menuBarSelection != nil, menuBarMode == nil {
        throw BrrainzToolsError.invalidArguments("`--menu-bar-index` and `--menu-bar-item` require `--menu-tree`, menu-bar `--press`, `--press-menu-item`, or `--capture-menu`.")
    }

    if accessibilityMode != nil, parsed.region != nil {
        throw BrrainzToolsError.invalidArguments("Accessibility inspection and actions cannot be combined with rectangle coordinates.")
    }

    if accessibilityMode != nil, windowCrop != nil {
        throw BrrainzToolsError.invalidArguments("Accessibility inspection and actions cannot be combined with `--window-crop`.")
    }

    if accessibilityMode != nil, outputPath != nil {
        throw BrrainzToolsError.invalidArguments("Accessibility inspection and actions return JSON data and do not use `--output`.")
    }

    if wantsAccessibilityGet, selector.isEmpty {
        throw BrrainzToolsError.invalidArguments("`--get` (alias: `--get-element`) requires at least one selector field: `--path`, `--role`, `--subrole`, `--title`, `--identifier`, or `--description`.")
    }

    if wantsAccessibilityWaitForElement, selector.isEmpty {
        throw BrrainzToolsError.invalidArguments("`--wait-for-element` requires at least one selector field: `--path`, `--role`, `--subrole`, `--title`, `--identifier`, or `--description`.")
    }

    if wantsAccessibilitySetValue, selector.isEmpty {
        throw BrrainzToolsError.invalidArguments("`--set-value` requires at least one selector field: `--path`, `--role`, `--subrole`, `--title`, `--identifier`, or `--description`.")
    }

    if wantsAccessibilityPress, selector.isEmpty {
        throw BrrainzToolsError.invalidArguments("`--press` (alias: `--press-element`) requires at least one selector field: `--path`, `--role`, `--subrole`, `--title`, `--identifier`, or `--description`.")
    }

    if !wantsAccessibilityGet, !wantsAccessibilityWaitForElement, !wantsAccessibilitySetValue, !wantsAccessibilityPress, scrollDelta == nil, !selector.isEmpty {
        throw BrrainzToolsError.invalidArguments("Selector fields require `--get`/`--get-element`, `--wait-for-element`, `--set-value`, `--scroll`, or `--press`/`--press-element`.")
    }

    if pressPoint != nil, !selector.isEmpty {
        throw BrrainzToolsError.invalidArguments("`--press-at` cannot be combined with selector fields.")
    }

    if parsed.region != nil, windowSelection != nil {
        throw BrrainzToolsError.invalidArguments("Rectangle capture cannot be combined with specific window selection. Choose one capture mode.")
    }

    if parsed.region != nil, windowCrop != nil {
        throw BrrainzToolsError.invalidArguments("Rectangle capture cannot be combined with `--window-crop`. `--window-crop` is relative to a selected app window.")
    }

    if windowCrop != nil, windowSelection == nil, !wantsVisibleWindowCapture {
        throw BrrainzToolsError.invalidArguments("`--window-crop` requires one of `--frontmost-window`, `--window-index`, or `--window-name`.")
    }

    if let menuBarMode {
        return .menuBar(
            MenuBarCommand(
                applicationSelector: applicationSelector!,
                selection: menuBarSelection,
                mode: menuBarMode,
                promptForAccessibility: !wantsNoPrompt,
                outputURL: wantsCaptureMenu ? try outputURL(from: outputPath, format: imageOutput.format) : nil,
                screenCaptureTimeout: screenCaptureTimeout,
                rawOutput: wantsRawOutput,
                textOutput: captureTextOutput,
                imageOutput: imageOutput
            )
        )
    }

    if applicationSelector != nil, parsed.region == nil, windowSelection == nil, outputPath != nil, !wantsVisibleWindowCapture {
        throw BrrainzToolsError.invalidArguments("`--output` requires a capture mode. Use rectangle coordinates, `--visible-window`, or one of `--frontmost-window`, `--window-index`, or `--window-name`. `--app` alone lists windows as JSON.")
    }

    if wantsVisibleWindowList {
        return .listVisibleWindows(
            VisibleWindowsCommand(
                applicationSelector: applicationSelector!
            )
        )
    }

    if wantsVisibleWindowCapture {
        return .captureVisibleWindow(
            VisibleWindowCaptureCommand(
                applicationSelector: applicationSelector!,
                windowSelection: windowSelection,
                windowCrop: windowCrop,
                outputURL: try outputURL(from: outputPath, format: imageOutput.format),
                screenCaptureTimeout: screenCaptureTimeout,
                rawOutput: wantsRawOutput,
                textOutput: captureTextOutput,
                imageOutput: imageOutput
            )
        )
    }

    if wantsWindowList || (applicationSelector != nil && parsed.region == nil && windowSelection == nil && accessibilityMode == nil) {
        return .listWindows(
            ListWindowsCommand(
                applicationSelector: applicationSelector!,
                screenCaptureTimeout: screenCaptureTimeout
            )
        )
    }

    if let accessibilityMode {
        return .inspectAccessibility(
            AccessibilityCommand(
                applicationSelector: applicationSelector!,
                windowSelection: windowSelection,
                mode: accessibilityMode,
                promptForAccessibility: !wantsNoPrompt,
                treeDepth: elementTreeDepth,
                treeChildLimit: elementTreeChildLimit,
                treeRoleFilter: elementTreeRoleFilter,
                treeInteractiveOnly: wantsElementTreeInteractiveOnly,
                treeFlat: wantsElementTreeFlat,
                timeout: screenCaptureTimeout
            )
        )
    }

    if parsed.region == nil, applicationSelector == nil, displaySelection == nil {
        throw BrrainzToolsError.invalidArguments("Missing rectangle arguments.")
    }

    let outputURL = try outputURL(from: outputPath, format: imageOutput.format)
    return .capture(
        CaptureCommand(
            region: parsed.region,
            displaySelection: displaySelection,
            outputURL: outputURL,
            applicationSelector: applicationSelector,
            windowSelection: windowSelection,
            windowCrop: windowCrop,
            screenCaptureTimeout: screenCaptureTimeout,
            rawOutput: wantsRawOutput,
            textOutput: captureTextOutput,
            imageOutput: imageOutput
        )
    )
}

private func parseSubcommand(arguments: [String]) throws -> CommandBehavior? {
    guard let subcommand = arguments.first else {
        return nil
    }

    let trailingArguments = Array(arguments.dropFirst())
    switch subcommand {
    case "capture":
        return try parseCaptureSubcommand(arguments: trailingArguments)
    case "apps":
        return try parseAppsSubcommand(arguments: trailingArguments)
    case "windows":
        return try parseWindowsSubcommand(arguments: trailingArguments)
    case "ax":
        return try parseAXSubcommand(arguments: trailingArguments)
    case "menu":
        return try parseMenuSubcommand(arguments: trailingArguments)
    case "ascii":
        return try parseASCIISubcommand(arguments: trailingArguments)
    case "displays":
        return try parseDisplaysSubcommand(arguments: trailingArguments)
    case "doctor":
        return isHelpRequest(trailingArguments) ? .showHelpText(doctorHelpText) : nil
    case "clipboard":
        return isHelpRequest(trailingArguments) ? .showHelpText(clipboardHelpText) : nil
    case "reveal":
        return isHelpRequest(trailingArguments) ? .showHelpText(revealHelpText) : nil
    case "open-file":
        return isHelpRequest(trailingArguments) ? .showHelpText(openFileHelpText) : nil
    case "launch":
        return isHelpRequest(trailingArguments) ? .showHelpText(launchHelpText) : nil
    case "activate":
        return isHelpRequest(trailingArguments) ? .showHelpText(activateHelpText) : nil
    case "quit":
        return isHelpRequest(trailingArguments) ? .showHelpText(quitHelpText) : nil
    default:
        return nil
    }
}

private func isHelpRequest(_ arguments: [String]) -> Bool {
    arguments.count == 1 && (arguments[0] == "--help" || arguments[0] == "-h")
}

private func parseCaptureSubcommand(arguments: [String]) throws -> CommandBehavior {
    if arguments.isEmpty || isHelpRequest(arguments) {
        return .showHelpText(captureHelpText)
    }

    if let first = arguments.first, !first.hasPrefix("--"), Int(first) == nil {
        throw BrrainzToolsError.invalidArguments("`capture` expects rectangle coordinates or capture flags. Run `brrainztools capture --help`.")
    }

    let forwardedArguments = try captureSubcommandArguments(arguments)
    let behavior = try parse(arguments: forwardedArguments)

    switch behavior {
    case .capture, .captureVisibleWindow:
        return behavior
    default:
        throw BrrainzToolsError.invalidArguments("`capture` requires rectangle coordinates, `--display`, `--all-displays`, `--visible-window`, or an app window selection. Use `brrainztools windows` to list app windows.")
    }
}

private func captureSubcommandArguments(_ arguments: [String]) throws -> [String] {
    let parsed = try parseRawArguments(arguments)
    let hasApplicationSelector = try parseApplicationSelector(values: parsed.values) != nil
    let hasWindowSelection = parsed.flags.contains("--frontmost-window") ||
        parsed.values["--window-index"] != nil ||
        parsed.values["--window-name"] != nil
    let hasRegion = parsed.region != nil
    let hasDisplaySelection = parsed.values["--display"] != nil ||
        parsed.flags.contains("--all-displays")
    let hasVisibleWindowCapture = parsed.flags.contains("--visible-window")

    if hasApplicationSelector,
       !hasWindowSelection,
       !hasRegion,
       !hasDisplaySelection,
       !hasVisibleWindowCapture {
        return arguments + ["--frontmost-window"]
    }

    return arguments
}

private func parseAppsSubcommand(arguments: [String]) throws -> CommandBehavior {
    if arguments.isEmpty || isHelpRequest(arguments) {
        return .showHelpText(appsHelpText)
    }

    guard !arguments.contains(where: { $0.hasPrefix("--") }) else {
        throw BrrainzToolsError.invalidArguments("`apps` accepts a search query. Run `brrainztools apps --help`.")
    }

    return try parse(arguments: ["--find-app", arguments.joined(separator: " ")])
}

private func parseDisplaysSubcommand(arguments: [String]) throws -> CommandBehavior {
    if isHelpRequest(arguments) {
        return .showHelpText(displaysHelpText)
    }

    guard arguments.isEmpty else {
        throw BrrainzToolsError.invalidArguments("`displays` does not accept additional arguments. Run `brrainztools displays --help`.")
    }

    return .listDisplays
}

private func parseASCIISubcommand(arguments: [String]) throws -> CommandBehavior {
    if arguments.isEmpty || isHelpRequest(arguments) {
        return .showHelpText(asciiHelpText)
    }

    guard let imagePath = arguments.first, !imagePath.hasPrefix("--") else {
        throw BrrainzToolsError.invalidArguments("`ascii` requires IMAGE before options. Run `brrainztools ascii --help`.")
    }

    return try parse(arguments: ["--ascii", imagePath] + Array(arguments.dropFirst()))
}

private func parseWindowsSubcommand(arguments: [String]) throws -> CommandBehavior {
    if arguments.isEmpty || isHelpRequest(arguments) {
        return .showHelpText(windowsHelpText)
    }

    var forwardedArguments: [String] = []
    var modeFlag = "--list-windows"
    var sawModeFlag = false

    for argument in arguments {
        switch argument {
        case "--visible":
            guard !sawModeFlag else {
                throw BrrainzToolsError.invalidArguments("Choose only one of `--visible` or `--ax` for `windows`.")
            }
            sawModeFlag = true
            modeFlag = "--list-visible-windows"
        case "--ax":
            guard !sawModeFlag else {
                throw BrrainzToolsError.invalidArguments("Choose only one of `--visible` or `--ax` for `windows`.")
            }
            sawModeFlag = true
            modeFlag = "--list-accessibility-windows"
        default:
            forwardedArguments.append(argument)
        }
    }

    return try parse(arguments: forwardedArguments + [modeFlag])
}

private let subcommandValueOptionFlags: Set<String> = [
    "--x", "--y", "--width", "--height", "--display", "--output", "--app", "--app-name", "--pid", "--find-app",
    "--timeout", "--window-index", "--window-name", "--window-crop", "--menu-bar-index", "--menu-bar-item",
    "--press-menu-item", "--element-at", "--wait-for-window", "--press-at", "--path", "--role", "--subrole",
    "--title", "--identifier", "--description", "--set-value", "--type", "--key", "--click", "--drag",
    "--scroll", "--move-window", "--resize-window", "--depth", "--max-children", "--roles", "--ascii",
    "--ascii-width", "--ascii-max-height", "--ascii-style", "--ascii-language", "--format", "--quality",
    "--max-dimension",
]

private func parseAXSubcommand(arguments: [String]) throws -> CommandBehavior {
    let flagActions = [
        "windows": "--list-accessibility-windows",
        "tree": "--list-elements",
        "elements": "--list-elements",
        "get": "--get",
        "wait-for-element": "--wait-for-element",
        "press": "--press",
        "raise": "--raise-window",
        "close": "--close-window",
        "minimize": "--minimize-window",
    ]
    let valueActions = [
        "wait-for-window": "--wait-for-window",
        "set-value": "--set-value",
        "type": "--type",
        "key": "--key",
        "press-at": "--press-at",
        "element-at": "--element-at",
        "click": "--click",
        "drag": "--drag",
        "scroll": "--scroll",
        "move": "--move-window",
        "resize": "--resize-window",
    ]

    if arguments.isEmpty ||
        isHelpRequest(arguments) ||
        isActionHelpRequest(arguments, actionNames: Set(flagActions.keys).union(valueActions.keys)) {
        return .showHelpText(axHelpText)
    }

    let translated = try translateActionSubcommand(
        name: "ax",
        arguments: arguments,
        flagActions: flagActions,
        valueActions: valueActions
    )
    return try parse(arguments: translated)
}

private func parseMenuSubcommand(arguments: [String]) throws -> CommandBehavior {
    let flagActions = [
        "list": "--list-menu-bar-items",
        "tree": "--menu-tree",
        "press": "--menu-bar-press",
        "capture": "--capture-menu",
    ]
    let valueActions = [
        "press-item": "--press-menu-item",
    ]

    if arguments.isEmpty ||
        isHelpRequest(arguments) ||
        isActionHelpRequest(arguments, actionNames: Set(flagActions.keys).union(valueActions.keys)) {
        return .showHelpText(menuHelpText)
    }

    let translated = try translateActionSubcommand(
        name: "menu",
        arguments: arguments,
        flagActions: flagActions,
        valueActions: valueActions
    )
    return try parse(arguments: translated)
}

private func isActionHelpRequest(_ arguments: [String], actionNames: Set<String>) -> Bool {
    guard
        let last = arguments.last,
        last == "--help" || last == "-h",
        let action = firstUnknownActionToken(in: Array(arguments.dropLast()))
    else {
        return false
    }

    return actionNames.contains(action)
}

private func translateActionSubcommand(
    name: String,
    arguments: [String],
    flagActions: [String: String],
    valueActions: [String: String]
) throws -> [String] {
    var forwardedArguments: [String] = []
    var actionArguments: [String] = []
    var foundAction = false
    var index = 0

    while index < arguments.count {
        let argument = arguments[index]

        if !foundAction, let flag = flagActions[argument] {
            foundAction = true
            actionArguments.append(flag)
            index += 1
            continue
        }

        if !foundAction, let flag = valueActions[argument] {
            let valueIndex = index + 1
            guard valueIndex < arguments.count else {
                throw BrrainzToolsError.invalidArguments("`\(name) \(argument)` requires a value. Run `brrainztools \(name) --help`.")
            }

            foundAction = true
            actionArguments.append(contentsOf: [flag, arguments[valueIndex]])
            index += 2
            continue
        }

        forwardedArguments.append(argument)
        if subcommandValueOptionFlags.contains(argument), index + 1 < arguments.count {
            forwardedArguments.append(arguments[index + 1])
            index += 2
        } else {
            index += 1
        }
    }

    guard foundAction else {
        if let unknownAction = firstUnknownActionToken(in: arguments) {
            throw BrrainzToolsError.invalidArguments("Unknown `\(name)` action `\(unknownAction)`. Run `brrainztools \(name) --help`.")
        }

        throw BrrainzToolsError.invalidArguments("Missing `\(name)` action. Run `brrainztools \(name) --help`.")
    }

    return forwardedArguments + actionArguments
}

private func firstUnknownActionToken(in arguments: [String]) -> String? {
    var index = 0

    while index < arguments.count {
        let argument = arguments[index]
        if argument.hasPrefix("--") {
            index += subcommandValueOptionFlags.contains(argument) ? 2 : 1
            continue
        }

        return argument
    }

    return nil
}

private func parseRawArguments(_ arguments: [String]) throws -> ParsedArguments {
    var region: CaptureRegion?
    var trailingArguments = arguments

    if let positionalRegion = try parsePositionalRegion(arguments: arguments) {
        region = positionalRegion
        trailingArguments = Array(arguments.dropFirst(4))
    }

    let parsedOptions = try parseOptions(arguments: trailingArguments)
    if region != nil {
        return ParsedArguments(region: region, values: parsedOptions.values, flags: parsedOptions.flags)
    }

    let flaggedRegion = try parseFlaggedRegion(values: parsedOptions.values)
    return ParsedArguments(region: flaggedRegion, values: parsedOptions.values, flags: parsedOptions.flags)
}

private func parsePositionalRegion(arguments: [String]) throws -> CaptureRegion? {
    guard arguments.count >= 4 else {
        return nil
    }

    let positional = Array(arguments.prefix(4))
    guard positional.allSatisfy({ Int($0) != nil }) else {
        return nil
    }

    let region = try CaptureRegion(
        x: parseInteger(positional[0], flag: "<x>"),
        y: parseInteger(positional[1], flag: "<y>"),
        width: parseInteger(positional[2], flag: "<width>"),
        height: parseInteger(positional[3], flag: "<height>")
    )

    try validate(region: region)
    return region
}

private func parseOptions(arguments: [String]) throws -> (values: [String: String], flags: Set<String>) {
    var values: [String: String] = [:]
    var flags: Set<String> = []
    var index = 0

    while index < arguments.count {
        let argument = arguments[index]

        switch argument {
        case "--help", "-h", "--version", "--doctor", "--list-displays", "--all-displays", "--list-windows", "--list-visible-windows", "--visible-window", "--frontmost-window", "--list-accessibility-windows", "--list-ax-windows", "--list-elements", "--interactive", "--flat", "--list-menu-bar-items", "--menu-tree", "--menu-bar-press", "--get", "--get-element", "--wait-for-element", "--press", "--press-element", "--raise-window", "--raise", "--close-window", "--minimize-window", "--right", "--double", "--capture-menu", "--ascii-invert", "--ascii-no-ocr", "--ocr-only", "--raw", "--with-ascii", "--with-ocr", "--no-prompt":
            flags.insert(argument)
            index += 1
        case "--x", "--y", "--width", "--height", "--display", "--output", "--app", "--app-name", "--pid", "--find-app", "--timeout", "--window-index", "--window-name", "--window-crop", "--menu-bar-index", "--menu-bar-item", "--press-menu-item", "--element-at", "--wait-for-window", "--press-at", "--path", "--role", "--subrole", "--title", "--identifier", "--description", "--set-value", "--type", "--key", "--click", "--drag", "--scroll", "--move-window", "--resize-window", "--depth", "--max-children", "--roles", "--ascii", "--ascii-width", "--ascii-max-height", "--ascii-style", "--ascii-language", "--format", "--quality", "--max-dimension":
            let valueIndex = index + 1
            guard valueIndex < arguments.count else {
                throw BrrainzToolsError.invalidArguments("Missing value for \(argument).")
            }

            values[argument] = arguments[valueIndex]
            index += 2
        default:
            throw BrrainzToolsError.invalidArguments("Unexpected argument `\(argument)`.")
        }
    }

    return (values, flags)
}

func parseClipboardCommand(arguments: [String]) throws -> ClipboardCommand {
    guard !arguments.isEmpty else {
        return ClipboardCommand(setText: nil)
    }

    guard arguments.count == 2, arguments[0] == "--set" else {
        throw BrrainzToolsError.invalidArguments("`clipboard` accepts no arguments or `--set TEXT`.")
    }

    return ClipboardCommand(setText: arguments[1])
}

func parseRevealCommand(arguments: [String]) throws -> RevealCommand {
    guard arguments.count == 1 else {
        throw BrrainzToolsError.invalidArguments("`reveal` requires exactly one PATH.")
    }

    let path = arguments[0]
    guard !path.isEmpty else {
        throw BrrainzToolsError.invalidArguments("`reveal` requires a non-empty PATH.")
    }

    return RevealCommand(path: path)
}

func parseOpenFileCommand(arguments: [String]) throws -> OpenFileCommand {
    var path: String?
    var applicationTarget: LaunchTarget?
    var waitForWindow = false
    var promptForAccessibility = true
    var timeout = defaultScreenCaptureKitTimeout
    var index = 0

    while index < arguments.count {
        let argument = arguments[index]

        switch argument {
        case "--app":
            let valueIndex = index + 1
            guard valueIndex < arguments.count,
                  !arguments[valueIndex].hasPrefix("--"),
                  let value = normalizedArgumentValue(arguments[valueIndex]) else {
                throw BrrainzToolsError.invalidArguments("`open-file --app` requires an app bundle PATH or BUNDLE_ID.")
            }
            guard applicationTarget == nil else {
                throw BrrainzToolsError.invalidArguments("`open-file` accepts only one `--app PATH|BUNDLE_ID` target.")
            }
            applicationTarget = inferLaunchTarget(value)
            index += 2
        case "--wait-window":
            waitForWindow = true
            index += 1
        case "--no-prompt":
            promptForAccessibility = false
            index += 1
        case "--timeout":
            let valueIndex = index + 1
            guard valueIndex < arguments.count else {
                throw BrrainzToolsError.invalidArguments("Missing value for --timeout.")
            }
            timeout = try parseTimeout(arguments[valueIndex])
            index += 2
        default:
            if argument.hasPrefix("--") {
                throw BrrainzToolsError.invalidArguments(
                    "`open-file` accepts PATH, optional `--app PATH|BUNDLE_ID`, optional `--wait-window`, optional `--no-prompt`, and optional `--timeout SECONDS`."
                )
            }

            guard path == nil else {
                throw BrrainzToolsError.invalidArguments("`open-file` accepts exactly one document PATH.")
            }
            path = argument
            index += 1
        }
    }

    guard let rawPath = path, let normalizedPath = normalizedArgumentValue(rawPath) else {
        throw BrrainzToolsError.invalidArguments("`open-file` requires a document PATH.")
    }

    if !promptForAccessibility, !waitForWindow {
        throw BrrainzToolsError.invalidArguments(
            "`open-file --no-prompt` requires `--wait-window`; opening without waiting does not use Accessibility."
        )
    }

    return OpenFileCommand(
        path: normalizedPath,
        applicationTarget: applicationTarget,
        waitForWindow: waitForWindow,
        promptForAccessibility: promptForAccessibility,
        timeout: timeout
    )
}

func parseActivateApplicationCommand(arguments: [String]) throws -> ActivateApplicationCommand {
    let parsed = try parseRawArguments(arguments)
    let allowedValueKeys: Set<String> = ["--app", "--app-name", "--pid"]
    let hasOtherValue = parsed.values.keys.contains { !allowedValueKeys.contains($0) }

    if parsed.region != nil || hasOtherValue || !parsed.flags.isEmpty {
        throw BrrainzToolsError.invalidArguments("`activate` accepts only an app selector (`--app`, `--app-name`, or `--pid`).")
    }

    guard let applicationSelector = try parseApplicationSelector(values: parsed.values) else {
        throw BrrainzToolsError.invalidArguments("`activate` requires an app selector (`--app`, `--app-name`, or `--pid`).")
    }

    return ActivateApplicationCommand(applicationSelector: applicationSelector)
}

func parseLaunchApplicationCommand(arguments: [String]) throws -> LaunchApplicationCommand {
    var target: String?
    var launchArguments: [String] = []
    var waitForWindow = false
    var promptForAccessibility = true
    var timeout = defaultScreenCaptureKitTimeout
    var index = 0

    while index < arguments.count {
        let argument = arguments[index]

        switch argument {
        case "--args":
            guard target != nil else {
                throw BrrainzToolsError.invalidArguments("`launch` requires PATH|BUNDLE_ID before `--args`.")
            }
            launchArguments = Array(arguments.dropFirst(index + 1))
            index = arguments.count
        case "--wait-window":
            waitForWindow = true
            index += 1
        case "--no-prompt":
            promptForAccessibility = false
            index += 1
        case "--timeout":
            let valueIndex = index + 1
            guard valueIndex < arguments.count else {
                throw BrrainzToolsError.invalidArguments("Missing value for --timeout.")
            }
            timeout = try parseTimeout(arguments[valueIndex])
            index += 2
        default:
            if argument.hasPrefix("--") {
                throw BrrainzToolsError.invalidArguments("`launch` accepts PATH|BUNDLE_ID, optional `--wait-window`, optional `--no-prompt`, optional `--timeout SECONDS`, and optional `--args ARG ...`.")
            }

            guard target == nil else {
                throw BrrainzToolsError.invalidArguments("`launch` accepts exactly one PATH|BUNDLE_ID target before `--args`.")
            }

            target = argument
            index += 1
        }
    }

    guard let rawTarget = target, let normalizedTarget = normalizedArgumentValue(rawTarget) else {
        throw BrrainzToolsError.invalidArguments("`launch` requires PATH|BUNDLE_ID.")
    }

    if !promptForAccessibility, !waitForWindow {
        throw BrrainzToolsError.invalidArguments("`launch --no-prompt` requires `--wait-window`; launch without waiting does not use Accessibility.")
    }

    return LaunchApplicationCommand(
        target: inferLaunchTarget(normalizedTarget),
        arguments: launchArguments,
        waitForWindow: waitForWindow,
        promptForAccessibility: promptForAccessibility,
        timeout: timeout
    )
}

private func inferLaunchTarget(_ rawValue: String) -> LaunchTarget {
    if looksLikeLaunchPath(rawValue) {
        return .path(rawValue)
    }

    return .bundleIdentifier(rawValue)
}

private func looksLikeLaunchPath(_ value: String) -> Bool {
    value.hasPrefix("/") ||
        value.hasPrefix(".") ||
        value.contains("/") ||
        FileManager.default.fileExists(atPath: fileURL(from: value).path)
}

func parseQuitApplicationCommand(arguments: [String]) throws -> QuitApplicationCommand {
    var force = false
    var waitForTermination = false
    var timeout = defaultApplicationTerminationTimeout
    var timeoutWasSpecified = false
    var filteredArguments: [String] = []
    filteredArguments.reserveCapacity(arguments.count)
    var index = 0

    while index < arguments.count {
        switch arguments[index] {
        case "--force":
            force = true
            index += 1
        case "--wait":
            waitForTermination = true
            index += 1
        case "--timeout":
            let valueIndex = index + 1
            guard valueIndex < arguments.count else {
                throw BrrainzToolsError.invalidArguments("Missing value for --timeout.")
            }
            timeout = try parseTimeout(arguments[valueIndex])
            timeoutWasSpecified = true
            index += 2
        default:
            filteredArguments.append(arguments[index])
            index += 1
        }
    }

    let parsed = try parseRawArguments(filteredArguments)
    let allowedValueKeys: Set<String> = ["--app", "--app-name", "--pid"]
    let hasOtherValue = parsed.values.keys.contains { !allowedValueKeys.contains($0) }

    if parsed.region != nil || hasOtherValue || !parsed.flags.isEmpty {
        throw BrrainzToolsError.invalidArguments("`quit` accepts only an app selector (`--app`, `--app-name`, or `--pid`), optional `--force`, and optional `--wait [--timeout SECONDS]`.")
    }

    guard let applicationSelector = try parseApplicationSelector(values: parsed.values) else {
        throw BrrainzToolsError.invalidArguments("`quit` requires an app selector (`--app`, `--app-name`, or `--pid`).")
    }

    if timeoutWasSpecified, !waitForTermination {
        throw BrrainzToolsError.invalidArguments("`quit --timeout` requires `--wait`; quit without waiting does not use a timeout.")
    }

    return QuitApplicationCommand(
        applicationSelector: applicationSelector,
        force: force,
        waitForTermination: waitForTermination,
        timeout: timeout
    )
}

func parseApplicationSelector(values: [String: String]) throws -> ApplicationSelector? {
    let selectorKeys = ["--app", "--app-name", "--pid"]
    let presentSelectorKeys = selectorKeys.filter { values[$0] != nil }

    guard !presentSelectorKeys.isEmpty else {
        return nil
    }

    guard presentSelectorKeys.count == 1 else {
        throw BrrainzToolsError.invalidArguments("Choose only one of `--app`, `--app-name`, or `--pid`.")
    }

    if let rawApp = values["--app"] {
        guard let app = normalizedArgumentValue(rawApp) else {
            throw BrrainzToolsError.invalidArguments("`--app` requires a non-empty app name, bundle id, or pid.")
        }

        return ApplicationSelector(rawValue: app)
    }

    if let rawAppName = values["--app-name"] {
        guard let appName = normalizedArgumentValue(rawAppName) else {
            throw BrrainzToolsError.invalidArguments("`--app-name` requires a non-empty app name or bundle id.")
        }

        return .name(appName)
    }

    guard let rawPID = values["--pid"] else {
        return nil
    }

    let processID = try parseInteger(rawPID, flag: "--pid")
    guard processID > 0, let pid = Int32(exactly: processID) else {
        throw BrrainzToolsError.invalidArguments("`--pid` requires a positive 32-bit process id.")
    }

    return .processID(pid)
}

private func parseDisplayCaptureSelection(_ parsed: ParsedArguments) throws -> DisplayCaptureSelection? {
    let wantsAllDisplays = parsed.flags.contains("--all-displays")
    let rawDisplayID = parsed.values["--display"]

    if wantsAllDisplays, rawDisplayID != nil {
        throw BrrainzToolsError.invalidArguments("Choose only one of `--display DISPLAY_ID` or `--all-displays`.")
    }

    if wantsAllDisplays {
        return .allDisplays
    }

    guard let rawDisplayID else {
        return nil
    }

    guard let trimmedDisplayID = normalizedArgumentValue(rawDisplayID) else {
        throw BrrainzToolsError.invalidArguments("`--display` requires a display id from `--list-displays`.")
    }

    let displayID = try parseInteger(trimmedDisplayID, flag: "--display")
    guard displayID > 0, displayID <= Int(UInt32.max) else {
        throw BrrainzToolsError.invalidArguments("`--display` requires a positive 32-bit display id from `--list-displays`.")
    }

    return .displayID(CGDirectDisplayID(displayID))
}

private func parseFlaggedRegion(values: [String: String]) throws -> CaptureRegion? {
    let rectangleKeys = ["--x", "--y", "--width", "--height"]
    let presentKeys = rectangleKeys.filter { values[$0] != nil }

    if presentKeys.isEmpty {
        return nil
    }

    guard presentKeys.count == rectangleKeys.count else {
        throw BrrainzToolsError.invalidArguments("Expected all of `--x`, `--y`, `--width`, and `--height` when using flagged rectangle coordinates.")
    }

    let region = try CaptureRegion(
        x: parseInteger(values["--x"]!, flag: "--x"),
        y: parseInteger(values["--y"]!, flag: "--y"),
        width: parseInteger(values["--width"]!, flag: "--width"),
        height: parseInteger(values["--height"]!, flag: "--height")
    )

    try validate(region: region)
    return region
}

private func parseWindowSelection(_ parsed: ParsedArguments) throws -> WindowSelection? {
    var selections: [WindowSelection] = []

    if parsed.flags.contains("--frontmost-window") {
        selections.append(.frontmost)
    }

    if let rawIndex = parsed.values["--window-index"] {
        let index = try parseInteger(rawIndex, flag: "--window-index")
        guard index >= 0 else {
            throw BrrainzToolsError.invalidArguments("`--window-index` must be zero or greater.")
        }
        selections.append(.index(index))
    }

    if let windowName = parsed.values["--window-name"] {
        let trimmed = windowName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BrrainzToolsError.invalidArguments("`--window-name` requires a non-empty title.")
        }
        selections.append(.name(trimmed))
    }

    guard selections.count <= 1 else {
        throw BrrainzToolsError.invalidArguments("Choose only one of `--frontmost-window`, `--window-index`, or `--window-name`.")
    }

    return selections.first
}

private func parseMenuBarSelection(_ parsed: ParsedArguments) throws -> MenuBarSelection? {
    var selections: [MenuBarSelection] = []

    if let rawIndex = parsed.values["--menu-bar-index"] {
        let index = try parseInteger(rawIndex, flag: "--menu-bar-index")
        guard index >= 0 else {
            throw BrrainzToolsError.invalidArguments("`--menu-bar-index` must be zero or greater.")
        }
        selections.append(.index(index))
    }

    if let itemName = parsed.values["--menu-bar-item"] {
        let trimmed = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BrrainzToolsError.invalidArguments("`--menu-bar-item` requires a non-empty title, description, or identifier.")
        }
        selections.append(.name(trimmed))
    }

    guard selections.count <= 1 else {
        throw BrrainzToolsError.invalidArguments("Choose only one of `--menu-bar-index` or `--menu-bar-item`.")
    }

    return selections.first
}

private func parseWindowCrop(_ rawValue: String?) throws -> WindowCropRect? {
    guard let rawValue else {
        return nil
    }

    let components = rawValue
        .split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    guard components.count == 4 else {
        throw BrrainzToolsError.invalidArguments("`--window-crop` must use `x,y,width,height`.")
    }

    let crop = try WindowCropRect(
        x: parseInteger(components[0], flag: "--window-crop"),
        y: parseInteger(components[1], flag: "--window-crop"),
        width: parseInteger(components[2], flag: "--window-crop"),
        height: parseInteger(components[3], flag: "--window-crop")
    )

    guard crop.x >= 0, crop.y >= 0 else {
        throw BrrainzToolsError.invalidArguments("`--window-crop` requires non-negative x and y coordinates.")
    }

    guard crop.width > 0, crop.height > 0 else {
        throw BrrainzToolsError.invalidArguments("`--window-crop` width and height must be greater than zero.")
    }

    return crop
}

private func parseWindowPoint(_ rawValue: String?, flag: String) throws -> WindowPoint? {
    guard let rawValue else {
        return nil
    }

    let components = rawValue
        .split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    guard components.count == 2 else {
        throw BrrainzToolsError.invalidArguments("`\(flag)` must use `x,y`.")
    }

    let point = try WindowPoint(
        x: parseInteger(components[0], flag: flag),
        y: parseInteger(components[1], flag: flag)
    )

    guard point.x >= 0, point.y >= 0 else {
        throw BrrainzToolsError.invalidArguments("`\(flag)` requires non-negative x and y coordinates.")
    }

    return point
}

private func parseWindowDrag(_ rawValue: String?, flag: String) throws -> WindowDrag? {
    guard let rawValue else {
        return nil
    }

    let components = rawValue
        .split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    guard components.count == 4 else {
        throw BrrainzToolsError.invalidArguments("`\(flag)` must use `x1,y1,x2,y2`.")
    }

    let start = try WindowPoint(
        x: parseInteger(components[0], flag: flag),
        y: parseInteger(components[1], flag: flag)
    )
    let end = try WindowPoint(
        x: parseInteger(components[2], flag: flag),
        y: parseInteger(components[3], flag: flag)
    )

    guard start.x >= 0, start.y >= 0, end.x >= 0, end.y >= 0 else {
        throw BrrainzToolsError.invalidArguments("`\(flag)` requires non-negative window coordinates.")
    }

    return WindowDrag(start: start, end: end)
}

private func parseScrollDelta(_ rawValue: String?, flag: String) throws -> ScrollDelta? {
    guard let rawValue else {
        return nil
    }

    let components = rawValue
        .split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    guard components.count == 2 else {
        throw BrrainzToolsError.invalidArguments("`\(flag)` must use `dx,dy`.")
    }

    let x = try parseInteger(components[0], flag: flag)
    let y = try parseInteger(components[1], flag: flag)

    guard x != 0 || y != 0 else {
        throw BrrainzToolsError.invalidArguments("`\(flag)` requires a non-zero x or y delta.")
    }

    guard let deltaX = Int32(exactly: x), let deltaY = Int32(exactly: y) else {
        throw BrrainzToolsError.invalidArguments("`\(flag)` deltas must fit in a 32-bit signed integer.")
    }

    return ScrollDelta(x: deltaX, y: deltaY)
}

private func parseWindowPosition(_ rawValue: String?, flag: String) throws -> WindowPosition? {
    guard let rawValue else {
        return nil
    }

    let components = rawValue
        .split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    guard components.count == 2 else {
        throw BrrainzToolsError.invalidArguments("`\(flag)` must use `x,y`.")
    }

    return try WindowPosition(
        x: parseInteger(components[0], flag: flag),
        y: parseInteger(components[1], flag: flag)
    )
}

private func parseWindowSize(_ rawValue: String?, flag: String) throws -> WindowSize? {
    guard let rawValue else {
        return nil
    }

    let components = rawValue
        .split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    guard components.count == 2 else {
        throw BrrainzToolsError.invalidArguments("`\(flag)` must use `width,height`.")
    }

    let size = try WindowSize(
        width: parseInteger(components[0], flag: flag),
        height: parseInteger(components[1], flag: flag)
    )

    guard size.width > 0, size.height > 0 else {
        throw BrrainzToolsError.invalidArguments("`\(flag)` width and height must be greater than zero.")
    }

    return size
}

private func parseKeyChord(_ rawValue: String?) throws -> KeyChord? {
    guard let rawValue else {
        return nil
    }

    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw BrrainzToolsError.invalidArguments("`--key` requires a non-empty key chord.")
    }

    let parts = trimmed
        .split(separator: "+", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    guard !parts.contains(where: \.isEmpty) else {
        throw BrrainzToolsError.invalidArguments("`--key` chord contains an empty component.")
    }

    var modifiers: [KeyModifier] = []
    var keyNames: [String] = []

    for part in parts {
        if let modifier = keyModifier(named: part) {
            if !modifiers.contains(modifier) {
                modifiers.append(modifier)
            }
        } else {
            keyNames.append(part)
        }
    }

    guard keyNames.count == 1, let keyName = keyNames.first else {
        throw BrrainzToolsError.invalidArguments("`--key` requires exactly one non-modifier key, for example `cmd+s` or `escape`.")
    }

    let normalizedKey = normalizedKeyChordComponent(keyName)
    guard let keyCode = keyCodeByName[normalizedKey] else {
        throw BrrainzToolsError.invalidArguments("Unsupported `--key` key `\(keyName)`.")
    }

    return KeyChord(
        rawValue: trimmed,
        keyName: normalizedKey,
        keyCode: keyCode,
        modifiers: modifiers
    )
}

private func keyModifier(named name: String) -> KeyModifier? {
    switch normalizedKeyChordComponent(name) {
    case "cmd", "command", "meta":
        return .command
    case "shift":
        return .shift
    case "option", "opt", "alt":
        return .option
    case "control", "ctrl":
        return .control
    case "function", "fn":
        return .function
    default:
        return nil
    }
}

private func normalizedKeyChordComponent(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "-", with: "")
        .replacingOccurrences(of: "_", with: "")
        .replacingOccurrences(of: " ", with: "")
}

private let keyCodeByName: [String: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
    "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
    "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
    "5": 23, "equal": 24, "=": 24, "9": 25, "7": 26, "minus": 27,
    "-": 27, "8": 28, "0": 29, "rightbracket": 30, "]": 30, "o": 31,
    "u": 32, "leftbracket": 33, "[": 33, "i": 34, "p": 35, "return": 36,
    "enter": 36, "l": 37, "j": 38, "quote": 39, "'": 39, "k": 40,
    "semicolon": 41, ";": 41, "backslash": 42, "\\": 42, "comma": 43,
    ",": 43, "slash": 44, "/": 44, "n": 45, "m": 46, "period": 47,
    ".": 47, "tab": 48, "space": 49, "spacebar": 49, "grave": 50,
    "`": 50, "delete": 51, "backspace": 51, "escape": 53, "esc": 53,
    "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
    "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    "home": 115, "pageup": 116, "forwarddelete": 117, "end": 119,
    "pagedown": 121, "left": 123, "leftarrow": 123, "arrowleft": 123,
    "right": 124, "rightarrow": 124, "arrowright": 124, "down": 125,
    "downarrow": 125, "arrowdown": 125, "up": 126, "uparrow": 126,
    "arrowup": 126,
]

private func parseAccessibilitySelector(from values: [String: String]) -> AccessibilitySelector {
    AccessibilitySelector(
        path: normalizedArgumentValue(values["--path"]),
        role: normalizedArgumentValue(values["--role"]),
        subrole: normalizedArgumentValue(values["--subrole"]),
        title: normalizedArgumentValue(values["--title"]),
        identifier: normalizedArgumentValue(values["--identifier"]),
        elementDescription: normalizedArgumentValue(values["--description"])
    )
}

private func validateAccessibilitySelector(_ selector: AccessibilitySelector) throws {
    guard let path = selector.path else {
        return
    }

    try validateAccessibilityPath(path)

    if selector.hasNonPathFields {
        throw BrrainzToolsError.invalidArguments("`--path` cannot be combined with `--role`, `--subrole`, `--title`, `--identifier`, or `--description`; paths already identify one element.")
    }
}

private func validateAccessibilityPath(_ path: String) throws {
    let components = path.split(separator: ".", omittingEmptySubsequences: false)
    guard !components.isEmpty else {
        throw BrrainzToolsError.invalidArguments("`--path` requires a dot-separated element path such as `0.3.1`.")
    }

    for component in components {
        guard !component.isEmpty, component.allSatisfy(\.isNumber) else {
            throw BrrainzToolsError.invalidArguments("`--path` requires dot-separated non-negative child indices, for example `0.3.1`.")
        }
    }

    guard components.first == "0" else {
        throw BrrainzToolsError.invalidArguments("`--path` must start at the selected window root `0`.")
    }
}

private func normalizedArgumentValue(_ value: String?) -> String? {
    guard let value else {
        return nil
    }

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func outputURL(from path: String?, format: ImageOutputFormat) throws -> URL {
    guard let path, !path.isEmpty else {
        return temporaryOutputURL(format: format)
    }

    return fileURL(from: path)
}

private func inputURL(from path: String) throws -> URL {
    let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedPath.isEmpty else {
        throw BrrainzToolsError.invalidArguments("Expected a non-empty file path.")
    }

    return fileURL(from: trimmedPath)
}

private func fileURL(from path: String) -> URL {
    let expandedPath = (path as NSString).expandingTildeInPath
    let fileURL: URL

    if expandedPath.hasPrefix("/") {
        fileURL = URL(fileURLWithPath: expandedPath)
    } else {
        fileURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(expandedPath)
    }

    return fileURL.standardizedFileURL
}

private func temporaryOutputURL(format: ImageOutputFormat = .png) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("brrainztools-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString.lowercased())")
        .appendingPathExtension(format.fileExtension)
}

private func parseInteger(_ value: String, flag: String) throws -> Int {
    guard let integer = Int(value) else {
        throw BrrainzToolsError.invalidInteger(flag: flag, value: value)
    }

    return integer
}

private func parseBoundedIntegerOption(
    _ rawValue: String?,
    flag: String,
    defaultValue: Int,
    allowedRange: ClosedRange<Int>
) throws -> Int {
    guard let rawValue else {
        return defaultValue
    }

    let value = try parseInteger(rawValue, flag: flag)
    guard allowedRange.contains(value) else {
        throw BrrainzToolsError.invalidArguments("`\(flag)` must be between \(allowedRange.lowerBound) and \(allowedRange.upperBound).")
    }

    return value
}

private func parseTimeout(_ rawValue: String?) throws -> TimeInterval {
    guard let rawValue else {
        return defaultScreenCaptureKitTimeout
    }

    guard let timeout = TimeInterval(rawValue), timeout > 0 else {
        throw BrrainzToolsError.invalidArguments("`--timeout` requires a positive number of seconds.")
    }

    return timeout
}

private func parseImageOutputOptions(
    formatValue: String?,
    qualityValue: String?,
    maxDimensionValue: String?
) throws -> ImageOutputOptions {
    let format = try parseImageOutputFormat(formatValue)
    let jpegQuality = try parseJPEGQuality(qualityValue)
    let maxDimension = try parseImageMaxDimension(maxDimensionValue)

    return ImageOutputOptions(
        format: format,
        jpegQuality: jpegQuality,
        maxDimension: maxDimension
    )
}

private func parseImageOutputFormat(_ rawValue: String?) throws -> ImageOutputFormat {
    guard let rawValue else {
        return defaultImageOutputOptions.format
    }

    let normalizedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch normalizedValue {
    case "png":
        return .png
    case "jpg", "jpeg":
        return .jpeg
    default:
        throw BrrainzToolsError.invalidArguments("`--format` must be `png` or `jpeg`, got `\(rawValue)`.")
    }
}

private func parseJPEGQuality(_ rawValue: String?) throws -> Double {
    guard let rawValue else {
        return defaultImageOutputOptions.jpegQuality
    }

    guard let quality = Double(rawValue), quality >= 0, quality <= 1 else {
        throw BrrainzToolsError.invalidArguments("`--quality` must be a number from 0 to 1.")
    }

    return quality
}

private func parseImageMaxDimension(_ rawValue: String?) throws -> Int? {
    guard let rawValue else {
        return defaultImageOutputOptions.maxDimension
    }

    let maxDimension = try parseInteger(rawValue, flag: "--max-dimension")
    guard imageMaxDimensionRange.contains(maxDimension) else {
        throw BrrainzToolsError.invalidArguments("`--max-dimension` must be between \(imageMaxDimensionRange.lowerBound) and \(imageMaxDimensionRange.upperBound).")
    }

    return maxDimension
}

private func parseAsciiStyle(_ rawValue: String?) throws -> AsciiArtStyle {
    guard let rawValue else {
        return .layout
    }

    let normalizedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalizedValue.isEmpty else {
        throw BrrainzToolsError.invalidArguments("`--ascii-style` requires `layout` or `tone`.")
    }

    guard let style = AsciiArtStyle(rawValue: normalizedValue) else {
        throw BrrainzToolsError.invalidArguments("`--ascii-style` must be `layout` or `tone`, got `\(rawValue)`.")
    }

    return style
}

func parseOCRLanguages(_ rawValue: String?) throws -> [String] {
    guard let rawValue else {
        return []
    }

    let languages = rawValue
        .split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    guard !languages.isEmpty, languages.allSatisfy({ !$0.isEmpty }) else {
        throw BrrainzToolsError.invalidArguments("`--ascii-language` requires one or more comma-separated language codes.")
    }

    return languages
}

private func parseAccessibilityRoles(_ rawValue: String?) throws -> Set<String> {
    guard let rawValue else {
        return []
    }

    let roles = rawValue
        .split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    guard !roles.isEmpty, roles.allSatisfy({ !$0.isEmpty }) else {
        throw BrrainzToolsError.invalidArguments("`--roles` requires one or more comma-separated accessibility roles.")
    }

    return Set(roles)
}

private func parseAsciiDimension(
    _ rawValue: String?,
    flag: String,
    defaultValue: Int,
    allowedRange: ClosedRange<Int>
) throws -> Int {
    guard let rawValue else {
        return defaultValue
    }

    let dimension = try parseInteger(rawValue, flag: flag)
    guard allowedRange.contains(dimension) else {
        throw BrrainzToolsError.invalidArguments("`\(flag)` must be between \(allowedRange.lowerBound) and \(allowedRange.upperBound).")
    }

    return dimension
}

func captureRegionForDisplayFrame(_ frame: CGRect) throws -> CaptureRegion {
    try captureRegionForDisplayFrames([frame])
}

func captureRegionForDisplayFrames(_ frames: [CGRect]) throws -> CaptureRegion {
    guard let firstFrame = frames.first else {
        throw BrrainzToolsError.captureFailed("No active displays were found.")
    }

    let unionFrame = frames.dropFirst().reduce(firstFrame) { partialResult, frame in
        partialResult.union(frame)
    }
    let minX = Int(floor(unionFrame.minX))
    let minY = Int(floor(unionFrame.minY))
    let maxX = Int(ceil(unionFrame.maxX))
    let maxY = Int(ceil(unionFrame.maxY))
    let region = CaptureRegion(
        x: minX,
        y: minY,
        width: maxX - minX,
        height: maxY - minY
    )

    try validate(region: region)
    return region
}

private func captureRegion(for displaySelection: DisplayCaptureSelection) throws -> CaptureRegion {
    let frames = activeDisplayFrames()

    switch displaySelection {
    case .displayID(let displayID):
        guard let frame = frames.first(where: { $0.id == displayID })?.frame else {
            throw BrrainzToolsError.invalidArguments("No active display has id \(displayID). Run `brrainztools --list-displays` to see display ids.")
        }

        return try captureRegionForDisplayFrame(frame)
    case .allDisplays:
        return try captureRegionForDisplayFrames(frames.map(\.frame))
    }
}

private func validate(region: CaptureRegion) throws {
    guard region.width > 0 else {
        throw BrrainzToolsError.invalidRegion("Width must be greater than zero.")
    }

    guard region.height > 0 else {
        throw BrrainzToolsError.invalidRegion("Height must be greater than zero.")
    }
}

private func capture(using command: CaptureCommand) async throws {
    let directoryURL = command.outputURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

    if let displaySelection = command.displaySelection {
        let region = try captureRegion(for: displaySelection)
        try await captureScreenRegion(
            region: region,
            outputURL: command.outputURL,
            timeout: command.screenCaptureTimeout,
            imageOutput: command.imageOutput
        )
        return
    }

    if let applicationSelector = command.applicationSelector {
        let shareableContent = try await loadShareableContent(
            timeout: command.screenCaptureTimeout,
            selector: applicationSelector
        )
        let catalog = try buildWindowCatalog(selector: applicationSelector, in: shareableContent)

        if let windowSelection = command.windowSelection {
            let window = try selectWindow(from: catalog, using: windowSelection)
            try await captureWindow(
                window,
                crop: command.windowCrop,
                outputURL: command.outputURL,
                timeout: command.screenCaptureTimeout,
                selector: applicationSelector,
                imageOutput: command.imageOutput
            )
            return
        }

        guard let region = command.region else {
            throw BrrainzToolsError.invalidArguments("App-filtered rectangle capture requires rectangle coordinates.")
        }

        try await captureApplicationRegion(
            application: catalog.application,
            windows: catalog.windows.map(\.scWindow),
            displays: shareableContent.displays,
            region: region,
            outputURL: command.outputURL,
            timeout: command.screenCaptureTimeout,
            selector: applicationSelector,
            imageOutput: command.imageOutput
        )
        return
    }

    guard let region = command.region else {
        throw BrrainzToolsError.invalidArguments("Rectangle capture requires coordinates when no app is specified.")
    }

    try await captureScreenRegion(
        region: region,
        outputURL: command.outputURL,
        timeout: command.screenCaptureTimeout,
        imageOutput: command.imageOutput
    )
}

private func captureScreenRegion(
    region: CaptureRegion,
    outputURL: URL,
    timeout: TimeInterval = defaultScreenCaptureKitTimeout,
    imageOutput: ImageOutputOptions = defaultImageOutputOptions
) async throws {
    try await captureScreenRegion(
        region: region,
        outputURL: outputURL,
        ensureAccess: ensureScreenCaptureAccess,
        runCapture: { region, outputURL in
            try await captureDisplayRegion(
                region: region,
                outputURL: outputURL,
                timeout: timeout,
                imageOutput: imageOutput
            )
        },
        fileExists: { FileManager.default.fileExists(atPath: $0) }
    )
}

func captureScreenRegion(
    region: CaptureRegion,
    outputURL: URL,
    ensureAccess: () throws -> Void,
    runCapture: (CaptureRegion, URL) async throws -> Void,
    fileExists: (String) -> Bool
) async throws {
    try ensureAccess()

    try await runCapture(region, outputURL)

    guard fileExists(outputURL.path) else {
        throw BrrainzToolsError.captureFailed("Capture succeeded but no PNG was written to \(outputURL.path).")
    }
}

private func listWindows(using command: ListWindowsCommand) async throws -> String {
    let shareableContent = try await loadShareableContent(
        timeout: command.screenCaptureTimeout,
        selector: command.applicationSelector
    )
    let catalog = try buildWindowCatalog(selector: command.applicationSelector, in: shareableContent)

    let response = WindowListResponse(
        application: windowListApplication(for: catalog.application),
        windows: catalog.windows.map(windowListEntry(for:))
    )

    return try encodeJSON(response)
}

private func inspectAccessibility(using command: AccessibilityCommand) async throws -> String {
    try ensureAccessibilityAccess(prompt: command.promptForAccessibility)

    switch command.mode {
    case .typeText(let text):
        let application = try resolveAutomationApplication(selector: command.applicationSelector)
        let activationRequestAccepted = activateApplication(application)
        try await Task.sleep(nanoseconds: 100_000_000)
        try postText(text, to: application.processID)
        return try encodeJSON(
            KeyboardInputResponse(
                application: windowListApplication(for: application),
                mode: "type",
                text: text,
                chord: nil,
                key: nil,
                modifiers: nil,
                activationRequestAccepted: activationRequestAccepted
            )
        )
    case .keyChord(let chord):
        let application = try resolveAutomationApplication(selector: command.applicationSelector)
        let activationRequestAccepted = activateApplication(application)
        try await Task.sleep(nanoseconds: 100_000_000)
        try postKeyChord(chord, to: application.processID)
        return try encodeJSON(
            KeyboardInputResponse(
                application: windowListApplication(for: application),
                mode: "key",
                text: nil,
                chord: chord.rawValue,
                key: chord.keyName,
                modifiers: chord.modifierNames,
                activationRequestAccepted: activationRequestAccepted
            )
        )
    default:
        break
    }

    if case .waitForWindow(let title) = command.mode {
        let waited = try waitForAccessibilityWindow(
            selector: command.applicationSelector,
            title: title,
            timeout: command.timeout
        )
        let response = AccessibilityWaitForWindowResponse(
            application: windowListApplication(for: waited.catalog.application),
            frontmostApplication: waited.catalog.frontmostApplication.map(windowListApplication(for:)),
            mode: "wait-for-window",
            title: title,
            window: accessibilityWindowEntry(for: waited.window)
        )
        return try encodeJSON(response)
    }

    let catalog = try buildAccessibilityWindowCatalog(selector: command.applicationSelector)
    let selectedWindow = try selectAccessibilityWindow(from: catalog, using: command.windowSelection)
    let accessibilityWindow = selectedWindow.element

    switch command.mode {
    case .waitForWindow, .typeText, .keyChord:
        throw BrrainzToolsError.accessibilityQueryFailed("Internal error: an app-level accessibility action reached the selected-window execution path.")
    case .listWindows:
        let response = AccessibilityWindowListResponse(
            application: windowListApplication(for: catalog.application),
            frontmostApplication: catalog.frontmostApplication.map(windowListApplication(for:)),
            frontnessSemantics: "AX-focused/main window of NSWorkspace frontmost application",
            windows: catalog.windows.map(accessibilityWindowEntry(for:))
        )
        return try encodeJSON(response)
    case .listElements:
        let tree = accessibilityElementResponse(
            for: accessibilityWindow,
            depthRemaining: command.treeDepth,
            childLimit: command.treeChildLimit,
            path: "0"
        )
        let filteredTree = filteredAccessibilityTree(
            tree,
            roleFilter: command.treeRoleFilter,
            interactiveOnly: command.treeInteractiveOnly
        ) ?? replacingChildren(in: tree, with: tree.children == nil ? nil : [])

        if command.treeFlat {
            let response = AccessibilityFlatTreeResponse(
                application: windowListApplication(for: catalog.application),
                window: accessibilityWindowEntry(for: selectedWindow),
                elements: flatAccessibilityElements(
                    from: tree,
                    roleFilter: command.treeRoleFilter,
                    interactiveOnly: command.treeInteractiveOnly
                )
            )
            return try encodeJSON(response)
        }

        let response = AccessibilityTreeResponse(
            application: windowListApplication(for: catalog.application),
            window: accessibilityWindowEntry(for: selectedWindow),
            tree: filteredTree
        )
        return try encodeJSON(response)
    case .elementAt(let point):
        try validate(windowPoint: point, within: selectedWindow.frame, windowTitle: displayTitle(selectedWindow.title), flag: "--element-at")

        let screenPoint = CGPoint(
            x: selectedWindow.frame.minX + CGFloat(point.x),
            y: selectedWindow.frame.minY + CGFloat(point.y)
        )

        let hitElement = try hitTestElement(at: screenPoint)
        try validateHitElement(
            hitElement,
            belongsTo: accessibilityWindow,
            selectedWindowTitle: selectedWindow.title
        )
        let refinedHitElement = deepestAccessibilityElement(
            in: accessibilityWindow,
            containing: screenPoint,
            depthRemaining: 8
        ) ?? hitElement

        let response = AccessibilityHitResponse(
            application: windowListApplication(for: catalog.application),
            window: accessibilityWindowEntry(for: selectedWindow),
            point: JSONPoint(point.point),
            screenPoint: JSONPoint(screenPoint),
            hit: accessibilityElementResponse(for: refinedHitElement, depthRemaining: 1),
            ancestors: accessibilityAncestorResponses(for: refinedHitElement, stoppingAt: accessibilityWindow)
        )
        return try encodeJSON(response)
    case .getElement(let selector):
        let selectedElement = try selectAccessibilityElement(in: accessibilityWindow, using: selector)
        let response = AccessibilityGetResponse(
            application: windowListApplication(for: catalog.application),
            window: accessibilityWindowEntry(for: selectedWindow),
            mode: "get",
            selector: accessibilitySelectorResponse(for: selector),
            matched: accessibilityElementResponse(for: selectedElement.element, depthRemaining: 1),
            ancestors: accessibilityAncestorResponses(for: selectedElement.element, stoppingAt: accessibilityWindow)
        )
        return try encodeJSON(response)
    case .waitForElement(let selector):
        let selectedElement = try waitForAccessibilityElement(
            in: accessibilityWindow,
            using: selector,
            timeout: command.timeout
        )
        let response = AccessibilityGetResponse(
            application: windowListApplication(for: catalog.application),
            window: accessibilityWindowEntry(for: selectedWindow),
            mode: "wait-for-element",
            selector: accessibilitySelectorResponse(for: selector),
            matched: accessibilityElementResponse(for: selectedElement.element, depthRemaining: 1),
            ancestors: accessibilityAncestorResponses(for: selectedElement.element, stoppingAt: accessibilityWindow)
        )
        return try encodeJSON(response)
    case .setValue(let selector, let value):
        let selectedElement = try selectAccessibilityElement(in: accessibilityWindow, using: selector)
        let matchedSnapshot = accessibilityElementResponse(
            for: selectedElement.element,
            depthRemaining: 1
        )
        let ancestorSnapshots = accessibilityAncestorResponses(
            for: selectedElement.element,
            stoppingAt: accessibilityWindow
        )
        try performSetValue(value, on: selectedElement.element)
        let response = AccessibilitySetValueResponse(
            application: windowListApplication(for: catalog.application),
            window: accessibilityWindowEntry(for: selectedWindow),
            mode: "set-value",
            attribute: kAXValueAttribute as String,
            value: value,
            selector: accessibilitySelectorResponse(for: selector),
            matched: refreshedAccessibilityElementResponse(
                for: selectedElement.element,
                fallback: matchedSnapshot
            ),
            ancestors: ancestorSnapshots
        )
        return try encodeJSON(response)
    case .click(let click):
        try validate(windowPoint: click.point, within: selectedWindow.frame, windowTitle: displayTitle(selectedWindow.title), flag: "--click")
        let screenPoint = screenPoint(for: click.point, in: selectedWindow.frame)
        let preparation = try await prepareForMouseInput(application: catalog.application, window: accessibilityWindow)
        try postMouseClick(click, at: screenPoint)
        let response = MouseActionResponse(
            application: windowListApplication(for: catalog.application),
            window: accessibilityWindowEntry(for: selectedWindow),
            mode: "click",
            selector: nil,
            matched: nil,
            button: click.button.rawValue,
            clickCount: click.clickCount,
            point: JSONPoint(click.point.point),
            screenPoint: JSONPoint(screenPoint),
            endPoint: nil,
            screenEndPoint: nil,
            deltaX: nil,
            deltaY: nil,
            activationRequestAccepted: preparation.activationRequestAccepted,
            windowRaiseAttempted: preparation.windowRaiseAttempted
        )
        return try encodeJSON(response)
    case .drag(let drag):
        try validate(windowPoint: drag.start, within: selectedWindow.frame, windowTitle: displayTitle(selectedWindow.title), flag: "--drag")
        try validate(windowPoint: drag.end, within: selectedWindow.frame, windowTitle: displayTitle(selectedWindow.title), flag: "--drag")
        let startScreenPoint = screenPoint(for: drag.start, in: selectedWindow.frame)
        let endScreenPoint = screenPoint(for: drag.end, in: selectedWindow.frame)
        let preparation = try await prepareForMouseInput(application: catalog.application, window: accessibilityWindow)
        try postMouseDrag(from: startScreenPoint, to: endScreenPoint)
        let response = MouseActionResponse(
            application: windowListApplication(for: catalog.application),
            window: accessibilityWindowEntry(for: selectedWindow),
            mode: "drag",
            selector: nil,
            matched: nil,
            button: MouseButton.left.rawValue,
            clickCount: nil,
            point: JSONPoint(drag.start.point),
            screenPoint: JSONPoint(startScreenPoint),
            endPoint: JSONPoint(drag.end.point),
            screenEndPoint: JSONPoint(endScreenPoint),
            deltaX: nil,
            deltaY: nil,
            activationRequestAccepted: preparation.activationRequestAccepted,
            windowRaiseAttempted: preparation.windowRaiseAttempted
        )
        return try encodeJSON(response)
    case .scroll(let delta, let selector):
        let selectedElement = try selector.map {
            try selectAccessibilityElement(in: accessibilityWindow, using: $0)
        }
        let targetScreenPoint: CGPoint
        let point: CGPoint

        if let selector, let selectedElement {
            guard
                let elementFrame = selectedElement.frame,
                let visibleCenter = visibleCenterPoint(of: elementFrame, within: selectedWindow.frame)
            else {
                throw BrrainzToolsError.accessibilityQueryFailed(
                    "Accessibility element matching \(describe(selector: selector)) has no visible frame inside window `\(displayTitle(selectedWindow.title))`."
                )
            }

            targetScreenPoint = visibleCenter
            point = CGPoint(
                x: targetScreenPoint.x - selectedWindow.frame.minX,
                y: targetScreenPoint.y - selectedWindow.frame.minY
            )
        } else {
            let windowPoint = centerPoint(in: selectedWindow.frame)
            point = windowPoint.point
            targetScreenPoint = screenPoint(for: windowPoint, in: selectedWindow.frame)
        }

        let matchedSnapshot = selectedElement.map {
            accessibilityElementResponse(
                for: $0.element,
                depthRemaining: 0,
                path: selector?.path
            )
        }
        let preparation = try await prepareForMouseInput(application: catalog.application, window: accessibilityWindow)
        try postScroll(delta, at: targetScreenPoint)
        let response = MouseActionResponse(
            application: windowListApplication(for: catalog.application),
            window: accessibilityWindowEntry(for: selectedWindow),
            mode: "scroll",
            selector: selector.map(accessibilitySelectorResponse(for:)),
            matched: matchedSnapshot,
            button: nil,
            clickCount: nil,
            point: JSONPoint(point),
            screenPoint: JSONPoint(targetScreenPoint),
            endPoint: nil,
            screenEndPoint: nil,
            deltaX: delta.x,
            deltaY: delta.y,
            activationRequestAccepted: preparation.activationRequestAccepted,
            windowRaiseAttempted: preparation.windowRaiseAttempted
        )
        return try encodeJSON(response)
    case .pressAt(let point):
        try validate(windowPoint: point, within: selectedWindow.frame, windowTitle: displayTitle(selectedWindow.title), flag: "--press-at")

        let screenPoint = CGPoint(
            x: selectedWindow.frame.minX + CGFloat(point.x),
            y: selectedWindow.frame.minY + CGFloat(point.y)
        )

        let hitElement = try hitTestElement(at: screenPoint)
        try validateHitElement(
            hitElement,
            belongsTo: accessibilityWindow,
            selectedWindowTitle: selectedWindow.title
        )
        let refinedHitElement = deepestAccessibilityElement(
            in: accessibilityWindow,
            containing: screenPoint,
            depthRemaining: 8
        ) ?? hitElement
        let pressableElement = try resolvePressableElement(
            startingAt: refinedHitElement,
            within: accessibilityWindow,
            failureContext: "No pressable accessibility element was found at window point \(point.x),\(point.y)."
        )
        let matchedSnapshot = accessibilityElementResponse(
            for: refinedHitElement,
            depthRemaining: 1
        )
        let pressedSnapshot = accessibilityElementResponse(
            for: pressableElement,
            depthRemaining: 1
        )
        let ancestorSnapshots = accessibilityAncestorResponses(
            for: pressableElement,
            stoppingAt: accessibilityWindow
        )
        let modalProbe = transientModalDisappearanceProbe(
            for: pressableElement,
            stoppingAt: accessibilityWindow
        )

        try performPress(
            on: pressableElement,
            verifyPostcondition: modalProbe.map { probe in
                { probe.isAbsent() }
            }
        )

        let response = AccessibilityPressResponse(
            application: windowListApplication(for: catalog.application),
            window: accessibilityWindowEntry(for: selectedWindow),
            mode: "press-at",
            action: kAXPressAction as String,
            selector: nil,
            point: JSONPoint(point.point),
            screenPoint: JSONPoint(screenPoint),
            matched: refreshedAccessibilityElementResponse(
                for: refinedHitElement,
                fallback: matchedSnapshot
            ),
            pressed: refreshedAccessibilityElementResponse(
                for: pressableElement,
                fallback: pressedSnapshot
            ),
            ancestors: ancestorSnapshots
        )
        return try encodeJSON(response)
    case .pressElement(let selector):
        let pressableElement = try selectPressableAccessibilityElement(in: accessibilityWindow, using: selector)
        let matchedSnapshot = accessibilityElementResponse(
            for: pressableElement.element,
            depthRemaining: 1
        )
        let ancestorSnapshots = accessibilityAncestorResponses(
            for: pressableElement.element,
            stoppingAt: accessibilityWindow
        )
        let modalProbe = transientModalDisappearanceProbe(
            for: pressableElement.element,
            stoppingAt: accessibilityWindow
        )

        try performPress(
            on: pressableElement.element,
            verifyPostcondition: modalProbe.map { probe in
                { probe.isAbsent() }
            }
        )

        let response = AccessibilityPressResponse(
            application: windowListApplication(for: catalog.application),
            window: accessibilityWindowEntry(for: selectedWindow),
            mode: "press",
            action: kAXPressAction as String,
            selector: accessibilitySelectorResponse(for: selector),
            point: nil,
            screenPoint: nil,
            matched: refreshedAccessibilityElementResponse(
                for: pressableElement.element,
                fallback: matchedSnapshot
            ),
            pressed: refreshedAccessibilityElementResponse(
                for: pressableElement.element,
                fallback: matchedSnapshot
            ),
            ancestors: ancestorSnapshots
        )
        return try encodeJSON(response)
    case .raiseWindow:
        let activationRequestAccepted = activateApplication(catalog.application)
        _ = try performRaise(
            on: accessibilityWindow,
            application: catalog.application
        )
        try await Task.sleep(nanoseconds: 150_000_000)

        let refreshedCatalog = try buildAccessibilityWindowCatalog(selector: command.applicationSelector)
        let refreshedWindow = try selectAccessibilityWindow(from: refreshedCatalog, using: command.windowSelection)
        let response = AccessibilityRaiseWindowResponse(
            application: windowListApplication(for: refreshedCatalog.application),
            frontmostApplication: refreshedCatalog.frontmostApplication.map(windowListApplication(for:)),
            window: accessibilityWindowEntry(for: refreshedWindow),
            action: kAXRaiseAction as String,
            activationRequestAccepted: activationRequestAccepted
        )
        return try encodeJSON(response)
    case .closeWindow:
        guard let closeButton = copyAXElement(from: accessibilityWindow, attribute: kAXCloseButtonAttribute as CFString) else {
            throw BrrainzToolsError.accessibilityQueryFailed("Selected window \(formatAXElement(accessibilityWindow)) does not expose an `AXCloseButton`.")
        }

        let targetSnapshot = accessibilityElementResponse(
            for: closeButton,
            depthRemaining: 1
        )
        let disappearanceProbe = windowDisappearanceProbe(
            application: catalog.application,
            window: accessibilityWindow
        )
        try performPress(
            on: closeButton,
            verifyPostcondition: {
                if disappearanceProbe?.isAbsent() == true {
                    return true
                }

                guard let runningApplication = NSRunningApplication(
                    processIdentifier: catalog.application.processID
                ) else {
                    return true
                }
                return runningApplication.isTerminated
            }
        )
        let response = AccessibilityCloseWindowResponse(
            application: windowListApplication(for: catalog.application),
            window: accessibilityWindowEntry(for: selectedWindow),
            action: kAXPressAction as String,
            target: refreshedAccessibilityElementResponse(
                for: closeButton,
                fallback: targetSnapshot
            )
        )
        return try encodeJSON(response)
    case .minimizeWindow:
        guard let minimizeButton = copyAXElement(from: accessibilityWindow, attribute: kAXMinimizeButtonAttribute as CFString) else {
            throw BrrainzToolsError.accessibilityQueryFailed("Selected window \(formatAXElement(accessibilityWindow)) does not expose an `AXMinimizeButton`.")
        }

        let targetSnapshot = accessibilityElementResponse(
            for: minimizeButton,
            depthRemaining: 1
        )
        try performPress(
            on: minimizeButton,
            verifyPostcondition: {
                copyAXBool(
                    from: accessibilityWindow,
                    attribute: kAXMinimizedAttribute as CFString
                ) == true
            }
        )
        let response = AccessibilityMinimizeWindowResponse(
            application: windowListApplication(for: catalog.application),
            window: accessibilityWindowEntry(for: selectedWindow),
            action: kAXPressAction as String,
            target: refreshedAccessibilityElementResponse(
                for: minimizeButton,
                fallback: targetSnapshot
            )
        )
        return try encodeJSON(response)
    case .moveWindow(let position):
        try performSetWindowPosition(position, on: accessibilityWindow)
        let response = AccessibilityMoveWindowResponse(
            application: windowListApplication(for: catalog.application),
            window: accessibilityWindowEntry(for: selectedWindow),
            attribute: kAXPositionAttribute as String,
            position: JSONPoint(position.point),
            updatedFrame: copyAXFrame(from: accessibilityWindow).map(JSONRect.init)
        )
        return try encodeJSON(response)
    case .resizeWindow(let size):
        try performSetWindowSize(size, on: accessibilityWindow)
        let response = AccessibilityResizeWindowResponse(
            application: windowListApplication(for: catalog.application),
            window: accessibilityWindowEntry(for: selectedWindow),
            attribute: kAXSizeAttribute as String,
            size: JSONSize(size.size),
            updatedFrame: copyAXFrame(from: accessibilityWindow).map(JSONRect.init)
        )
        return try encodeJSON(response)
    }
}

private func handleMenuBar(using command: MenuBarCommand) async throws -> String {
    try ensureAccessibilityAccess(prompt: command.promptForAccessibility)

    let catalog = try buildMenuBarItemCatalog(selector: command.applicationSelector)

    switch command.mode {
    case .listItems:
        let response = MenuBarListResponse(
            application: windowListApplication(for: catalog.application),
            items: catalog.items.map(menuBarItemEntry(for:))
        )
        return try encodeJSON(response)
    case .tree(let options):
        let items: [MenuBarCatalogItem]
        if let selection = command.selection {
            items = [try selectMenuBarItem(from: catalog, using: selection)]
        } else {
            items = catalog.items
        }

        let response = MenuTreeResponse(
            application: windowListApplication(for: catalog.application),
            items: items.map { item in
                menuTreeNode(
                    for: item,
                    depthRemaining: options.depth,
                    childLimit: options.childLimit
                )
            }
        )
        return try encodeJSON(response)
    case .pressItem:
        let item = try selectMenuBarItem(from: catalog, using: command.selection)
        let menu = try activateMenuBarItem(item, requireVisibleMenu: false)
        let response = MenuBarPressResponse(
            application: windowListApplication(for: catalog.application),
            item: menuBarItemEntry(for: item),
            action: kAXPressAction as String,
            menu: menu.map { accessibilityElementResponse(for: $0, depthRemaining: 2) }
        )
        return try encodeJSON(response)
    case .pressMenuItem(let childSelection):
        let item = try selectMenuBarItem(from: catalog, using: command.selection)
        guard let menu = try activateMenuBarItem(item, requireVisibleMenu: true) else {
            throw BrrainzToolsError.accessibilityQueryFailed("No visible AX menu appeared after pressing \(formatMenuBarCandidate(item)).")
        }

        do {
            let menuItem = try selectMenuChildItem(in: menu, matching: childSelection)
            let menuItemResponse = accessibilityElementResponse(for: menuItem.element, depthRemaining: 1)
            let ancestors = accessibilityAncestorResponses(for: menuItem.element, stoppingAt: menu)
            let action = try performMenuItemAction(on: menuItem, in: menu)

            let response = MenuBarChildPressResponse(
                application: windowListApplication(for: catalog.application),
                item: menuBarItemEntry(for: item),
                action: action,
                menuItem: menuItemResponse,
                ancestors: ancestors
            )
            return try encodeJSON(response)
        } catch {
            cancelMenu(menu)
            throw error
        }
    case .captureMenu:
        let item = try selectMenuBarItem(from: catalog, using: command.selection)
        let surface = try openMenuBarSurface(for: item, application: catalog.application)
        defer {
            closeMenuBarSurface(surface, item: item)
        }

        let outputURL = command.outputURL ?? temporaryOutputURL()
        let directoryURL = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try await captureMenuBarSurface(
            surface,
            item: item,
            outputURL: outputURL,
            timeout: command.screenCaptureTimeout,
            imageOutput: command.imageOutput
        )
        return outputURL.path
    }
}

private func findApps(using command: FindAppsCommand) throws -> String {
    let matches = rankedRunningApplicationMatches(query: command.query)
        .enumerated()
        .map { offset, match in
            runningApplicationEntry(
                for: match.application,
                index: offset,
                visibleWindowCount: match.visibleWindowCount
            )
        }

    return try encodeJSON(
        RunningApplicationSearchResponse(
            query: command.query,
            matches: matches
        )
    )
}

private func listVisibleWindows(using command: VisibleWindowsCommand) throws -> String {
    let catalog = try buildVisibleWindowCatalog(selector: command.applicationSelector)
    let response = VisibleWindowListResponse(
        application: windowListApplication(for: catalog.application),
        captureSemantics: "visible-pixels; other windows in front of the target window are included",
        windows: catalog.windows.map(visibleWindowEntry(for:))
    )
    return try encodeJSON(response)
}

private func captureVisibleWindow(using command: VisibleWindowCaptureCommand) async throws {
    let directoryURL = command.outputURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

    let catalog = try buildVisibleWindowCatalog(selector: command.applicationSelector)
    let window = try selectVisibleWindow(from: catalog, using: command.windowSelection)
    let region = try captureRegion(forVisibleWindow: window, crop: command.windowCrop)

    do {
        try await captureScreenRegion(
            region: region,
            outputURL: command.outputURL,
            timeout: command.screenCaptureTimeout,
            imageOutput: command.imageOutput
        )
    } catch BrrainzToolsError.captureFailed(let message) {
        throw BrrainzToolsError.captureFailed("Failed to capture visible window [\(window.index)] \(displayTitle(window.title)) for `\(catalog.application.name)` at `\(region.rectangleArgument)`: \(message)")
    }
}

private func asciiArtReport(using command: AsciiArtCommand) async throws -> String {
    let image = try loadImage(at: command.imageURL)
    let ocrStatus: OCRReportStatus
    if command.includeOCR {
        do {
            ocrStatus = .blocks(try await recognizeTextBlocks(
                in: image,
                recognitionLanguages: command.recognitionLanguages
            ))
        } catch {
            ocrStatus = .unavailable(error.localizedDescription)
        }
    } else {
        ocrStatus = .disabled
    }

    if case .ocrOnly = command.outputMode {
        return try formatOCROnlyResponse(
            imagePath: command.imageURL.path,
            imageWidth: image.width,
            imageHeight: image.height,
            ocrStatus: ocrStatus
        )
    }

    let rendered: RenderedAsciiArt
    switch command.style {
    case .layout:
        let textBlocks: [OCRTextBlock]
        if case .blocks(let blocks) = ocrStatus {
            textBlocks = blocks
        } else {
            textBlocks = []
        }

        rendered = try renderAsciiLayout(
            from: image,
            options: AsciiLayoutOptions(
                width: command.width,
                maxHeight: command.maxHeight
            ),
            textBlocks: textBlocks
        )
    case .tone:
        rendered = try renderAsciiArt(
            from: image,
            options: AsciiArtOptions(
                width: command.width,
                maxHeight: command.maxHeight,
                invert: command.invert
            )
        )
    }

    return formatAsciiArtReport(
        imagePath: command.imageURL.path,
        imageWidth: image.width,
        imageHeight: image.height,
        style: command.style,
        rendered: rendered,
        ocrStatus: ocrStatus
    )
}

private func captureOutputEnvelopeJSON(
    mode: String,
    outputURL: URL,
    textOutput: CaptureTextOptions?
) async throws -> String {
    guard let textOutput else {
        return try outputEnvelopeJSON(mode: mode, output: outputURL.path)
    }

    let command = AsciiArtCommand(
        imageURL: outputURL,
        style: textOutput.style,
        outputMode: textOutput.outputMode,
        width: textOutput.width,
        maxHeight: textOutput.maxHeight,
        invert: textOutput.invert,
        includeOCR: textOutput.includeOCR,
        recognitionLanguages: textOutput.recognitionLanguages,
        rawOutput: false
    )
    let text = try await asciiArtReport(using: command)

    switch textOutput.outputMode {
    case .report:
        return try outputReportEnvelopeJSON(mode: mode, output: outputURL.path, report: text)
    case .ocrOnly:
        return try outputDataEnvelopeJSON(mode: mode, output: outputURL.path, dataJSON: text)
    }
}

private func loadImage(at imageURL: URL) throws -> CGImage {
    guard FileManager.default.fileExists(atPath: imageURL.path) else {
        throw BrrainzToolsError.captureFailed("Image file not found: \(imageURL.path)")
    }

    guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil) else {
        throw BrrainzToolsError.captureFailed("Failed to read image data from \(imageURL.path).")
    }

    guard let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: true] as CFDictionary) else {
        throw BrrainzToolsError.captureFailed("Failed to decode an image from \(imageURL.path).")
    }

    return image
}

func renderAsciiArt(from image: CGImage, options: AsciiArtOptions) throws -> RenderedAsciiArt {
    guard image.width > 0, image.height > 0 else {
        throw BrrainzToolsError.captureFailed("Cannot render ASCII art for an empty image.")
    }

    guard options.width > 0, options.maxHeight > 0 else {
        throw BrrainzToolsError.invalidArguments("ASCII width and max height must be greater than zero.")
    }

    let targetWidth = options.width
    let aspectRatio = Double(image.height) / Double(image.width)
    let naturalHeight = max(1, Int((Double(targetWidth) * aspectRatio * 0.5).rounded()))
    let targetHeight = min(options.maxHeight, naturalHeight)
    let renderedPixels = try renderImagePixels(
        from: image,
        width: targetWidth,
        height: targetHeight,
        interpolationQuality: .medium,
        failureContext: "ASCII"
    )

    let ramp = Array("@%#*+=-:. ")
    var lines: [String] = []
    lines.reserveCapacity(targetHeight)

    for row in 0..<targetHeight {
        var line = ""
        line.reserveCapacity(targetWidth)

        for column in 0..<targetWidth {
            let luminance = renderedPixels.luminance(atColumn: column, row: row)
            let mappedLuminance = options.invert ? 255 - luminance : luminance
            let rampIndex = min(
                ramp.count - 1,
                max(0, Int((Double(mappedLuminance) / 255.0) * Double(ramp.count - 1)))
            )

            line.append(ramp[rampIndex])
        }

        lines.append(line)
    }

    return RenderedAsciiArt(
        width: targetWidth,
        height: targetHeight,
        text: lines.joined(separator: "\n")
    )
}

func renderAsciiLayout(from image: CGImage, options: AsciiLayoutOptions, textBlocks: [OCRTextBlock]) throws -> RenderedAsciiArt {
    guard image.width > 0, image.height > 0 else {
        throw BrrainzToolsError.captureFailed("Cannot render ASCII layout for an empty image.")
    }

    guard options.width > 0, options.maxHeight > 0 else {
        throw BrrainzToolsError.invalidArguments("ASCII width and max height must be greater than zero.")
    }

    let targetWidth = options.width
    let aspectRatio = Double(image.height) / Double(image.width)
    let naturalHeight = max(1, Int((Double(targetWidth) * aspectRatio * 0.5).rounded()))
    let targetHeight = min(options.maxHeight, naturalHeight)
    let renderedPixels = try renderImagePixels(
        from: image,
        width: targetWidth,
        height: targetHeight,
        interpolationQuality: .medium,
        failureContext: "ASCII layout"
    )
    var canvas = makeCharacterCanvas(width: targetWidth, height: targetHeight)
    let luminanceGrid = luminanceGrid(from: renderedPixels)

    drawLayoutEdges(on: &canvas, luminanceGrid: luminanceGrid)
    clearOCRRegions(
        on: &canvas,
        textBlocks: textBlocks,
        imageWidth: image.width,
        imageHeight: image.height
    )
    overlayOCRText(
        on: &canvas,
        textBlocks: textBlocks,
        imageWidth: image.width,
        imageHeight: image.height
    )

    return RenderedAsciiArt(
        width: targetWidth,
        height: targetHeight,
        text: canvas.map { String($0) }.joined(separator: "\n")
    )
}

private struct RenderedImagePixels {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let pixels: [UInt8]

    func luminance(atColumn column: Int, row: Int) -> Int {
        let offset = (row * bytesPerRow) + (column * 4)
        let red = Double(pixels[offset])
        let green = Double(pixels[offset + 1])
        let blue = Double(pixels[offset + 2])
        return Int((0.2126 * red + 0.7152 * green + 0.0722 * blue).rounded())
    }
}

private func renderImagePixels(
    from image: CGImage,
    width targetWidth: Int,
    height targetHeight: Int,
    interpolationQuality: CGInterpolationQuality,
    failureContext: String
) throws -> RenderedImagePixels {
    let bytesPerPixel = 4
    let bytesPerRow = targetWidth * bytesPerPixel
    var pixels = [UInt8](repeating: 255, count: bytesPerRow * targetHeight)

    try pixels.withUnsafeMutableBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else {
            throw BrrainzToolsError.captureFailed("Failed to allocate an \(failureContext) render buffer.")
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue |
            CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: baseAddress,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw BrrainzToolsError.captureFailed("Failed to create an \(failureContext) render context.")
        }

        let targetRect = CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(targetRect)
        context.interpolationQuality = interpolationQuality
        context.draw(image, in: targetRect)
    }

    return RenderedImagePixels(
        width: targetWidth,
        height: targetHeight,
        bytesPerRow: bytesPerRow,
        pixels: pixels
    )
}

private func luminanceGrid(from pixels: RenderedImagePixels) -> [[Int]] {
    (0..<pixels.height).map { row in
        (0..<pixels.width).map { column in
            pixels.luminance(atColumn: column, row: row)
        }
    }
}

private func makeCharacterCanvas(width: Int, height: Int) -> [[Character]] {
    Array(repeating: Array(repeating: Character(" "), count: width), count: height)
}

private func drawLayoutEdges(on canvas: inout [[Character]], luminanceGrid: [[Int]]) {
    let height = luminanceGrid.count
    guard height > 2, let width = luminanceGrid.first?.count, width > 2 else {
        return
    }

    let strongEdgeThreshold = 42

    for row in 1..<(height - 1) {
        for column in 1..<(width - 1) {
            let horizontalGradient = abs(luminanceGrid[row][column + 1] - luminanceGrid[row][column - 1])
            let verticalGradient = abs(luminanceGrid[row + 1][column] - luminanceGrid[row - 1][column])
            let localContrast = max(horizontalGradient, verticalGradient)

            guard localContrast >= strongEdgeThreshold else {
                continue
            }

            let character: Character
            if horizontalGradient >= strongEdgeThreshold, verticalGradient >= strongEdgeThreshold {
                character = "+"
            } else if horizontalGradient > verticalGradient {
                character = "|"
            } else {
                character = "-"
            }

            canvas[row][column] = character
        }
    }
}

private func clearOCRRegions(
    on canvas: inout [[Character]],
    textBlocks: [OCRTextBlock],
    imageWidth: Int,
    imageHeight: Int
) {
    let gridHeight = canvas.count
    guard gridHeight > 0, let gridWidth = canvas.first?.count else {
        return
    }

    for block in textBlocks {
        let rect = gridRect(
            forPixelRect: block.bounds,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            gridWidth: gridWidth,
            gridHeight: gridHeight
        ).expandedBy(columns: 1, rows: 1, gridWidth: gridWidth, gridHeight: gridHeight)

        for row in rect.row..<(rect.row + rect.height) {
            for column in rect.column..<(rect.column + rect.width) {
                canvas[row][column] = " "
            }
        }
    }
}

private func overlayOCRText(
    on canvas: inout [[Character]],
    textBlocks: [OCRTextBlock],
    imageWidth: Int,
    imageHeight: Int
) {
    let gridHeight = canvas.count
    guard gridHeight > 0, let gridWidth = canvas.first?.count else {
        return
    }

    var occupiedText = Array(repeating: Array(repeating: false, count: gridWidth), count: gridHeight)

    for block in sortedOCRTextBlocks(textBlocks) {
        let text = layoutText(block.text)
        guard !text.isEmpty else {
            continue
        }

        let rect = gridRect(
            forPixelRect: block.bounds,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            gridWidth: gridWidth,
            gridHeight: gridHeight
        )
        let startColumn = min(max(0, rect.column), gridWidth - 1)
        let baseRow = min(max(0, rect.row + rect.height / 2), gridHeight - 1)
        let spillWidth = min(gridWidth - startColumn, max(rect.width, min(text.count, rect.width + 12)))
        let chunks = wrapLayoutText(text, maxWidth: max(1, spillWidth))
        var placedAllChunks = true

        for (lineOffset, chunk) in chunks.enumerated() {
            let preferredRow = min(gridHeight - 1, baseRow + lineOffset)
            guard let row = firstAvailableTextRow(
                preferredRow: preferredRow,
                startColumn: startColumn,
                textWidth: chunk.count,
                occupiedText: occupiedText
            ) else {
                placedAllChunks = false
                break
            }

            writeLayoutText(
                chunk,
                row: row,
                column: startColumn,
                canvas: &canvas,
                occupiedText: &occupiedText
            )
        }

        if !placedAllChunks {
            let anchoredText = "@\(rect.row),\(rect.column) \(text)"
            let fallback = String(anchoredText.prefix(max(1, gridWidth - startColumn)))
            writeLayoutText(
                fallback,
                row: baseRow,
                column: startColumn,
                canvas: &canvas,
                occupiedText: &occupiedText,
                allowCollision: true
            )
        }
    }
}

private struct GridRect {
    let column: Int
    let row: Int
    let width: Int
    let height: Int

    func expandedBy(columns: Int, rows: Int, gridWidth: Int, gridHeight: Int) -> GridRect {
        let expandedColumn = max(0, column - columns)
        let expandedRow = max(0, row - rows)
        let maxColumn = min(gridWidth, column + width + columns)
        let maxRow = min(gridHeight, row + height + rows)

        return GridRect(
            column: expandedColumn,
            row: expandedRow,
            width: max(1, maxColumn - expandedColumn),
            height: max(1, maxRow - expandedRow)
        )
    }
}

private func gridRect(
    forPixelRect pixelRect: CGRect,
    imageWidth: Int,
    imageHeight: Int,
    gridWidth: Int,
    gridHeight: Int
) -> GridRect {
    let xScale = Double(gridWidth) / Double(imageWidth)
    let yScale = Double(gridHeight) / Double(imageHeight)
    let minColumn = min(max(0, Int(floor(Double(pixelRect.minX) * xScale))), gridWidth - 1)
    let minRow = min(max(0, Int(floor(Double(pixelRect.minY) * yScale))), gridHeight - 1)
    let maxColumn = min(max(minColumn + 1, Int(ceil(Double(pixelRect.maxX) * xScale))), gridWidth)
    let maxRow = min(max(minRow + 1, Int(ceil(Double(pixelRect.maxY) * yScale))), gridHeight)

    return GridRect(
        column: minColumn,
        row: minRow,
        width: max(1, maxColumn - minColumn),
        height: max(1, maxRow - minRow)
    )
}

private func layoutText(_ text: String) -> String {
    singleLineText(text)
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
}

private func wrapLayoutText(_ text: String, maxWidth: Int) -> [String] {
    guard text.count > maxWidth else {
        return [text]
    }

    guard maxWidth > 0 else {
        return [text]
    }

    var chunks: [String] = []

    for word in text.split(separator: " ").map(String.init) {
        if word.count > maxWidth {
            chunks.append(contentsOf: splitLayoutWord(word, maxWidth: maxWidth))
            continue
        }

        if let lastChunk = chunks.last, lastChunk.count + 1 + word.count <= maxWidth {
            chunks[chunks.count - 1] = "\(lastChunk) \(word)"
        } else {
            chunks.append(word)
        }
    }

    return chunks.isEmpty ? [text] : chunks
}

private func splitLayoutWord(_ word: String, maxWidth: Int) -> [String] {
    let characters = Array(word)
    var chunks: [String] = []
    var index = 0

    while index < characters.count {
        let endIndex = min(index + maxWidth, characters.count)
        chunks.append(String(characters[index..<endIndex]))
        index = endIndex
    }

    return chunks
}

private func firstAvailableTextRow(
    preferredRow: Int,
    startColumn: Int,
    textWidth: Int,
    occupiedText: [[Bool]]
) -> Int? {
    let height = occupiedText.count
    guard height > 0, let width = occupiedText.first?.count else {
        return nil
    }

    let clampedPreferredRow = min(max(0, preferredRow), height - 1)
    let offsets = [0, 1, -1, 2, -2, 3, -3]

    for offset in offsets {
        let candidateRow = clampedPreferredRow + offset
        guard candidateRow >= 0, candidateRow < height else {
            continue
        }

        let endColumn = min(width, startColumn + textWidth)
        if (startColumn..<endColumn).allSatisfy({ !occupiedText[candidateRow][$0] }) {
            return candidateRow
        }
    }

    return nil
}

private func writeLayoutText(
    _ text: String,
    row: Int,
    column: Int,
    canvas: inout [[Character]],
    occupiedText: inout [[Bool]],
    allowCollision: Bool = false
) {
    guard row >= 0, row < canvas.count, let gridWidth = canvas.first?.count else {
        return
    }

    let characters = Array(text)
    for (offset, character) in characters.enumerated() {
        let targetColumn = column + offset
        guard targetColumn >= 0, targetColumn < gridWidth else {
            break
        }

        if !allowCollision, occupiedText[row][targetColumn] {
            continue
        }

        canvas[row][targetColumn] = character
        occupiedText[row][targetColumn] = true
    }
}

private func recognizeTextBlocks(in image: CGImage, recognitionLanguages: [String]) async throws -> [OCRTextBlock] {
    let ocrImage = try normalizedImageForOCR(image)
    var request = RecognizeTextRequest()
    configureTextRecognitionRequest(&request, recognitionLanguages: recognitionLanguages)

    let observations = try await withSuppressedStandardOutput {
        try await request.perform(on: ocrImage)
    }

    let blocks = observations.compactMap { observation -> OCRTextBlock? in
        guard let candidate = observation.topCandidates(1).first else {
            return nil
        }

        let text = normalizedOCRText(candidate.string)
        guard !text.isEmpty else {
            return nil
        }

        return OCRTextBlock(
            text: text,
            confidence: candidate.confidence,
            bounds: pixelBounds(
                forNormalizedVisionRect: observation.boundingBox.cgRect,
                imageWidth: ocrImage.width,
                imageHeight: ocrImage.height
            )
        )
    }

    return sortedOCRTextBlocks(blocks)
}

private func withSuppressedStandardOutput<T>(_ operation: () async throws -> T) async throws -> T {
    // Vision may emit model diagnostics directly to stdout; keep BrrainzTools's JSON channel clean.
    fflush(stdout)

    let originalStandardOutput = dup(STDOUT_FILENO)
    guard originalStandardOutput >= 0 else {
        return try await operation()
    }

    let devNull = open("/dev/null", O_WRONLY)
    guard devNull >= 0 else {
        close(originalStandardOutput)
        return try await operation()
    }

    dup2(devNull, STDOUT_FILENO)
    close(devNull)

    do {
        let result = try await operation()
        fflush(stdout)
        dup2(originalStandardOutput, STDOUT_FILENO)
        close(originalStandardOutput)
        return result
    } catch {
        fflush(stdout)
        dup2(originalStandardOutput, STDOUT_FILENO)
        close(originalStandardOutput)
        throw error
    }
}

func configureTextRecognitionRequest(_ request: inout RecognizeTextRequest, recognitionLanguages: [String]) {
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    if recognitionLanguages.isEmpty {
        request.automaticallyDetectsLanguage = true
        request.recognitionLanguages = []
    } else {
        request.automaticallyDetectsLanguage = false
        request.recognitionLanguages = recognitionLanguages.map(Locale.Language.init(identifier:))
    }
}

private func normalizedImageForOCR(_ image: CGImage) throws -> CGImage {
    let width = image.width
    let height = image.height
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 255, count: bytesPerRow * height)

    return try pixels.withUnsafeMutableBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else {
            throw BrrainzToolsError.captureFailed("Failed to allocate an OCR image buffer.")
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue |
            CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw BrrainzToolsError.captureFailed("Failed to create an OCR image context.")
        }

        let imageRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(imageRect)
        context.interpolationQuality = .none
        context.draw(image, in: imageRect)

        guard let normalizedImage = context.makeImage() else {
            throw BrrainzToolsError.captureFailed("Failed to prepare image data for OCR.")
        }

        return normalizedImage
    }
}

private func pixelBounds(forNormalizedVisionRect normalizedRect: CGRect, imageWidth: Int, imageHeight: Int) -> CGRect {
    let width = CGFloat(imageWidth)
    let height = CGFloat(imageHeight)
    let minX = normalizedRect.minX * width
    let maxY = normalizedRect.maxY * height

    return CGRect(
        x: minX.rounded(),
        y: (height - maxY).rounded(),
        width: (normalizedRect.width * width).rounded(),
        height: (normalizedRect.height * height).rounded()
    )
}

func sortedOCRTextBlocks(_ blocks: [OCRTextBlock]) -> [OCRTextBlock] {
    blocks.sorted { lhs, rhs in
        let rowTolerance = max(4, min(lhs.bounds.height, rhs.bounds.height) * 0.5)
        let verticalDelta = abs(lhs.bounds.minY - rhs.bounds.minY)

        if verticalDelta > rowTolerance {
            return lhs.bounds.minY < rhs.bounds.minY
        }

        if lhs.bounds.minX != rhs.bounds.minX {
            return lhs.bounds.minX < rhs.bounds.minX
        }

        return lhs.text < rhs.text
    }
}

enum OCRReportStatus {
    case disabled
    case unavailable(String)
    case blocks([OCRTextBlock])
}

func formatAsciiArtReport(
    imagePath: String,
    imageWidth: Int,
    imageHeight: Int,
    style: AsciiArtStyle,
    rendered: RenderedAsciiArt,
    ocrStatus: OCRReportStatus
) -> String {
    let outputLabel = style == .layout ? "layout" : "ascii"

    return [
        "image: \(imagePath)",
        "size: \(imageWidth)x\(imageHeight) px",
        "\(outputLabel): \(rendered.width)x\(rendered.height) chars",
        rendered.text,
        "",
        formatOCRSection(ocrStatus),
    ].joined(separator: "\n")
}

func formatOCROnlyResponse(
    imagePath: String,
    imageWidth: Int,
    imageHeight: Int,
    ocrStatus: OCRReportStatus
) throws -> String {
    let blocks: [OCRTextBlock]
    let error: String?

    switch ocrStatus {
    case .blocks(let recognizedBlocks):
        blocks = recognizedBlocks
        error = nil
    case .unavailable(let reason):
        blocks = []
        error = singleLineText(reason).trimmingCharacters(in: .whitespacesAndNewlines)
    case .disabled:
        blocks = []
        error = "OCR disabled"
    }

    return try encodeJSON(
        OCROnlyResponse(
            image: OCRImageEntry(
                path: imagePath,
                width: imageWidth,
                height: imageHeight
            ),
            blocks: sortedOCRTextBlocks(blocks).map(ocrTextBlockEntry(for:)),
            error: error
        )
    )
}

private func ocrTextBlockEntry(for block: OCRTextBlock) -> OCRTextBlockEntry {
    OCRTextBlockEntry(
        text: block.text,
        confidence: block.confidence,
        bounds: JSONRect(block.bounds)
    )
}

func formatOCRSection(_ status: OCRReportStatus) -> String {
    switch status {
    case .disabled:
        return "ocr: disabled"
    case .unavailable(let reason):
        return "ocr: unavailable (\(singleLineText(reason)))"
    case .blocks(let blocks):
        return formatOCRTextBlocks(blocks)
    }
}

func formatOCRTextBlocks(_ blocks: [OCRTextBlock]) -> String {
    let sortedBlocks = sortedOCRTextBlocks(blocks)
    guard !sortedBlocks.isEmpty else {
        return "ocr: no text found"
    }

    var lines = ["ocr:"]
    lines.reserveCapacity(sortedBlocks.count + 1)

    for block in sortedBlocks {
        let x = Int(block.bounds.minX.rounded())
        let y = Int(block.bounds.minY.rounded())
        let width = Int(block.bounds.width.rounded())
        let height = Int(block.bounds.height.rounded())
        let confidence = String(
            format: "%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            Double(block.confidence)
        )
        lines.append("- [x=\(x) y=\(y) w=\(width) h=\(height) confidence=\(confidence)] \"\(escapedOCRText(block.text))\"")
    }

    return lines.joined(separator: "\n")
}

private func normalizedOCRText(_ text: String) -> String {
    singleLineText(text).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func singleLineText(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\r\n", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
}

private func escapedOCRText(_ text: String) -> String {
    singleLineText(text)
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

func encodeJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)

    guard let json = String(data: data, encoding: .utf8) else {
        throw BrrainzToolsError.encodeFailed("Failed to encode the response as UTF-8 JSON.")
    }

    return json
}

private func encodeJSONString(_ value: String) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    let data = try encoder.encode(value)

    guard let json = String(data: data, encoding: .utf8) else {
        throw BrrainzToolsError.encodeFailed("Failed to encode the response as UTF-8 JSON.")
    }

    return json
}

func dataEnvelopeJSON(mode: String, dataJSON: String, version: String = currentBrrainzToolsVersion()) throws -> String {
    let modeJSON = try encodeJSONString(mode)
    let versionJSON = try encodeJSONString(version)
    return #"{"data":\#(dataJSON),"mode":\#(modeJSON),"ok":true,"version":\#(versionJSON)}"#
}

func basicEnvelopeJSON(mode: String, version: String = currentBrrainzToolsVersion()) throws -> String {
    try encodeJSON(
        BasicEnvelope(
            mode: mode,
            ok: true,
            version: version
        )
    )
}

func outputEnvelopeJSON(mode: String, output: String, version: String = currentBrrainzToolsVersion()) throws -> String {
    try encodeJSON(
        OutputEnvelope(
            mode: mode,
            ok: true,
            output: output,
            version: version
        )
    )
}

func outputDataEnvelopeJSON(mode: String, output: String, dataJSON: String, version: String = currentBrrainzToolsVersion()) throws -> String {
    let modeJSON = try encodeJSONString(mode)
    let outputJSON = try encodeJSONString(output)
    let versionJSON = try encodeJSONString(version)
    return #"{"data":\#(dataJSON),"mode":\#(modeJSON),"ok":true,"output":\#(outputJSON),"version":\#(versionJSON)}"#
}

func reportEnvelopeJSON(mode: String, report: String, version: String = currentBrrainzToolsVersion()) throws -> String {
    try encodeJSON(
        ReportEnvelope(
            mode: mode,
            ok: true,
            report: report,
            version: version
        )
    )
}

func outputReportEnvelopeJSON(mode: String, output: String, report: String, version: String = currentBrrainzToolsVersion()) throws -> String {
    try encodeJSON(
        OutputReportEnvelope(
            mode: mode,
            ok: true,
            output: output,
            report: report,
            version: version
        )
    )
}

func errorEnvelopeJSON(error: BrrainzToolsError, version: String = currentBrrainzToolsVersion()) throws -> String {
    try encodeJSON(
        ErrorEnvelope(
            error: ErrorEntry(
                kind: error.kind,
                message: error.localizedDescription,
                exitCode: error.exitCode
            ),
            ok: false,
            version: version
        )
    )
}

private func fallbackErrorEnvelopeJSON(kind: String, message: String, exitCode: Int32) -> String {
    let sanitizedKind = kind.replacingOccurrences(of: "\"", with: "")
    let sanitizedMessage = message
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
    return #"{"error":{"exitCode":\#(exitCode),"kind":"\#(sanitizedKind)","message":"\#(sanitizedMessage)"},"ok":false,"version":"unknown"}"#
}

private func windowListApplication(for application: SCRunningApplication) -> WindowListApplication {
    WindowListApplication(
        name: application.applicationName,
        bundleIdentifier: application.bundleIdentifier,
        processID: application.processID
    )
}

private func windowListApplication(for application: AutomationApplication) -> WindowListApplication {
    WindowListApplication(
        name: application.name,
        bundleIdentifier: application.bundleIdentifier,
        processID: Int32(application.processID)
    )
}

func windowlessApplicationMessage(
    name: String,
    bundleIdentifier: String,
    processID: pid_t,
    windowKind: String,
    modeDescription: String
) -> String {
    let bundleSummary = bundleIdentifier.isEmpty ? "" : ", \(bundleIdentifier)"
    let policyNote: String

    switch NSRunningApplication(processIdentifier: processID)?.activationPolicy {
    case .accessory?:
        policyNote = " It is running as an accessory/background app, which commonly means menu-bar UI; menu bar items are not app windows."
    case .prohibited?:
        policyNote = " It is running as a background-only app and is not expected to expose normal app windows."
    case .regular?:
        policyNote = " It is a regular app, but no matching window is currently open or visible to this API."
    case nil:
        policyNote = ""
    @unknown default:
        policyNote = ""
    }

    return "`\(name)` was found (pid \(processID)\(bundleSummary)), but macOS exposed no \(windowKind) windows for it.\(policyNote) \(modeDescription) Use `--list-menu-bar-items` and `--capture-menu` for menu-bar/status-item UI, use rectangle capture (`brrainztools X Y WIDTH HEIGHT`) for raw visible pixels, or open a normal app window first."
}

private func windowListEntry(for window: CatalogWindow) -> WindowListEntry {
    WindowListEntry(
        index: window.index,
        windowID: window.windowID,
        title: normalizedTitle(window.title),
        frame: JSONRect(window.frame),
        layer: window.layer,
        isOnScreen: window.isOnScreen,
        isActive: window.isActive
    )
}

private func visibleWindowEntry(for window: VisibleCatalogWindow) -> VisibleWindowEntry {
    VisibleWindowEntry(
        index: window.index,
        windowID: window.windowID,
        title: normalizedTitle(window.title),
        frame: JSONRect(window.frame),
        layer: window.layer
    )
}

private func accessibilityWindowEntry(for window: AccessibilityCatalogWindow) -> AccessibilityWindowEntry {
    AccessibilityWindowEntry(
        index: window.index,
        title: normalizedTitle(window.title),
        frame: JSONRect(window.frame),
        isFocused: window.isFocused,
        isMain: window.isMain,
        isFrontmostApplication: window.isFrontmostApplication,
        isFrontmostWindow: window.isFrontmostWindow,
        actions: window.actions
    )
}

private func accessibilitySelectorResponse(for selector: AccessibilitySelector) -> AccessibilitySelectorResponse {
    AccessibilitySelectorResponse(
        path: selector.path,
        role: selector.role,
        subrole: selector.subrole,
        title: selector.title,
        identifier: selector.identifier,
        description: selector.elementDescription
    )
}

private func menuBarItemEntry(for item: MenuBarCatalogItem) -> MenuBarItemEntry {
    MenuBarItemEntry(
        index: item.index,
        source: item.source,
        role: item.role,
        subrole: item.subrole,
        title: item.title,
        description: item.description,
        identifier: item.identifier,
        frame: item.frame.map(JSONRect.init),
        actions: item.actions,
        childCount: item.childCount
    )
}

private func menuTreeNode(
    for item: MenuBarCatalogItem,
    depthRemaining: Int,
    childLimit: Int
) -> MenuTreeNode {
    menuTreeNode(
        for: item.element,
        path: String(item.index),
        index: item.index,
        source: item.source,
        depthRemaining: depthRemaining,
        childLimit: childLimit
    )
}

private func menuTreeNode(
    for element: AXUIElement,
    path: String,
    index: Int? = nil,
    source: String? = nil,
    depthRemaining: Int,
    childLimit: Int
) -> MenuTreeNode {
    let rawChildren = copyAXElements(from: element, attribute: kAXChildrenAttribute as CFString)
    let limitedChildren = depthRemaining > 0 ? Array(rawChildren.prefix(childLimit)) : []
    let nestedChildren = limitedChildren.enumerated().map { childIndex, child in
        menuTreeNode(
            for: child,
            path: "\(path).\(childIndex)",
            depthRemaining: depthRemaining - 1,
            childLimit: childLimit
        )
    }
    let role = copyAXString(from: element, attribute: kAXRoleAttribute as CFString)
    let checkState = menuItemCheckState(for: element, role: role)

    return MenuTreeNode(
        path: path,
        index: index,
        source: source,
        role: role,
        subrole: copyAXString(from: element, attribute: kAXSubroleAttribute as CFString),
        title: normalizedTitle(copyAXString(from: element, attribute: kAXTitleAttribute as CFString)),
        description: normalizedTitle(copyAXString(from: element, attribute: kAXDescriptionAttribute as CFString)),
        identifier: normalizedTitle(copyAXString(from: element, attribute: kAXIdentifierAttribute as CFString)),
        enabled: copyAXBool(from: element, attribute: kAXEnabledAttribute as CFString),
        checked: checkState.checked,
        mark: checkState.mark,
        shortcut: menuShortcut(for: element),
        frame: copyAXFrame(from: element).map(JSONRect.init),
        actions: copyAXActions(from: element),
        childCount: rawChildren.count,
        truncated: rawChildren.count > limitedChildren.count ? true : nil,
        children: nestedChildren.isEmpty ? nil : nestedChildren
    )
}

private func menuItemCheckState(
    for element: AXUIElement,
    role: String?
) -> (checked: Bool?, mark: String?) {
    var value: CFTypeRef?
    if
        AXUIElementCopyAttributeValue(element, kAXMenuItemMarkCharAttribute as CFString, &value) == .success,
        let rawMark = value as? String
    {
        let mark = normalizedTitle(rawMark)
        return (mark != nil, mark)
    }

    if role == (kAXMenuItemRole as String) {
        return (false, nil)
    }

    return (nil, nil)
}

private func menuShortcut(for element: AXUIElement) -> MenuShortcut? {
    menuShortcut(
        character: normalizedTitle(copyAXString(from: element, attribute: kAXMenuItemCmdCharAttribute as CFString)),
        virtualKey: copyAXInteger(from: element, attribute: kAXMenuItemCmdVirtualKeyAttribute as CFString),
        glyph: copyAXInteger(from: element, attribute: kAXMenuItemCmdGlyphAttribute as CFString),
        modifierMask: copyAXUInt32(from: element, attribute: kAXMenuItemCmdModifiersAttribute as CFString)
    )
}

func menuShortcut(
    character: String?,
    virtualKey: Int?,
    glyph: Int?,
    modifierMask: UInt32?
) -> MenuShortcut? {
    guard character != nil || virtualKey != nil || glyph != nil else {
        return nil
    }

    return MenuShortcut(
        character: character,
        virtualKey: virtualKey,
        glyph: glyph,
        modifierMask: modifierMask,
        modifiers: modifierMask.map(menuShortcutModifierNames)
    )
}

func menuShortcutModifierNames(_ mask: UInt32) -> [String] {
    let shiftMask: UInt32 = 1 << 0
    let optionMask: UInt32 = 1 << 1
    let controlMask: UInt32 = 1 << 2
    let noCommandMask: UInt32 = 1 << 3
    let knownMask = shiftMask | optionMask | controlMask | noCommandMask
    var modifiers: [String] = []

    if mask & controlMask != 0 { modifiers.append("control") }
    if mask & optionMask != 0 { modifiers.append("option") }
    if mask & shiftMask != 0 { modifiers.append("shift") }
    if mask & noCommandMask == 0 { modifiers.append("command") }
    let unknownMask = mask & ~knownMask
    if unknownMask != 0 {
        modifiers.append(String(format: "unknown:0x%X", unknownMask))
    }

    return modifiers
}

private func buildMenuBarItemCatalog(selector: ApplicationSelector) throws -> MenuBarItemCatalog {
    let runningApplication = try resolveAutomationApplication(selector: selector)
    let applicationElement = AXUIElementCreateApplication(runningApplication.processID)

    var items: [MenuBarCatalogItem] = []
    appendMenuBarItems(
        from: copyAXElement(from: applicationElement, attribute: "AXExtrasMenuBar" as CFString),
        source: "extras",
        to: &items
    )
    appendMenuBarItems(
        from: copyAXElement(from: applicationElement, attribute: kAXMenuBarAttribute as CFString),
        source: "menuBar",
        to: &items
    )

    guard !items.isEmpty else {
        throw BrrainzToolsError.windowNotFound("No menu-bar items are currently available for `\(runningApplication.name)`.")
    }

    return MenuBarItemCatalog(
        application: runningApplication,
        items: items.enumerated().map { offset, item in
            MenuBarCatalogItem(
                index: offset,
                source: item.source,
                role: item.role,
                subrole: item.subrole,
                title: item.title,
                description: item.description,
                identifier: item.identifier,
                frame: item.frame,
                actions: item.actions,
                childCount: item.childCount,
                element: item.element
            )
        }
    )
}

private func appendMenuBarItems(
    from menuBar: AXUIElement?,
    source: String,
    to items: inout [MenuBarCatalogItem]
) {
    guard let menuBar else {
        return
    }

    for element in copyAXElements(from: menuBar, attribute: kAXChildrenAttribute as CFString) {
        guard let frame = copyAXFrame(from: element), !frame.isEmpty else {
            continue
        }

        let children = copyAXElements(from: element, attribute: kAXChildrenAttribute as CFString)
        items.append(
            MenuBarCatalogItem(
                index: items.count,
                source: source,
                role: copyAXString(from: element, attribute: kAXRoleAttribute as CFString),
                subrole: copyAXString(from: element, attribute: kAXSubroleAttribute as CFString),
                title: normalizedTitle(copyAXString(from: element, attribute: kAXTitleAttribute as CFString)),
                description: normalizedTitle(copyAXString(from: element, attribute: kAXDescriptionAttribute as CFString)),
                identifier: normalizedTitle(copyAXString(from: element, attribute: kAXIdentifierAttribute as CFString)),
                frame: frame,
                actions: copyAXActions(from: element),
                childCount: children.count,
                element: element
            )
        )
    }
}

func selectMenuBarItem(
    from catalog: MenuBarItemCatalog,
    using selection: MenuBarSelection?
) throws -> MenuBarCatalogItem {
    guard let selection else {
        let extras = catalog.items.filter { $0.source == "extras" }
        if extras.count == 1, let item = extras.first {
            return item
        }

        if catalog.items.count == 1, let item = catalog.items.first {
            return item
        }

        let suggestions = catalog.items
            .prefix(6)
            .map(formatMenuBarCandidate)
            .joined(separator: ", ")
        throw BrrainzToolsError.ambiguousWindow("More than one menu-bar item is available for `\(catalog.application.name)`. Choose `--menu-bar-index` or `--menu-bar-item`: \(suggestions)")
    }

    switch selection {
    case .index(let index):
        guard let item = catalog.items.first(where: { $0.index == index }) else {
            throw BrrainzToolsError.windowNotFound("No menu-bar item at index \(index) for `\(catalog.application.name)`. Run `brrainztools --app \"\(catalog.application.name)\" --list-menu-bar-items` to inspect available items.")
        }
        return item
    case .name(let query):
        let exactMatches = catalog.items.filter { item in
            menuBarSearchTexts(for: item, application: catalog.application).contains { text in
                normalizedSelectorText(text) == normalizedSelectorText(query)
            }
        }

        if exactMatches.count == 1, let match = exactMatches.first {
            return match
        }

        let partialMatches = catalog.items.filter { item in
            menuBarSearchTexts(for: item, application: catalog.application).contains { text in
                guard
                    let normalizedText = normalizedSelectorText(text),
                    let normalizedQuery = normalizedSelectorText(query)
                else {
                    return false
                }
                return normalizedText.contains(normalizedQuery)
            }
        }
        let matches = exactMatches.isEmpty ? partialMatches : exactMatches

        guard !matches.isEmpty else {
            throw BrrainzToolsError.windowNotFound("No menu-bar item matching `\(query)` was found for `\(catalog.application.name)`. Run `brrainztools --app \"\(catalog.application.name)\" --list-menu-bar-items` to inspect available items.")
        }

        guard matches.count == 1, let match = matches.first else {
            let suggestions = matches
                .prefix(6)
                .map(formatMenuBarCandidate)
                .joined(separator: ", ")
            throw BrrainzToolsError.ambiguousWindow("More than one menu-bar item matches `\(query)`: \(suggestions)")
        }

        return match
    }
}

private func menuBarSearchTexts(
    for item: MenuBarCatalogItem,
    application: AutomationApplication
) -> [String] {
    var texts = [
        item.title,
        item.description,
        item.identifier,
    ].compactMap { $0 }

    if item.source == "extras", texts.isEmpty {
        texts.append(application.name)
        if !application.bundleIdentifier.isEmpty {
            texts.append(application.bundleIdentifier)
        }
    }

    return texts
}

private func formatMenuBarCandidate(_ item: MenuBarCatalogItem) -> String {
    let role = item.role ?? "?"
    let subrole = item.subrole.map { "/\($0)" } ?? ""
    let title = item.title.map { " title=\($0)" } ?? ""
    let description = item.description.map { " description=\($0)" } ?? ""
    let identifier = item.identifier.map { " id=\($0)" } ?? ""
    let frame = item.frame.map { " @ \(formatFrame($0))" } ?? ""
    return "[\(item.index)] \(item.source) \(role)\(subrole)\(title)\(description)\(identifier)\(frame)"
}

private func selectMenuChildItem(
    in menu: AXUIElement,
    matching selection: MenuChildSelection
) throws -> AccessibilityElementCandidate {
    let candidates = collectAccessibilityElementCandidates(in: menu, depthRemaining: 8, childLimit: 120)
        .filter { candidate in
            normalizedSelectorText(candidate.role) == normalizedSelectorText(kAXMenuItemRole as String) &&
            candidate.actions.contains { action in
                normalizedSelectorText(action) == normalizedSelectorText(kAXPressAction as String) ||
                normalizedSelectorText(action) == normalizedSelectorText(kAXPickAction as String)
            }
        }

    let exactMatches = candidates.filter { candidate in
        menuChildSearchTexts(for: candidate).contains { text in
            normalizedSelectorText(text) == normalizedSelectorText(selection.query)
        }
    }

    let partialMatches = candidates.filter { candidate in
        menuChildSearchTexts(for: candidate).contains { text in
            guard
                let normalizedText = normalizedSelectorText(text),
                let normalizedQuery = normalizedSelectorText(selection.query)
            else {
                return false
            }
            return normalizedText.contains(normalizedQuery)
        }
    }
    let matches = exactMatches.isEmpty ? partialMatches : exactMatches

    guard !matches.isEmpty else {
        let suggestions = candidates
            .prefix(8)
            .map(formatAccessibilityCandidate)
            .joined(separator: ", ")
        let suffix = suggestions.isEmpty ? "" : " Candidates: \(suggestions)"
        throw BrrainzToolsError.accessibilityQueryFailed("No visible child menu item matching `\(selection.query)` was found after opening the selected menu-bar item.\(suffix)")
    }

    guard matches.count == 1, let match = matches.first else {
        let suggestions = matches
            .prefix(8)
            .map(formatAccessibilityCandidate)
            .joined(separator: ", ")
        throw BrrainzToolsError.accessibilityQueryFailed("More than one child menu item matches `\(selection.query)`: \(suggestions)")
    }

    return match
}

private func menuChildSearchTexts(for candidate: AccessibilityElementCandidate) -> [String] {
    [
        candidate.title,
        candidate.description,
        candidate.identifier,
    ].compactMap { $0 }
}

private func buildVisibleWindowCatalog(selector: ApplicationSelector) throws -> VisibleWindowCatalog {
    let runningApplication = try resolveAutomationApplication(selector: selector)
    let windows = visibleWindows(
        for: runningApplication.processID,
        snapshots: currentWindowSnapshots()
    )

    guard !windows.isEmpty else {
        throw BrrainzToolsError.windowNotFound(
            windowlessApplicationMessage(
                name: runningApplication.name,
                bundleIdentifier: runningApplication.bundleIdentifier,
                processID: runningApplication.processID,
                windowKind: "visible",
                modeDescription: "`--list-visible-windows` and `--visible-window` use currently visible app windows and capture visible pixels only."
            )
        )
    }

    return VisibleWindowCatalog(
        application: runningApplication,
        windows: windows
    )
}

func visibleWindows(
    for processID: pid_t,
    snapshots: [WindowSnapshot]
) -> [VisibleCatalogWindow] {
    snapshots
        .filter { snapshot in
            snapshot.ownerPID == processID &&
            snapshot.layer >= 0 &&
            snapshot.layer <= maximumVisibleAppWindowLayer &&
            snapshot.alpha > 0 &&
            !snapshot.bounds.isEmpty
        }
        .enumerated()
        .map { offset, snapshot in
            VisibleCatalogWindow(
                index: offset,
                windowID: snapshot.windowID,
                title: snapshot.title,
                frame: snapshot.bounds,
                layer: snapshot.layer
            )
        }
}

private func selectVisibleWindow(
    from catalog: VisibleWindowCatalog,
    using selection: WindowSelection?
) throws -> VisibleCatalogWindow {
    guard let selection else {
        guard let first = catalog.windows.first else {
            throw BrrainzToolsError.windowNotFound("`\(catalog.application.name)` has no visible windows.")
        }
        return first
    }

    switch selection {
    case .frontmost:
        guard let first = catalog.windows.first else {
            throw BrrainzToolsError.windowNotFound("`\(catalog.application.name)` has no visible windows.")
        }
        return first
    case .index(let index):
        guard let window = catalog.windows.first(where: { $0.index == index }) else {
            throw BrrainzToolsError.windowNotFound("No visible window at index \(index) for `\(catalog.application.name)`. Run `brrainztools --app \"\(catalog.application.name)\" --list-visible-windows` to inspect available windows.")
        }
        return window
    case .name(let query):
        let normalizedQuery = query.lowercased()
        let exactMatches = catalog.windows.filter { ($0.title ?? "").lowercased() == normalizedQuery }

        if exactMatches.count == 1, let match = exactMatches.first {
            return match
        }

        let partialMatches = catalog.windows.filter { ($0.title ?? "").lowercased().contains(normalizedQuery) }
        let matches = exactMatches.isEmpty ? partialMatches : exactMatches

        guard !matches.isEmpty else {
            throw BrrainzToolsError.windowNotFound("No visible window named `\(query)` was found for `\(catalog.application.name)`. Run `brrainztools --app \"\(catalog.application.name)\" --list-visible-windows` to inspect available windows.")
        }

        guard matches.count == 1, let match = matches.first else {
            let suggestions = matches
                .prefix(5)
                .map { "[\($0.index)] \(displayTitle($0.title))" }
                .joined(separator: ", ")
            throw BrrainzToolsError.ambiguousWindow("More than one visible window matches `\(query)`: \(suggestions)")
        }

        return match
    }
}

private func captureRegion(
    forVisibleWindow window: VisibleCatalogWindow,
    crop: WindowCropRect?
) throws -> CaptureRegion {
    let captureRect: CGRect

    if let crop {
        try validate(windowCrop: crop, within: window.frame, windowTitle: displayTitle(window.title))
        captureRect = CGRect(
            x: window.frame.minX + CGFloat(crop.x),
            y: window.frame.minY + CGFloat(crop.y),
            width: CGFloat(crop.width),
            height: CGFloat(crop.height)
        )
    } else {
        captureRect = window.frame
    }

    let minX = Int(floor(captureRect.minX))
    let minY = Int(floor(captureRect.minY))
    let maxX = Int(ceil(captureRect.maxX))
    let maxY = Int(ceil(captureRect.maxY))
    let region = CaptureRegion(
        x: minX,
        y: minY,
        width: maxX - minX,
        height: maxY - minY
    )
    try validate(region: region)
    return region
}

private func buildAccessibilityWindowCatalog(selector: ApplicationSelector) throws -> AccessibilityWindowCatalog {
    let runningApplication = try resolveAutomationApplication(selector: selector)
    let frontmostApplication = NSWorkspace.shared.frontmostApplication.map(automationApplication(from:))
    let isFrontmostApplication = frontmostApplication?.processID == runningApplication.processID
    let applicationElement = AXUIElementCreateApplication(runningApplication.processID)
    let focusedWindow = copyAXElement(from: applicationElement, attribute: kAXFocusedWindowAttribute as CFString)
    let mainWindow = copyAXElement(from: applicationElement, attribute: kAXMainWindowAttribute as CFString)
    let rawWindows = copyAXElements(from: applicationElement, attribute: kAXWindowsAttribute as CFString)

    let sortedWindows = rawWindows
        .compactMap { element -> AccessibilityCatalogWindow? in
            guard let frame = copyAXFrame(from: element), !frame.isEmpty else {
                return nil
            }

            return AccessibilityCatalogWindow(
                index: 0,
                title: normalizedTitle(copyAXString(from: element, attribute: kAXTitleAttribute as CFString)),
                frame: frame,
                isFocused: focusedWindow.map { CFEqual($0, element) } ?? false,
                isMain: mainWindow.map { CFEqual($0, element) } ?? false,
                isFrontmostApplication: isFrontmostApplication,
                isFrontmostWindow: false,
                actions: copyAXActions(from: element),
                element: element
            )
        }
        .sorted(by: accessibilityWindowSort)

    let hasFocusedWindow = sortedWindows.contains(where: \.isFocused)
    let hasMainWindow = sortedWindows.contains(where: \.isMain)

    let windows = sortedWindows
        .enumerated()
        .map { offset, window in
            AccessibilityCatalogWindow(
                index: offset,
                title: window.title,
                frame: window.frame,
                isFocused: window.isFocused,
                isMain: window.isMain,
                isFrontmostApplication: isFrontmostApplication,
                isFrontmostWindow: isFrontmostAccessibilityWindow(
                    window: window,
                    index: offset,
                    isFrontmostApplication: isFrontmostApplication,
                    hasFocusedWindow: hasFocusedWindow,
                    hasMainWindow: hasMainWindow
                ),
                actions: window.actions,
                element: window.element
            )
        }

    guard !windows.isEmpty else {
        throw BrrainzToolsError.windowNotFound(
            windowlessApplicationMessage(
                name: runningApplication.name,
                bundleIdentifier: runningApplication.bundleIdentifier,
                processID: runningApplication.processID,
                windowKind: "accessibility app",
                modeDescription: "`--list-elements`, `--press`, and related Accessibility modes operate inside app windows."
            )
        )
    }

    return AccessibilityWindowCatalog(
        application: runningApplication,
        frontmostApplication: frontmostApplication,
        isFrontmostApplication: isFrontmostApplication,
        windows: windows
    )
}

private func waitForAccessibilityWindow(
    selector: ApplicationSelector,
    title: String,
    timeout: TimeInterval,
    pollInterval: TimeInterval = 0.1
) throws -> WaitedAccessibilityWindow {
    let deadline = Date().addingTimeInterval(timeout)
    let selection = WindowSelection.name(title)

    repeat {
        do {
            let catalog = try buildAccessibilityWindowCatalog(selector: selector)
            let window = try selectAccessibilityWindow(from: catalog, using: selection)
            return WaitedAccessibilityWindow(catalog: catalog, window: window)
        } catch BrrainzToolsError.windowNotFound {
            Thread.sleep(forTimeInterval: pollInterval)
        }
    } while Date() < deadline

    throw BrrainzToolsError.operationTimedOut("No accessibility window named `\(title)` appeared for `\(selector.label)` within \(formatSeconds(timeout)).")
}

private func waitForAnyAccessibilityWindow(
    selector: ApplicationSelector,
    timeout: TimeInterval,
    pollInterval: TimeInterval = 0.1
) throws -> WaitedAccessibilityWindow {
    let deadline = Date().addingTimeInterval(timeout)

    repeat {
        do {
            let catalog = try buildAccessibilityWindowCatalog(selector: selector)
            let window = try selectAccessibilityWindow(from: catalog, using: nil)
            return WaitedAccessibilityWindow(catalog: catalog, window: window)
        } catch BrrainzToolsError.applicationNotFound {
            Thread.sleep(forTimeInterval: pollInterval)
        } catch BrrainzToolsError.windowNotFound {
            Thread.sleep(forTimeInterval: pollInterval)
        }
    } while Date() < deadline

    throw BrrainzToolsError.operationTimedOut("No accessibility window appeared for `\(selector.label)` within \(formatSeconds(timeout)).")
}

private func isFrontmostAccessibilityWindow(
    window: AccessibilityCatalogWindow,
    index: Int,
    isFrontmostApplication: Bool,
    hasFocusedWindow: Bool,
    hasMainWindow: Bool
) -> Bool {
    guard isFrontmostApplication else {
        return false
    }

    if hasFocusedWindow {
        return window.isFocused
    }

    if hasMainWindow {
        return window.isMain
    }

    return index == 0
}

private func resolveAutomationApplication(selector: ApplicationSelector) throws -> AutomationApplication {
    let runningApplications = NSWorkspace.shared.runningApplications

    switch selector {
    case .processID(let processID):
        if let application = runningApplications.first(where: { $0.processIdentifier == processID }) {
            return automationApplication(from: application)
        }

        if let application = NSRunningApplication(processIdentifier: processID) {
            return automationApplication(from: application)
        }

        let probeResult = Darwin.kill(processID, 0)
        if probeResult == 0 || errno == EPERM {
            return AutomationApplication(name: "pid \(processID)", bundleIdentifier: "", processID: processID)
        }

        throw BrrainzToolsError.applicationNotFound("No running application matches pid \(processID).")
    case .name(let query):
        guard normalizedSelectorText(query) != nil else {
            throw BrrainzToolsError.invalidArguments("App selectors require a non-empty name, bundle id, or process id.")
        }

        let matches = rankedRunningApplicationMatches(
            query: query,
            applications: runningApplications
        )
        guard !matches.isEmpty else {
            throw BrrainzToolsError.applicationNotFound("No running application matches `\(query)`.")
        }

        if let match = uniqueBestRunningApplication(from: matches) {
            return automationApplication(from: match)
        }

        let best = matches[0]
        let equivalentMatches = matches.filter {
            $0.score == best.score &&
            $0.visibleWindowCount == best.visibleWindowCount &&
            $0.activationRank == best.activationRank
        }

        guard equivalentMatches.count == 1, let match = equivalentMatches.first?.application else {
            let suggestions = matches
                .prefix(5)
                .map { match in
                    let summary = automationApplication(from: match.application)
                    return "\(summary.name) (pid \(summary.processID), \(summary.bundleIdentifier), visible windows \(match.visibleWindowCount))"
                }
                .joined(separator: ", ")
            throw BrrainzToolsError.ambiguousApplication("More than one running application matches `\(query)`: \(suggestions)")
        }

        return automationApplication(from: match)
    }
}

private func automationApplication(from application: NSRunningApplication) -> AutomationApplication {
    AutomationApplication(
        name: application.localizedName ?? "<unknown>",
        bundleIdentifier: application.bundleIdentifier ?? "",
        processID: application.processIdentifier
    )
}

private func rankedRunningApplicationMatches(
    query: String,
    applications: [NSRunningApplication] = NSWorkspace.shared.runningApplications,
    snapshots: [WindowSnapshot] = currentWindowSnapshots()
) -> [RunningApplicationMatch] {
    applications
        .compactMap { application -> RunningApplicationMatch? in
            guard let score = applicationSearchScore(
                for: runningApplicationSearchTexts(for: application),
                query: query
            ) else {
                return nil
            }

            let visibleWindowCount = visibleWindows(
                for: application.processIdentifier,
                snapshots: snapshots
            ).count

            return RunningApplicationMatch(
                application: application,
                score: score,
                visibleWindowCount: visibleWindowCount,
                activationRank: activationPolicyRank(application.activationPolicy)
            )
        }
        .sorted(by: applicationMatchSort)
}

private func uniqueBestRunningApplication(
    from matches: [RunningApplicationMatch]
) -> NSRunningApplication? {
    guard let first = matches.first else {
        return nil
    }

    let equivalentMatches = matches.filter {
        $0.score == first.score &&
        $0.visibleWindowCount == first.visibleWindowCount &&
        $0.activationRank == first.activationRank
    }

    return equivalentMatches.count == 1 ? first.application : nil
}

private func applicationMatchSort(
    _ left: RunningApplicationMatch,
    _ right: RunningApplicationMatch
) -> Bool {
    if left.score != right.score {
        return left.score < right.score
    }

    if left.visibleWindowCount != right.visibleWindowCount {
        return left.visibleWindowCount > right.visibleWindowCount
    }

    if left.activationRank != right.activationRank {
        return left.activationRank < right.activationRank
    }

    let leftName = left.application.localizedName ?? ""
    let rightName = right.application.localizedName ?? ""
    if leftName != rightName {
        return leftName.localizedCaseInsensitiveCompare(rightName) == .orderedAscending
    }

    return left.application.processIdentifier < right.application.processIdentifier
}

private func runningApplicationSearchTexts(for application: NSRunningApplication) -> [String] {
    [
        application.localizedName,
        application.bundleIdentifier,
        application.bundleURL?.path,
        application.executableURL?.path,
    ].compactMap { $0 }
}

func applicationSearchScore(
    for texts: [String],
    query: String
) -> Int? {
    guard let normalizedQuery = normalizedSelectorText(query) else {
        return nil
    }

    var bestScore: Int?
    for text in texts {
        guard let normalizedText = normalizedSelectorText(text) else {
            continue
        }

        if normalizedText == normalizedQuery {
            bestScore = min(bestScore ?? Int.max, 0)
        }

        let lastPathComponent = (text as NSString).lastPathComponent
        let pathStem = (lastPathComponent as NSString).deletingPathExtension
        if normalizedSelectorText(lastPathComponent) == normalizedQuery ||
            normalizedSelectorText(pathStem) == normalizedQuery {
            bestScore = min(bestScore ?? Int.max, 1)
        }

        if normalizedText.contains(normalizedQuery) {
            bestScore = min(bestScore ?? Int.max, 10)
        }
    }

    return bestScore
}

private func runningApplicationEntry(
    for application: NSRunningApplication,
    index: Int,
    visibleWindowCount: Int
) -> RunningApplicationEntry {
    RunningApplicationEntry(
        index: index,
        processID: application.processIdentifier,
        name: application.localizedName ?? "<unknown>",
        bundleIdentifier: application.bundleIdentifier ?? "",
        activationPolicy: activationPolicyName(application.activationPolicy),
        bundlePath: application.bundleURL?.path,
        executablePath: application.executableURL?.path,
        visibleWindowCount: visibleWindowCount
    )
}

private func activationPolicyName(_ policy: NSApplication.ActivationPolicy) -> String {
    switch policy {
    case .regular:
        return "regular"
    case .accessory:
        return "accessory"
    case .prohibited:
        return "prohibited"
    @unknown default:
        return "unknown"
    }
}

private func activationPolicyRank(_ policy: NSApplication.ActivationPolicy?) -> Int {
    switch policy {
    case .regular?:
        return 0
    case .accessory?:
        return 1
    case .prohibited?:
        return 2
    case nil:
        return 3
    @unknown default:
        return 3
    }
}

private func accessibilityWindowSort(
    _ left: AccessibilityCatalogWindow,
    _ right: AccessibilityCatalogWindow
) -> Bool {
    if left.isFocused != right.isFocused {
        return left.isFocused && !right.isFocused
    }

    if left.isMain != right.isMain {
        return left.isMain && !right.isMain
    }

    let leftTitle = normalizedTitle(left.title) ?? ""
    let rightTitle = normalizedTitle(right.title) ?? ""
    if leftTitle != rightTitle {
        return leftTitle.localizedCaseInsensitiveCompare(rightTitle) == .orderedAscending
    }

    if left.frame.minY != right.frame.minY {
        return left.frame.minY < right.frame.minY
    }

    if left.frame.minX != right.frame.minX {
        return left.frame.minX < right.frame.minX
    }

    if left.frame.width != right.frame.width {
        return left.frame.width < right.frame.width
    }

    return left.frame.height < right.frame.height
}

private func selectAccessibilityWindow(
    from catalog: AccessibilityWindowCatalog,
    using selection: WindowSelection?
) throws -> AccessibilityCatalogWindow {
    guard let selection else {
        if let focused = catalog.windows.first(where: \.isFocused) {
            return focused
        }
        if let main = catalog.windows.first(where: \.isMain) {
            return main
        }
        guard let first = catalog.windows.first else {
            throw BrrainzToolsError.windowNotFound("`\(catalog.application.name)` has no accessibility windows.")
        }
        return first
    }

    switch selection {
    case .frontmost:
        if let focused = catalog.windows.first(where: \.isFocused) {
            return focused
        }
        if let main = catalog.windows.first(where: \.isMain) {
            return main
        }
        guard let first = catalog.windows.first else {
            throw BrrainzToolsError.windowNotFound("`\(catalog.application.name)` has no accessibility windows.")
        }
        return first
    case .index(let index):
        guard let window = catalog.windows.first(where: { $0.index == index }) else {
            throw BrrainzToolsError.windowNotFound("No accessibility window at index \(index) for `\(catalog.application.name)`.")
        }
        return window
    case .name(let query):
        let normalizedQuery = query.lowercased()
        let exactMatches = catalog.windows.filter { ($0.title ?? "").lowercased() == normalizedQuery }

        if exactMatches.count == 1, let match = exactMatches.first {
            return match
        }

        let partialMatches = catalog.windows.filter { ($0.title ?? "").lowercased().contains(normalizedQuery) }
        let matches = exactMatches.isEmpty ? partialMatches : exactMatches

        guard !matches.isEmpty else {
            throw BrrainzToolsError.windowNotFound("No accessibility window named `\(query)` was found for `\(catalog.application.name)`.")
        }

        guard matches.count == 1, let match = matches.first else {
            let suggestions = matches
                .prefix(5)
                .map { "[\($0.index)] \(displayTitle($0.title))" }
                .joined(separator: ", ")
            throw BrrainzToolsError.ambiguousWindow("More than one accessibility window matches `\(query)`: \(suggestions)")
        }

        return match
    }
}

private func accessibilityElementResponse(
    for element: AXUIElement,
    depthRemaining: Int,
    childLimit: Int = 25,
    path: String? = nil
) -> AccessibilityElementResponse {
    let children = copyAXElements(from: element, attribute: kAXChildrenAttribute as CFString)
    let shouldDescend = depthRemaining > 0
    let limitedChildren = shouldDescend ? Array(children.prefix(childLimit)) : []
    let childResponses = shouldDescend
        ? limitedChildren.enumerated().map { index, child in
            accessibilityElementResponse(
                for: child,
                depthRemaining: depthRemaining - 1,
                childLimit: childLimit,
                path: path.map { "\($0).\(index)" }
            )
        }
        : nil
    let truncated = (children.count > childLimit) || (depthRemaining == 0 && !children.isEmpty)
    let actions = reportedAXActions(copyAXActions(from: element))

    return AccessibilityElementResponse(
        path: path,
        role: copyAXString(from: element, attribute: kAXRoleAttribute as CFString),
        subrole: copyAXString(from: element, attribute: kAXSubroleAttribute as CFString),
        title: normalizedTitle(copyAXString(from: element, attribute: kAXTitleAttribute as CFString)),
        description: normalizedTitle(copyAXString(from: element, attribute: kAXDescriptionAttribute as CFString)),
        identifier: normalizedTitle(copyAXString(from: element, attribute: kAXIdentifierAttribute as CFString)),
        value: copyAXStringifiedValue(from: element, attribute: kAXValueAttribute as CFString),
        enabled: copyAXBool(from: element, attribute: kAXEnabledAttribute as CFString),
        focused: copyAXBool(from: element, attribute: kAXFocusedAttribute as CFString),
        selected: copyAXBool(from: element, attribute: kAXSelectedAttribute as CFString),
        frame: copyAXFrame(from: element).map(JSONRect.init),
        actions: actions.isEmpty ? nil : actions,
        childCount: children.count,
        truncated: truncated ? true : nil,
        children: childResponses
    )
}

func preferredAccessibilityElementResponse(
    refreshed: AccessibilityElementResponse,
    fallback: AccessibilityElementResponse
) -> AccessibilityElementResponse {
    refreshed.role == nil ? fallback : refreshed
}

private func refreshedAccessibilityElementResponse(
    for element: AXUIElement,
    fallback: AccessibilityElementResponse,
    depthRemaining: Int = 1
) -> AccessibilityElementResponse {
    preferredAccessibilityElementResponse(
        refreshed: accessibilityElementResponse(for: element, depthRemaining: depthRemaining),
        fallback: fallback
    )
}

func reportedAXActions(_ actions: [String]) -> [String] {
    if actions == [kAXShowMenuAction as String] {
        return []
    }

    return actions
}

private func filteredAccessibilityTree(
    _ response: AccessibilityElementResponse,
    roleFilter: Set<String>,
    interactiveOnly: Bool,
    keepRoot: Bool = true
) -> AccessibilityElementResponse? {
    let filteredChildren = response.children?.compactMap {
        filteredAccessibilityTree(
            $0,
            roleFilter: roleFilter,
            interactiveOnly: interactiveOnly,
            keepRoot: false
        )
    }
    let hasMatchingChild = !(filteredChildren?.isEmpty ?? true)
    let matches = accessibilityElementMatchesTreeFilter(
        response,
        roleFilter: roleFilter,
        interactiveOnly: interactiveOnly
    )

    guard keepRoot || matches || hasMatchingChild else {
        return nil
    }

    return replacingChildren(
        in: response,
        with: response.children == nil ? nil : filteredChildren
    )
}

private func flatAccessibilityElements(
    from response: AccessibilityElementResponse,
    roleFilter: Set<String>,
    interactiveOnly: Bool
) -> [AccessibilityElementResponse] {
    let current = accessibilityElementMatchesTreeFilter(
        response,
        roleFilter: roleFilter,
        interactiveOnly: interactiveOnly
    ) ? [replacingChildren(in: response, with: nil)] : []
    let descendants = response.children?.flatMap {
        flatAccessibilityElements(from: $0, roleFilter: roleFilter, interactiveOnly: interactiveOnly)
    } ?? []
    return current + descendants
}

private func accessibilityElementMatchesTreeFilter(
    _ response: AccessibilityElementResponse,
    roleFilter: Set<String>,
    interactiveOnly: Bool
) -> Bool {
    let roleMatches = roleFilter.isEmpty || response.role.map(roleFilter.contains) == true
    let interactiveMatches = !interactiveOnly || !(response.actions ?? []).isEmpty
    return roleMatches && interactiveMatches
}

private func replacingChildren(
    in response: AccessibilityElementResponse,
    with children: [AccessibilityElementResponse]?
) -> AccessibilityElementResponse {
    AccessibilityElementResponse(
        path: response.path,
        role: response.role,
        subrole: response.subrole,
        title: response.title,
        description: response.description,
        identifier: response.identifier,
        value: response.value,
        enabled: response.enabled,
        focused: response.focused,
        selected: response.selected,
        frame: response.frame,
        actions: response.actions,
        childCount: response.childCount,
        truncated: response.truncated,
        children: children
    )
}

private func accessibilityAncestorResponses(
    for element: AXUIElement,
    stoppingAt targetWindow: AXUIElement
) -> [AccessibilityElementResponse] {
    var responses: [AccessibilityElementResponse] = []
    var current = copyAXElement(from: element, attribute: kAXParentAttribute as CFString)
    var iterationCount = 0

    while let currentElement = current, iterationCount < 64 {
        responses.append(accessibilityElementResponse(for: currentElement, depthRemaining: 0))
        if CFEqual(currentElement, targetWindow) {
            break
        }

        current = copyAXElement(from: currentElement, attribute: kAXParentAttribute as CFString)
        iterationCount += 1
    }

    return responses
}

private func hitTestElement(at screenPoint: CGPoint) throws -> AXUIElement {
    var element: AXUIElement?
    let error = AXUIElementCopyElementAtPosition(
        AXUIElementCreateSystemWide(),
        Float(screenPoint.x),
        Float(screenPoint.y),
        &element
    )

    guard error == .success, let element else {
        throw BrrainzToolsError.accessibilityQueryFailed("No accessibility element was found at screen point \(Int(screenPoint.x)),\(Int(screenPoint.y)).")
    }

    return element
}

private func validateHitElement(
    _ element: AXUIElement,
    belongsTo selectedWindow: AXUIElement,
    selectedWindowTitle: String?
) throws {
    guard let containingWindow = containingAccessibilityWindow(for: element) else {
        throw BrrainzToolsError.accessibilityQueryFailed("The hit-tested element does not expose a containing accessibility window.")
    }

    guard CFEqual(containingWindow, selectedWindow) else {
        let actualWindow = accessibilityElementResponse(for: containingWindow, depthRemaining: 0)
        let actualTitle = displayTitle(actualWindow.title)
        throw BrrainzToolsError.accessibilityQueryFailed("The requested point resolved to a different visible window (`\(actualTitle)`) instead of the selected window `\(displayTitle(selectedWindowTitle))`. Another window or overlay may be in front.")
    }
}

private func containingAccessibilityWindow(for element: AXUIElement) -> AXUIElement? {
    var current: AXUIElement? = element
    var iterationCount = 0

    while let currentElement = current, iterationCount < 64 {
        if copyAXString(from: currentElement, attribute: kAXRoleAttribute as CFString) == (kAXWindowRole as String) {
            return currentElement
        }

        current = copyAXElement(from: currentElement, attribute: kAXParentAttribute as CFString)
        iterationCount += 1
    }

    return nil
}

private func deepestAccessibilityElement(
    in root: AXUIElement,
    containing screenPoint: CGPoint,
    depthRemaining: Int,
    childLimit: Int = 64
) -> AXUIElement? {
    guard let rootFrame = copyAXFrame(from: root), rootFrame.contains(screenPoint) else {
        return nil
    }

    guard depthRemaining > 0 else {
        return root
    }

    let matchingChildren = copyAXElements(from: root, attribute: kAXChildrenAttribute as CFString)
        .prefix(childLimit)
        .compactMap { child -> (element: AXUIElement, area: CGFloat)? in
            guard let frame = copyAXFrame(from: child), frame.contains(screenPoint) else {
                return nil
            }
            return (child, frame.width * frame.height)
        }
        .sorted { $0.area < $1.area }

    for child in matchingChildren {
        if let descendant = deepestAccessibilityElement(
            in: child.element,
            containing: screenPoint,
            depthRemaining: depthRemaining - 1,
            childLimit: childLimit
        ) {
            return descendant
        }
    }

    return root
}

private func resolvePressableElement(
    startingAt element: AXUIElement,
    within targetWindow: AXUIElement,
    failureContext: String
) throws -> AXUIElement {
    var current: AXUIElement? = element
    var iterationCount = 0

    while let currentElement = current, iterationCount < 64 {
        if supportsAXAction(currentElement, action: kAXPressAction as String) {
            return currentElement
        }

        if CFEqual(currentElement, targetWindow) {
            break
        }

        current = copyAXElement(from: currentElement, attribute: kAXParentAttribute as CFString)
        iterationCount += 1
    }

    throw BrrainzToolsError.accessibilityQueryFailed(failureContext)
}

private func selectAccessibilityElement(
    in root: AXUIElement,
    using selector: AccessibilitySelector
) throws -> AccessibilityElementCandidate {
    if let path = selector.path {
        return try accessibilityElementCandidate(atPath: path, in: root, requirePressAction: false)
    }

    let candidates = matchingAccessibilityElementCandidates(
        in: root,
        using: selector,
        requirePressAction: false
    )

    return try selectUniqueAccessibilityCandidate(
        from: candidates,
        selector: selector,
        candidateDescription: "accessibility element"
    )
}

private func waitForAccessibilityElement(
    in root: AXUIElement,
    using selector: AccessibilitySelector,
    timeout: TimeInterval,
    pollInterval: TimeInterval = 0.1
) throws -> AccessibilityElementCandidate {
    let deadline = Date().addingTimeInterval(timeout)

    repeat {
        if let path = selector.path {
            do {
                return try accessibilityElementCandidate(atPath: path, in: root, requirePressAction: false)
            } catch BrrainzToolsError.accessibilityQueryFailed {
                Thread.sleep(forTimeInterval: pollInterval)
                continue
            }
        }

        let candidates = matchingAccessibilityElementCandidates(
            in: root,
            using: selector,
            requirePressAction: false
        )

        if candidates.count == 1, let candidate = candidates.first {
            return candidate
        }

        if candidates.count > 1 {
            return try selectUniqueAccessibilityCandidate(
                from: candidates,
                selector: selector,
                candidateDescription: "accessibility element"
            )
        }

        Thread.sleep(forTimeInterval: pollInterval)
    } while Date() < deadline

    throw BrrainzToolsError.operationTimedOut("No accessibility element matched \(describe(selector: selector)) within \(formatSeconds(timeout)).")
}

private func selectPressableAccessibilityElement(
    in root: AXUIElement,
    using selector: AccessibilitySelector
) throws -> AccessibilityElementCandidate {
    if let path = selector.path {
        return try accessibilityElementCandidate(atPath: path, in: root, requirePressAction: true)
    }

    let candidates = matchingAccessibilityElementCandidates(
        in: root,
        using: selector,
        requirePressAction: true
    )

    return try selectUniqueAccessibilityCandidate(
        from: candidates,
        selector: selector,
        candidateDescription: "pressable accessibility element"
    )
}

private func matchingAccessibilityElementCandidates(
    in root: AXUIElement,
    using selector: AccessibilitySelector,
    requirePressAction: Bool
) -> [AccessibilityElementCandidate] {
    var candidates = collectAccessibilityElementCandidates(in: root, depthRemaining: 10, childLimit: 80)

    if requirePressAction {
        candidates = candidates.filter { $0.actions.contains(kAXPressAction as String) }
    }

    candidates = filterCandidates(candidates, exactMatchFor: selector.role) { candidate in
        candidate.role
    }
    candidates = filterCandidates(candidates, exactMatchFor: selector.subrole) { candidate in
        candidate.subrole
    }
    candidates = refineCandidates(
        candidates,
        preferredText: selector.title
    ) { candidate in
        candidate.title
    }
    candidates = refineCandidates(
        candidates,
        preferredText: selector.identifier
    ) { candidate in
        candidate.identifier
    }
    candidates = refineCandidates(
        candidates,
        preferredText: selector.elementDescription
    ) { candidate in
        candidate.description
    }

    return candidates
}

private func accessibilityElementCandidate(
    atPath path: String,
    in root: AXUIElement,
    requirePressAction: Bool
) throws -> AccessibilityElementCandidate {
    let resolved = try resolveAccessibilityElement(atPath: path, in: root)
    let candidate = accessibilityElementCandidate(for: resolved.element, depth: resolved.depth)

    if requirePressAction, !candidate.actions.contains(kAXPressAction as String) {
        throw BrrainzToolsError.accessibilityQueryFailed("Accessibility element at path `\(path)` does not support `AXPress`.")
    }

    return candidate
}

private func resolveAccessibilityElement(atPath path: String, in root: AXUIElement) throws -> (element: AXUIElement, depth: Int) {
    let indices = path
        .split(separator: ".", omittingEmptySubsequences: false)
        .compactMap { Int($0) }
    var currentElement = root
    var currentPath = "0"

    for (depth, index) in indices.dropFirst().enumerated() {
        let children = copyAXElements(from: currentElement, attribute: kAXChildrenAttribute as CFString)
        guard index < children.count else {
            throw BrrainzToolsError.accessibilityQueryFailed("No accessibility element exists at path `\(path)`: child index \(index) is outside the \(children.count) children at path `\(currentPath)`.")
        }

        currentElement = children[index]
        currentPath += ".\(index)"

        if depth > 64 {
            throw BrrainzToolsError.accessibilityQueryFailed("Accessibility path `\(path)` is too deep.")
        }
    }

    return (currentElement, max(0, indices.count - 1))
}

private func accessibilityElementCandidate(for element: AXUIElement, depth: Int) -> AccessibilityElementCandidate {
    AccessibilityElementCandidate(
        element: element,
        depth: depth,
        role: copyAXString(from: element, attribute: kAXRoleAttribute as CFString),
        subrole: copyAXString(from: element, attribute: kAXSubroleAttribute as CFString),
        title: normalizedTitle(copyAXString(from: element, attribute: kAXTitleAttribute as CFString)),
        description: normalizedTitle(copyAXString(from: element, attribute: kAXDescriptionAttribute as CFString)),
        identifier: normalizedTitle(copyAXString(from: element, attribute: kAXIdentifierAttribute as CFString)),
        frame: copyAXFrame(from: element),
        actions: copyAXActions(from: element)
    )
}

private func selectUniqueAccessibilityCandidate(
    from candidates: [AccessibilityElementCandidate],
    selector: AccessibilitySelector,
    candidateDescription: String
) throws -> AccessibilityElementCandidate {
    guard !candidates.isEmpty else {
        throw BrrainzToolsError.accessibilityQueryFailed("No \(candidateDescription) matched \(describe(selector: selector)).")
    }

    if candidates.count == 1, let candidate = candidates.first {
        return candidate
    }

    let suggestions = candidates
        .prefix(5)
        .map(formatAccessibilityCandidate)
        .joined(separator: ", ")

    throw BrrainzToolsError.accessibilityQueryFailed("More than one \(candidateDescription) matched \(describe(selector: selector)): \(suggestions)")
}

private func collectAccessibilityElementCandidates(
    in root: AXUIElement,
    depthRemaining: Int,
    childLimit: Int,
    currentDepth: Int = 0
) -> [AccessibilityElementCandidate] {
    let candidate = accessibilityElementCandidate(for: root, depth: currentDepth)

    guard depthRemaining > 0 else {
        return [candidate]
    }

    let childCandidates = copyAXElements(from: root, attribute: kAXChildrenAttribute as CFString)
        .prefix(childLimit)
        .flatMap { child in
            collectAccessibilityElementCandidates(
                in: child,
                depthRemaining: depthRemaining - 1,
                childLimit: childLimit,
                currentDepth: currentDepth + 1
            )
        }

    return [candidate] + childCandidates
}

private func filterCandidates(
    _ candidates: [AccessibilityElementCandidate],
    exactMatchFor query: String?,
    extractor: (AccessibilityElementCandidate) -> String?
) -> [AccessibilityElementCandidate] {
    guard let query = normalizedSelectorText(query) else {
        return candidates
    }

    return candidates.filter { candidate in
        normalizedSelectorText(extractor(candidate)) == query
    }
}

private func refineCandidates(
    _ candidates: [AccessibilityElementCandidate],
    preferredText query: String?,
    extractor: (AccessibilityElementCandidate) -> String?
) -> [AccessibilityElementCandidate] {
    guard let query = normalizedSelectorText(query) else {
        return candidates
    }

    let exactMatches = candidates.filter { candidate in
        normalizedSelectorText(extractor(candidate)) == query
    }
    if !exactMatches.isEmpty {
        return exactMatches
    }

    return candidates.filter { candidate in
        guard let value = normalizedSelectorText(extractor(candidate)) else {
            return false
        }
        return value.contains(query)
    }
}

private func openMenuBarSurface(
    for item: MenuBarCatalogItem,
    application: AutomationApplication
) throws -> MenuBarSurface {
    if let existingMenu = visibleMenu(for: item.element) {
        cancelMenu(existingMenu)
        waitForMenuToClose(existingMenu)
        Thread.sleep(forTimeInterval: 0.1)
    }

    if let existingWindow = waitForStableMenuBarSurfaceWindow(
        for: application,
        near: item,
        excludingWindowIDs: [],
        timeout: 0.25
    ) {
        return .window(existingWindow)
    }

    guard supportsAXAction(item.element, action: kAXPressAction as String) else {
        throw BrrainzToolsError.accessibilityQueryFailed("Menu-bar item \(formatMenuBarCandidate(item)) does not support `AXPress`.")
    }

    let excludedWindowIDs = Set(
        currentWindowSnapshots()
            .filter { $0.ownerPID == application.processID }
            .map(\.windowID)
    )

    let error = AXUIElementPerformAction(item.element, kAXPressAction as CFString)
    if let surface = waitForVisibleMenuBarSurface(
        for: item,
        application: application,
        excludingWindowIDs: excludedWindowIDs
    ) {
        return surface
    }

    guard error == .success else {
        throw BrrainzToolsError.accessibilityQueryFailed(
            "Failed to perform `AXPress` on \(formatMenuBarCandidate(item)) (AX error \(formatAXError(error)))."
        )
    }

    throw BrrainzToolsError.accessibilityQueryFailed("No visible menu or menu-like popover appeared after pressing \(formatMenuBarCandidate(item)).")
}

private func activateMenuBarItem(
    _ item: MenuBarCatalogItem,
    requireVisibleMenu: Bool
) throws -> AXUIElement? {
    guard supportsAXAction(item.element, action: kAXPressAction as String) else {
        throw BrrainzToolsError.accessibilityQueryFailed("Menu-bar item \(formatMenuBarCandidate(item)) does not support `AXPress`.")
    }

    let error = AXUIElementPerformAction(item.element, kAXPressAction as CFString)
    let visibleMenu = waitForVisibleMenu(for: item.element)

    if requireVisibleMenu, visibleMenu == nil {
        if error == .success {
            throw BrrainzToolsError.accessibilityQueryFailed(
                "No visible menu appeared after pressing \(formatMenuBarCandidate(item))."
            )
        }

        throw BrrainzToolsError.accessibilityQueryFailed(
            "Failed to perform `AXPress` on \(formatMenuBarCandidate(item)); no visible menu appeared (AX error \(formatAXError(error)))."
        )
    }

    guard error == .success || visibleMenu != nil else {
        throw BrrainzToolsError.accessibilityQueryFailed(
            "Failed to perform `AXPress` on \(formatMenuBarCandidate(item)) (AX error \(formatAXError(error)))."
        )
    }

    return visibleMenu
}

private func waitForVisibleMenu(
    for item: AXUIElement,
    timeout: TimeInterval = 1.5
) -> AXUIElement? {
    let deadline = Date().addingTimeInterval(timeout)

    repeat {
        if let menu = visibleMenu(for: item) {
            return menu
        }
        Thread.sleep(forTimeInterval: 0.05)
    } while Date() < deadline

    return nil
}

private func waitForVisibleMenuBarSurface(
    for item: MenuBarCatalogItem,
    application: AutomationApplication,
    excludingWindowIDs: Set<CGWindowID>,
    timeout: TimeInterval = 1.5
) -> MenuBarSurface? {
    let deadline = Date().addingTimeInterval(timeout)
    var lastMenuFrame: CGRect?

    repeat {
        if let menu = visibleMenu(for: item.element) {
            let frame = copyAXFrame(from: menu)
            if let frame, let lastMenuFrame, nearlyEqual(frame, lastMenuFrame) {
                return .menu(menu)
            }
            lastMenuFrame = frame
        }

        if let window = waitForStableMenuBarSurfaceWindow(
            for: application,
            near: item,
            excludingWindowIDs: excludingWindowIDs,
            timeout: 0.1
        ) {
            return .window(window)
        }

        Thread.sleep(forTimeInterval: 0.05)
    } while Date() < deadline

    return nil
}

private func waitForStableMenuBarSurfaceWindow(
    for application: AutomationApplication,
    near item: MenuBarCatalogItem,
    excludingWindowIDs: Set<CGWindowID>,
    timeout: TimeInterval = 1.0
) -> WindowSnapshot? {
    let deadline = Date().addingTimeInterval(timeout)
    var previous: WindowSnapshot?

    repeat {
        if let current = visibleMenuBarSurfaceWindow(
            for: application,
            near: item,
            excludingWindowIDs: excludingWindowIDs
        ) {
            if
                let previous,
                previous.windowID == current.windowID,
                nearlyEqual(previous.bounds, current.bounds)
            {
                return current
            }
            previous = current
        }

        Thread.sleep(forTimeInterval: 0.05)
    } while Date() < deadline

    return previous
}

private func visibleMenuBarSurfaceWindow(
    for application: AutomationApplication,
    near item: MenuBarCatalogItem,
    excludingWindowIDs: Set<CGWindowID>
) -> WindowSnapshot? {
    guard let itemFrame = item.frame else {
        return nil
    }

    return currentWindowSnapshots()
        .filter { snapshot in
            snapshot.ownerPID == application.processID &&
            snapshot.layer > 0 &&
            !excludingWindowIDs.contains(snapshot.windowID) &&
            snapshot.bounds.width >= 20 &&
            snapshot.bounds.height >= 20 &&
            isLikelyMenuBarSurfaceWindow(snapshot.bounds, near: itemFrame)
        }
        .sorted { left, right in
            let leftDistance = abs(left.bounds.minY - itemFrame.maxY)
            let rightDistance = abs(right.bounds.minY - itemFrame.maxY)
            if leftDistance != rightDistance {
                return leftDistance < rightDistance
            }

            let leftArea = left.bounds.width * left.bounds.height
            let rightArea = right.bounds.width * right.bounds.height
            return leftArea < rightArea
        }
        .first
}

private func isLikelyMenuBarSurfaceWindow(_ windowFrame: CGRect, near itemFrame: CGRect) -> Bool {
    let horizontalMargin: CGFloat = 80
    let itemMidX = itemFrame.midX
    let horizontallyRelated =
        itemMidX >= windowFrame.minX - horizontalMargin &&
        itemMidX <= windowFrame.maxX + horizontalMargin

    let belowMenuBar =
        windowFrame.minY >= itemFrame.maxY - 8 &&
        windowFrame.minY <= itemFrame.maxY + 220

    let aboveMenuBar =
        windowFrame.maxY <= itemFrame.minY + 8 &&
        windowFrame.maxY >= itemFrame.minY - 220

    return horizontallyRelated && (belowMenuBar || aboveMenuBar)
}

private func nearlyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 1) -> Bool {
    abs(lhs.minX - rhs.minX) <= tolerance &&
    abs(lhs.minY - rhs.minY) <= tolerance &&
    abs(lhs.width - rhs.width) <= tolerance &&
    abs(lhs.height - rhs.height) <= tolerance
}

private func waitForMenuToClose(
    _ menu: AXUIElement,
    timeout: TimeInterval = 0.5
) {
    let deadline = Date().addingTimeInterval(timeout)

    repeat {
        if let frame = copyAXFrame(from: menu), frame.isEmpty {
            return
        }
        Thread.sleep(forTimeInterval: 0.05)
    } while Date() < deadline
}

private func visibleMenu(for item: AXUIElement) -> AXUIElement? {
    copyAXElements(from: item, attribute: kAXChildrenAttribute as CFString)
        .first { element in
            guard copyAXString(from: element, attribute: kAXRoleAttribute as CFString) == (kAXMenuRole as String) else {
                return false
            }
            guard let frame = copyAXFrame(from: element) else {
                return false
            }
            return !frame.isEmpty
        }
}

private func cancelMenu(_ menu: AXUIElement) {
    _ = AXUIElementPerformAction(menu, kAXCancelAction as CFString)
}

private func closeMenuBarSurface(_ surface: MenuBarSurface, item: MenuBarCatalogItem) {
    switch surface {
    case .menu(let menu):
        cancelMenu(menu)
        waitForMenuToClose(menu)
    case .window(let snapshot):
        closeMenuBarWindowSurface(processID: snapshot.ownerPID, windowID: snapshot.windowID) { attempt in
            switch attempt {
            case .pressEscape(let processID, let windowID):
                pressEscapeKey(inProcess: processID)
                return waitForWindowToClose(windowID)
            case .pressMenuBarItem(let windowID):
                return windowClosesAfterPressingMenuBarItem(item, windowID: windowID)
            }
        }
    }
}

func closeMenuBarWindowSurface(
    processID: pid_t,
    windowID: CGWindowID,
    attemptClose: (MenuBarWindowCloseAttempt) -> Bool
) {
    if attemptClose(.pressEscape(processID: processID, windowID: windowID)) {
        return
    }

    _ = attemptClose(.pressMenuBarItem(windowID: windowID))
}

private func windowClosesAfterPressingMenuBarItem(
    _ item: MenuBarCatalogItem,
    windowID: CGWindowID
) -> Bool {
    _ = AXUIElementPerformAction(item.element, kAXPressAction as CFString)
    return waitForWindowToClose(windowID)
}

private func waitForWindowToClose(
    _ windowID: CGWindowID,
    timeout: TimeInterval = 0.75
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)

    repeat {
        if !currentWindowSnapshots().contains(where: { $0.windowID == windowID }) {
            return true
        }
        Thread.sleep(forTimeInterval: 0.05)
    } while Date() < deadline

    return false
}

private func prepareForMouseInput(
    application: AutomationApplication,
    window: AXUIElement
) async throws -> (activationRequestAccepted: Bool, windowRaiseAttempted: Bool) {
    let activationRequestAccepted = activateApplication(application)
    var windowRaiseAttempted = false

    if supportsAXAction(window, action: kAXRaiseAction as String) {
        windowRaiseAttempted = try performRaise(
            on: window,
            application: application
        )
    }

    try await Task.sleep(nanoseconds: 100_000_000)
    return (activationRequestAccepted, windowRaiseAttempted)
}

private func screenPoint(for point: WindowPoint, in windowFrame: CGRect) -> CGPoint {
    CGPoint(
        x: windowFrame.minX + CGFloat(point.x),
        y: windowFrame.minY + CGFloat(point.y)
    )
}

private func centerPoint(in windowFrame: CGRect) -> WindowPoint {
    WindowPoint(
        x: max(0, Int((windowFrame.width / 2).rounded(.down))),
        y: max(0, Int((windowFrame.height / 2).rounded(.down)))
    )
}

func visibleCenterPoint(of targetFrame: CGRect, within windowFrame: CGRect) -> CGPoint? {
    let visibleFrame = targetFrame.intersection(windowFrame)
    guard !visibleFrame.isNull, !visibleFrame.isEmpty else {
        return nil
    }

    return CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
}

private func postMouseClick(_ click: MouseClick, at screenPoint: CGPoint) throws {
    guard let source = CGEventSource(stateID: .privateState) else {
        throw BrrainzToolsError.accessibilityQueryFailed("Failed to create a mouse event source.")
    }

    let downType: CGEventType = click.button == .right ? .rightMouseDown : .leftMouseDown
    let upType: CGEventType = click.button == .right ? .rightMouseUp : .leftMouseUp
    let button: CGMouseButton = click.button == .right ? .right : .left

    for clickIndex in 1...click.clickCount {
        try postMouseEvent(
            type: downType,
            at: screenPoint,
            button: button,
            clickState: clickIndex,
            source: source
        )
        try postMouseEvent(
            type: upType,
            at: screenPoint,
            button: button,
            clickState: clickIndex,
            source: source
        )
    }
}

private func postMouseDrag(from startPoint: CGPoint, to endPoint: CGPoint) throws {
    guard let source = CGEventSource(stateID: .privateState) else {
        throw BrrainzToolsError.accessibilityQueryFailed("Failed to create a mouse event source.")
    }

    try postMouseEvent(type: .leftMouseDown, at: startPoint, button: .left, clickState: 1, source: source)

    let distance = hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y)
    let stepCount = max(1, min(24, Int(distance / 24)))
    for step in 1...stepCount {
        let progress = CGFloat(step) / CGFloat(stepCount)
        let point = CGPoint(
            x: startPoint.x + ((endPoint.x - startPoint.x) * progress),
            y: startPoint.y + ((endPoint.y - startPoint.y) * progress)
        )
        try postMouseEvent(type: .leftMouseDragged, at: point, button: .left, clickState: 1, source: source)
    }

    try postMouseEvent(type: .leftMouseUp, at: endPoint, button: .left, clickState: 1, source: source)
}

private func postMouseEvent(
    type: CGEventType,
    at screenPoint: CGPoint,
    button: CGMouseButton,
    clickState: Int,
    source: CGEventSource
) throws {
    guard let event = CGEvent(
        mouseEventSource: source,
        mouseType: type,
        mouseCursorPosition: screenPoint,
        mouseButton: button
    ) else {
        throw BrrainzToolsError.accessibilityQueryFailed("Failed to create mouse event.")
    }

    event.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
    event.post(tap: .cgSessionEventTap)
    Thread.sleep(forTimeInterval: 0.01)
}

private func postScroll(_ delta: ScrollDelta, at screenPoint: CGPoint) throws {
    guard
        let source = CGEventSource(stateID: .privateState),
        let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 2,
            wheel1: delta.y,
            wheel2: delta.x,
            wheel3: 0
        )
    else {
        throw BrrainzToolsError.accessibilityQueryFailed("Failed to create scroll event.")
    }

    event.location = screenPoint
    event.post(tap: .cgSessionEventTap)
}

private func postText(_ text: String, to processID: pid_t) throws {
    guard let source = CGEventSource(stateID: .privateState) else {
        throw BrrainzToolsError.accessibilityQueryFailed("Failed to create a keyboard event source.")
    }

    for character in text {
        var utf16 = Array(String(character).utf16)
        try postUnicodeKeyEvent(utf16: &utf16, source: source, to: processID)
        Thread.sleep(forTimeInterval: 0.005)
    }
}

private func postUnicodeKeyEvent(
    utf16: inout [UInt16],
    source: CGEventSource,
    to processID: pid_t
) throws {
    guard
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
    else {
        throw BrrainzToolsError.accessibilityQueryFailed("Failed to create Unicode keyboard events.")
    }

    utf16.withUnsafeBufferPointer { buffer in
        keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
        keyUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
    }

    keyDown.flags = []
    keyUp.flags = []
    keyDown.postToPid(processID)
    keyUp.postToPid(processID)
}

private func postKeyChord(_ chord: KeyChord, to processID: pid_t) throws {
    guard let source = CGEventSource(stateID: .privateState) else {
        throw BrrainzToolsError.accessibilityQueryFailed("Failed to create a keyboard event source.")
    }

    // Modifier shortcuts are interpreted by the frontmost app; the caller activates the target process before posting.
    _ = processID
    let activeFlags = chord.eventFlags
    try postKeyCode(chord.keyCode, keyDown: true, flags: activeFlags, source: source)
    try postKeyCode(chord.keyCode, keyDown: false, flags: activeFlags, source: source)
}

private func postKeyCode(
    _ keyCode: CGKeyCode,
    keyDown: Bool,
    flags: CGEventFlags,
    source: CGEventSource
) throws {
    guard
        let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown)
    else {
        throw BrrainzToolsError.accessibilityQueryFailed("Failed to create keyboard event for virtual key \(keyCode).")
    }

    event.flags = flags
    event.post(tap: .cgSessionEventTap)
    Thread.sleep(forTimeInterval: 0.005)
}

private func pressEscapeKey(inProcess processID: pid_t) {
    let source = CGEventSource(stateID: .hidSystemState)
    CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true)?.postToPid(processID)
    CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false)?.postToPid(processID)
}

private func captureMenuBarSurface(
    _ surface: MenuBarSurface,
    item: MenuBarCatalogItem,
    outputURL: URL,
    timeout: TimeInterval,
    imageOutput: ImageOutputOptions
) async throws {
    let stableFrame = waitForStableMenuBarSurfaceFrame(
        initialFrame: menuBarSurfaceFrame(surface),
        readFrame: { menuBarSurfaceFrame(surface) }
    )
    let region = try captureRegion(forMenuFrame: stableFrame, item: item)

    do {
        try await captureScreenRegion(
            region: region,
            outputURL: outputURL,
            timeout: timeout,
            imageOutput: imageOutput
        )
    } catch BrrainzToolsError.captureFailed(let message) {
        throw BrrainzToolsError.captureFailed("Failed to capture \(surface.kind) for \(formatMenuBarCandidate(item)) at `\(region.rectangleArgument)`: \(message)")
    }
}

private func menuBarSurfaceFrame(_ surface: MenuBarSurface) -> CGRect? {
    switch surface {
    case .menu(let element):
        return copyAXFrame(from: element)
    case .window(let snapshot):
        return currentWindowSnapshots()
            .first { $0.windowID == snapshot.windowID }?
            .bounds ?? snapshot.bounds
    }
}

func waitForStableMenuBarSurfaceFrame(
    initialFrame: CGRect?,
    timeout: TimeInterval = 0.5,
    pollInterval: TimeInterval = 0.05,
    now: () -> Date = Date.init,
    sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
    readFrame: () -> CGRect?
) -> CGRect? {
    let deadline = now().addingTimeInterval(timeout)
    var previous = nonEmptyMenuBarSurfaceFrame(initialFrame)
    var latest = previous

    repeat {
        if let current = nonEmptyMenuBarSurfaceFrame(readFrame()) {
            if let previous, nearlyEqual(previous, current) {
                return current
            }

            previous = current
            latest = current
        }

        sleep(pollInterval)
    } while now() < deadline

    return latest
}

private func nonEmptyMenuBarSurfaceFrame(_ frame: CGRect?) -> CGRect? {
    guard let frame, !frame.isEmpty else {
        return nil
    }

    return frame
}

private func captureRegion(
    forMenuFrame frame: CGRect?,
    item: MenuBarCatalogItem
) throws -> CaptureRegion {
    guard let frame, !frame.isEmpty else {
        throw BrrainzToolsError.captureFailed("The opened menu for \(formatMenuBarCandidate(item)) did not expose a visible frame.")
    }

    let minX = Int(floor(frame.minX))
    let minY = Int(floor(frame.minY))
    let maxX = Int(ceil(frame.maxX))
    let maxY = Int(ceil(frame.maxY))
    let originX = max(0, minX)
    let originY = max(0, minY)
    let region = CaptureRegion(
        x: originX,
        y: originY,
        width: maxX - originX,
        height: maxY - originY
    )
    try validate(region: region)
    return region
}

private struct AXElementCollectionRead {
    let error: AXError
    let elements: [AXUIElement]
}

private struct AXElementCollectionMembershipProbe {
    let parent: AXUIElement
    let attribute: CFString
    let element: AXUIElement

    func isPresent() -> Bool {
        let read = copyAXElementCollection(from: parent, attribute: attribute)
        guard read.error == .success else {
            return false
        }

        return read.elements.contains { CFEqual($0, element) }
    }

    func isAbsent() -> Bool {
        let read = copyAXElementCollection(from: parent, attribute: attribute)
        guard read.error == .success else {
            return false
        }

        return !read.elements.contains { CFEqual($0, element) }
    }
}

private func membershipProbe(
    for element: AXUIElement,
    in parent: AXUIElement,
    attribute: CFString
) -> AXElementCollectionMembershipProbe? {
    let probe = AXElementCollectionMembershipProbe(
        parent: parent,
        attribute: attribute,
        element: element
    )
    return probe.isPresent() ? probe : nil
}

private func directParentMembershipProbe(
    for element: AXUIElement
) -> AXElementCollectionMembershipProbe? {
    guard let parent = copyAXElement(from: element, attribute: kAXParentAttribute as CFString) else {
        return nil
    }

    let role = copyAXString(from: element, attribute: kAXRoleAttribute as CFString)
    let attribute = role == (kAXWindowRole as String)
        ? kAXWindowsAttribute as CFString
        : kAXChildrenAttribute as CFString
    return membershipProbe(for: element, in: parent, attribute: attribute)
}

private func transientModalDisappearanceProbe(
    for element: AXUIElement,
    stoppingAt targetWindow: AXUIElement
) -> AXElementCollectionMembershipProbe? {
    var current: AXUIElement? = element
    var iterationCount = 0

    while let currentElement = current, iterationCount < 64 {
        let role = copyAXString(from: currentElement, attribute: kAXRoleAttribute as CFString)
        let subrole = copyAXString(from: currentElement, attribute: kAXSubroleAttribute as CFString)
        let isTransientModal =
            role == (kAXSheetRole as String) ||
            subrole == "AXDialog" ||
            copyAXBool(from: currentElement, attribute: kAXModalAttribute as CFString) == true

        if isTransientModal, let probe = directParentMembershipProbe(for: currentElement) {
            return probe
        }

        if CFEqual(currentElement, targetWindow) {
            break
        }

        current = copyAXElement(from: currentElement, attribute: kAXParentAttribute as CFString)
        iterationCount += 1
    }

    return nil
}

private func windowDisappearanceProbe(
    application: AutomationApplication,
    window: AXUIElement
) -> AXElementCollectionMembershipProbe? {
    membershipProbe(
        for: window,
        in: AXUIElementCreateApplication(application.processID),
        attribute: kAXWindowsAttribute as CFString
    )
}

private func windowIsReadyForInput(
    application: AutomationApplication,
    window: AXUIElement
) -> Bool {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processID else {
        return false
    }

    let applicationElement = AXUIElementCreateApplication(application.processID)
    let focusedWindow = copyAXElement(
        from: applicationElement,
        attribute: kAXFocusedWindowAttribute as CFString
    )
    let mainWindow = copyAXElement(
        from: applicationElement,
        attribute: kAXMainWindowAttribute as CFString
    )

    if focusedWindow.map({ CFEqual($0, window) }) == true ||
        mainWindow.map({ CFEqual($0, window) }) == true ||
        copyAXBool(from: window, attribute: kAXFocusedAttribute as CFString) == true
    {
        return true
    }

    guard focusedWindow == nil, mainWindow == nil else {
        return false
    }

    return copyAXElements(
        from: applicationElement,
        attribute: kAXWindowsAttribute as CFString
    ).first.map { CFEqual($0, window) } == true
}

func axPointMatches(
    _ actual: CGPoint?,
    expected: CGPoint,
    tolerance: CGFloat = 1
) -> Bool {
    guard let actual else {
        return false
    }

    return abs(actual.x - expected.x) <= tolerance &&
        abs(actual.y - expected.y) <= tolerance
}

func axSizeMatches(
    _ actual: CGSize?,
    expected: CGSize,
    tolerance: CGFloat = 1
) -> Bool {
    guard let actual else {
        return false
    }

    return abs(actual.width - expected.width) <= tolerance &&
        abs(actual.height - expected.height) <= tolerance
}

private func performMenuItemAction(
    on candidate: AccessibilityElementCandidate,
    in menu: AXUIElement
) throws -> String {
    let target = formatAccessibilityCandidate(candidate)
    let menuProbe = directParentMembershipProbe(for: menu)
    let itemProbe = directParentMembershipProbe(for: candidate.element)
    let actions = [kAXPressAction as String, kAXPickAction as String]
        .filter { supportsAXAction(candidate.element, action: $0) }

    guard let primaryAction = actions.first else {
        throw BrrainzToolsError.accessibilityQueryFailed(
            "Child menu item \(target) does not support `AXPress` or `AXPick`."
        )
    }

    let primaryOutcome = performAXMutationOnce(
        perform: {
            AXUIElementPerformAction(candidate.element, primaryAction as CFString)
        },
        verifyPostcondition: menuProbe.map { probe in
            { probe.isAbsent() }
        }
    )
    if primaryOutcome.accepted {
        return primaryAction
    }

    let alternateAction = actions.first { $0 != primaryAction }
    let menuStillVisible = menuProbe?.isPresent() ?? false
    let itemStillReachable = itemProbe?.isPresent() ?? false
    if
        let alternateAction,
        shouldAttemptAlternateMenuAction(
            primaryAccepted: false,
            menuStillVisible: menuStillVisible,
            itemStillReachable: itemStillReachable,
            supportsAlternateAction: true
        )
    {
        let alternateOutcome = performAXMutationOnce(
            perform: {
                AXUIElementPerformAction(candidate.element, alternateAction as CFString)
            },
            verifyPostcondition: menuProbe.map { probe in
                { probe.isAbsent() }
            }
        )
        if alternateOutcome.accepted {
            return alternateAction
        }

        throw BrrainzToolsError.accessibilityQueryFailed(
            "Failed to press child menu item \(target): `\(primaryAction)` returned \(formatAXError(primaryOutcome.error)); `\(alternateAction)` returned \(formatAXError(alternateOutcome.error))."
        )
    }

    throw BrrainzToolsError.accessibilityQueryFailed(
        "Failed to press child menu item \(target): `\(primaryAction)` returned \(formatAXError(primaryOutcome.error)); no alternate action was attempted because the original menu item was no longer safely reachable."
    )
}

private func performSetValue(_ value: String, on element: AXUIElement) throws {
    let target = formatAccessibilityCandidate(accessibilityElementCandidate(for: element, depth: 0))
    var isSettable = DarwinBoolean(false)
    let settableError = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &isSettable)
    if settableError == .success, !isSettable.boolValue {
        throw BrrainzToolsError.accessibilityQueryFailed("Selected element \(target) does not allow setting `AXValue`.")
    }

    let outcome = performAXMutationOnce(
        perform: {
            AXUIElementSetAttributeValue(
                element,
                kAXValueAttribute as CFString,
                value as CFString
            )
        },
        verifyPostcondition: {
            copyAXString(from: element, attribute: kAXValueAttribute as CFString) == value
        }
    )
    guard outcome.accepted else {
        throw BrrainzToolsError.accessibilityQueryFailed(
            "Failed to set `AXValue` on \(target) (AX error \(formatAXError(outcome.error)))."
        )
    }
}

private func performSetWindowPosition(_ position: WindowPosition, on element: AXUIElement) throws {
    let target = formatAccessibilityCandidate(accessibilityElementCandidate(for: element, depth: 0))
    var point = position.point
    guard let value = AXValueCreate(.cgPoint, &point) else {
        throw BrrainzToolsError.accessibilityQueryFailed("Failed to create `AXPosition` value \(position.x),\(position.y).")
    }

    let outcome = performAXMutationOnce(
        perform: {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
        },
        verifyPostcondition: {
            axPointMatches(
                copyAXPoint(from: element, attribute: kAXPositionAttribute as CFString),
                expected: position.point
            )
        }
    )
    guard outcome.accepted else {
        throw BrrainzToolsError.accessibilityQueryFailed(
            "Failed to set `AXPosition` on \(target) (AX error \(formatAXError(outcome.error)))."
        )
    }
}

private func performSetWindowSize(_ size: WindowSize, on element: AXUIElement) throws {
    let target = formatAccessibilityCandidate(accessibilityElementCandidate(for: element, depth: 0))
    var cgSize = size.size
    guard let value = AXValueCreate(.cgSize, &cgSize) else {
        throw BrrainzToolsError.accessibilityQueryFailed("Failed to create `AXSize` value \(size.width),\(size.height).")
    }

    let outcome = performAXMutationOnce(
        perform: {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
        },
        verifyPostcondition: {
            axSizeMatches(
                copyAXSize(from: element, attribute: kAXSizeAttribute as CFString),
                expected: size.size
            )
        }
    )
    guard outcome.accepted else {
        throw BrrainzToolsError.accessibilityQueryFailed(
            "Failed to set `AXSize` on \(target) (AX error \(formatAXError(outcome.error)))."
        )
    }
}

private func performPress(
    on element: AXUIElement,
    verifyPostcondition: (() -> Bool)? = nil
) throws {
    let target = formatAccessibilityCandidate(accessibilityElementCandidate(for: element, depth: 0))
    let outcome = performAXMutationOnce(
        perform: {
            AXUIElementPerformAction(element, kAXPressAction as CFString)
        },
        verifyPostcondition: verifyPostcondition
    )
    guard outcome.accepted else {
        throw BrrainzToolsError.accessibilityQueryFailed(
            "Failed to perform `AXPress` on \(target) (AX error \(formatAXError(outcome.error)))."
        )
    }
}

private func activateApplication(_ application: AutomationApplication) -> Bool {
    guard let runningApplication = NSRunningApplication(processIdentifier: application.processID) else {
        return false
    }

    return runningApplication.activate(from: .current, options: [])
}

private func performRaise(
    on element: AXUIElement,
    application: AutomationApplication
) throws -> Bool {
    if windowIsReadyForInput(application: application, window: element) {
        return false
    }

    let target = formatAccessibilityCandidate(accessibilityElementCandidate(for: element, depth: 0))
    guard supportsAXAction(element, action: kAXRaiseAction as String) else {
        throw BrrainzToolsError.accessibilityQueryFailed("Selected window \(target) does not support `AXRaise`.")
    }

    let outcome = performAXMutationOnce(
        perform: {
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        },
        verifyPostcondition: {
            windowIsReadyForInput(application: application, window: element)
        }
    )
    guard outcome.accepted else {
        throw BrrainzToolsError.accessibilityQueryFailed(
            "Failed to perform `AXRaise` on \(target) (AX error \(formatAXError(outcome.error)))."
        )
    }

    return true
}

private func supportsAXAction(_ element: AXUIElement, action: String) -> Bool {
    let normalizedAction = normalizedSelectorText(action)
    return copyAXActions(from: element).contains { candidate in
        normalizedSelectorText(candidate) == normalizedAction
    }
}

private func normalizedSelectorText(_ value: String?) -> String? {
    guard let value else {
        return nil
    }

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }

    return trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
}

private func describe(selector: AccessibilitySelector) -> String {
    let parts = [
        selector.path.map { "path `\($0)`" },
        selector.role.map { "role `\($0)`" },
        selector.subrole.map { "subrole `\($0)`" },
        selector.title.map { "title `\($0)`" },
        selector.identifier.map { "identifier `\($0)`" },
        selector.elementDescription.map { "description `\($0)`" },
    ].compactMap { $0 }

    return parts.joined(separator: ", ")
}

private func formatAXElement(_ element: AXUIElement) -> String {
    formatAccessibilityCandidate(
        AccessibilityElementCandidate(
            element: element,
            depth: 0,
            role: copyAXString(from: element, attribute: kAXRoleAttribute as CFString),
            subrole: copyAXString(from: element, attribute: kAXSubroleAttribute as CFString),
            title: normalizedTitle(copyAXString(from: element, attribute: kAXTitleAttribute as CFString)),
            description: normalizedTitle(copyAXString(from: element, attribute: kAXDescriptionAttribute as CFString)),
            identifier: normalizedTitle(copyAXString(from: element, attribute: kAXIdentifierAttribute as CFString)),
            frame: copyAXFrame(from: element),
            actions: copyAXActions(from: element)
        )
    )
}

private func formatAccessibilityCandidate(_ candidate: AccessibilityElementCandidate) -> String {
    let role = candidate.role ?? "?"
    let subrole = candidate.subrole.map { "/\($0)" } ?? ""
    let title = candidate.title.map { " title=\($0)" } ?? ""
    let identifier = candidate.identifier.map { " id=\($0)" } ?? ""
    let frame = candidate.frame.map { " @ \(formatFrame($0))" } ?? ""
    return "\(role)\(subrole)\(title)\(identifier)\(frame)"
}

private func copyAXString(from element: AXUIElement, attribute: CFString) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
        return nil
    }
    return value as? String
}

private func copyAXStringifiedValue(from element: AXUIElement, attribute: CFString) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success, let value else {
        return nil
    }

    return stringifyAXAttributeValue(value)
}

private func copyAXBool(from element: AXUIElement, attribute: CFString) -> Bool? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success, let value else {
        return nil
    }

    if let boolValue = value as? Bool {
        return boolValue
    }

    if let numberValue = value as? NSNumber {
        return numberValue.boolValue
    }

    return nil
}

private func copyAXInteger(from element: AXUIElement, attribute: CFString) -> Int? {
    var value: CFTypeRef?
    guard
        AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
        let number = value as? NSNumber
    else {
        return nil
    }

    return number.intValue
}

private func copyAXUInt32(from element: AXUIElement, attribute: CFString) -> UInt32? {
    var value: CFTypeRef?
    guard
        AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
        let number = value as? NSNumber
    else {
        return nil
    }

    return number.uint32Value
}

func stringifyAXAttributeValue(_ value: Any) -> String? {
    switch value {
    case let string as String:
        return normalizedTitle(singleLineText(string))
    case let attributedString as NSAttributedString:
        return normalizedTitle(singleLineText(attributedString.string))
    case let bool as Bool:
        return bool ? "true" : "false"
    case let number as NSNumber:
        return number.stringValue
    case let url as URL:
        return url.absoluteString
    default:
        return nil
    }
}

private func copyAXElement(from element: AXUIElement, attribute: CFString) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success, let value else {
        return nil
    }
    guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
        return nil
    }
    let axElement = value as! AXUIElement
    return axElement
}

private func copyAXElements(from element: AXUIElement, attribute: CFString) -> [AXUIElement] {
    let read = copyAXElementCollection(from: element, attribute: attribute)
    return read.error == .success ? read.elements : []
}

private func copyAXElementCollection(
    from element: AXUIElement,
    attribute: CFString
) -> AXElementCollectionRead {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute, &value)
    guard error == .success else {
        return AXElementCollectionRead(error: error, elements: [])
    }

    return AXElementCollectionRead(
        error: error,
        elements: value as? [AXUIElement] ?? []
    )
}

private func copyAXActions(from element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success else {
        return []
    }
    return names as? [String] ?? []
}

private func copyAXFrame(from element: AXUIElement) -> CGRect? {
    guard
        let position = copyAXPoint(from: element, attribute: kAXPositionAttribute as CFString),
        let size = copyAXSize(from: element, attribute: kAXSizeAttribute as CFString)
    else {
        return nil
    }

    return CGRect(origin: position, size: size)
}

private func copyAXPoint(from element: AXUIElement, attribute: CFString) -> CGPoint? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success, let value else {
        return nil
    }
    guard CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }

    let axValue = value as! AXValue
    guard AXValueGetType(axValue) == .cgPoint else {
        return nil
    }

    var point = CGPoint.zero
    guard AXValueGetValue(axValue, .cgPoint, &point) else {
        return nil
    }
    return point
}

private func copyAXSize(from element: AXUIElement, attribute: CFString) -> CGSize? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success, let value else {
        return nil
    }
    guard CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }

    let axValue = value as! AXValue
    guard AXValueGetType(axValue) == .cgSize else {
        return nil
    }

    var size = CGSize.zero
    guard AXValueGetValue(axValue, .cgSize, &size) else {
        return nil
    }
    return size
}

private func formatFrame(_ frame: CGRect) -> String {
    "\(Int(frame.minX.rounded(.down))),\(Int(frame.minY.rounded(.down))) \(Int(frame.width.rounded(.down)))x\(Int(frame.height.rounded(.down)))"
}

private final class TimeoutRaceState<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private var operationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var cancelLateOperationTask = false
    private var cancelLateTimeoutTask = false

    func setOperationTask(_ task: Task<Void, Never>) {
        let shouldCancel: Bool
        lock.lock()
        if completed {
            shouldCancel = cancelLateOperationTask
        } else {
            operationTask = task
            shouldCancel = false
        }
        lock.unlock()

        if shouldCancel {
            task.cancel()
        }
    }

    func setTimeoutTask(_ task: Task<Void, Never>) {
        let shouldCancel: Bool
        lock.lock()
        if completed {
            shouldCancel = cancelLateTimeoutTask
        } else {
            timeoutTask = task
            shouldCancel = false
        }
        lock.unlock()

        if shouldCancel {
            task.cancel()
        }
    }

    func complete(
        _ result: Result<T, Error>,
        continuation: CheckedContinuation<T, Error>,
        cancelOperationTask: Bool,
        cancelTimeoutTask: Bool
    ) {
        let operationTaskToCancel: Task<Void, Never>?
        let timeoutTaskToCancel: Task<Void, Never>?

        lock.lock()
        if completed {
            lock.unlock()
            return
        }

        completed = true
        cancelLateOperationTask = cancelOperationTask
        cancelLateTimeoutTask = cancelTimeoutTask
        operationTaskToCancel = cancelOperationTask ? operationTask : nil
        timeoutTaskToCancel = cancelTimeoutTask ? timeoutTask : nil
        lock.unlock()

        operationTaskToCancel?.cancel()
        timeoutTaskToCancel?.cancel()
        continuation.resume(with: result)
    }

    func cancelAll() {
        let operationTaskToCancel: Task<Void, Never>?
        let timeoutTaskToCancel: Task<Void, Never>?

        lock.lock()
        completed = true
        cancelLateOperationTask = true
        cancelLateTimeoutTask = true
        operationTaskToCancel = operationTask
        timeoutTaskToCancel = timeoutTask
        lock.unlock()

        operationTaskToCancel?.cancel()
        timeoutTaskToCancel?.cancel()
    }
}

func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    timeoutMessage: @escaping @Sendable () -> String,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let state = TimeoutRaceState<T>()
    let nanoseconds = timeoutNanoseconds(seconds)

    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            let operationTask = Task {
                do {
                    let value = try await operation()
                    state.complete(
                        .success(value),
                        continuation: continuation,
                        cancelOperationTask: false,
                        cancelTimeoutTask: true
                    )
                } catch {
                    state.complete(
                        .failure(error),
                        continuation: continuation,
                        cancelOperationTask: false,
                        cancelTimeoutTask: true
                    )
                }
            }
            state.setOperationTask(operationTask)

            let timeoutTask = Task {
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    return
                }

                state.complete(
                    .failure(BrrainzToolsError.operationTimedOut(timeoutMessage())),
                    continuation: continuation,
                    cancelOperationTask: false,
                    cancelTimeoutTask: false
                )
            }
            state.setTimeoutTask(timeoutTask)
        }
    } onCancel: {
        state.cancelAll()
    }
}

private func timeoutNanoseconds(_ seconds: TimeInterval) -> UInt64 {
    let boundedSeconds = max(0.001, min(seconds, TimeInterval(UInt64.max) / 1_000_000_000))
    return UInt64((boundedSeconds * 1_000_000_000).rounded(.up))
}

private func screenCaptureKitTimeoutMessage(
    operation: String,
    selector: ApplicationSelector,
    timeout: TimeInterval
) -> String {
    let commandArgument = shellQuoted(selector.commandArgument)
    return "ScreenCaptureKit did not \(operation) within \(formatSeconds(timeout)) for `\(selector.label)`. Try `brrainztools --app \(commandArgument) --list-visible-windows` or `brrainztools --app \(commandArgument) --visible-window --output FILE` for visible-pixel capture. If ScreenCaptureKit is only slow, retry with `--timeout SECONDS`."
}

private func formatSeconds(_ seconds: TimeInterval) -> String {
    if seconds < 0.1 {
        return String(format: "%.3fs", seconds)
    }

    let rounded = (seconds * 10).rounded() / 10
    if rounded.rounded() == rounded {
        return "\(Int(rounded))s"
    }

    return "\(rounded)s"
}

private func shellQuoted(_ value: String) -> String {
    let safeCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./:-")
    if value.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
        return value
    }

    return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func loadShareableContent(
    timeout: TimeInterval,
    selector: ApplicationSelector
) async throws -> SCShareableContent {
    try ensureScreenCaptureAccess()
    return try await withTimeout(
        seconds: timeout,
        timeoutMessage: {
            screenCaptureKitTimeoutMessage(
                operation: "return shareable app/window content",
                selector: selector,
                timeout: timeout
            )
        },
        operation: {
            try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        }
    )
}

private func loadDisplayShareableContent(timeout: TimeInterval) async throws -> SCShareableContent {
    return try await withTimeout(
        seconds: timeout,
        timeoutMessage: {
            "ScreenCaptureKit did not return display content within \(formatSeconds(timeout)). If ScreenCaptureKit is only slow, retry with `--timeout SECONDS`."
        },
        operation: {
            try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        }
    )
}

private func buildWindowCatalog(selector: ApplicationSelector, in shareableContent: SCShareableContent) throws -> AppWindowCatalog {
    let application = try resolveShareableApplication(selector: selector, in: shareableContent.applications)
    let eligibleWindows = shareableContent.windows.filter {
        $0.owningApplication?.processID == application.processID &&
        !$0.frame.isEmpty &&
        ($0.isOnScreen || $0.isActive)
    }

    guard !eligibleWindows.isEmpty else {
        throw BrrainzToolsError.windowNotFound(
            windowlessApplicationMessage(
                name: application.applicationName,
                bundleIdentifier: application.bundleIdentifier,
                processID: application.processID,
                windowKind: "capturable app",
                modeDescription: "`--app` window listing and app/window capture only target app windows."
            )
        )
    }

    let windowsByID = Dictionary(uniqueKeysWithValues: eligibleWindows.map { ($0.windowID, $0) })
    let orderedSnapshots = currentWindowSnapshots().filter { $0.ownerPID == application.processID }

    var orderedWindows: [CatalogWindow] = []
    var seenWindowIDs: Set<CGWindowID> = []

    for snapshot in orderedSnapshots {
        guard let scWindow = windowsByID[snapshot.windowID] else {
            continue
        }

        let catalogWindow = CatalogWindow(
            index: orderedWindows.count,
            windowID: scWindow.windowID,
            title: normalizedTitle(scWindow.title) ?? normalizedTitle(snapshot.title),
            frame: scWindow.frame,
            layer: scWindow.windowLayer,
            isOnScreen: scWindow.isOnScreen,
            isActive: scWindow.isActive,
            scWindow: scWindow
        )

        orderedWindows.append(catalogWindow)
        seenWindowIDs.insert(scWindow.windowID)
    }

    let fallbackWindows = eligibleWindows
        .filter { !seenWindowIDs.contains($0.windowID) }
        .sorted {
            let leftTitle = normalizedTitle($0.title) ?? ""
            let rightTitle = normalizedTitle($1.title) ?? ""

            if leftTitle != rightTitle {
                return leftTitle.localizedCaseInsensitiveCompare(rightTitle) == .orderedAscending
            }

            return $0.windowID < $1.windowID
        }

    for scWindow in fallbackWindows {
        orderedWindows.append(
            CatalogWindow(
                index: orderedWindows.count,
                windowID: scWindow.windowID,
                title: normalizedTitle(scWindow.title),
                frame: scWindow.frame,
                layer: scWindow.windowLayer,
                isOnScreen: scWindow.isOnScreen,
                isActive: scWindow.isActive,
                scWindow: scWindow
            )
        )
    }

    return AppWindowCatalog(application: application, windows: orderedWindows)
}

private func currentWindowSnapshots() -> [WindowSnapshot] {
    let rawWindowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

    return rawWindowInfo.compactMap { entry -> WindowSnapshot? in
        guard
            let windowNumber = entry[kCGWindowNumber as String] as? NSNumber,
            let ownerPID = entry[kCGWindowOwnerPID as String] as? NSNumber,
            let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
            let layer = entry[kCGWindowLayer as String] as? NSNumber
        else {
            return nil
        }

        guard let bounds = CGRect(dictionaryRepresentation: boundsDictionary), !bounds.isEmpty else {
            return nil
        }

        let alpha = (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        guard alpha > 0 else {
            return nil
        }

        return WindowSnapshot(
            windowID: CGWindowID(truncating: windowNumber),
            ownerPID: pid_t(truncating: ownerPID),
            title: normalizedTitle(entry[kCGWindowName as String] as? String),
            bounds: bounds,
            layer: layer.intValue,
            alpha: alpha
        )
    }
}

private func resolveShareableApplication(selector: ApplicationSelector, in applications: [SCRunningApplication]) throws -> SCRunningApplication {
    let resolvedApplication = try resolveAutomationApplication(selector: selector)
    guard let application = applications.first(where: { $0.processID == resolvedApplication.processID }) else {
        throw BrrainzToolsError.applicationNotFound(
            "`\(resolvedApplication.name)` (pid \(resolvedApplication.processID)) is running but ScreenCaptureKit did not report it as shareable."
        )
    }

    return application
}

private func selectWindow(from catalog: AppWindowCatalog, using selection: WindowSelection) throws -> CatalogWindow {
    switch selection {
    case .frontmost:
        guard let window = catalog.windows.first else {
            throw BrrainzToolsError.windowNotFound("`\(catalog.application.applicationName)` has no capturable windows.")
        }
        return window
    case .index(let index):
        guard let window = catalog.windows.first(where: { $0.index == index }) else {
            throw BrrainzToolsError.windowNotFound("No window at index \(index) for `\(catalog.application.applicationName)`. Run `brrainztools --app \"\(catalog.application.applicationName)\" --list-windows` to inspect available windows.")
        }
        return window
    case .name(let query):
        let normalizedQuery = query.lowercased()
        let exactMatches = catalog.windows.filter { ($0.title ?? "").lowercased() == normalizedQuery }

        if exactMatches.count == 1, let match = exactMatches.first {
            return match
        }

        let partialMatches = catalog.windows.filter { ($0.title ?? "").lowercased().contains(normalizedQuery) }
        let matches = exactMatches.isEmpty ? partialMatches : exactMatches

        guard !matches.isEmpty else {
            throw BrrainzToolsError.windowNotFound("No window named `\(query)` was found for `\(catalog.application.applicationName)`. Run `brrainztools --app \"\(catalog.application.applicationName)\" --list-windows` to inspect available windows.")
        }

        guard matches.count == 1, let match = matches.first else {
            let suggestions = matches
                .prefix(5)
                .map { "[\($0.index)] \(displayTitle($0.title))" }
                .joined(separator: ", ")
            throw BrrainzToolsError.ambiguousWindow("More than one window matches `\(query)`: \(suggestions)")
        }

        return match
    }
}

private func captureWindow(
    _ window: CatalogWindow,
    crop: WindowCropRect?,
    outputURL: URL,
    timeout: TimeInterval,
    selector: ApplicationSelector,
    imageOutput: ImageOutputOptions
) async throws {
    let filter = SCContentFilter(desktopIndependentWindow: window.scWindow)
    let info = SCShareableContent.info(for: filter)
    let clearBackgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0)
    let configuration = SCStreamConfiguration()

    configuration.width = max(1, Int(ceil(info.contentRect.width * CGFloat(info.pointPixelScale))))
    configuration.height = max(1, Int(ceil(info.contentRect.height * CGFloat(info.pointPixelScale))))
    configuration.showsCursor = false
    configuration.scalesToFit = false
    configuration.backgroundColor = clearBackgroundColor
    configuration.ignoreShadowsSingleWindow = true
    configuration.ignoreGlobalClipSingleWindow = true

    let capturedImage = try await withTimeout(
        seconds: timeout,
        timeoutMessage: {
            screenCaptureKitTimeoutMessage(
                operation: "capture window [\(window.index)] \(displayTitle(window.title))",
                selector: selector,
                timeout: timeout
            )
        },
        operation: {
            try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        }
    )

    let finalImage: CGImage
    if let crop {
        try validate(windowCrop: crop, within: info.contentRect, windowTitle: displayTitle(window.title))
        finalImage = try cropWindowImage(capturedImage, using: crop, pointPixelScale: CGFloat(info.pointPixelScale))
    } else {
        finalImage = capturedImage
    }

    try writeImage(finalImage, to: outputURL, options: imageOutput)
}

private func captureDisplayRegion(
    region: CaptureRegion,
    outputURL: URL,
    timeout: TimeInterval,
    imageOutput: ImageOutputOptions
) async throws {
    try validate(region: region)
    let shareableContent = try await loadDisplayShareableContent(timeout: timeout)
    let regionRect = region.rect
    let plans = planDisplayRegionCaptures(displays: shareableContent.displays, regionRect: regionRect)

    guard !plans.isEmpty else {
        throw BrrainzToolsError.captureFailed("No display intersects the requested rectangle \(region.rectangleArgument).")
    }

    let canvasScale = max(1, plans.map(\.pointPixelScale).max() ?? 1)
    let canvasSize = CGSize(
        width: max(1, ceil(regionRect.width * canvasScale)),
        height: max(1, ceil(regionRect.height * canvasScale))
    )

    let context = try makeCaptureCanvas(size: canvasSize)

    for plan in plans {
        let filter = SCContentFilter(display: plan.display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(ceil(plan.intersectionRect.width * plan.pointPixelScale)))
        configuration.height = max(1, Int(ceil(plan.intersectionRect.height * plan.pointPixelScale)))
        configuration.sourceRect = CGRect(
            x: plan.intersectionRect.minX - plan.display.frame.minX,
            y: plan.intersectionRect.minY - plan.display.frame.minY,
            width: plan.intersectionRect.width,
            height: plan.intersectionRect.height
        )
        // The requested output size already matches sourceRect at the display's
        // pixel scale. On macOS 27, asking ScreenCaptureKit to scale this 1:1
        // capture mirrors window surfaces in place while leaving their screen
        // coordinates unchanged.
        configuration.scalesToFit = false
        configuration.showsCursor = false
        configuration.ignoreShadowsDisplay = true

        let image = try await withTimeout(
            seconds: timeout,
            timeoutMessage: {
                "ScreenCaptureKit did not capture display rectangle \(region.rectangleArgument) within \(formatSeconds(timeout)). If ScreenCaptureKit is only slow, retry with `--timeout SECONDS`."
            },
            operation: {
                try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            }
        )
        let destinationRect = CGRect(
            x: (plan.intersectionRect.minX - regionRect.minX) * canvasScale,
            y: (plan.intersectionRect.minY - regionRect.minY) * canvasScale,
            width: plan.intersectionRect.width * canvasScale,
            height: plan.intersectionRect.height * canvasScale
        )

        context.draw(image, in: destinationRect)
    }

    guard let image = context.makeImage() else {
        throw BrrainzToolsError.captureFailed("ScreenCaptureKit returned no image data for the display capture.")
    }

    try writeImage(image, to: outputURL, options: imageOutput)
}

private func captureApplicationRegion(
    application: SCRunningApplication,
    windows: [SCWindow],
    displays: [SCDisplay],
    region: CaptureRegion,
    outputURL: URL,
    timeout: TimeInterval,
    selector: ApplicationSelector,
    imageOutput: ImageOutputOptions
) async throws {
    let regionRect = region.rect
    let plans = planDisplayCaptures(
        displays: displays,
        windows: windows,
        regionRect: regionRect
    )

    guard !plans.isEmpty else {
        throw BrrainzToolsError.captureFailed("No visible content from `\(application.applicationName)` intersects the requested rectangle.")
    }

    let canvasScale = max(1, plans.map(\.pointPixelScale).max() ?? 1)
    let canvasSize = CGSize(
        width: max(1, ceil(regionRect.width * canvasScale)),
        height: max(1, ceil(regionRect.height * canvasScale))
    )

    let context = try makeCaptureCanvas(size: canvasSize)

    for plan in plans {
        let filter = SCContentFilter(display: plan.display, including: [application], exceptingWindows: [])
        let clearBackgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0)
        let configuration = SCStreamConfiguration()

        configuration.width = max(1, Int(ceil(plan.intersectionRect.width * plan.pointPixelScale)))
        configuration.height = max(1, Int(ceil(plan.intersectionRect.height * plan.pointPixelScale)))
        configuration.sourceRect = CGRect(
            x: plan.intersectionRect.minX - plan.display.frame.minX,
            y: plan.intersectionRect.minY - plan.display.frame.minY,
            width: plan.intersectionRect.width,
            height: plan.intersectionRect.height
        )
        // See captureDisplayRegion: this is already a 1:1 source-rect capture.
        configuration.scalesToFit = false
        configuration.showsCursor = false
        configuration.backgroundColor = clearBackgroundColor
        configuration.ignoreShadowsDisplay = true

        let image = try await withTimeout(
            seconds: timeout,
            timeoutMessage: {
                screenCaptureKitTimeoutMessage(
                    operation: "capture app-filtered rectangle \(region.rectangleArgument) for `\(application.applicationName)`",
                    selector: selector,
                    timeout: timeout
                )
            },
            operation: {
                try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            }
        )
        let destinationRect = CGRect(
            x: (plan.intersectionRect.minX - regionRect.minX) * canvasScale,
            y: (plan.intersectionRect.minY - regionRect.minY) * canvasScale,
            width: plan.intersectionRect.width * canvasScale,
            height: plan.intersectionRect.height * canvasScale
        )

        context.draw(image, in: destinationRect)
    }

    guard let image = context.makeImage() else {
        throw BrrainzToolsError.captureFailed("ScreenCaptureKit returned no image data for the filtered capture.")
    }

    try writeImage(image, to: outputURL, options: imageOutput)
}

func makeCaptureCanvas(size: CGSize) throws -> CGContext {
    // Keep the identity CTM. ScreenCaptureKit images already draw in encoded pixel
    // orientation; flipping this canvas rotates composited captures for raw decoders.
    guard
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else {
        throw BrrainzToolsError.captureFailed("Failed to allocate an image buffer for the capture.")
    }

    return context
}

private func planDisplayRegionCaptures(
    displays: [SCDisplay],
    regionRect: CGRect
) -> [DisplayCapturePlan] {
    displays.compactMap { display in
        let intersectionRect = display.frame.intersection(regionRect)
        guard !intersectionRect.isNull, !intersectionRect.isEmpty else {
            return nil
        }

        return DisplayCapturePlan(
            display: display,
            intersectionRect: intersectionRect,
            pointPixelScale: pointPixelScale(for: display)
        )
    }
}

private func planDisplayCaptures(
    displays: [SCDisplay],
    windows: [SCWindow],
    regionRect: CGRect
) -> [DisplayCapturePlan] {
    displays.compactMap { display in
        let intersectionRect = display.frame.intersection(regionRect)
        guard !intersectionRect.isNull, !intersectionRect.isEmpty else {
            return nil
        }

        let hasWindowContent = windows.contains { window in
            !window.frame.intersection(intersectionRect).isNull
        }

        guard hasWindowContent else {
            return nil
        }

        return DisplayCapturePlan(
            display: display,
            intersectionRect: intersectionRect,
            pointPixelScale: pointPixelScale(for: display)
        )
    }
}

private func pointPixelScale(for display: SCDisplay) -> CGFloat {
    guard
        display.width > 0,
        let mode = CGDisplayCopyDisplayMode(display.displayID)
    else {
        return 1
    }

    return max(1, CGFloat(mode.pixelWidth) / CGFloat(display.width))
}

private func ensureScreenCaptureAccess() throws {
    if CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() {
        return
    }

    throw BrrainzToolsError.capturePermissionDenied
}

private func ensureAccessibilityAccess(prompt: Bool) throws {
    let isTrusted: Bool
    if prompt {
        let promptKey = "AXTrustedCheckOptionPrompt"
        isTrusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    } else {
        isTrusted = AXIsProcessTrusted()
    }

    guard isTrusted else {
        throw BrrainzToolsError.accessibilityPermissionDenied
    }
}

private func validate(windowCrop: WindowCropRect, within contentRect: CGRect, windowTitle: String) throws {
    let cropRect = windowCrop.rect
    let windowRect = CGRect(origin: .zero, size: contentRect.size)

    guard cropRect.maxX <= windowRect.maxX, cropRect.maxY <= windowRect.maxY else {
        let windowWidth = Int(windowRect.width.rounded(.down))
        let windowHeight = Int(windowRect.height.rounded(.down))
        throw BrrainzToolsError.invalidArguments("`--window-crop` \(windowCrop.x),\(windowCrop.y),\(windowCrop.width),\(windowCrop.height) falls outside the selected window \(windowTitle) sized \(windowWidth)x\(windowHeight) points.")
    }
}

private func validate(windowPoint: WindowPoint, within windowFrame: CGRect, windowTitle: String, flag: String) throws {
    guard CGFloat(windowPoint.x) < windowFrame.width, CGFloat(windowPoint.y) < windowFrame.height else {
        let windowWidth = Int(windowFrame.width.rounded(.down))
        let windowHeight = Int(windowFrame.height.rounded(.down))
        throw BrrainzToolsError.invalidArguments("`\(flag)` \(windowPoint.x),\(windowPoint.y) falls outside the selected window \(windowTitle) sized \(windowWidth)x\(windowHeight) points.")
    }
}

private func cropWindowImage(_ image: CGImage, using crop: WindowCropRect, pointPixelScale: CGFloat) throws -> CGImage {
    let scale = max(1, pointPixelScale)
    let minX = max(0, Int(floor(CGFloat(crop.x) * scale)))
    let minY = max(0, Int(floor(CGFloat(crop.y) * scale)))
    let maxX = min(image.width, Int(ceil(CGFloat(crop.x + crop.width) * scale)))
    let maxY = min(image.height, Int(ceil(CGFloat(crop.y + crop.height) * scale)))
    let croppedWidth = maxX - minX
    let croppedHeight = maxY - minY

    guard croppedWidth > 0, croppedHeight > 0 else {
        throw BrrainzToolsError.captureFailed("`--window-crop` resolved to an empty image.")
    }

    let cropRect = CGRect(x: minX, y: minY, width: croppedWidth, height: croppedHeight)
    guard let croppedImage = image.cropping(to: cropRect) else {
        throw BrrainzToolsError.captureFailed("Failed to crop the selected window image.")
    }

    return croppedImage
}

private func writeImage(_ image: CGImage, to outputURL: URL, options: ImageOutputOptions) throws {
    let imageForEncoding = try preparedImageForEncoding(image, options: options)
    guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, options.format.typeIdentifier as CFString, 1, nil) else {
        throw BrrainzToolsError.encodeFailed("Failed to create a \(options.format.displayName) destination for \(outputURL.path).")
    }

    let properties: CFDictionary?
    switch options.format {
    case .png:
        properties = nil
    case .jpeg:
        properties = [
            kCGImageDestinationLossyCompressionQuality as String: options.jpegQuality,
        ] as CFDictionary
    }

    CGImageDestinationAddImage(destination, imageForEncoding, properties)

    guard CGImageDestinationFinalize(destination) else {
        throw BrrainzToolsError.encodeFailed("Failed to write \(options.format.displayName) data to \(outputURL.path).")
    }
}

private func preparedImageForEncoding(_ image: CGImage, options: ImageOutputOptions) throws -> CGImage {
    let targetSize = scaledImageSize(
        width: image.width,
        height: image.height,
        maxDimension: options.maxDimension
    )
    let needsResize = targetSize.width != image.width || targetSize.height != image.height
    let needsJPEGComposite = options.format == .jpeg

    guard needsResize || needsJPEGComposite else {
        return image
    }

    return try renderImageForEncoding(
        image,
        width: targetSize.width,
        height: targetSize.height,
        opaque: needsJPEGComposite
    )
}

private func scaledImageSize(width: Int, height: Int, maxDimension: Int?) -> (width: Int, height: Int) {
    guard let maxDimension else {
        return (width, height)
    }

    let largestDimension = max(width, height)
    guard largestDimension > maxDimension else {
        return (width, height)
    }

    let scale = Double(maxDimension) / Double(largestDimension)
    return (
        max(1, Int((Double(width) * scale).rounded())),
        max(1, Int((Double(height) * scale).rounded()))
    )
}

private func renderImageForEncoding(
    _ image: CGImage,
    width targetWidth: Int,
    height targetHeight: Int,
    opaque: Bool
) throws -> CGImage {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    let alphaInfo: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | alphaInfo.rawValue

    guard let context = CGContext(
        data: nil,
        width: targetWidth,
        height: targetHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        throw BrrainzToolsError.encodeFailed("Failed to create an image resize context.")
    }

    let targetRect = CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
    if opaque {
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(targetRect)
    }
    context.interpolationQuality = .medium
    context.draw(image, in: targetRect)

    guard let renderedImage = context.makeImage() else {
        throw BrrainzToolsError.encodeFailed("Failed to render the resized image.")
    }

    return renderedImage
}

private func normalizedTitle(_ title: String?) -> String? {
    guard let title else {
        return nil
    }

    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func displayTitle(_ title: String?) -> String {
    normalizedTitle(title) ?? "<untitled>"
}

private func writeStandardError(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}
