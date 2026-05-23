import AVFoundation
import CoreGraphics
import ScreenCaptureKit

private let screenRecordingPromptedKey = "screenRecordingPermissionPrompted"

enum PermissionStatus {
    case granted
    case denied
    case notDetermined
}

private struct ScreenCaptureDiagnosis {
    let status: PermissionStatus
    let message: String
}

/// Tracks camera, microphone and screen-recording authorization.
@MainActor
final class PermissionManager: ObservableObject {
    @Published var cameraStatus: PermissionStatus = .notDetermined
    @Published var microphoneStatus: PermissionStatus = .notDetermined
    @Published var screenRecordingStatus: PermissionStatus = .notDetermined
    @Published var screenRecordingDiagnosticMessage = "点击“权限诊断”查看当前屏幕录制权限的真实检测结果。"

    private var screenStatusRefreshTask: Task<Void, Never>?

    var requiresSetup: Bool {
        cameraStatus != .granted ||
        microphoneStatus != .granted ||
        screenRecordingStatus != .granted
    }

    init() {
        refresh()
    }

    /// Re-reads the current authorization status of every permission.
    func refresh() {
        cameraStatus = Self.captureStatus(for: .video)
        microphoneStatus = Self.captureStatus(for: .audio)
        screenStatusRefreshTask?.cancel()
        screenStatusRefreshTask = Task { [weak self] in
            let diagnosis = await Self.diagnoseScreenCapture()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.screenRecordingStatus = diagnosis.status
            }
        }
    }

    /// Prompts the user for camera and microphone access.
    func requestCameraAndMicrophone() async {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        refresh()
    }

    /// Triggers the system screen-recording permission prompt.
    func requestScreenRecording() {
        Self.markScreenRecordingPrompted()
        CGRequestScreenCaptureAccess()
        refresh()
    }

    func runScreenRecordingDiagnostics() async {
        let diagnosis = await Self.diagnoseScreenCapture()
        screenRecordingStatus = diagnosis.status
        screenRecordingDiagnosticMessage = diagnosis.message
    }

    nonisolated static func canCaptureScreen() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    nonisolated static func isScreenCapturePermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == SCStreamErrorDomain &&
               nsError.code == SCStreamError.Code.userDeclined.rawValue
    }

    nonisolated static func markScreenRecordingPrompted() {
        UserDefaults.standard.set(true, forKey: screenRecordingPromptedKey)
    }

    private nonisolated static func diagnoseScreenCapture() async -> ScreenCaptureDiagnosis {
        let preflightGranted = CGPreflightScreenCaptureAccess()

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            let displayCount = content.displays.count
            if preflightGranted {
                return ScreenCaptureDiagnosis(
                    status: .granted,
                    message: "诊断结果：已授权。CGPreflightScreenCaptureAccess = true；SCShareableContent 成功返回 \(displayCount) 个显示器。"
                )
            }
            if displayCount > 0 {
                return ScreenCaptureDiagnosis(
                    status: .granted,
                    message: "诊断结果：已授权，但预检与实际结果不一致。CGPreflightScreenCaptureAccess = false；SCShareableContent 实际返回 \(displayCount) 个显示器。"
                )
            }
        } catch {
            let nsError = error as NSError
            let prompted = UserDefaults.standard.bool(forKey: screenRecordingPromptedKey)
            if isScreenCapturePermissionError(error) {
                return ScreenCaptureDiagnosis(
                    status: .denied,
                    message: "诊断结果：被系统拒绝。CGPreflightScreenCaptureAccess = \(preflightGranted ? "true" : "false")；ScreenCaptureKit 返回 \(nsError.domain) / \(nsError.code)：\(nsError.localizedDescription)"
                )
            }

            return ScreenCaptureDiagnosis(
                status: prompted ? .denied : .notDetermined,
                message: "诊断结果：未拿到可用的屏幕采集结果。CGPreflightScreenCaptureAccess = \(preflightGranted ? "true" : "false")；ScreenCaptureKit 返回 \(nsError.domain) / \(nsError.code)：\(nsError.localizedDescription)"
            )
        }

        return ScreenCaptureDiagnosis(
            status: preflightGranted ? .granted : (UserDefaults.standard.bool(forKey: screenRecordingPromptedKey) ? .denied : .notDetermined),
            message: "诊断结果：未发现显示器列表。CGPreflightScreenCaptureAccess = \(preflightGranted ? "true" : "false")；ScreenCaptureKit 未报错，但没有返回可录制显示器。"
        )
    }

    private static func captureStatus(for mediaType: AVMediaType) -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }
}
