import Foundation

struct ConfigSanitizationResult {
    let config: AppConfig
    let warnings: [String]
}

enum AppConfigDefaultsFactory {
    static var sampleVideos: [FightVideo] {
        [
            FightVideo(
                id: UUID(uuidString: "34B27580-2C2C-48B3-85D5-B85F2778AC4A") ?? UUID(),
                title: "Fights Your OLD MAN Told You About",
                fighterA: "Classic UFC",
                fighterB: "Marathon",
                eventName: "Throwback Marathon",
                year: 2025,
                url: URL(string: "https://www.youtube.com/watch?v=R4slhs8PA9w")!,
                tags: ["ufc", "marathon", "throwback"]
            ),
            FightVideo(
                id: UUID(uuidString: "60F41507-C5AF-4E41-A8AA-459F0358A42E") ?? UUID(),
                title: "UFC 325: Free Fight Marathon",
                fighterA: "Volkanovski",
                fighterB: "Lopes 2",
                eventName: "UFC 325",
                year: 2026,
                url: URL(string: "https://www.youtube.com/watch?v=PqTBCISwu7k")!,
                tags: ["ufc325", "marathon", "full-fight"]
            ),
            FightVideo(
                id: UUID(uuidString: "3F164208-10C6-4997-B54F-C4450D87473F") ?? UUID(),
                title: "UFC 323: Free Fight Marathon",
                fighterA: "Dvalishvili",
                fighterB: "Yan 2",
                eventName: "UFC 323",
                year: 2025,
                url: URL(string: "https://www.youtube.com/watch?v=m8pvYuhGwtU")!,
                tags: ["ufc323", "marathon", "full-fight"]
            ),
            FightVideo(
                id: UUID(uuidString: "7EF4730B-B34E-4976-B570-654175CCFB4B") ?? UUID(),
                title: "UFC 320: Free Fight Marathon",
                fighterA: "Ankalaev",
                fighterB: "Pereira 2",
                eventName: "UFC 320",
                year: 2025,
                url: URL(string: "https://www.youtube.com/watch?v=QB5KLSaxH2U")!,
                tags: ["ufc320", "marathon", "full-fight"]
            ),
            FightVideo(
                id: UUID(uuidString: "FFB27649-5A53-43A7-80B6-3EC2B30A0229") ?? UUID(),
                title: "UFC 326: Free Fight Marathon",
                fighterA: "Holloway",
                fighterB: "Oliveira 2",
                eventName: "UFC 326",
                year: 2026,
                url: URL(string: "https://www.youtube.com/live/0W6WbF2qio4")!,
                tags: ["ufc326", "marathon", "full-fight"]
            )
        ]
    }
}

enum AppConfigValidator {
    private static let knownBrokenVideoIDs: Set<String> = [
        "jjLwL8VYqZg",
        "YbJkN5Z5F0s",
        "sC6eC7SgW-I"
    ]

    static func sanitize(_ config: AppConfig) -> ConfigSanitizationResult {
        var warnings: [String] = []
        var sanitized = config

        let normalizedHotkey = normalizeToggleHotkey(config.settings.hotkeys)
        sanitized.settings.hotkeys = [normalizedHotkey]

        if normalizedHotkey.key != toggleHotkey(from: config.settings.hotkeys).key || !toggleHotkey(from: config.settings.hotkeys).modifiers.isEmpty {
            warnings.append("Hotkey was reset to \(normalizedHotkey.key). Only single function keys F13-F19 are supported.")
        }

        let validVideos = sanitized.videos.filter { validateVideo($0) == nil }
        let invalidVideos = sanitized.videos.compactMap(validateVideo)
        if !invalidVideos.isEmpty {
            warnings.append(invalidVideos.joined(separator: " "))
        }

        if validVideos.isEmpty {
            sanitized.videos = AppConfigDefaultsFactory.sampleVideos
            warnings.append("Configured videos were unavailable or invalid. Restored validated sample UFC videos.")
        } else {
            sanitized.videos = validVideos
        }

        return ConfigSanitizationResult(config: sanitized, warnings: warnings)
    }

    static func validateForSave(_ config: AppConfig) throws {
        let hotkey = normalizeToggleHotkey(config.settings.hotkeys)
        guard AppConfigDefaults.supportedFunctionKeys.contains(hotkey.key.uppercased()) else {
            throw ConfigValidationError.invalidHotkey(hotkey.key)
        }

        guard !config.videos.isEmpty else {
            throw ConfigValidationError.noVideosConfigured
        }

        for video in config.videos {
            if let issue = validateVideo(video) {
                throw ConfigValidationError.invalidVideo(issue)
            }
        }
    }

    static func normalizeToggleHotkey(_ hotkeys: [HotkeyDefinition]) -> HotkeyDefinition {
        var toggle = toggleHotkey(from: hotkeys)
        let uppercasedKey = toggle.key.uppercased()
        if !AppConfigDefaults.supportedFunctionKeys.contains(uppercasedKey) {
            toggle = .defaultToggle
        } else {
            toggle.key = uppercasedKey
            toggle.modifiers = []
            toggle.action = .pickNextVideo
        }
        return toggle
    }

    static func toggleHotkey(from hotkeys: [HotkeyDefinition]) -> HotkeyDefinition {
        hotkeys.first(where: { $0.action == .pickNextVideo }) ?? .defaultToggle
    }

    static func validateVideo(_ video: FightVideo) -> String? {
        guard let videoID = extractYouTubeVideoID(from: video.url) else {
            return "Invalid YouTube URL for '\(video.title)'."
        }

        if knownBrokenVideoIDs.contains(videoID) {
            return "Known broken YouTube URL for '\(video.title)'."
        }

        guard canonicalPlaybackURL(for: video.url, timestampSeconds: 30) != nil else {
            return "Could not build a playback URL for '\(video.title)'."
        }

        return nil
    }

    static func canonicalPlaybackURL(for url: URL, timestampSeconds: Int) -> URL? {
        guard let videoID = extractYouTubeVideoID(from: url) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/watch"
        components.queryItems = [
            URLQueryItem(name: "v", value: videoID),
            URLQueryItem(name: "t", value: "\(timestampSeconds)s")
        ]
        return components.url
    }

    static func extractYouTubeVideoID(from url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }

        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            let trimmed = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return trimmed.isEmpty ? nil : trimmed
        }

        guard host.contains("youtube.com") else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        if components.path == "/watch" {
            return components.queryItems?.first(where: { $0.name == "v" })?.value
        }

        if components.path.hasPrefix("/live/") || components.path.hasPrefix("/shorts/") {
            let trimmed = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return trimmed.split(separator: "/").last.map(String.init)
        }

        return nil
    }
}

enum ConfigValidationError: LocalizedError {
    case invalidHotkey(String)
    case noVideosConfigured
    case invalidVideo(String)

    var errorDescription: String? {
        switch self {
        case .invalidHotkey(let key):
            return "Unsupported hotkey '\(key)'. Use one function key from F13-F19."
        case .noVideosConfigured:
            return "At least one valid YouTube video is required."
        case .invalidVideo(let message):
            return message
        }
    }
}
