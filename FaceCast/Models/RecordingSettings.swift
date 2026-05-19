import Foundation
import AVFoundation

/// Output container format.
enum VideoContainer: String, CaseIterable, Identifiable {
    case mp4
    case mov

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mp4: return "MP4 (H.264)"
        case .mov: return "MOV (H.264)"
        }
    }

    var fileExtension: String { rawValue }

    var avFileType: AVFileType {
        switch self {
        case .mp4: return .mp4
        case .mov: return .mov
        }
    }
}

/// User-configurable options for a recording session.
struct RecordingSettings {
    var container: VideoContainer = .mp4
    var frameRate: Int = 60
    var captureMicrophone: Bool = true
    var captureSystemAudio: Bool = true
    var countdownEnabled: Bool = true

    var outputDirectory: URL = FileManager.default
        .urls(for: .moviesDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
}
