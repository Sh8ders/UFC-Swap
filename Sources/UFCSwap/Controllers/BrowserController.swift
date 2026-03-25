import AppKit
import Foundation

struct BrowserSession: Sendable {
    let windowID: Int
    let tabID: Int
}

protocol BrowserController {
    func validateManagedPlaybackEnvironment() throws
    func open(_ url: URL, preferredBrowserBundleID: String?) throws
    func openManagedPlayback(_ url: URL) throws -> BrowserSession
    func fullscreenManagedPlayback(_ session: BrowserSession) throws
    func closeManagedPlayback(_ session: BrowserSession) throws -> Bool
    func focusBrowser(bundleID: String?) -> Bool
    func focusManagedPlayback(_ session: BrowserSession) throws -> Bool
}

struct WorkspaceBrowserController: BrowserController {
    private static let chromeBundleID = "com.google.Chrome"
    private static let chromeAppName = "Google Chrome"
    private static let tabReadyRetryCount = 10
    private static let playabilityRetryCount = 12
    private static let fullscreenRetryCount = 6
    let focusManager: FocusManager

    func validateManagedPlaybackEnvironment() throws {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.chromeBundleID) != nil else {
            throw BrowserControllerError.chromeUnavailable
        }
    }

    func open(_ url: URL, preferredBrowserBundleID: String?) throws {
        if let bundleID = preferredBrowserBundleID,
           let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: applicationURL, configuration: configuration) { _, error in
                if let error {
                    AppLogger.browser.error("Preferred browser open failed: \(error.localizedDescription)")
                }
            }
            AppLogger.browser.info("Opened URL in preferred browser \(bundleID, privacy: .public)")
            return
        }

        NSWorkspace.shared.open(url)
        AppLogger.browser.info("Opened URL in default browser")
    }

    func openManagedPlayback(_ url: URL) throws -> BrowserSession {
        try validateManagedPlaybackEnvironment()
        let chromeWasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.chromeBundleID).isEmpty
        AppLogger.startup("Chrome already running: \(chromeWasRunning)")

        let script = """
        tell application "\(Self.chromeAppName)"
            activate
            set newWindow to make new window
            set URL of active tab of newWindow to "\(escapeAppleScriptString(url.absoluteString))"
            delay 0.2
            return "\(chromeWasRunning ? "running" : "launched")" & "|" & (id of newWindow as text) & "," & (id of active tab of newWindow as text)
        end tell
        """

        let output = try runAppleScript(script).trimmingCharacters(in: .whitespacesAndNewlines)
        let outputParts = output.split(separator: "|", maxSplits: 1).map(String.init)
        guard outputParts.count == 2 else {
            throw BrowserControllerError.invalidBrowserSession(output)
        }

        let creationMode = outputParts[0]
        let parts = outputParts[1].split(separator: ",", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let windowID = Int(parts[0]),
              let tabID = Int(parts[1]) else {
            throw BrowserControllerError.invalidBrowserSession(output)
        }

        let session = BrowserSession(windowID: windowID, tabID: tabID)
        do {
            try waitForManagedPlaybackTab(session, expectedURL: url)
            try waitForManagedPlaybackToBecomePlayable(session)
        } catch {
            _ = try? closeManagedPlayback(session)
            throw error
        }
        AppLogger.startup("Chrome creation mode: \(creationMode == "running" ? "new-window-while-running" : "launched-new-window")")
        AppLogger.startup("returned window/tab IDs: \(windowID)/\(tabID)")
        AppLogger.browser.info("Opened managed Chrome playback windowID=\(windowID) tabID=\(tabID) url=\(url.absoluteString, privacy: .public)")
        return session
    }

    func fullscreenManagedPlayback(_ session: BrowserSession) throws {
        _ = try focusManagedPlayback(session)

        for attempt in 1...Self.fullscreenRetryCount {
            do {
                let response = try prepareManagedPlaybackForFullscreen(session)
                AppLogger.browser.info("Prepared Chrome playback fullscreen attempt=\(attempt) windowID=\(session.windowID) tabID=\(session.tabID) response=\(response, privacy: .public)")
                if response == "sent-f" {
                    AppLogger.browser.info("Fullscreen command sent to managed Chrome playback windowID=\(session.windowID) tabID=\(session.tabID) attempt=\(attempt)")
                    return
                }
            } catch {
                AppLogger.browser.error("Managed Chrome fullscreen attempt=\(attempt) failed: \(error.localizedDescription)")
            }

            Thread.sleep(forTimeInterval: 0.5)
        }

        throw BrowserControllerError.fullscreenFailed(windowID: session.windowID, tabID: session.tabID)
    }

    func closeManagedPlayback(_ session: BrowserSession) throws -> Bool {
        let script = """
        tell application "\(Self.chromeAppName)"
            if (count of (every window whose id is \(session.windowID))) is 0 then
                return "missing"
            end if
            close (first window whose id is \(session.windowID))
            return "closed-window:" & "\(session.windowID)"
        end tell
        """

        let output = try runAppleScript(script).trimmingCharacters(in: .whitespacesAndNewlines)
        let closed = output.hasPrefix("closed-window:")
        AppLogger.browser.info("Close managed Chrome playback windowID=\(session.windowID) tabID=\(session.tabID) result=\(output, privacy: .public)")
        return closed
    }

    func focusBrowser(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return focusManager.bringAppToFront(bundleID: bundleID)
    }

    func focusManagedPlayback(_ session: BrowserSession) throws -> Bool {
        let script = """
        tell application "\(Self.chromeAppName)"
            if (count of (every window whose id is \(session.windowID))) is 0 then
                return "missing"
            end if
            set targetWindow to first window whose id is \(session.windowID)
            set index of targetWindow to 1
            activate
            return "focused:" & (id of targetWindow as text)
        end tell
        """

        let output = try runAppleScript(script).trimmingCharacters(in: .whitespacesAndNewlines)
        let focused = output.hasPrefix("focused:")
        AppLogger.browser.info("Focus managed Chrome playback windowID=\(session.windowID) tabID=\(session.tabID) result=\(output, privacy: .public)")
        return focused
    }

    private func waitForManagedPlaybackTab(_ session: BrowserSession, expectedURL: URL) throws {
        let normalizedExpectedURL = expectedURL.absoluteString

        for attempt in 1...Self.tabReadyRetryCount {
            let script = """
            tell application "\(Self.chromeAppName)"
                if (count of (every window whose id is \(session.windowID))) is 0 then
                    return "missing"
                end if
                set targetWindow to first window whose id is \(session.windowID)
                return (URL of active tab of targetWindow as text)
            end tell
            """

            let output = try runAppleScript(script).trimmingCharacters(in: .whitespacesAndNewlines)
            AppLogger.browser.info("Chrome playback tab readiness attempt=\(attempt) windowID=\(session.windowID) tabID=\(session.tabID) observedURL=\(output, privacy: .public)")

            if output == normalizedExpectedURL || output.hasPrefix("https://www.youtube.com") || output.hasPrefix("https://youtube.com") {
                return
            }

            Thread.sleep(forTimeInterval: 0.35)
        }

        throw BrowserControllerError.tabLoadTimedOut(windowID: session.windowID, tabID: session.tabID, expectedURL: normalizedExpectedURL)
    }

    private func prepareManagedPlaybackForFullscreen(_ session: BrowserSession) throws -> String {
        let script = """
        tell application "\(Self.chromeAppName)"
            if (count of (every window whose id is \(session.windowID))) is 0 then
                return "missing"
            end if
            set targetWindow to first window whose id is \(session.windowID)
            set index of targetWindow to 1
            activate
        end tell
        tell application "System Events"
            keystroke "f"
        end tell
        return "sent-f"
        """

        return try runAppleScript(script).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func waitForManagedPlaybackToBecomePlayable(_ session: BrowserSession) throws {
        for attempt in 1...Self.playabilityRetryCount {
            let script = """
            tell application "\(Self.chromeAppName)"
                if (count of (every window whose id is \(session.windowID))) is 0 then
                    return "missing"
                end if
                set targetWindow to first window whose id is \(session.windowID)
                set targetTab to active tab of targetWindow
                return (title of targetTab as text) & "|" & (URL of targetTab as text)
            end tell
            """

            let output = try runAppleScript(script).trimmingCharacters(in: .whitespacesAndNewlines)
            AppLogger.browser.info("Chrome playback playability attempt=\(attempt) windowID=\(session.windowID) tabID=\(session.tabID) result=\(output, privacy: .public)")

            let parts = output.split(separator: "|", maxSplits: 1).map(String.init)
            let title = parts.first ?? ""
            let observedURL = parts.count > 1 ? parts[1] : ""

            if title.localizedCaseInsensitiveContains("video unavailable")
                || title.localizedCaseInsensitiveContains("private video")
                || title.localizedCaseInsensitiveContains("sign in") {
                throw BrowserControllerError.videoUnavailable(windowID: session.windowID, tabID: session.tabID)
            }

            if !title.isEmpty,
               title != "YouTube",
               title != "about:blank",
               observedURL.contains("youtube.com/watch") {
                return
            }

            Thread.sleep(forTimeInterval: 0.5)
        }

        throw BrowserControllerError.videoUnavailable(windowID: session.windowID, tabID: session.tabID)
    }

    private func runAppleScript(_ script: String) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
        if process.terminationStatus == 0 {
            return output
        }
        throw BrowserControllerError.appleScriptFailed(output)
    }

    private func escapeAppleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

enum BrowserControllerError: LocalizedError {
    case chromeUnavailable
    case invalidBrowserSession(String)
    case appleScriptFailed(String)
    case tabLoadTimedOut(windowID: Int, tabID: Int, expectedURL: String)
    case fullscreenFailed(windowID: Int, tabID: Int)
    case videoUnavailable(windowID: Int, tabID: Int)

    var errorDescription: String? {
        switch self {
        case .chromeUnavailable:
            return "Google Chrome is not installed."
        case .invalidBrowserSession(let output):
            return "Could not parse Chrome session identifiers: \(output)"
        case .appleScriptFailed(let output):
            return "Browser AppleScript failed: \(output)"
        case .tabLoadTimedOut(let windowID, let tabID, let expectedURL):
            return "Google Chrome did not finish loading the managed tab windowID=\(windowID) tabID=\(tabID) expectedURL=\(expectedURL)."
        case .fullscreenFailed(let windowID, let tabID):
            return "Google Chrome could not fullscreen the managed YouTube tab windowID=\(windowID) tabID=\(tabID)."
        case .videoUnavailable(let windowID, let tabID):
            return "The selected YouTube video was unavailable in Google Chrome windowID=\(windowID) tabID=\(tabID)."
        }
    }
}
