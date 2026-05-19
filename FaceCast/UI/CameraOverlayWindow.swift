import AppKit
import AVFoundation

/// Layer-backed view that renders the live camera preview.
final class CameraPreviewView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    var onDoubleClick: (() -> Void)?
    var allowsDrag = true

    private var previewShape: PiPShape = .roundedRect
    private var roundedRectRadius: CGFloat = 26

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.masksToBounds = true
        previewLayer.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func makeBackingLayer() -> CALayer {
        previewLayer
    }

    override func layout() {
        super.layout()
        applyChrome()
    }

    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        previewLayer.videoGravity = gravity
    }

    /// Updates the preview chrome to match the current floating overlay style.
    func setShape(_ shape: PiPShape, cornerRadius: CGFloat) {
        previewShape = shape
        roundedRectRadius = cornerRadius
        applyChrome()
    }

    private func applyChrome() {
        switch previewShape {
        case .roundedRect:
            previewLayer.cornerRadius = roundedRectRadius
        case .circle:
            previewLayer.cornerRadius = min(bounds.width, bounds.height) / 2
        }

        let hasRadius = previewLayer.cornerRadius > 0
        previewLayer.borderWidth = hasRadius ? 1.25 : 0
        previewLayer.borderColor = NSColor.white.withAlphaComponent(0.78).cgColor
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
        } else if allowsDrag {
            window?.performDrag(with: event)
        }
    }
}

/// Small bottom-right grip that resizes the overlay panel.
///
/// Handling the mouse here also suppresses the parent's window drag in this
/// region, so the grip resizes instead of moving the window.
final class ResizeHandleView: NSView {
    var onDrag: ((NSEvent) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.26).cgColor
        layer?.cornerRadius = 7
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.42).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {
        onDrag?(event)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }
}

final class OverlayAccessoryButton: NSButton {
    var actionHandler: (() -> Void)?

    init(symbolName: String, tooltip: String) {
        super.init(frame: .zero)
        bezelStyle = .regularSquare
        isBordered = false
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)
        contentTintColor = NSColor.white.withAlphaComponent(0.96)
        imageScaling = .scaleProportionallyDown
        toolTip = tooltip
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.24).cgColor
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        target = self
        action = #selector(handleTap)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.24).cgColor
    }

    @objc private func handleTap() {
        actionHandler?()
    }
}

/// Borderless floating panel that shows the live camera preview and acts as the
/// drag handle for the picture-in-picture overlay.
///
/// - Important: this window is excluded from screen capture by
///   `ScreenCaptureManager`, so it is never recorded into the frame.
final class CameraOverlayWindow: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 158),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
}
