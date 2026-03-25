import AppKit
import Foundation

protocol VolumeController {
    func validateEnvironment() throws
    func currentVolume(for bundleID: String) throws -> Double
    func setVolume(_ volume: Double, for bundleID: String) throws
    func mute(bundleID: String) throws
}

struct BackgroundMusicVolumeController: VolumeController {
    private static let appName = "Background Music"
    private static let expectedScriptingTerms = ["audio application", "bundleID", "vol"]

    func validateEnvironment() throws {
        _ = try resolveInstallation()
    }

    func currentVolume(for bundleID: String) throws -> Double {
        let installation = try resolveInstallation()
        let result = try runAppleScript(
            """
            tell application "\(escapeAppleScriptString(installation.applicationName))"
                set targetApp to first audio application whose bundleID is "\(escapeAppleScriptString(bundleID))"
                return vol of targetApp
            end tell
            """,
            installation: installation
        )

        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let volume = Double(trimmed) else {
            throw VolumeControllerError.invalidVolumeResponse(trimmed)
        }

        AppLogger.media.info("Read Background Music volume bundleID=\(bundleID, privacy: .public) volume=\(volume)")
        return volume
    }

    func setVolume(_ volume: Double, for bundleID: String) throws {
        let installation = try resolveInstallation()
        let normalizedVolume = Self.normalize(volume)

        _ = try runAppleScript(
            """
            tell application "\(escapeAppleScriptString(installation.applicationName))"
                set targetApp to first audio application whose bundleID is "\(escapeAppleScriptString(bundleID))"
                set vol of targetApp to \(Self.appleScriptNumber(normalizedVolume))
            end tell
            """,
            installation: installation
        )

        AppLogger.media.info("Set Background Music volume bundleID=\(bundleID, privacy: .public) volume=\(normalizedVolume)")
    }

    func mute(bundleID: String) throws {
        try setVolume(0, for: bundleID)
        AppLogger.media.info("Muted Background Music app volume bundleID=\(bundleID, privacy: .public)")
    }

    private func resolveInstallation() throws -> BackgroundMusicInstallation {
        guard let appURL = findApplicationURL() else {
            throw VolumeControllerError.backgroundMusicNotInstalled
        }

        let bundle = Bundle(url: appURL)
        let bundleID = bundle?.bundleIdentifier
        let appName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String ?? Self.appName

        guard isRunning(bundleID: bundleID, appName: appName) else {
            throw VolumeControllerError.backgroundMusicNotRunning
        }

        let scriptingDefinition = try loadScriptingDefinition(from: appURL)
        let missingTerms = Self.expectedScriptingTerms.filter { !scriptingDefinition.contains($0) }
        guard missingTerms.isEmpty else {
            throw VolumeControllerError.appleScriptIntegrationUnavailable(missingTerms)
        }

        return BackgroundMusicInstallation(applicationURL: appURL, applicationName: appName, bundleID: bundleID)
    }

    private func findApplicationURL() -> URL? {
        let fallbackPaths = [
            "/Applications/Background Music.app",
            ("~/Applications/Background Music.app" as NSString).expandingTildeInPath
        ]

        let fileManager = FileManager.default
        return fallbackPaths
            .map(URL.init(fileURLWithPath:))
            .first { fileManager.fileExists(atPath: $0.path) }
    }

    private func isRunning(bundleID: String?, appName: String) -> Bool {
        if let bundleID, !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            return true
        }

        return NSWorkspace.shared.runningApplications.contains { $0.localizedName == appName }
    }

    private func loadScriptingDefinition(from appURL: URL) throws -> String {
        let bundledSdefURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("BGMApp.sdef")

        if let data = try? Data(contentsOf: bundledSdefURL),
           let text = String(data: data, encoding: .utf8) {
            return text
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sdef")
        process.arguments = [appURL.path]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw VolumeControllerError.appleScriptProbeFailed(error.localizedDescription)
        }

        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)

        guard process.terminationStatus == 0 else {
            throw VolumeControllerError.appleScriptProbeFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return output
    }

    private func runAppleScript(_ script: String, installation: BackgroundMusicInstallation) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw VolumeControllerError.appleScriptExecutionFailed(error.localizedDescription)
        }

        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)

        if process.terminationStatus == 0 {
            return output
        }

        if output.localizedCaseInsensitiveContains("Can't get audio application") ||
            output.localizedCaseInsensitiveContains("Invalid index") {
            throw VolumeControllerError.targetApplicationNotFound(bundleIDHintFrom(script))
        }

        throw VolumeControllerError.appleScriptExecutionFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func escapeAppleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func bundleIDHintFrom(_ script: String) -> String {
        guard let start = script.range(of: "whose bundleID is \"")?.upperBound,
              let end = script[start...].firstIndex(of: "\"") else {
            return "unknown"
        }

        return String(script[start..<end])
    }

    private static func normalize(_ volume: Double) -> Double {
        min(100, max(0, volume))
    }

    private static func appleScriptNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }

        return String(format: "%.4f", value)
    }
}

private struct BackgroundMusicInstallation {
    let applicationURL: URL
    let applicationName: String
    let bundleID: String?
}

enum VolumeControllerError: LocalizedError {
    case backgroundMusicNotInstalled
    case backgroundMusicNotRunning
    case appleScriptIntegrationUnavailable([String])
    case appleScriptProbeFailed(String)
    case appleScriptExecutionFailed(String)
    case targetApplicationNotFound(String)
    case invalidVolumeResponse(String)

    var errorDescription: String? {
        switch self {
        case .backgroundMusicNotInstalled:
            return "Background Music is not installed. Install Background Music.app before using per-app volume control."
        case .backgroundMusicNotRunning:
            return "Background Music is installed but not running. Launch Background Music.app and make sure it is active before using UFCSwap."
        case .appleScriptIntegrationUnavailable(let missingTerms):
            return "Background Music is installed, but its AppleScript integration is missing required terms: \(missingTerms.joined(separator: ", "))."
        case .appleScriptProbeFailed(let output):
            return "Could not inspect Background Music's AppleScript dictionary: \(output)"
        case .appleScriptExecutionFailed(let output):
            return "Background Music AppleScript command failed: \(output)"
        case .targetApplicationNotFound(let bundleID):
            return "Background Music could not find the target app '\(bundleID)' for per-app volume control."
        case .invalidVolumeResponse(let output):
            return "Background Music returned an unexpected volume value: \(output)"
        }
    }
}
