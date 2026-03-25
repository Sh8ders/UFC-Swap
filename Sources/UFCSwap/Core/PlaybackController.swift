import Foundation

@MainActor
final class PlaybackController {
    private static let randomTimestampRange = 15...900

    private let appStateStore: AppStateStore
    private let configStore: ConfigStore
    private let permissionManager: PermissionManager
    private let browserController: BrowserController
    private let focusManager: FocusManager
    private let videoPicker: VideoPicker
    private let feedbackStore: ActionFeedbackStore

    private var isTransitioning = false

    init(
        appStateStore: AppStateStore,
        configStore: ConfigStore,
        permissionManager: PermissionManager,
        browserController: BrowserController,
        focusManager: FocusManager,
        videoPicker: VideoPicker,
        feedbackStore: ActionFeedbackStore
    ) {
        self.appStateStore = appStateStore
        self.configStore = configStore
        self.permissionManager = permissionManager
        self.browserController = browserController
        self.focusManager = focusManager
        self.videoPicker = videoPicker
        self.feedbackStore = feedbackStore
    }

    func togglePlayback() async {
        feedbackStore.post("toggle() is entered")
        if isTransitioning {
            feedbackStore.post("toggle ignored because a transition is already in progress", isError: true)
            AppLogger.playback.info("Ignoring toggle request because a playback transition is already in progress")
            return
        }

        isTransitioning = true
        defer { isTransitioning = false }

        let state = await appStateStore.snapshot()
        if let session = state.activeSession {
            await deactivate(session: session, config: state.config)
        } else {
            await activate()
        }
    }

    func activateIfNeeded() async {
        feedbackStore.post("toggleOn() is entered")
        if isTransitioning {
            feedbackStore.post("toggleOn ignored because a transition is already in progress", isError: true)
            AppLogger.playback.info("Ignoring activate request because a playback transition is already in progress")
            return
        }

        let state = await appStateStore.snapshot()
        guard state.activeSession == nil else {
            feedbackStore.post("toggleOn ignored because playback is already active", isError: true)
            AppLogger.playback.info("Activate request ignored because playback is already active")
            return
        }

        isTransitioning = true
        defer { isTransitioning = false }
        await activate()
    }

    func deactivateIfNeeded() async {
        feedbackStore.post("toggleOff() is entered")
        if isTransitioning {
            feedbackStore.post("toggleOff ignored because a transition is already in progress", isError: true)
            AppLogger.playback.info("Ignoring deactivate request because a playback transition is already in progress")
            return
        }

        let state = await appStateStore.snapshot()
        guard let session = state.activeSession else {
            feedbackStore.post("toggleOff ignored because playback is already inactive", isError: true)
            AppLogger.playback.info("Deactivate request ignored because playback is already inactive")
            return
        }

        isTransitioning = true
        defer { isTransitioning = false }
        await deactivate(session: session, config: state.config)
    }

    private func activate() async {
        var createdWindowID: Int?
        var previousBundleID: String?

        do {
            let config = configStore.currentConfig()
            guard permissionManager.accessibilityStatus() == .granted else {
                throw PlaybackControllerError.missingAccessibilityPermission
            }

            do {
                try browserController.validateManagedPlaybackEnvironment()
            } catch {
                feedbackStore.post("toggleOn dependency failed: Chrome installed", isError: true)
                throw error
            }

            guard !config.videos.isEmpty else {
                throw PlaybackControllerError.noVideosConfigured
            }

            feedbackStore.post("toggleOn step: save focused app")
            previousBundleID = focusManager.frontmostApplicationBundleID()
            AppLogger.startup("detected frontmost app: \(previousBundleID ?? "nil")")

            if let previousBundleID {
                feedbackStore.post("toggleOn step: hide frontmost app")
                AppLogger.startup("app hide attempt: \(previousBundleID)")
                let hidden = focusManager.hideApp(bundleID: previousBundleID)
                if hidden {
                    AppLogger.startup("app hide success: \(previousBundleID)")
                } else {
                    AppLogger.startup("app hide failure: \(previousBundleID)")
                    feedbackStore.post("Frontmost app could not be hidden; continuing anyway", isError: true)
                }
            } else {
                feedbackStore.post("No frontmost app detected to hide; continuing anyway", isError: true)
            }

            feedbackStore.post("toggleOn step: pick video")
            let (video, timestampSeconds, playbackURL, browserSession) = try await selectAndOpenPlaybackVideo(from: config.videos)
            createdWindowID = browserSession.windowID
            AppLogger.startup("Chrome open: windowID=\(browserSession.windowID) tabID=\(browserSession.tabID)")

            feedbackStore.post("toggleOn step: fullscreen video")
            AppLogger.startup("fullscreen attempt: windowID=\(browserSession.windowID) tabID=\(browserSession.tabID)")
            do {
                try browserController.fullscreenManagedPlayback(browserSession)
            } catch {
                feedbackStore.post("Fullscreen failed; continuing with playback window open", isError: true)
                AppLogger.playback.error("Fullscreen failed but playback will continue: \(error.localizedDescription, privacy: .public)")
            }

            let session = PlaybackSession(
                video: video,
                playbackURL: playbackURL,
                timestampSeconds: timestampSeconds,
                previousFrontmostBundleID: previousBundleID,
                browserWindowID: browserSession.windowID,
                browserTabID: browserSession.tabID,
                activatedAt: Date()
            )

            await appStateStore.activateSession(session)
            feedbackStore.post("toggleOn completed")
            AppLogger.playback.info("Toggle-on completed session=\(session.description, privacy: .public)")
        } catch {
            feedbackStore.post("toggleOn failed: \(error.localizedDescription)", isError: true)
            AppLogger.playback.error("Toggle-on failed: \(error.localizedDescription, privacy: .public)")

            if let windowID = createdWindowID {
                do {
                    let cleanupSession = BrowserSession(windowID: windowID, tabID: -1)
                    let closed = try browserController.closeManagedPlayback(cleanupSession)
                    AppLogger.playback.info("Cleanup close after failed toggle-on windowID=\(windowID) closed=\(closed)")
                } catch {
                    AppLogger.playback.error("Cleanup close after failed toggle-on failed: \(error.localizedDescription, privacy: .public)")
                }
            }

            if let previousBundleID {
                let restored = focusManager.bringAppToFront(bundleID: previousBundleID)
                AppLogger.playback.info("Cleanup restored focus bundleID=\(previousBundleID, privacy: .public) success=\(restored)")
            }

            await appStateStore.clearActiveSession()
        }
    }

    private func deactivate(session: PlaybackSession, config: AppConfig) async {
        feedbackStore.post("toggleOff entered")
        AppLogger.playback.info("Toggle-off starting session=\(session.description, privacy: .public)")

        do {
            let browserSession = BrowserSession(windowID: session.browserWindowID, tabID: session.browserTabID)
            let closed = try browserController.closeManagedPlayback(browserSession)
            AppLogger.playback.info("Closed managed playback windowID=\(session.browserWindowID) closed=\(closed)")
        } catch {
            AppLogger.playback.error("Closing managed playback window failed: \(error.localizedDescription, privacy: .public)")
        }

        if let previousBundleID = session.previousFrontmostBundleID {
            AppLogger.startup("restore previous app: \(previousBundleID)")
            let unhidden = focusManager.unhideApp(bundleID: previousBundleID)
            let restored = focusManager.bringAppToFront(bundleID: previousBundleID)
            AppLogger.playback.info("Restore previous app bundleID=\(previousBundleID, privacy: .public) unhideSuccess=\(unhidden) activateSuccess=\(restored)")
            AppLogger.playback.info("Restored previous frontmost app bundleID=\(previousBundleID, privacy: .public) success=\(restored)")
        } else {
            AppLogger.playback.info("Skipped focus restoration because no previous frontmost app was recorded")
        }

        await appStateStore.clearActiveSession()
        feedbackStore.post("toggleOff completed")
        AppLogger.playback.info("Toggle-off completed and active session state cleared")
    }

    private static func randomTimestamp() -> Int {
        Int.random(in: randomTimestampRange)
    }

    private func selectAndOpenPlaybackVideo(from videos: [FightVideo]) async throws -> (FightVideo, Int, URL, BrowserSession) {
        let candidates = videos.shuffled()

        for video in candidates {
            let timestampSeconds = Self.randomTimestamp()
            guard let playbackURL = AppConfigValidator.canonicalPlaybackURL(for: video.url, timestampSeconds: timestampSeconds) else {
                AppLogger.playback.error("Skipping invalid playback URL title=\(video.title, privacy: .public) rawURL=\(video.url.absoluteString, privacy: .public)")
                continue
            }

            await appStateStore.setCurrentVideo(video)
            AppLogger.startup("selected video title: \(video.title)")
            AppLogger.startup("selected raw URL: \(video.url.absoluteString)")
            AppLogger.startup("chosen timestamp: \(timestampSeconds)")
            AppLogger.startup("final YouTube URL: \(playbackURL.absoluteString)")
            AppLogger.playback.info("Prepared playback video=\(video.title, privacy: .public) rawURL=\(video.url.absoluteString, privacy: .public) timestampSeconds=\(timestampSeconds) url=\(playbackURL.absoluteString, privacy: .public)")

            feedbackStore.post("toggleOn step: open Chrome")
            do {
                let browserSession = try browserController.openManagedPlayback(playbackURL)
                return (video, timestampSeconds, playbackURL, browserSession)
            } catch {
                AppLogger.playback.error("Playback video failed title=\(video.title, privacy: .public) rawURL=\(video.url.absoluteString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                feedbackStore.post("Playback candidate failed: \(video.title). Trying another video.", isError: true)
            }
        }

        throw PlaybackControllerError.noPlayableVideosConfigured
    }
}

enum PlaybackControllerError: LocalizedError {
    case missingAccessibilityPermission
    case noVideosConfigured
    case noPlayableVideosConfigured

    var errorDescription: String? {
        switch self {
        case .missingAccessibilityPermission:
            return "Accessibility permission is not granted."
        case .noVideosConfigured:
            return "At least one UFC video must be configured."
        case .noPlayableVideosConfigured:
            return "None of the configured YouTube videos could be opened successfully."
        }
    }
}
