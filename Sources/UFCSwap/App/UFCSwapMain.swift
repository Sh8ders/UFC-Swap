import AppKit

@main
enum UFCSwapMain {
    private static let retainedDelegate = AppDelegate()

    static func main() {
        AppLogger.startup("app entry reached")
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        application.delegate = retainedDelegate
        AppLogger.startup("starting NSApplication run loop")
        application.run()
        AppLogger.startup("NSApplication run loop exited")
    }
}
