import SwiftUI

struct ControlPanelView: View {
    @ObservedObject var viewModel: ControlPanelViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("UFCSwap")
                    .font(.title2.weight(.semibold))

                GroupBox("Status") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Accessibility: \(viewModel.accessibilityStatus.rawValue)")
                        Text("Automation: \(viewModel.automationStatus.displayText)")
                        Text(viewModel.statusMessage)
                            .foregroundStyle(viewModel.statusIsError ? .red : .secondary)
                        HStack {
                            Button("Refresh") { viewModel.refreshSetupChecks() }
                            Button("Request Permission") { viewModel.requestPermission() }
                            Button("Test On") { viewModel.testOn() }
                            Button("Test Off") { viewModel.testOff() }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Setup Checklist") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Google Chrome")
                                .frame(width: 180, alignment: .leading)
                            Text(viewModel.chromeInstalled ? "Installed" : "Missing")
                                .foregroundStyle(viewModel.chromeInstalled ? .green : .red)
                            Spacer()
                            if !viewModel.chromeInstalled {
                                Button("Download Chrome") { viewModel.openChromeDownloadPage() }
                            }
                        }

                        HStack {
                            Text("Accessibility")
                                .frame(width: 180, alignment: .leading)
                            Text(viewModel.accessibilityStatus == .granted ? "Granted" : "Missing")
                                .foregroundStyle(viewModel.accessibilityStatus == .granted ? .green : .red)
                            Spacer()
                            if viewModel.accessibilityStatus != .granted {
                                Button("Request") { viewModel.requestPermission() }
                                Button("Open Settings") { viewModel.openAccessibilitySettings() }
                            }
                        }

                        HStack {
                            Text("Automation to Chrome")
                                .frame(width: 180, alignment: .leading)
                            Text(viewModel.automationStatus.displayText)
                                .foregroundStyle(viewModel.automationStatus == .granted ? .green : .orange)
                            Spacer()
                            Button("Check / Request") { viewModel.requestAutomationPermission() }
                            Button("Open Settings") { viewModel.openAutomationSettings() }
                        }

                        HStack {
                            Text("Video Configuration")
                                .frame(width: 180, alignment: .leading)
                            Text(viewModel.videosValid ? "Valid" : "Needs Attention")
                                .foregroundStyle(viewModel.videosValid ? .green : .orange)
                            Spacer()
                        }

                        Text("Use this checklist the first time you open UFCSwap from Applications.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Hotkey") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Current Hotkey: \(viewModel.hotkeyKey)")
                                .font(.headline)
                            Button(viewModel.isCapturingHotkey ? "Press a function key" : "Set Hotkey") {
                                viewModel.enterHotkeyCaptureMode()
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        if viewModel.isCapturingHotkey {
                            Text("Capture mode is active. Press F1 through F19.")
                                .foregroundStyle(.secondary)
                        }

                        Text("Only plain function keys are supported for the global hotkey.")
                            .foregroundStyle(.secondary)
                        Text("On many Macs, F1-F12 may require enabling \"Use F1, F2, etc. keys as standard function keys\" or holding the fn key.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Playback") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Playback uses the current frontmost app automatically.")
                            .foregroundStyle(.secondary)

                        Picker("Browser", selection: viewModel.bindingForBrowserSelection()) {
                            Text("Default").tag("")
                            ForEach(viewModel.browsers) { browser in
                                Text(browser.name).tag(browser.bundleID)
                            }
                        }
                    }
                }

                GroupBox("Videos") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button("Add Video") { viewModel.addVideo() }
                            Spacer()
                        }

                        ForEach($viewModel.config.videos) { $video in
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Title", text: $video.title)
                                HStack {
                                    TextField("Fighter A", text: $video.fighterA)
                                    TextField("Fighter B", text: $video.fighterB)
                                }
                                HStack {
                                    TextField("Event", text: $video.eventName)
                                    TextField("Year", value: $video.year, format: .number)
                                        .frame(width: 100)
                                }
                                TextField(
                                    "YouTube URL",
                                    text: Binding(
                                        get: { video.url.absoluteString },
                                        set: { video.url = URL(string: $0) ?? video.url }
                                    )
                                )
                                TextField(
                                    "Tags (comma separated)",
                                    text: Binding(
                                        get: { video.tags.joined(separator: ", ") },
                                        set: { video.tags = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                                    )
                                )
                                Button("Remove") {
                                    if let index = viewModel.config.videos.firstIndex(where: { $0.id == video.id }) {
                                        viewModel.config.videos.remove(at: index)
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                            Divider()
                        }
                    }
                }

                HStack {
                    Button("Reload") { viewModel.reload() }
                    Button("Save") { viewModel.save() }
                    Text(viewModel.statusMessage)
                        .foregroundStyle(viewModel.statusIsError ? .red : .secondary)
                    Spacer()
                }
            }
            .padding(16)
        }
        .frame(minWidth: 760, minHeight: 620)
    }
}
