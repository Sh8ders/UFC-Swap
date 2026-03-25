import AppKit
import Combine
import Foundation
import SwiftUI

struct AppOption: Identifiable, Hashable {
    let bundleID: String
    let name: String

    var id: String { bundleID }
}

@MainActor
final class ControlPanelViewModel: ObservableObject {
    @Published var config: AppConfig
    @Published var browsers: [AppOption] = []
    @Published var accessibilityStatus: AccessibilityPermissionStatus
    @Published var automationStatus: AutomationPermissionStatus = .notDetermined
    @Published var chromeInstalled = false
    @Published var videosValid = true
    @Published var statusMessage: String = ""
    @Published var statusIsError = false
    @Published var isCapturingHotkey = false

    private let container: AppContainer
    private var cancellables: Set<AnyCancellable> = []
    private var hotkeyCaptureMonitor: Any?

    init(container: AppContainer) {
        self.container = container
        self.config = container.configStore.currentConfig()
        self.accessibilityStatus = container.permissionManager.accessibilityStatus()
        self.statusMessage = container.feedbackStore.latestMessage
        self.statusIsError = container.feedbackStore.latestIsError
        refreshOptions()
        refreshSetupChecks()

        container.feedbackStore.$latestMessage
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                self?.statusMessage = message
            }
            .store(in: &cancellables)

        container.feedbackStore.$latestIsError
            .receive(on: RunLoop.main)
            .sink { [weak self] isError in
                self?.statusIsError = isError
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshSetupChecks()
            }
            .store(in: &cancellables)
    }

    var toggleHotkey: HotkeyDefinition {
        get {
            AppConfigValidator.toggleHotkey(from: config.settings.hotkeys)
        }
        set {
            if let index = config.settings.hotkeys.firstIndex(where: { $0.action == .pickNextVideo }) {
                config.settings.hotkeys[index] = newValue
            } else {
                config.settings.hotkeys.append(newValue)
            }
        }
    }

    var hotkeyKey: String {
        get { toggleHotkey.key }
        set {
            var definition = toggleHotkey
            definition.key = newValue.uppercased()
            definition.modifiers = []
            toggleHotkey = definition
        }
    }

    func refreshOptions() {
        let browserCandidates = [
            AppOption(bundleID: "com.google.Chrome", name: "Google Chrome"),
            AppOption(bundleID: "com.apple.Safari", name: "Safari"),
            AppOption(bundleID: "org.mozilla.firefox", name: "Firefox"),
            AppOption(bundleID: "company.thebrowser.Browser", name: "Arc")
        ]

        browsers = browserCandidates.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil
        }

        accessibilityStatus = container.permissionManager.accessibilityStatus()
        AppLogger.app.info("Refresh options accessibility=\(self.accessibilityStatus.rawValue, privacy: .public)")
    }

    func refreshSetupChecks() {
        refreshOptions()
        chromeInstalled = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") != nil
        videosValid = config.videos.allSatisfy { AppConfigValidator.validateVideo($0) == nil } && !config.videos.isEmpty
        AppLogger.app.info("Setup checks chromeInstalled=\(self.chromeInstalled) accessibility=\(self.accessibilityStatus.rawValue, privacy: .public) videosValid=\(self.videosValid)")

        Task { @MainActor in
            automationStatus = await container.permissionManager.automationStatus(for: "com.google.Chrome")
            AppLogger.app.info("Setup checks automation=\(self.automationStatus.rawValue, privacy: .public)")
        }
    }

    func enterHotkeyCaptureMode() {
        if isCapturingHotkey {
            return
        }

        AppLogger.startup("hotkey capture mode entered")
        container.feedbackStore.post("Press a function key to set the hotkey")
        isCapturingHotkey = true

        hotkeyCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleHotkeyCapture(event)
        }
    }

    func cancelHotkeyCaptureMode() {
        guard isCapturingHotkey else { return }
        AppLogger.hotkeys.info("Hotkey capture mode cancelled")
        teardownHotkeyCapture()
    }

    func save() {
        container.feedbackStore.post("Save button pressed")
        do {
            try container.applyConfig(config)
            config = container.configStore.currentConfig()
            refreshSetupChecks()
            container.feedbackStore.post("Config saved")
        } catch {
            container.feedbackStore.post(error.localizedDescription, isError: true)
        }
    }

    func reload() {
        container.feedbackStore.post("Reload button pressed")
        do {
            try container.configStore.reload()
            config = container.configStore.currentConfig()
            refreshSetupChecks()
            let warnings = container.configStore.startupWarnings()
            if let warning = warnings.last {
                container.feedbackStore.post(warning, isError: true)
            } else {
                container.feedbackStore.post("Config reloaded")
            }
        } catch {
            container.feedbackStore.post(error.localizedDescription, isError: true)
        }
    }

    func requestPermission() {
        container.feedbackStore.post("Request Permission button pressed")
        container.permissionManager.requestAccessibilityPermission()
        container.feedbackStore.post("Accessibility request opened. Enable UFCSwap in System Settings, then click Refresh.")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            refreshSetupChecks()
        }
    }

    func openAccessibilitySettings() {
        container.permissionManager.openAccessibilitySettings()
    }

    func requestAutomationPermission() {
        Task { @MainActor in
            if !chromeInstalled {
                container.feedbackStore.post("Google Chrome is required for automation checks.", isError: true)
                return
            }

            _ = launchChromeIfNeeded()
            try? await Task.sleep(for: .seconds(2))
            let updatedStatus = await container.permissionManager.requestAutomationPermission(for: "com.google.Chrome")
            automationStatus = updatedStatus
            container.feedbackStore.post("Automation permission status: \(updatedStatus.displayText)")
        }
    }

    func openAutomationSettings() {
        container.permissionManager.openAutomationSettings()
    }

    func openChromeDownloadPage() {
        guard let url = URL(string: "https://www.google.com/chrome/") else { return }
        NSWorkspace.shared.open(url)
    }

    func testOn() {
        container.feedbackStore.post("Test On button is pressed")
        container.actionRouter.testTurnOn()
    }

    func testOff() {
        container.feedbackStore.post("Test Off button is pressed")
        container.actionRouter.testTurnOff()
    }

    func addVideo() {
        if let sampleVideo = AppConfigDefaultsFactory.sampleVideos.first {
            var video = sampleVideo
            video.id = UUID()
            config.videos.append(video)
        }
    }

    func removeVideos(at offsets: IndexSet) {
        config.videos.remove(atOffsets: offsets)
    }

    func bindingForBrowserSelection() -> Binding<String> {
        Binding(
            get: { self.config.settings.preferredBrowserBundleID ?? "" },
            set: { self.config.settings.preferredBrowserBundleID = $0.isEmpty ? nil : $0 }
        )
    }

    deinit {
        if let hotkeyCaptureMonitor {
            NSEvent.removeMonitor(hotkeyCaptureMonitor)
        }
    }

    private func handleHotkeyCapture(_ event: NSEvent) -> NSEvent? {
        let description = FunctionKeyMap.name(for: event.keyCode) ?? event.charactersIgnoringModifiers ?? "unknown"
        AppLogger.startup("hotkey capture key detected: \(description)")

        guard FunctionKeyMap.isFunctionKeyEvent(event),
              let functionKey = FunctionKeyMap.name(for: event.keyCode) else {
            AppLogger.startup("hotkey capture rejected: \(description)")
            container.feedbackStore.post("Ignored key \(description). Press F1 through F19.", isError: true)
            return nil
        }

        AppLogger.startup("hotkey capture accepted: \(functionKey)")
        hotkeyKey = functionKey

        do {
            try container.applyConfig(config)
            config = container.configStore.currentConfig()
            container.feedbackStore.post("Hotkey set to \(functionKey)")
        } catch {
            container.feedbackStore.post(error.localizedDescription, isError: true)
        }

        teardownHotkeyCapture()
        return nil
    }

    private func teardownHotkeyCapture() {
        if let hotkeyCaptureMonitor {
            NSEvent.removeMonitor(hotkeyCaptureMonitor)
            self.hotkeyCaptureMonitor = nil
        }
        isCapturingHotkey = false
    }

    private func launchChromeIfNeeded() -> Bool {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").isEmpty {
            return true
        }

        guard let chromeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else {
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: chromeURL, configuration: configuration) { _, error in
            if let error {
                AppLogger.permissions.error("Failed to launch Chrome for automation setup: \(error.localizedDescription, privacy: .public)")
            }
        }
        return true
    }
}
