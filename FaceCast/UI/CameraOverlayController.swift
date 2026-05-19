import AppKit
import AVFoundation

/// Owns the camera overlay panel: shows the live preview and translates the
/// panel's on-screen position/size into normalized PiP layout values.
///
/// Double-clicking the preview asks the coordinator to toggle the PiP mode
/// (floating ⇄ fullscreen); the controller then resizes the panel accordingly,
/// remembering the floating frame so it can be restored.
@MainActor
final class CameraOverlayController: NSObject, NSWindowDelegate {
    /// Called with (normalizedCenter, normalizedWidth) whenever the panel moves
    /// or resizes. Coordinates use a top-left origin.
    var onLayoutChanged: ((CGPoint, CGFloat) -> Void)?

    /// Called when the user double-clicks the preview, asking to toggle modes.
    var onRequestModeToggle: (() -> Void)?
    var onRequestMuteToggle: (() -> Void)?
    var onRequestShapeToggle: (() -> Void)?
    var onRequestHide: (() -> Void)?

    private(set) var isVisible = false

    private let panel = CameraOverlayWindow()
    private let previewView = CameraPreviewView()
    private let resizeHandle = ResizeHandleView()
    private let accessoryBar = NSVisualEffectView()
    private let muteButton = OverlayAccessoryButton(symbolName: "mic.fill", tooltip: "静音麦克风")
    private let shapeButton = OverlayAccessoryButton(symbolName: "circle.dashed", tooltip: "切换圆形气泡")
    private let hideButton = OverlayAccessoryButton(symbolName: "eye.slash", tooltip: "隐藏浮窗")
    private var aspectRatio: CGFloat = 16.0 / 9.0
    private var mode: PiPMode = .floating
    private var shape: PiPShape = .roundedRect
    private var savedFloatingFrame: NSRect?
    private var accessoryTrailingConstraint: NSLayoutConstraint?
    private var accessoryCenterXConstraint: NSLayoutConstraint?
    private var accessoryTopConstraint: NSLayoutConstraint?

    private let floatingCornerRadius: CGFloat = 26

    init(session: AVCaptureSession) {
        super.init()

        previewView.previewLayer.session = session
        previewView.onDoubleClick = { [weak self] in
            self?.onRequestModeToggle?()
        }
        previewView.setShape(.roundedRect, cornerRadius: floatingCornerRadius)

        panel.contentView = previewView
        panel.delegate = self

        accessoryBar.translatesAutoresizingMaskIntoConstraints = false
        accessoryBar.blendingMode = .withinWindow
        accessoryBar.material = .hudWindow
        accessoryBar.state = .active
        accessoryBar.wantsLayer = true
        accessoryBar.layer?.cornerRadius = 17
        accessoryBar.layer?.masksToBounds = true

        let accessoryStack = NSStackView(views: [muteButton, shapeButton, hideButton])
        accessoryStack.orientation = .horizontal
        accessoryStack.spacing = 8
        accessoryStack.translatesAutoresizingMaskIntoConstraints = false

        for button in [muteButton, shapeButton, hideButton] {
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 30),
                button.heightAnchor.constraint(equalToConstant: 30),
            ])
        }

        previewView.addSubview(accessoryBar)
        accessoryBar.addSubview(accessoryStack)
        accessoryTopConstraint = accessoryBar.topAnchor.constraint(equalTo: previewView.topAnchor, constant: 12)
        accessoryTrailingConstraint = accessoryBar.trailingAnchor.constraint(equalTo: previewView.trailingAnchor, constant: -12)
        accessoryCenterXConstraint = accessoryBar.centerXAnchor.constraint(equalTo: previewView.centerXAnchor)

        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        previewView.addSubview(resizeHandle)
        NSLayoutConstraint.activate([
            accessoryTopConstraint!,
            accessoryTrailingConstraint!,
            accessoryStack.leadingAnchor.constraint(equalTo: accessoryBar.leadingAnchor, constant: 8),
            accessoryStack.trailingAnchor.constraint(equalTo: accessoryBar.trailingAnchor, constant: -8),
            accessoryStack.topAnchor.constraint(equalTo: accessoryBar.topAnchor, constant: 8),
            accessoryStack.bottomAnchor.constraint(equalTo: accessoryBar.bottomAnchor, constant: -8),
            resizeHandle.widthAnchor.constraint(equalToConstant: 22),
            resizeHandle.heightAnchor.constraint(equalToConstant: 22),
            resizeHandle.trailingAnchor.constraint(equalTo: previewView.trailingAnchor, constant: -8),
            resizeHandle.bottomAnchor.constraint(equalTo: previewView.bottomAnchor, constant: -8),
        ])
        resizeHandle.onDrag = { [weak self] event in
            self?.resize(with: event)
        }
        muteButton.actionHandler = { [weak self] in
            self?.onRequestMuteToggle?()
        }
        shapeButton.actionHandler = { [weak self] in
            self?.onRequestShapeToggle?()
        }
        hideButton.actionHandler = { [weak self] in
            self?.onRequestHide?()
        }
        updateAccessoryLayout()
    }

    /// Updates the camera aspect ratio used when sizing the panel.
    func setCameraResolution(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        aspectRatio = size.width / size.height
    }

    /// Shows the panel positioned to match the given normalized layout.
    func show(normalizedCenter: CGPoint, normalizedWidth: CGFloat) {
        guard let screen = NSScreen.main else { return }
        panel.setFrame(panelFrame(center: normalizedCenter,
                                  width: normalizedWidth,
                                  screen: screen),
                       display: true)
        panel.orderFront(nil)
        isVisible = true
        applyMode(mode)
        reportLayout()
    }

    func hide() {
        panel.orderOut(nil)
        isVisible = false
    }

    func setMicrophoneMuted(_ isMuted: Bool) {
        let symbolName = isMuted ? "mic.slash.fill" : "mic.fill"
        muteButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: muteButton.toolTip)
        muteButton.toolTip = isMuted ? "取消麦克风静音" : "静音麦克风"
    }

    func setShape(_ newShape: PiPShape) {
        shape = newShape
        let symbolName = newShape == .circle ? "rectangle.roundedtop.fill" : "circle.dashed"
        shapeButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: shapeButton.toolTip)
        shapeButton.toolTip = newShape == .circle ? "切回标准比例" : "切换圆形气泡"
        updateAccessoryLayout()
        guard isVisible else { return }

        if mode == .floating {
            adjustFloatingFrameForShape()
        } else {
            previewView.setShape(.roundedRect, cornerRadius: 0)
        }
    }

    /// Resizes the panel and adjusts chrome to match the new PiP mode.
    func applyMode(_ newMode: PiPMode) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            apply(mode: newMode)
        }
    }

    private func apply(mode newMode: PiPMode) {
        switch newMode {
        case .fullscreen:
            if mode != .fullscreen {
                savedFloatingFrame = panel.frame
            }
            if let screen = panel.screen ?? NSScreen.main {
                panel.animator().setFrame(screen.visibleFrame, display: true)
            }
            previewView.setShape(.roundedRect, cornerRadius: 0)
            previewView.allowsDrag = false
            resizeHandle.isHidden = true

        case .floating:
            if let saved = savedFloatingFrame {
                panel.animator().setFrame(saved, display: true)
            }
            previewView.setShape(shape, cornerRadius: floatingCornerRadius)
            previewView.allowsDrag = true
            resizeHandle.isHidden = false
        }
        mode = newMode
        updateAccessoryLayout()
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        reportLayout()
    }

    func windowDidResize(_ notification: Notification) {
        reportLayout()
    }

    // MARK: - Private

    private func panelFrame(center: CGPoint, width: CGFloat, screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let panelWidth = min(max(width * screenFrame.width, 150), screenFrame.width * 0.5)
        let panelHeight = shape == .circle ? panelWidth : panelWidth / aspectRatio
        let midX = screenFrame.minX + center.x * screenFrame.width
        let midY = screenFrame.minY + (1 - center.y) * screenFrame.height
        return NSRect(x: midX - panelWidth / 2,
                      y: midY - panelHeight / 2,
                      width: panelWidth,
                      height: panelHeight)
    }

    private func resize(with event: NSEvent) {
        guard mode == .floating else { return }
        var frame = panel.frame
        let top = frame.maxY
        let newWidth = min(max(180, frame.width + event.deltaX), 500)
        let newHeight = shape == .circle ? newWidth : newWidth / aspectRatio
        frame.size = NSSize(width: newWidth, height: newHeight)
        frame.origin.y = top - newHeight
        panel.setFrame(frame, display: true)
        reportLayout()
    }

    private func adjustFloatingFrameForShape() {
        guard mode == .floating else { return }
        var frame = panel.frame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let width = max(frame.width, frame.height)

        if shape == .circle {
            let square = min(max(width, 180), 360)
            frame.size = NSSize(width: square, height: square)
        } else {
            let adjustedWidth = min(max(width, 180), 500)
            frame.size = NSSize(width: adjustedWidth, height: adjustedWidth / aspectRatio)
        }

        frame.origin = CGPoint(x: center.x - frame.width / 2, y: center.y - frame.height / 2)
        savedFloatingFrame = frame

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().setFrame(frame, display: true)
        }
        previewView.setShape(shape, cornerRadius: floatingCornerRadius)
        reportLayout()
    }

    private func updateAccessoryLayout() {
        let useCenteredLayout = mode == .floating && shape == .circle
        accessoryTrailingConstraint?.isActive = !useCenteredLayout
        accessoryCenterXConstraint?.isActive = useCenteredLayout
        accessoryTopConstraint?.constant = useCenteredLayout ? 24 : 12
    }

    private func reportLayout() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let screenFrame = screen.frame
        guard screenFrame.width > 0, screenFrame.height > 0 else { return }

        let panelFrame = panel.frame
        let centerX = (panelFrame.midX - screenFrame.minX) / screenFrame.width
        let centerY = 1 - (panelFrame.midY - screenFrame.minY) / screenFrame.height
        let width = panelFrame.width / screenFrame.width
        onLayoutChanged?(CGPoint(x: centerX, y: centerY), width)
    }
}
