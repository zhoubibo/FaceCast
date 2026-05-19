import AVFoundation
import CoreMedia
import CoreVideo

enum CameraCaptureError: LocalizedError {
    case noCameraAvailable
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .noCameraAvailable: return "未找到可用的摄像头。"
        case .cannotAddInput: return "无法添加摄像头输入。"
        case .cannotAddOutput: return "无法添加摄像头输出。"
        }
    }
}

/// Captures camera frames via AVFoundation.
///
/// The session is reused for both the live overlay preview and recording:
/// `configure` + `startRunning` drive the session, while `onCameraFrame` is set
/// only while recording.
final class CameraCaptureManager: NSObject {
    /// Invoked on the camera queue for every camera frame (set while recording).
    var onCameraFrame: ((CVPixelBuffer, CMTime) -> Void)?

    /// The capture session. Exposed so a preview layer can attach to it.
    let session = AVCaptureSession()

    /// Native pixel size of the active camera.
    private(set) var cameraResolution = CGSize(width: 1280, height: 720)

    private let videoOutput = AVCaptureVideoDataOutput()
    private let cameraQueue = DispatchQueue(label: "com.facecast.camera")
    private var isConfigured = false

    /// Cameras currently connected to the system.
    func availableCameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    /// Configures the session with a camera. Safe to call repeatedly.
    func configure(device: AVCaptureDevice?) throws {
        guard !isConfigured else { return }

        let camera = device ?? AVCaptureDevice.default(for: .video)
        guard let camera else { throw CameraCaptureError.noCameraAvailable }

        session.beginConfiguration()
        for input in session.inputs {
            session.removeInput(input)
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CameraCaptureError.cannotAddInput
        }
        session.addInput(input)

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if !session.outputs.contains(videoOutput) {
            guard session.canAddOutput(videoOutput) else {
                session.commitConfiguration()
                throw CameraCaptureError.cannotAddOutput
            }
            session.addOutput(videoOutput)
        }
        videoOutput.setSampleBufferDelegate(self, queue: cameraQueue)
        session.commitConfiguration()

        let dimensions = CMVideoFormatDescriptionGetDimensions(camera.activeFormat.formatDescription)
        if dimensions.width > 0, dimensions.height > 0 {
            cameraResolution = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
        }
        isConfigured = true
    }

    func startRunning() {
        cameraQueue.async { [session] in
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    func stopRunning() {
        cameraQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }
}

extension CameraCaptureManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        onCameraFrame?(pixelBuffer, time)
    }
}
