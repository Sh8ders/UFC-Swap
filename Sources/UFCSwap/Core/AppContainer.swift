import Foundation

struct AppContainer {
    let appStateStore: AppStateStore
    let configStore: ConfigStore
    let permissionManager: PermissionManager
    let hotkeyManager: HotkeyManager
    let volumeController: VolumeController
    let browserController: BrowserController
    let focusManager: FocusManager
    let videoPicker: VideoPicker
    let actionRouter: AppActionRouter
    let feedbackStore: ActionFeedbackStore

    @MainActor
    static func bootstrap() throws -> AppContainer {
        AppLogger.startup("bootstrap started")
        let configStore = try DefaultConfigStore()
        AppLogger.startup("config store created")
        let config = try configStore.load()
        AppLogger.startup("config loaded")
        let appStateStore = AppStateStore(initialState: AppRuntimeState(config: config))
        let permissionManager = DefaultPermissionManager()
        let focusManager = DefaultFocusManager()
        let volumeController = BackgroundMusicVolumeController()
        let browserController = WorkspaceBrowserController(focusManager: focusManager)
        let hotkeyManager = GlobalHotkeyManager()
        let videoPicker = RoundRobinVideoPicker(configStore: configStore, appStateStore: appStateStore)
        let feedbackStore = ActionFeedbackStore()
        AppLogger.startup("core managers created")
        let playbackController = PlaybackController(
            appStateStore: appStateStore,
            configStore: configStore,
            permissionManager: permissionManager,
            browserController: browserController,
            focusManager: focusManager,
            videoPicker: videoPicker,
            feedbackStore: feedbackStore
        )
        let actionRouter = AppActionRouter(
            appStateStore: appStateStore,
            configStore: configStore,
            volumeController: volumeController,
            browserController: browserController,
            playbackController: playbackController,
            focusManager: focusManager,
            feedbackStore: feedbackStore
        )
        AppLogger.startup("action router created")

        let container = AppContainer(
            appStateStore: appStateStore,
            configStore: configStore,
            permissionManager: permissionManager,
            hotkeyManager: hotkeyManager,
            volumeController: volumeController,
            browserController: browserController,
            focusManager: focusManager,
            videoPicker: videoPicker,
            actionRouter: actionRouter,
            feedbackStore: feedbackStore
        )

        AppLogger.startup("installing hotkeys")
        let registration = hotkeyManager.installHotkeys(from: config.settings.hotkeys) { action in
            Task { @MainActor in
                feedbackStore.post("hotkey is pressed: \(action.rawValue)")
            }
            actionRouter.handle(action)
        }
        applyHotkeyRegistrationFeedback(registration, feedbackStore: feedbackStore)
        applyConfigWarnings(configStore.startupWarnings(), feedbackStore: feedbackStore)
        AppLogger.startup("bootstrap finished")
        AppLogger.app.info("Bootstrapped with \(config.videos.count) configured videos")
        return container
    }

    @MainActor
    func applyConfig(_ config: AppConfig) throws {
        try configStore.save(config)
        let savedConfig = configStore.currentConfig()
        let registration = hotkeyManager.installHotkeys(from: savedConfig.settings.hotkeys) { action in
            Task { @MainActor in
                feedbackStore.post("hotkey is pressed: \(action.rawValue)")
            }
            actionRouter.handle(action)
        }
        Self.applyHotkeyRegistrationFeedback(registration, feedbackStore: feedbackStore)

        Task {
            await appStateStore.updateConfig(savedConfig)
        }

        AppLogger.app.info("Applied updated config videos=\(savedConfig.videos.count) hotkeys=\(savedConfig.settings.hotkeys.count)")
    }

    @MainActor
    private static func applyHotkeyRegistrationFeedback(_ result: HotkeyRegistrationResult, feedbackStore: ActionFeedbackStore) {
        if result.succeeded {
            feedbackStore.post(result.message)
        } else {
            feedbackStore.post(result.message, isError: true)
        }
    }

    @MainActor
    private static func applyConfigWarnings(_ warnings: [String], feedbackStore: ActionFeedbackStore) {
        guard !warnings.isEmpty else { return }
        let message = warnings.joined(separator: " ")
        AppLogger.startup("config validation warning: \(message)")
        feedbackStore.post(message, isError: true)
    }
}
