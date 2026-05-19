import SwiftUI
import AppKit

/// Settings window: output and audio options.
struct SettingsView: View {
    @ObservedObject var coordinator: RecordingCoordinator

    var body: some View {
        Form {
            Section("音频") {
                Toggle("录制麦克风", isOn: $coordinator.settings.captureMicrophone)
                Toggle("录制系统声音", isOn: $coordinator.settings.captureSystemAudio)
            }

            Section("视频") {
                Picker("输出格式", selection: $coordinator.settings.container) {
                    ForEach(VideoContainer.allCases) { container in
                        Text(container.displayName).tag(container)
                    }
                }
                Stepper("帧率：\(coordinator.settings.frameRate) fps",
                        value: $coordinator.settings.frameRate,
                        in: 24...60,
                        step: 6)
            }

            Section("录制") {
                Toggle("开始前 3 秒倒计时", isOn: $coordinator.settings.countdownEnabled)
            }

            Section("输出位置") {
                HStack {
                    Text(coordinator.settings.outputDirectory.path)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("选择…") {
                        chooseOutputDirectory()
                    }
                }
            }

            Section("快捷键") {
                LabeledContent("开始 / 停止录制", value: "⌘⇧2")
                LabeledContent("暂停 / 继续", value: "⌘⇧1")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 420)
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = coordinator.settings.outputDirectory
        if panel.runModal() == .OK, let url = panel.url {
            coordinator.settings.outputDirectory = url
        }
    }
}
