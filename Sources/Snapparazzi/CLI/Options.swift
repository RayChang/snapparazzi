import CoreGraphics

enum CaptureFormat: String {
    case jpg
    case heic
    case png

    static func parse(_ value: String) -> CaptureFormat? {
        switch value.lowercased() {
        case "jpg", "jpeg":
            return .jpg
        case "heic":
            return .heic
        case "png":
            return .png
        default:
            return nil
        }
    }
}

enum RunMode: String {
    case capture
    case list
}

struct CLIOptions {
    var mode: RunMode = .capture
    var windowID: CGWindowID?
    var interval: Double?
    var outputPath: String?
    var format: CaptureFormat = .jpg
    var maxDimension: Int?
}

enum AudioMode: String, CaseIterable {
    case none, system, mic, both

    var capturesSystem: Bool { self == .system || self == .both }
    var capturesMicrophone: Bool { self == .mic || self == .both }
}

enum VideoCodec: String {
    case h264, hevc
}

struct RecordingOptions {
    var windowID: CGWindowID?
    var audio: AudioMode = .none
    var fps = 30
    var codec: VideoCodec = .h264
    var duration: Double?
    var outputPath: String?
    var maxDimension: Int?
}

enum CLIAction {
    case help
    case version
    case run(CLIOptions)
    case recordingHelp
    case record(RecordingOptions)
}

struct CLIUsageError: Error {
    let message: String
}
