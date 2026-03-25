import AppKit
import Foundation

protocol FocusManager {
    func frontmostApplicationBundleID() -> String?
    func bringAppToFront(bundleID: String) -> Bool
    func hideApp(bundleID: String) -> Bool
    func unhideApp(bundleID: String) -> Bool
}

struct DefaultFocusManager: FocusManager {
    func frontmostApplicationBundleID() -> String? {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        AppLogger.playback.info("Detected frontmost application bundleID=\(bundleID ?? "nil", privacy: .public)")
        return bundleID
    }

    func bringAppToFront(bundleID: String) -> Bool {
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        let activated = app?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps]) ?? false
        AppLogger.playback.info("Focus restore request bundleID=\(bundleID, privacy: .public) success=\(activated)")
        return activated
    }

    func hideApp(bundleID: String) -> Bool {
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        let hidden = app?.hide() ?? false
        AppLogger.playback.info("Hide request bundleID=\(bundleID, privacy: .public) success=\(hidden)")
        return hidden
    }

    func unhideApp(bundleID: String) -> Bool {
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        app?.unhide()
        let activated = app?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps]) ?? false
        AppLogger.playback.info("Unhide request bundleID=\(bundleID, privacy: .public) success=\(activated)")
        return activated
    }
}
