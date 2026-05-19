import Foundation
import Combine
import CoreMedia
import CoreGraphics

/// Drives a recording session: wires the capture sources through the compositor
/// into the encoder, and owns the recording state machine.
@MainActor
final class RecordingCoordinator: ObservableObject {
    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var lastRecordingURL: URL?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isOverlayVisible = false
    @Published private(set) var isMicrophoneMuted = false
    @Published private(set) var elapsedSeconds = 0
    @Published var settings = RecordingSettings()
    @Published var pipState = PiPState()

    private let screenCapture = ScreenCaptureManager()
    private let cameraCapture = CameraCaptureManager()
    private let audioCapture = AudioCaptureManager()
    private let compositor = FrameCompositor()
    private let encoder = VideoEncoder()
    private let overlayController: CameraOverlayController
    private let hotkeys = HotkeyManager()

    private var cameraConfigured = false
    private var microphoneConfigured = false
    private var timerTask: Task<Void, Never>?
    private let microphoneMuteFlag = LockedFlag()

    init() {
        overlayController = CameraOverlayController(session: cameraCapture.session)
        overlayController.onLayoutChanged = { [weak self] center, width in
            self?.applyOverlayLayout(center: center, width: width)
        }
        overlayController.onRequestModeToggle = { [weak self] in
            self?.togglePiPMode()
        }
        overlayController.onRequestMuteToggle = { [weak self] in
            self?.toggleMicrophoneMuted()
        }
        overlayController.onRequestShapeToggle = { [weak self] in
            self?.togglePiPShape()
        }
        overlayController.onRequestHide = { [weak self] in
            self?.hideCameraOverlay()
        }
        overlayController.setMicrophoneMuted(false)
        overlayController.setShape(pipState.shape)
        hotkeys.onToggleRecording = { [weak self] in
            self?.toggleRecordingFromHotkey()
        }
        hotkeys.onTogglePause = { [weak self] in
            self?.togglePauseFromHotkey()
        }
        hotkeys.registerDefaults()
    }

    var isRecording: Bool {
        state == .recording || state == .paused
    }

    var elapsedTimeString: String {
        String(format: "%02d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }

    // MARK: - Camera overlay

    func toggleCameraOverlay() {
        if overlayController.isVisible {
            hideCameraOverlay()
        } else {
            showCameraOverlay()
        }
    }

    func showCameraOverlay() {
        do {
            try ensureCameraReady()
        } catch {
            errorMessage = "摄像头不可用：\(error.localizedDescription)"
            return
        }
        overlayController.setCameraResolution(cameraCapture.cameraResolution)
        overlayController.show(normalizedCenter: pipState.normalizedCenter,
                               normalizedWidth: pipState.normalizedWidth)
        isOverlayVisible = true
    }

    func hideCameraOverlay() {
        overlayController.hide()
        isOverlayVisible = false
        if !isRecording {
            cameraCapture.stopRunning()
        }
    }

    private func ensureCameraReady() throws {
        if !cameraConfigured {
            try cameraCapture.configure(device: nil)
            cameraConfigured = true
        }
        cameraCapture.startRunning()
    }

    private func ensureMicrophoneReady() throws {
        if !microphoneConfigured {
            try audioCapture.configure(device: nil)
            microphoneConfigured = true
        }
        audioCapture.startRunning()
    }

    private func applyOverlayLayout(center: CGPoint, width: CGFloat) {
        pipState.normalizedCenter = center
        pipState.normalizedWidth = width
        compositor.pipState = pipState
    }

    // MARK: - Recording lifecycle

    func startRecording() {
        guard state == .idle else { return }
        errorMessage = nil
        lastRecordingURL = nil

        if settings.countdownEnabled {
            state = .countingDown(secondsRemaining: 3)
            Task {
                for remaining in stride(from: 3, through: 1, by: -1) {
                    guard case .countingDown = state else { return }
                    state = .countingDown(secondsRemaining: remaining)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                guard case .countingDown = state else { return }
                beginCapture()
            }
        } else {
            beginCapture()
        }
    }

    func stopRecording() {
        if case .countingDown = state {
            state = .idle
            return
        }
        guard isRecording else { return }
        state = .stopping
        stopTimer()

        Task {
            await screenCapture.stop()
            stopCaptureSources()
            lastRecordingURL = await encoder.finish()
            if lastRecordingURL == nil {
                errorMessage = "录制未生成文件（未捕获到任何画面）。"
            }
            state = .idle
        }
    }

    func pause() {
        guard state == .recording else { return }
        encoder.pause()
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        encoder.resume()
        state = .recording
    }

    /// Toggles the camera overlay between fullscreen and floating modes.
    func togglePiPMode() {
        pipState.mode = (pipState.mode == .fullscreen) ? .floating : .fullscreen
        compositor.pipState = pipState
        if overlayController.isVisible {
            overlayController.applyMode(pipState.mode)
        }
    }

    func togglePiPShape() {
        pipState.shape = (pipState.shape == .roundedRect) ? .circle : .roundedRect
        compositor.pipState = pipState
        overlayController.setShape(pipState.shape)
    }

    func toggleMicrophoneMuted() {
        isMicrophoneMuted.toggle()
        microphoneMuteFlag.set(isMicrophoneMuted)
        overlayController.setMicrophoneMuted(isMicrophoneMuted)
    }

    /// Sets up the encoder + capture wiring and starts the streams.
    private func beginCapture() {
        guard PermissionManager.canCaptureScreen() else {
            PermissionManager.markScreenRecordingPrompted()
            CGRequestScreenCaptureAccess()
            errorMessage = "未获得屏幕录制权限。请在“系统设置 > 隐私与安全性 > 屏幕与系统音频录制”中允许 FaceCast，并在授权后完全退出再重新打开应用。"
            state = .idle
            return
        }

        let outputURL = Self.makeOutputURL(in: settings.outputDirectory,
                                           container: settings.container)
        encoder.prepare(outputURL: outputURL,
                        fileType: settings.container.avFileType,
                        captureMicrophone: settings.captureMicrophone,
                        captureSystemAudio: settings.captureSystemAudio)
        compositor.pipState = pipState

        screenCapture.onScreenSample = { [encoder, compositor] sampleBuffer in
            guard let screenBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let composed = compositor.compose(screenFrame: screenBuffer)
            encoder.appendVideo(composed, at: time)
        }
        screenCapture.onSystemAudioSample = { [encoder] sampleBuffer in
            encoder.appendSystemAudio(sampleBuffer)
        }
        screenCapture.onStreamStopped = { [weak self] error in
            Task { @MainActor in
                self?.handleUnexpectedStop(error)
            }
        }
        cameraCapture.onCameraFrame = { [compositor] pixelBuffer, _ in
            compositor.updateCameraFrame(pixelBuffer)
        }

        if settings.captureMicrophone {
            audioCapture.onMicrophoneSample = { [encoder, microphoneMuteFlag] sampleBuffer in
                guard !microphoneMuteFlag.value else { return }
                encoder.appendMicrophoneAudio(sampleBuffer)
            }
            do {
                try ensureMicrophoneReady()
            } catch {
                errorMessage = "麦克风不可用，将不录制麦克风：\(error.localizedDescription)"
            }
        }

        Task {
            do {
                try ensureCameraReady()
            } catch {
                errorMessage = "摄像头不可用，将仅录制屏幕：\(error.localizedDescription)"
            }
            do {
                try await screenCapture.start(frameRate: settings.frameRate,
                                              captureSystemAudio: settings.captureSystemAudio)
                state = .recording
                startTimer()
            } catch {
                stopCaptureSources()
                errorMessage = error.localizedDescription
                state = .idle
            }
        }
    }

    private func stopCaptureSources() {
        cameraCapture.onCameraFrame = nil
        if !overlayController.isVisible {
            cameraCapture.stopRunning()
        }
        audioCapture.onMicrophoneSample = nil
        audioCapture.stopRunning()
        screenCapture.onSystemAudioSample = nil
    }

    private func handleUnexpectedStop(_ error: Error) {
        guard isRecording else { return }
        errorMessage = "录制中断：\(error.localizedDescription)"
        state = .stopping
        stopTimer()
        Task {
            stopCaptureSources()
            lastRecordingURL = await encoder.finish()
            state = .idle
        }
    }

    // MARK: - Timer

    private func startTimer() {
        elapsedSeconds = 0
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                if self.state == .recording {
                    self.elapsedSeconds += 1
                }
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    // MARK: - Hotkeys

    private func toggleRecordingFromHotkey() {
        switch state {
        case .idle: startRecording()
        case .recording, .paused, .countingDown: stopRecording()
        case .stopping: break
        }
    }

    private func togglePauseFromHotkey() {
        switch state {
        case .recording: pause()
        case .paused: resume()
        default: break
        }
    }

    private static func makeOutputURL(in directory: URL,
                                      container: VideoContainer) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        let name = "FaceCast \(formatter.string(from: Date())).\(container.fileExtension)"
        return directory.appendingPathComponent(name)
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set(_ newValue: Bool) {
        lock.lock()
        storage = newValue
        lock.unlock()
    }
}
