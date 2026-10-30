import Foundation

enum AudioSource: String, CaseIterable {
    case system
    case microphone
}

// Why recording stopped. A later, more severe reason replaces an earlier one, so a
// failure that happens while a normal stop is in progress is never hidden.
enum RecordingStopReason: Equatable {
    case interrupt
    case terminate
    case durationReached
    case windowClosed
    case diskLow
    case failure(String)

    var severity: Int {
        switch self {
        case .interrupt, .terminate, .durationReached: return 0
        case .windowClosed: return 1
        case .diskLow, .failure: return 2
        }
    }

    var isSuccess: Bool { severity == 0 }

    var summary: String {
        switch self {
        case .interrupt: return "Ctrl-C"
        case .terminate: return "SIGTERM"
        case .durationReached: return "--duration"
        case .windowClosed: return "視窗已關閉 / window closed"
        case .diskLow: return "磁碟空間不足 / low disk space"
        case .failure(let message): return message
        }
    }

    func merged(with other: RecordingStopReason) -> RecordingStopReason {
        other.severity > severity ? other : self
    }
}

struct RecordingError: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct AudioTrackStats {
    var buffers = 0
    var paddedSamples: Int64 = 0
    var trimmedSamples: Int64 = 0
    var driftCorrection: Int64 = 0  // frames inserted (+) or dropped (-) to follow the device clock
    var drift = 0.0                 // last estimate of how far timestamps lagged real time (s)
}

struct RecordingStats {
    var sourceFrames = 0
    var writtenFrames = 0
    var droppedSlots = 0      // slots passed over because a tick came late
    var writerBusySlots = 0   // slots dropped because the encoder was not ready
    var blackFrames = 0
    var audio: [AudioSource: AudioTrackStats] = [:]
}
