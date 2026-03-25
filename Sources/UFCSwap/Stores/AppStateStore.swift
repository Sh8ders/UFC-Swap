import Foundation

actor AppStateStore {
    private var state: AppRuntimeState

    init(initialState: AppRuntimeState) {
        self.state = initialState
    }

    func snapshot() -> AppRuntimeState {
        state
    }

    func updateConfig(_ config: AppConfig) {
        state.config = config
    }

    func setCurrentVideo(_ video: FightVideo?) {
        state.currentVideo = video
    }

    func setFrontmostBundleID(_ bundleID: String?) {
        state.frontmostBundleID = bundleID
    }

    func activateSession(_ session: PlaybackSession) {
        state.activeSession = session
        state.currentVideo = session.video
        state.frontmostBundleID = session.previousFrontmostBundleID
    }

    func clearActiveSession() {
        state.activeSession = nil
        state.currentVideo = nil
        state.frontmostBundleID = nil
    }
}
