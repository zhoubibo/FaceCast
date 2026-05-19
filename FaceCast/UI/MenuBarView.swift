import SwiftUI
import AppKit

/// Contents of the menu bar extra.
struct MenuBarView: View {
    @ObservedObject var coordinator: RecordingCoordinator

    var body: some View {
        Text(statusText)

        Divider()

        if coordinator.state == .idle {
            Button("开始录制") {
                coordinator.startRecording()
            }
        } else {
            Button("停止录制") {
                coordinator.stopRecording()
            }
        }

        if coordinator.state == .recording {
            Button("暂停") {
                coordinator.pause()
            }
        } else if coordinator.state == .paused {
            Button("继续") {
                coordinator.resume()
            }
        }

        Divider()

        Button("退出 FaceCast") {
            NSApplication.shared.terminate(nil)
        }
    }

    private var statusText: String {
        switch coordinator.state {
        case .idle: return "就绪"
        case .countingDown(let seconds): return "倒计时 \(seconds)…"
        case .recording: return "录制中 \(coordinator.elapsedTimeString)"
        case .paused: return "已暂停 \(coordinator.elapsedTimeString)"
        case .stopping: return "正在保存…"
        }
    }
}
