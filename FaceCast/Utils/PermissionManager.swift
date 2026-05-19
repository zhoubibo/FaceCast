import AVFoundation
import CoreGraphics

private let screenRecordingPromptedKey = "screenRecordingPermissionPrompted"

enum PermissionStatus {
    case granted
    case denied
    case notDetermined
}

/// Tracks camera, microphone and screen-recording authorization.
@MainActor
final class PermissionManager: ObservableObject {
    @Published var cameraStatus: PermissionStatus = .notDetermined
    @Published var microphoneStatus: PermissionStatus = .notDetermined
    @Published var screenRecordingStatus: PermissionStatus = .notDetermined

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
        if Self.canCaptureScreen() {
            screenRecordingStatus = .granted
        } else if UserDefaults.standard.bool(forKey: screenRecordingPromptedKey) {
            screenRecordingStatus = .denied
        } else {
            screenRecordingStatus = .notDetermined
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

    nonisolated static func canCaptureScreen() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    nonisolated static func markScreenRecordingPrompted() {
        UserDefaults.standard.set(true, forKey: screenRecordingPromptedKey)
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
