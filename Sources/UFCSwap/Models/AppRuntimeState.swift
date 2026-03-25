import Foundation

struct PlaybackSession: Sendable, CustomStringConvertible {
    var video: FightVideo
    var playbackURL: URL
    var timestampSeconds: Int
    var previousFrontmostBundleID: String?
    var browserWindowID: Int
    var browserTabID: Int
    var activatedAt: Date

    var description: String {
        "video=\(video.title), timestampSeconds=\(timestampSeconds), previousFrontmostBundleID=\(previousFrontmostBundleID ?? "nil"), browserWindowID=\(browserWindowID), browserTabID=\(browserTabID)"
    }
}

struct AppRuntimeState: Sendable, CustomStringConvertible {
    var config: AppConfig
    var currentVideo: FightVideo?
    var frontmostBundleID: String?
    var activeSession: PlaybackSession?

    var description: String {
        "currentVideo=\(currentVideo?.title ?? "nil"), frontmostBundleID=\(frontmostBundleID ?? "nil"), isActive=\(activeSession != nil), activeSession=\(activeSession?.description ?? "nil"), configVideos=\(config.videos.count)"
    }
}
