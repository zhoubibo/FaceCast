import AVFoundation
import CoreMedia

enum AudioCaptureError: LocalizedError {
    case noMicrophoneAvailable
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .noMicrophoneAvailable: return "未找到可用的麦克风。"
        case .cannotAddInput: return "无法添加麦克风输入。"
        case .cannotAddOutput: return "无法添加麦克风输出。"
        }
    }
}

/// Captures microphone audio via AVFoundation.
///
/// System audio is delivered separately by `ScreenCaptureManager` (the `.audio`
/// output of `SCStream`); the two are written as separate tracks by `VideoEncoder`.
final class AudioCaptureManager: NSObject {
    /// Invoked on the microphone queue for every microphone sample buffer.
    var onMicrophoneSample: ((CMSampleBuffer) -> Void)?

    private let session = AVCaptureSession()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let microphoneQueue = DispatchQueue(label: "com.facecast.microphone")
    private var isConfigured = false

    func availableMicrophones() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    /// Configures the session with a microphone. Safe to call repeatedly.
    func configure(device: AVCaptureDevice?) throws {
        guard !isConfigured else { return }

        let microphone = device ?? AVCaptureDevice.default(for: .audio)
        guard let microphone else { throw AudioCaptureError.noMicrophoneAvailable }

        session.beginConfiguration()
        for input in session.inputs {
            session.removeInput(input)
        }

        let input = try AVCaptureDeviceInput(device: microphone)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw AudioCaptureError.cannotAddInput
        }
        session.addInput(input)

        if !session.outputs.contains(audioOutput) {
            guard session.canAddOutput(audioOutput) else {
                session.commitConfiguration()
                throw AudioCaptureError.cannotAddOutput
            }
            session.addOutput(audioOutput)
        }
        audioOutput.setSampleBufferDelegate(self, queue: microphoneQueue)
        session.commitConfiguration()

        isConfigured = true
    }

    func startRunning() {
        microphoneQueue.async { [session] in
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    func stopRunning() {
        microphoneQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }
}

extension AudioCaptureManager: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        onMicrophoneSample?(sampleBuffer)
    }
}
