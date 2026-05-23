import CoreGraphics

/// How the camera image is laid out within the composed frame.
enum PiPMode {
    /// Camera fills the whole output frame.
    case fullscreen
    /// Camera is a small draggable overlay on top of the screen frame.
    case floating
}

/// Visual shape of the floating camera overlay.
enum PiPShape {
    case roundedRect
    case circle
}

/// Shared layout state for the camera picture-in-picture overlay.
///
/// The floating window UI and the `FrameCompositor` both read this so that what
/// the user sees in the draggable preview matches what is written to the file.
struct PiPState {
    var mode: PiPMode = .floating
    var shape: PiPShape = .roundedRect

    /// Normalized center (0...1) of the overlay within the composed frame.
    var normalizedCenter: CGPoint = CGPoint(x: 0.82, y: 0.82)

    /// Overlay width as a fraction (0...1) of the composed frame width.
    var normalizedWidth: CGFloat = 0.14
}
