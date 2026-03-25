import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var controlPanelWindowController: ControlPanelWindowController?
    private var container: AppContainer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.startup("applicationDidFinishLaunching reached")

        do {
            AppLogger.startup("calling bootstrap")
            let container = try AppContainer.bootstrap()
            AppLogger.startup("bootstrap returned")
            self.container = container

            AppLogger.startup("creating main window controller")
            let controlPanelWindowController = ControlPanelWindowController(container: container)
            self.controlPanelWindowController = controlPanelWindowController

            AppLogger.startup("creating status item controller")
            self.statusItemController = StatusItemController(
                container: container,
                showControlPanel: { [weak controlPanelWindowController] in
                    controlPanelWindowController?.showWindow(nil)
                }
            )
            AppLogger.startup("installing status item")
            self.statusItemController?.install()
            AppLogger.startup("showing main window")
            controlPanelWindowController.showWindow(nil)

            if ProcessInfo.processInfo.arguments.contains("--auto-test-on") {
                AppLogger.startup("running automated Test On action")
                controlPanelWindowController.runAutomatedTestOn()
            }

            if ProcessInfo.processInfo.arguments.contains("--auto-test-off") {
                AppLogger.startup("running automated Test Off action")
                controlPanelWindowController.runAutomatedTestOff()
            }

            if ProcessInfo.processInfo.arguments.contains("--auto-test-cycle") {
                AppLogger.startup("running automated Test On/Test Off cycle")
                controlPanelWindowController.runAutomatedTestCycle()
            }

            if ProcessInfo.processInfo.arguments.contains("--auto-capture-hotkey") {
                AppLogger.startup("running automated hotkey capture mode")
                controlPanelWindowController.runAutomatedHotkeyCapture()
            }

            AppLogger.startup("app did finish launching")
            AppLogger.app.info("UFCSwap launched successfully")
        } catch {
            AppLogger.startup("launch failed: \(error.localizedDescription)")
            AppLogger.app.error("Failed to bootstrap app: \(error.localizedDescription)")
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLogger.app.info("UFCSwap is terminating")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
