import AppKit
import Foundation

protocol ConfigStore {
    func load() throws -> AppConfig
    func reload() throws
    func currentConfig() -> AppConfig
    func save(_ config: AppConfig) throws
    func openConfigFolder()
    func startupWarnings() -> [String]
}

final class ConfigCache {
    private var config: AppConfig

    init(config: AppConfig) {
        self.config = config
    }

    func get() -> AppConfig {
        config
    }

    func set(_ config: AppConfig) {
        self.config = config
    }
}

final class DefaultConfigStore: ConfigStore {
    private let fileManager: FileManager
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let configFileURL: URL
    private let cache: ConfigCache
    private var warnings: [String] = []

    init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("UFCSwap", isDirectory: true)

        if !fileManager.fileExists(atPath: appSupportURL.path) {
            try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true, attributes: nil)
        }

        self.configFileURL = appSupportURL.appendingPathComponent("config.json")

        if !fileManager.fileExists(atPath: self.configFileURL.path) {
            let bundledURL =
                Bundle.module.url(forResource: "sample-config", withExtension: "json", subdirectory: "Config") ??
                Bundle.module.url(forResource: "sample-config", withExtension: "json")
            guard let bundledURL else {
                throw ConfigError.missingBundledConfig
            }
            try fileManager.copyItem(at: bundledURL, to: self.configFileURL)
            AppLogger.config.info("Seeded config at \(self.configFileURL.path, privacy: .public)")
        }

        let config = try DefaultConfigStore.readConfig(from: self.configFileURL, decoder: decoder)
        self.cache = ConfigCache(config: config)
    }

    func load() throws -> AppConfig {
        let config = try Self.readConfig(from: configFileURL, decoder: decoder)
        let sanitized = try sanitizeAndPersistIfNeeded(config)
        cache.set(sanitized.config)
        warnings = sanitized.warnings
        return sanitized.config
    }

    func reload() throws {
        let config = try Self.readConfig(from: configFileURL, decoder: decoder)
        let sanitized = try sanitizeAndPersistIfNeeded(config)
        cache.set(sanitized.config)
        warnings = sanitized.warnings
    }

    func currentConfig() -> AppConfig {
        cache.get()
    }

    func save(_ config: AppConfig) throws {
        do {
            try AppConfigValidator.validateForSave(config)
            let normalized = AppConfigValidator.sanitize(config).config
            let data = try encoder.encode(normalized)
            try data.write(to: configFileURL, options: .atomic)
            cache.set(normalized)
            warnings = []
            AppLogger.config.info("Saved config to \(self.configFileURL.path, privacy: .public)")
        } catch {
            throw ConfigError.saveFailed(error)
        }
    }

    func openConfigFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([configFileURL])
    }

    func startupWarnings() -> [String] {
        warnings
    }

    private static func readConfig(from url: URL, decoder: JSONDecoder) throws -> AppConfig {
        let data = try Data(contentsOf: url)
        do {
            return try decoder.decode(AppConfig.self, from: data)
        } catch {
            throw ConfigError.decodeFailed(error)
        }
    }

    private func sanitizeAndPersistIfNeeded(_ config: AppConfig) throws -> ConfigSanitizationResult {
        let sanitized = AppConfigValidator.sanitize(config)
        if sanitized.config != config {
            let data = try encoder.encode(sanitized.config)
            try data.write(to: configFileURL, options: .atomic)
            AppLogger.config.info("Sanitized config at \(self.configFileURL.path, privacy: .public)")
        }
        return sanitized
    }
}

enum ConfigError: LocalizedError {
    case missingBundledConfig
    case decodeFailed(Error)
    case saveFailed(Error)

    var errorDescription: String? {
        switch self {
        case .missingBundledConfig:
            return "Bundled sample config is missing."
        case .decodeFailed(let error):
            return "Config decode failed: \(error.localizedDescription)"
        case .saveFailed(let error):
            return "Config save failed: \(error.localizedDescription)"
        }
    }
}
