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

enum CLIAction {
    case help
    case version
    case run(CLIOptions)
}

struct CLIUsageError: Error {
    let message: String
}
