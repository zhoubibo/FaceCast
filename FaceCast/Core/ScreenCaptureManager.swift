import ScreenCaptureKit
import CoreMedia
import CoreVideo
import AppKit

enum ScreenCaptureError: LocalizedError {
    case noDisplayAvailable

    var errorDescription: String? {
        switch self {
        case .noDisplayAvailable:
            return "未找到可录制的显示器。"
        }
    }
}

/// Captures the screen (and optionally system audio) via ScreenCaptureKit.
final class ScreenCaptureManager: NSObject {
    /// Invoked on the capture queue for every complete screen frame.
    var onScreenSample: ((CMSampleBuffer) -> Void)?

    /// Invoked on the audio queue for every system-audio sample buffer.
    var onSystemAudioSample: ((CMSampleBuffer) -> Void)?

    /// Invoked if the stream stops unexpectedly (e.g. revoked permission).
    var onStreamStopped: ((Error) -> Void)?

    private var stream: SCStream?
    private let captureQueue = DispatchQueue(label: "com.facecast.screencapture")
    private let audioQueue = DispatchQueue(label: "com.facecast.systemaudio")

    /// Resolves the main display, builds the stream and starts capturing.
    /// - Note: the app's own windows are excluded so the camera overlay panel
    ///   is never recorded into the frame.
    func start(frameRate: Int, captureSystemAudio: Bool) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )
        guard let display = content.displays.first else {
            throw ScreenCaptureError.noDisplayAvailable
        }

        let ownWindows = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)

        let (width, height) = Self.pixelSize(for: display)
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, frameRate)))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 6
        config.showsCursor = true
        if captureSystemAudio {
            config.capturesAudio = true
            config.sampleRate = 48000
            config.channelCount = 2
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
        if captureSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        }
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        guard let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
    }

    /// Converts a display's point size to its backing pixel size.
    private static func pixelSize(for display: SCDisplay) -> (Int, Int) {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        let scale = NSScreen.screens.first { screen in
            (screen.deviceDescription[screenNumberKey] as? NSNumber)?.uint32Value == display.displayID
        }?.backingScaleFactor ?? 1
        return (Int(CGFloat(display.width) * scale), Int(CGFloat(display.height) * scale))
    }

    /// A frame is usable only when ScreenCaptureKit reports `.complete` status.
    private func isComplete(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer, createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
              let info = attachments.first,
              let rawStatus = info[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus) else {
            return false
        }
        return status == .complete
    }
}

extension ScreenCaptureManager: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStreamStopped?(error)
    }
}

extension ScreenCaptureManager: SCStreamOutput {
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch type {
        case .screen:
            guard isComplete(sampleBuffer) else { return }
            onScreenSample?(sampleBuffer)
        case .audio:
            onSystemAudioSample?(sampleBuffer)
        default:
            break
        }
    }
}
