import OSLog

enum AppLogger {
    static let subsystem = "com.ufcswap.app"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let config = Logger(subsystem: subsystem, category: "config")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let hotkeys = Logger(subsystem: subsystem, category: "hotkeys")
    static let media = Logger(subsystem: subsystem, category: "media")
    static let browser = Logger(subsystem: subsystem, category: "browser")
    static let playback = Logger(subsystem: subsystem, category: "playback")

    static func startup(_ message: String) {
        print("[UFCSwap] \(message)")
        app.info("\(message, privacy: .public)")
    }
}
