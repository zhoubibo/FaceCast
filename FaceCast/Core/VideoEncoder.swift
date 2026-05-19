import AVFoundation
import CoreVideo
import CoreMedia
import AudioToolbox

/// Encodes composed video plus microphone and system-audio tracks via `AVAssetWriter`.
///
/// The microphone and system audio are written as two separate audio tracks;
/// no live mixing is performed. The writer and all its inputs are created
/// lazily from the first video frame.
///
/// Pause is implemented by dropping frames while paused and subtracting the
/// accumulated paused duration from every timestamp, so the paused span does
/// not appear as a frozen frame in playback.
final class VideoEncoder {
    private let queue = DispatchQueue(label: "com.facecast.encoder")

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var microphoneInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?

    private var outputURL: URL?
    private var fileType: AVFileType = .mp4
    private var wantsMicrophone = false
    private var wantsSystemAudio = false
    private var sessionStarted = false
    private var failed = false

    // Pause handling.
    private var isPaused = false
    private var pendingResume = false
    private var timeOffset = CMTime.zero
    private var lastVideoSourceTime = CMTime.zero

    /// Resets state for a new recording. Call before capture starts.
    func prepare(outputURL: URL,
                 fileType: AVFileType,
                 captureMicrophone: Bool,
                 captureSystemAudio: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.outputURL = outputURL
            self.fileType = fileType
            self.wantsMicrophone = captureMicrophone
            self.wantsSystemAudio = captureSystemAudio
            self.writer = nil
            self.videoInput = nil
            self.adaptor = nil
            self.microphoneInput = nil
            self.systemAudioInput = nil
            self.sessionStarted = false
            self.failed = false
            self.isPaused = false
            self.pendingResume = false
            self.timeOffset = .zero
            self.lastVideoSourceTime = .zero
        }
    }

    func pause() {
        queue.async { [weak self] in
            self?.isPaused = true
        }
    }

    func resume() {
        queue.async { [weak self] in
            guard let self, self.isPaused else { return }
            self.isPaused = false
            self.pendingResume = true
        }
    }

    /// Appends one composed frame. Safe to call from the capture queue.
    func appendVideo(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
        queue.async { [weak self] in
            guard let self, !self.failed, let outputURL = self.outputURL else { return }

            if self.writer == nil {
                self.setUpWriter(outputURL: outputURL, pixelBuffer: pixelBuffer)
            }
            guard !self.isPaused else { return }

            // The first frame after a resume reveals the paused span.
            if self.pendingResume {
                self.timeOffset = self.timeOffset + (time - self.lastVideoSourceTime)
                self.pendingResume = false
            }
            self.lastVideoSourceTime = time

            let adjustedTime = time - self.timeOffset
            self.startSessionIfNeeded(at: adjustedTime)

            guard let input = self.videoInput,
                  let adaptor = self.adaptor,
                  input.isReadyForMoreMediaData else {
                return
            }
            adaptor.append(pixelBuffer, withPresentationTime: adjustedTime)
        }
    }

    /// Appends one microphone sample buffer to the microphone track.
    func appendMicrophoneAudio(_ sampleBuffer: CMSampleBuffer) {
        appendAudio(sampleBuffer, toMicrophone: true)
    }

    /// Appends one system-audio sample buffer to the system-audio track.
    func appendSystemAudio(_ sampleBuffer: CMSampleBuffer) {
        appendAudio(sampleBuffer, toMicrophone: false)
    }

    private func appendAudio(_ sampleBuffer: CMSampleBuffer, toMicrophone: Bool) {
        queue.async { [weak self] in
            guard let self, !self.failed, self.sessionStarted, !self.isPaused else { return }

            let input = toMicrophone ? self.microphoneInput : self.systemAudioInput
            guard let input, input.isReadyForMoreMediaData else { return }

            guard let buffer = Self.retimed(sampleBuffer, offset: self.timeOffset) else { return }
            input.append(buffer)
        }
    }

    /// Finalizes the file. Returns the output URL on success, `nil` otherwise.
    func finish() async -> URL? {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self,
                      let writer = self.writer,
                      self.sessionStarted,
                      writer.status == .writing else {
                    continuation.resume(returning: nil)
                    return
                }
                self.videoInput?.markAsFinished()
                self.microphoneInput?.markAsFinished()
                self.systemAudioInput?.markAsFinished()
                writer.finishWriting {
                    let url = writer.status == .completed ? writer.outputURL : nil
                    continuation.resume(returning: url)
                }
            }
        }
    }

    /// Creates the asset writer and all inputs using the first frame's size.
    private func setUpWriter(outputURL: URL, pixelBuffer: CVPixelBuffer) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        do {
            try? FileManager.default.removeItem(at: outputURL)
            let writer = try AVAssetWriter(outputURL: outputURL, fileType: fileType)

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
            ]
            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = true

            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height,
                ]
            )

            guard writer.canAdd(videoInput) else {
                failed = true
                return
            }
            writer.add(videoInput)

            if wantsMicrophone {
                let input = Self.makeAudioInput()
                if writer.canAdd(input) {
                    writer.add(input)
                    microphoneInput = input
                }
            }
            if wantsSystemAudio {
                let input = Self.makeAudioInput()
                if writer.canAdd(input) {
                    writer.add(input)
                    systemAudioInput = input
                }
            }

            guard writer.startWriting() else {
                failed = true
                return
            }

            self.writer = writer
            self.videoInput = videoInput
            self.adaptor = adaptor
        } catch {
            failed = true
        }
    }

    private func startSessionIfNeeded(at time: CMTime) {
        guard let writer, !sessionStarted, writer.status == .writing else { return }
        writer.startSession(atSourceTime: time)
        sessionStarted = true
    }

    /// An AAC audio input. The writer transcodes whatever LPCM the source
    /// delivers, so the source sample rate / channel count need not match.
    private static func makeAudioInput() -> AVAssetWriterInput {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 48000,
            AVEncoderBitRateKey: 128000,
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        return input
    }

    /// Returns a copy of `sampleBuffer` with every timestamp shifted by `-offset`.
    private static func retimed(_ sampleBuffer: CMSampleBuffer, offset: CMTime) -> CMSampleBuffer? {
        guard offset != .zero else { return sampleBuffer }

        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer,
                                               entryCount: 0,
                                               arrayToFill: nil,
                                               entriesNeededOut: &count)
        guard count > 0 else { return sampleBuffer }

        var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer,
                                               entryCount: count,
                                               arrayToFill: &timing,
                                               entriesNeededOut: &count)
        for index in 0..<Int(count) {
            if timing[index].presentationTimeStamp.isValid {
                timing[index].presentationTimeStamp = timing[index].presentationTimeStamp - offset
            }
            if timing[index].decodeTimeStamp.isValid {
                timing[index].decodeTimeStamp = timing[index].decodeTimeStamp - offset
            }
        }

        var newBuffer: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault,
                                              sampleBuffer: sampleBuffer,
                                              sampleTimingEntryCount: count,
                                              sampleTimingArray: &timing,
                                              sampleBufferOut: &newBuffer)
        return newBuffer
    }
}
