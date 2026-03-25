import AppKit
import SwiftUI

@MainActor
final class ControlPanelWindowController: NSWindowController {
    private let viewModel: ControlPanelViewModel

    init(container: AppContainer) {
        let viewModel = ControlPanelViewModel(container: container)
        self.viewModel = viewModel
        let hostingController = NSHostingController(rootView: ControlPanelView(viewModel: viewModel))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "UFCSwap"
        window.setContentSize(NSSize(width: 900, height: 680))
        window.styleMask.insert(.resizable)
        window.center()
        super.init(window: window)
        shouldCascadeWindows = true
        AppLogger.startup("main window created")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(sender)
        AppLogger.startup("main window shown")
    }

    func runAutomatedTestOn() {
        viewModel.testOn()
    }

    func runAutomatedTestOff() {
        viewModel.testOff()
    }

    func runAutomatedTestCycle() {
        Task { @MainActor in
            viewModel.testOn()
            try? await Task.sleep(for: .seconds(4))
            viewModel.testOff()
        }
    }

    func runAutomatedHotkeyCapture() {
        viewModel.enterHotkeyCaptureMode()
    }
}
