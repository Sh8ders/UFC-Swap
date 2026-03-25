import Foundation

protocol VideoPicker {
    func pickNextVideo() async throws -> FightVideo
    func pickRandomVideo() async throws -> FightVideo
}

actor VideoCursor {
    private var index = 0

    func next(count: Int) -> Int {
        guard count > 0 else { return 0 }
        let current = index % count
        index += 1
        return current
    }
}

final class RoundRobinVideoPicker: VideoPicker {
    private let configStore: ConfigStore
    private let appStateStore: AppStateStore
    private let cursor = VideoCursor()

    init(configStore: ConfigStore, appStateStore: AppStateStore) {
        self.configStore = configStore
        self.appStateStore = appStateStore
    }

    func pickNextVideo() async throws -> FightVideo {
        let config = configStore.currentConfig()
        guard !config.videos.isEmpty else {
            throw VideoPickerError.noVideosConfigured
        }

        let nextIndex = await cursor.next(count: config.videos.count)
        let video = config.videos[nextIndex]
        await appStateStore.setCurrentVideo(video)
        return video
    }

    func pickRandomVideo() async throws -> FightVideo {
        let config = configStore.currentConfig()
        guard !config.videos.isEmpty else {
            throw VideoPickerError.noVideosConfigured
        }

        let index = Int.random(in: 0..<config.videos.count)
        let video = config.videos[index]
        await appStateStore.setCurrentVideo(video)
        AppLogger.playback.info("Randomly selected video index=\(index) title=\(video.title, privacy: .public)")
        return video
    }
}

enum VideoPickerError: LocalizedError {
    case noVideosConfigured

    var errorDescription: String? {
        switch self {
        case .noVideosConfigured:
            return "No videos are configured."
        }
    }
}
