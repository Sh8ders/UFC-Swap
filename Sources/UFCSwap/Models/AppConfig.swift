import Foundation

struct AppConfig: Codable, Sendable, Equatable {
    var settings: AppSettings
    var videos: [FightVideo]
}

struct AppSettings: Codable, Sendable, Equatable {
    var preferredBrowserBundleID: String?
    var targetAppBundleID: String?
    var playbackVolume: Double
    var volumeFadeDurationSeconds: Double
    var restoreVolumeAfterPlayback: Bool
    var preferredFocusBundleIDs: [String]
    var hotkeys: [HotkeyDefinition]

    init(
        preferredBrowserBundleID: String?,
        targetAppBundleID: String? = nil,
        playbackVolume: Double = 100,
        volumeFadeDurationSeconds: Double,
        restoreVolumeAfterPlayback: Bool,
        preferredFocusBundleIDs: [String],
        hotkeys: [HotkeyDefinition]
    ) {
        self.preferredBrowserBundleID = preferredBrowserBundleID
        self.targetAppBundleID = targetAppBundleID
        self.playbackVolume = playbackVolume
        self.volumeFadeDurationSeconds = volumeFadeDurationSeconds
        self.restoreVolumeAfterPlayback = restoreVolumeAfterPlayback
        self.preferredFocusBundleIDs = preferredFocusBundleIDs
        self.hotkeys = hotkeys
    }

    private enum CodingKeys: String, CodingKey {
        case preferredBrowserBundleID
        case targetAppBundleID
        case playbackVolume
        case volumeFadeDurationSeconds
        case restoreVolumeAfterPlayback
        case preferredFocusBundleIDs
        case hotkeys
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preferredBrowserBundleID = try container.decodeIfPresent(String.self, forKey: .preferredBrowserBundleID)
        targetAppBundleID = try container.decodeIfPresent(String.self, forKey: .targetAppBundleID)
        playbackVolume = try container.decodeIfPresent(Double.self, forKey: .playbackVolume) ?? 100
        volumeFadeDurationSeconds = try container.decode(Double.self, forKey: .volumeFadeDurationSeconds)
        restoreVolumeAfterPlayback = try container.decode(Bool.self, forKey: .restoreVolumeAfterPlayback)
        preferredFocusBundleIDs = try container.decode([String].self, forKey: .preferredFocusBundleIDs)
        hotkeys = try container.decodeIfPresent([HotkeyDefinition].self, forKey: .hotkeys) ?? [HotkeyDefinition.defaultToggle]
    }
}

struct FightVideo: Codable, Sendable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var fighterA: String
    var fighterB: String
    var eventName: String
    var year: Int
    var url: URL
    var tags: [String]
}

struct HotkeyDefinition: Codable, Sendable, Hashable, Equatable {
    var action: HotkeyAction
    var key: String
    var modifiers: [String]

    static let defaultToggle = HotkeyDefinition(
        action: .pickNextVideo,
        key: "F17",
        modifiers: []
    )
}

enum HotkeyAction: String, Codable, Sendable {
    case pickNextVideo
    case lowerVolume
    case restoreVolume
    case focusBrowser
}

enum AppConfigDefaults {
    static let supportedFunctionKeys = FunctionKeyMap.supportedNames
}
