import AppKit
import Foundation

final class StatusItemController: NSObject {
    private let container: AppContainer
    private let showControlPanel: () -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init(container: AppContainer, showControlPanel: @escaping () -> Void) {
        self.container = container
        self.showControlPanel = showControlPanel
    }

    func install() {
        if let button = statusItem.button {
            button.title = "UFC"
            button.toolTip = "UFCSwap"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Controls", action: #selector(showControls), keyEquivalent: "s"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Toggle Playback", action: #selector(togglePlayback), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "Log State", action: #selector(logState), keyEquivalent: "l"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Open Config Folder", action: #selector(openConfigFolder), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Request Accessibility Permission", action: #selector(requestAccessibilityPermission), keyEquivalent: "p"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    @objc
    private func showControls() {
        showControlPanel()
    }

    @objc
    private func reloadConfig() {
        do {
            try container.configStore.reload()
            Task {
                let config = container.configStore.currentConfig()
                await container.appStateStore.updateConfig(config)
                AppLogger.app.info("Config reloaded from disk")
            }
        } catch {
            AppLogger.app.error("Config reload failed: \(error.localizedDescription)")
        }
    }

    @objc
    private func togglePlayback() {
        container.actionRouter.handle(.pickNextVideo)
    }

    @objc
    private func logState() {
        Task {
            let state = await container.appStateStore.snapshot()
            AppLogger.app.info("App state: \(String(describing: state), privacy: .public)")
        }
    }

    @objc
    private func openConfigFolder() {
        container.configStore.openConfigFolder()
    }

    @objc
    private func requestAccessibilityPermission() {
        container.permissionManager.requestAccessibilityPermission()
    }

    @objc
    private func quit() {
        NSApp.terminate(nil)
    }
}
