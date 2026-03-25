import AppKit
import ApplicationServices
import Carbon
import CoreServices
import Foundation

protocol PermissionManager {
    func accessibilityStatus() -> AccessibilityPermissionStatus
    func requestAccessibilityPermission()
    func openAccessibilitySettings()
    func automationStatus(for bundleID: String) async -> AutomationPermissionStatus
    func requestAutomationPermission(for bundleID: String) async -> AutomationPermissionStatus
    func openAutomationSettings()
}

enum AccessibilityPermissionStatus: String, Sendable {
    case granted
    case denied
}

enum AutomationPermissionStatus: String, Sendable {
    case granted
    case notDetermined
    case denied
    case targetNotRunning
    case targetMissing
    case unknown

    var displayText: String {
        switch self {
        case .granted:
            return "Granted"
        case .notDetermined:
            return "Not Requested"
        case .denied:
            return "Denied"
        case .targetNotRunning:
            return "Chrome Not Running"
        case .targetMissing:
            return "Chrome Missing"
        case .unknown:
            return "Unknown"
        }
    }
}

struct DefaultPermissionManager: PermissionManager {
    func accessibilityStatus() -> AccessibilityPermissionStatus {
        AXIsProcessTrusted() ? .granted : .denied
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        let status: AccessibilityPermissionStatus = granted ? .granted : .denied
        AppLogger.permissions.info("Accessibility permission status: \(status.rawValue, privacy: .public)")
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func automationStatus(for bundleID: String) async -> AutomationPermissionStatus {
        await determineAutomationPermission(for: bundleID, askUserIfNeeded: false)
    }

    func requestAutomationPermission(for bundleID: String) async -> AutomationPermissionStatus {
        await determineAutomationPermission(for: bundleID, askUserIfNeeded: true)
    }

    func openAutomationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func determineAutomationPermission(for bundleID: String, askUserIfNeeded: Bool) async -> AutomationPermissionStatus {
        let task = Task.detached(priority: .userInitiated) {
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else {
                return AutomationPermissionStatus.targetMissing
            }

            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
                return AutomationPermissionStatus.targetNotRunning
            }

            let descriptor = NSAppleEventDescriptor(bundleIdentifier: bundleID)
            guard let targetDescriptor = descriptor.aeDesc else {
                return AutomationPermissionStatus.unknown
            }

            let status = AEDeterminePermissionToAutomateTarget(
                targetDescriptor,
                AEEventClass(typeWildCard),
                AEEventID(typeWildCard),
                askUserIfNeeded
            )

            switch status {
            case noErr:
                return .granted
            case OSStatus(errAEEventWouldRequireUserConsent):
                return .notDetermined
            case OSStatus(errAEEventNotPermitted):
                return .denied
            case OSStatus(procNotFound):
                return .targetNotRunning
            default:
                AppLogger.permissions.error("Automation permission check failed status=\(status)")
                return .unknown
            }
        }

        return await task.value
    }
}
