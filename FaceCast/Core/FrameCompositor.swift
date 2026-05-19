import CoreImage
import CoreVideo
import CoreGraphics

/// Composites the screen frame (base layer) with the camera frame (picture-in-picture).
///
/// The screen frame drives the output frame rate: every screen frame triggers a
/// composite using the most recent camera frame. Camera frames only refresh the
/// cached frame, so the two sources can run at different rates without stutter.
final class FrameCompositor {
    /// Layout used for the next composite. Thread-safe; the UI writes it and the
    /// capture queue reads it.
    var pipState: PiPState {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _pipState }
        set { stateLock.lock(); _pipState = newValue; stateLock.unlock() }
    }

    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    private let stateLock = NSLock()
    private var _pipState = PiPState()

    private let cameraLock = NSLock()
    private var latestCameraImage: CIImage?

    private var pool: CVPixelBufferPool?
    private var poolWidth = 0
    private var poolHeight = 0

    private var cachedMask: CIImage?
    private var cachedMaskWidth = 0
    private var cachedMaskHeight = 0
    private var cachedMaskShape: PiPShape = .roundedRect

    /// Caches the latest camera frame. Called from the camera capture queue.
    func updateCameraFrame(_ pixelBuffer: CVPixelBuffer) {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        cameraLock.lock()
        latestCameraImage = image
        cameraLock.unlock()
    }

    /// Composites the cached camera frame on top of `screenFrame`.
    /// Returns `screenFrame` unchanged until the first camera frame arrives.
    func compose(screenFrame: CVPixelBuffer) -> CVPixelBuffer {
        cameraLock.lock()
        let camera = latestCameraImage
        cameraLock.unlock()
        guard let camera else { return screenFrame }

        let width = CVPixelBufferGetWidth(screenFrame)
        let height = CVPixelBufferGetHeight(screenFrame)

        stateLock.lock()
        let state = _pipState
        stateLock.unlock()

        let screenImage = CIImage(cvPixelBuffer: screenFrame)
        let cameraLayer = layout(camera: camera, state: state,
                                 width: CGFloat(width), height: CGFloat(height))
        let composed = cameraLayer
            .composited(over: screenImage)
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))

        guard let output = makePixelBuffer(width: width, height: height) else {
            return screenFrame
        }
        ciContext.render(composed, to: output)
        return output
    }

    /// Scales, rounds and positions the camera image according to the PiP layout.
    private func layout(camera: CIImage, state: PiPState,
                        width: CGFloat, height: CGFloat) -> CIImage {
        let extent = camera.extent
        guard extent.width > 0, extent.height > 0 else { return camera }

        switch state.mode {
        case .fullscreen:
            let scale = max(width / extent.width, height / extent.height)
            let tx = (width - extent.width * scale) / 2 - extent.origin.x * scale
            let ty = (height - extent.height * scale) / 2 - extent.origin.y * scale
            return camera
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .transformed(by: CGAffineTransform(translationX: tx, y: ty))

        case .floating:
            let overlayWidth = state.normalizedWidth * width
            let overlayHeight: CGFloat
            let scale: CGFloat
            switch state.shape {
            case .roundedRect:
                scale = overlayWidth / extent.width
                overlayHeight = extent.height * scale
            case .circle:
                overlayHeight = overlayWidth
                scale = max(overlayWidth / extent.width, overlayHeight / extent.height)
            }

            var scaled = camera
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .transformed(by: CGAffineTransform(translationX: -extent.origin.x * scale,
                                                   y: -extent.origin.y * scale))
            scaled = masked(scaled, shape: state.shape, width: overlayWidth, height: overlayHeight)

            let centerX = state.normalizedCenter.x * width
            // PiPState uses a top-left origin; Core Image uses bottom-left.
            let centerY = (1 - state.normalizedCenter.y) * height
            let tx = centerX - overlayWidth / 2
            let ty = centerY - overlayHeight / 2
            return scaled.transformed(by: CGAffineTransform(translationX: tx, y: ty))
        }
    }

    /// Applies the chosen floating-overlay mask to a camera layer occupying
    /// `(0, 0, width, height)`.
    private func masked(_ image: CIImage, shape: PiPShape, width: CGFloat, height: CGFloat) -> CIImage {
        let pixelWidth = Int(width.rounded())
        let pixelHeight = Int(height.rounded())
        guard pixelWidth > 0, pixelHeight > 0 else { return image }

        guard let mask = overlayMask(shape: shape, width: pixelWidth, height: pixelHeight) else {
            return image
        }
        return image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: mask,
        ])
    }

    /// A white shape on black, used as an alpha mask. Cached by size and shape.
    private func overlayMask(shape: PiPShape, width: Int, height: Int) -> CIImage? {
        if let cachedMask,
           cachedMaskWidth == width,
           cachedMaskHeight == height,
           cachedMaskShape == shape {
            return cachedMask
        }
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: 1, alpha: 1)
        switch shape {
        case .roundedRect:
            let radius = min(CGFloat(width), CGFloat(height)) * 0.07
            context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height),
                                   cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.fillPath()
        case .circle:
            context.fillEllipse(in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        guard let cgImage = context.makeImage() else { return nil }

        let mask = CIImage(cgImage: cgImage)
        cachedMask = mask
        cachedMaskWidth = width
        cachedMaskHeight = height
        cachedMaskShape = shape
        return mask
    }

    /// Returns a pooled BGRA pixel buffer, recreating the pool on size change.
    private func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        if pool == nil || poolWidth != width || poolHeight != height {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ]
            var newPool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &newPool)
            pool = newPool
            poolWidth = width
            poolHeight = height
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }
}
