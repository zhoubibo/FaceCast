import SwiftUI
import AppKit

/// Main window: recording controls and live status.
struct ControlPanelView: View {
    @ObservedObject var coordinator: RecordingCoordinator
    @ObservedObject var permissions: PermissionManager

    var body: some View {
        Group {
            if permissions.requiresSetup {
                PermissionGuideView(permissions: permissions)
            } else {
                recordingControls
            }
        }
        .onAppear {
            permissions.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            permissions.refresh()
        }
    }

    private var statusText: String {
        switch coordinator.state {
        case .idle: return "就绪"
        case .countingDown(let seconds): return "倒计时 \(seconds)…"
        case .recording: return "● 录制中 \(coordinator.elapsedTimeString)"
        case .paused: return "已暂停 \(coordinator.elapsedTimeString)"
        case .stopping: return "正在保存…"
        }
    }

    private var statusColor: Color {
        switch coordinator.state {
        case .recording: return .red
        case .paused, .countingDown: return .orange
        default: return .secondary
        }
    }

    private var pipModeLabel: String {
        coordinator.pipState.mode == .fullscreen ? "切换到小浮窗" : "切换到全屏"
    }

    private var recordButtonTitle: String {
        switch coordinator.state {
        case .idle:
            return "开始录制"
        case .countingDown(let seconds):
            return "准备开始 · \(seconds)s"
        case .recording:
            return "录制进行中"
        case .paused:
            return "录制已暂停"
        case .stopping:
            return "正在保存"
        }
    }

    private var recordButtonIcon: String {
        switch coordinator.state {
        case .idle:
            return "record.circle.fill"
        case .countingDown:
            return "timer"
        case .recording:
            return "waveform.circle.fill"
        case .paused:
            return "pause.circle.fill"
        case .stopping:
            return "square.and.arrow.down.fill"
        }
    }

    private var recordingControls: some View {
        VStack(spacing: 18) {
            StudioCard {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            StudioTag(title: "RECORDER", tint: StudioPalette.accentDeep)

                            Text("FaceCast")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(StudioPalette.ink)

                            Text("快速录屏，摄像头浮窗双击即可在全屏和小窗之间切换。")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(StudioPalette.mutedInk)
                        }

                        Spacer(minLength: 16)

                        VStack(alignment: .trailing, spacing: 10) {
                            VStack(alignment: .trailing, spacing: 10) {
                                HStack(spacing: 10) {
                                    if coordinator.isRecording {
                                        StudioTag(title: "LIVE", tint: StudioPalette.accentDeep)
                                    }
                                    StudioWaveform(isActive: coordinator.isRecording)
                                        .frame(width: 56)
                                }

                                Image(systemName: coordinator.isRecording ? "record.circle.fill" : "video.badge.waveform")
                                    .font(.system(size: 34))
                                    .foregroundStyle(coordinator.isRecording ? StudioPalette.accent : StudioPalette.ink)
                                    .padding(14)
                                    .background(Color.white.opacity(0.74))
                                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            }

                            Text(statusText)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(statusColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(statusColor.opacity(0.12))
                                .clipShape(Capsule())
                                .monospacedDigit()
                        }
                    }

                    HStack(spacing: 12) {
                        StudioMetric(label: "格式", value: coordinator.settings.container.displayName)
                        StudioMetric(label: "帧率", value: "\(coordinator.settings.frameRate) fps")
                        StudioMetric(label: "模式", value: coordinator.pipState.mode == .fullscreen ? "全屏摄像头" : "浮窗叠加")
                    }
                }
            }

            StudioCard {
                VStack(spacing: 12) {
                    Button {
                        coordinator.startRecording()
                    } label: {
                        Label(recordButtonTitle, systemImage: recordButtonIcon)
                    }
                    .buttonStyle(StudioPrimaryButtonStyle())
                    .disabled(coordinator.state != .idle)
                    .opacity(coordinator.state == .idle ? 1 : 0.9)

                    HStack(spacing: 12) {
                        if coordinator.state == .paused {
                            Button {
                                coordinator.resume()
                            } label: {
                                Label("继续", systemImage: "play.fill")
                            }
                            .buttonStyle(StudioSecondaryButtonStyle())
                        } else {
                            Button {
                                coordinator.pause()
                            } label: {
                                Label("暂停", systemImage: "pause.fill")
                            }
                            .buttonStyle(StudioSecondaryButtonStyle())
                            .disabled(coordinator.state != .recording)
                        }

                        Button {
                            coordinator.stopRecording()
                        } label: {
                            Label("停止", systemImage: "stop.fill")
                        }
                        .buttonStyle(StudioSecondaryButtonStyle())
                        .disabled(coordinator.state == .idle)
                    }
                }
            }

            StudioCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("摄像头浮窗")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioPalette.ink)

                    Text("圆角浮窗、拖拽位置、右下角缩放，双击可在全屏和原始小浮窗之间切换。")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(StudioPalette.mutedInk)

                    HStack(spacing: 12) {
                        Button {
                            coordinator.toggleCameraOverlay()
                        } label: {
                            Label(coordinator.isOverlayVisible ? "隐藏浮窗" : "显示浮窗",
                                  systemImage: coordinator.isOverlayVisible ? "eye.slash" : "camera")
                        }
                        .buttonStyle(StudioSecondaryButtonStyle())

                        Button {
                            coordinator.togglePiPMode()
                        } label: {
                            Label(pipModeLabel, systemImage: "arrow.up.left.and.arrow.down.right")
                        }
                        .buttonStyle(StudioSecondaryButtonStyle())
                    }

                    HStack(spacing: 12) {
                        Button {
                            coordinator.togglePiPShape()
                        } label: {
                            Label(
                                coordinator.pipState.shape == .circle ? "切回标准比例" : "切换圆形气泡",
                                systemImage: coordinator.pipState.shape == .circle ? "rectangle.roundedtop" : "circle"
                            )
                        }
                        .buttonStyle(StudioSecondaryButtonStyle())

                        Button {
                            coordinator.toggleMicrophoneMuted()
                        } label: {
                            Label(
                                coordinator.isMicrophoneMuted ? "取消麦克风静音" : "麦克风静音",
                                systemImage: coordinator.isMicrophoneMuted ? "mic.fill" : "mic.slash.fill"
                            )
                        }
                        .buttonStyle(StudioSecondaryButtonStyle())
                    }
                }
            }

            if let error = coordinator.errorMessage {
                StudioCard {
                    Text(error)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(StudioPalette.accentDeep)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let url = coordinator.lastRecordingURL {
                StudioCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("录制已保存")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(StudioPalette.ink)

                        Text(url.lastPathComponent)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(StudioPalette.mutedInk)
                            .lineLimit(1)

                        Button("在访达中显示") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        .buttonStyle(StudioSecondaryButtonStyle())
                    }
                }
            }

            Button {
                permissions.refresh()
            } label: {
                Label("检查权限", systemImage: "lock.shield")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(StudioPalette.mutedInk)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(width: 500)
        .studioPanelBackground()
    }
}
