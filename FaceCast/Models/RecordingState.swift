import Foundation

/// State machine for a recording session.
enum RecordingState: Equatable {
    case idle
    case countingDown(secondsRemaining: Int)
    case recording
    case paused
    case stopping
}
