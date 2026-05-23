import SwiftUI
import AppKit

/// Onboarding view that explains and links to the required system permissions.
struct PermissionGuideView: View {
    @ObservedObject var permissions: PermissionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    StudioTag(title: "SETUP", tint: StudioPalette.accentDeep)

                    Text("准备你的录制空间")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioPalette.ink)

                    Text("V1.0.0 · 作者：Jenson")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(StudioPalette.mutedInk)

                    Text("先完成权限设置，FaceCast 就能开始录屏、摄像头叠加和系统音频采集。")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(StudioPalette.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 16)

                VStack(alignment: .trailing, spacing: 8) {
                    permissionStatusIcon
                    Text(permissions.requiresSetup ? "等待授权" : "全部就绪")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioPalette.mutedInk)
                }
            }

            StudioCard {
                VStack(spacing: 14) {
                    permissionRow("屏幕录制", permissions.screenRecordingStatus, hint: "用于显示器 / 窗口捕捉")
                    permissionRow("摄像头", permissions.cameraStatus, hint: "用于浮窗和全屏摄像头")
                    permissionRow("麦克风", permissions.microphoneStatus, hint: "用于人声解说")
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    requestScreenRecordingButton
                    requestCameraAndMicrophoneButton
                }

                VStack(spacing: 12) {
                    requestScreenRecordingButton
                    requestCameraAndMicrophoneButton
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    runDiagnosticsButton
                    openSystemSettingsButton
                }

                VStack(spacing: 12) {
                    runDiagnosticsButton
                    openSystemSettingsButton
                }
            }

            StudioCard {
                Text(permissions.screenRecordingDiagnosticMessage)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioPalette.mutedInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("提示：macOS 的屏幕录制权限在首次允许后，通常需要完全退出并重新打开 FaceCast 才会生效。")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(StudioPalette.mutedInk)
        }
        .padding(24)
        .frame(width: 420)
        .studioPanelBackground()
    }

    private var permissionStatusIcon: some View {
        Image(systemName: permissions.requiresSetup ? "lock.shield.fill" : "checkmark.shield.fill")
            .font(.system(size: 32, weight: .semibold))
            .foregroundStyle(permissions.requiresSetup ? StudioPalette.warning : StudioPalette.success)
            .padding(16)
            .background(Color.white.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func permissionRow(_ name: String, _ status: PermissionStatus, hint: String) -> some View {
        HStack(spacing: 14) {
            Circle()
                .fill(statusTint(status).opacity(0.16))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: status == .granted ? "checkmark" : "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(statusTint(status))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(StudioPalette.ink)
                Text(hint)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioPalette.mutedInk)
            }

            Spacer()

            Text(statusLabel(status))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(statusTint(status))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(statusTint(status).opacity(0.12))
                .clipShape(Capsule())
        }
    }

    private func statusLabel(_ status: PermissionStatus) -> String {
        switch status {
        case .granted: return "已授权"
        case .denied: return "已拒绝"
        case .notDetermined: return "未设置"
        }
    }

    private func statusTint(_ status: PermissionStatus) -> Color {
        switch status {
        case .granted: return StudioPalette.success
        case .denied, .notDetermined: return StudioPalette.warning
        }
    }

    private func openScreenRecordingSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private var requestScreenRecordingButton: some View {
        Button("请求屏幕录制") {
            permissions.requestScreenRecording()
        }
        .buttonStyle(StudioPrimaryButtonStyle())
    }

    private var requestCameraAndMicrophoneButton: some View {
        Button("请求摄像头 / 麦克风") {
            Task { await permissions.requestCameraAndMicrophone() }
        }
        .buttonStyle(StudioSecondaryButtonStyle())
    }

    private var runDiagnosticsButton: some View {
        Button("权限诊断") {
            Task { await permissions.runScreenRecordingDiagnostics() }
        }
        .buttonStyle(StudioSecondaryButtonStyle())
    }

    private var openSystemSettingsButton: some View {
        Button("打开系统设置") {
            openScreenRecordingSettings()
        }
        .buttonStyle(StudioSecondaryButtonStyle())
    }
}
