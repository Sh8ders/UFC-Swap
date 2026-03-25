import Foundation

final class AppActionRouter {
    private let appStateStore: AppStateStore
    private let configStore: ConfigStore
    private let volumeController: VolumeController
    private let browserController: BrowserController
    private let playbackController: PlaybackController
    private let focusManager: FocusManager
    private let feedbackStore: ActionFeedbackStore

    init(
        appStateStore: AppStateStore,
        configStore: ConfigStore,
        volumeController: VolumeController,
        browserController: BrowserController,
        playbackController: PlaybackController,
        focusManager: FocusManager,
        feedbackStore: ActionFeedbackStore
    ) {
        self.appStateStore = appStateStore
        self.configStore = configStore
        self.volumeController = volumeController
        self.browserController = browserController
        self.playbackController = playbackController
        self.focusManager = focusManager
        self.feedbackStore = feedbackStore
    }

    func handle(_ action: HotkeyAction) {
        Task { @MainActor in
            feedbackStore.post("action router received: \(action.rawValue)")
        }
        AppLogger.hotkeys.info("Routing action=\(action.rawValue, privacy: .public)")

        switch action {
        case .pickNextVideo:
            Task { @MainActor in
                await playbackController.togglePlayback()
            }
        case .lowerVolume:
            Task { @MainActor in
                feedbackStore.post("Per-app volume control is disabled for core playback", isError: true)
            }
        case .restoreVolume:
            Task { @MainActor in
                feedbackStore.post("Per-app volume control is disabled for core playback", isError: true)
            }
        case .focusBrowser:
            Task {
                let state = await appStateStore.snapshot()
                if let session = state.activeSession {
                    do {
                        let browserSession = BrowserSession(windowID: session.browserWindowID, tabID: session.browserTabID)
                        let focused = try browserController.focusManagedPlayback(browserSession)
                        AppLogger.browser.info("Focused active managed playback windowID=\(session.browserWindowID) success=\(focused)")
                    } catch {
                        AppLogger.browser.error("Managed playback focus failed: \(error.localizedDescription)")
                    }
                    return
                }

                let bundleID = configStore.currentConfig().settings.preferredBrowserBundleID
                let focused = browserController.focusBrowser(bundleID: bundleID)
                AppLogger.browser.info("Focused configured browser bundleID=\(bundleID ?? "nil", privacy: .public) success=\(focused)")
            }
        }
    }

    func testTurnOn() {
        Task { @MainActor in
            feedbackStore.post("Test On button is pressed")
        }
        Task { @MainActor in
            await playbackController.activateIfNeeded()
        }
    }

    func testTurnOff() {
        Task { @MainActor in
            feedbackStore.post("Test Off button is pressed")
        }
        Task { @MainActor in
            await playbackController.deactivateIfNeeded()
        }
    }
}
