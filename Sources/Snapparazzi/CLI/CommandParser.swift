import Foundation
import CoreGraphics

private let defaultInterval = 2.0
private let minimumInterval = 0.5

func parsedInterval(_ input: String, useDefaultForEmpty: Bool = true) -> Double? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty, useDefaultForEmpty {
        return defaultInterval
    }

    guard let value = Double(trimmed), value.isFinite, value >= minimumInterval else {
        return nil
    }
    return value
}

func parseWindowID(_ input: String) -> CGWindowID? {
    guard let value = UInt32(input), value > 0 else { return nil }
    return CGWindowID(value)
}

func parseArguments(_ arguments: [String]) throws -> CLIAction {
    var options = CLIOptions()
    var sawList = false
    var sawWindow = false
    var sawInterval = false
    var sawOutput = false
    var sawFormat = false
    var sawMaxDimension = false
    var index = 0

    func requiredValue(after option: String) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw CLIUsageError(message: "選項缺少值 / Missing value for \(option)")
        }
        return arguments[valueIndex]
    }

    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "-h", "--help":
            return .help

        case "-V", "--version":
            return .version

        case "-l", "--list":
            guard !sawList else {
                throw CLIUsageError(message: "選項重複 / Duplicate option: --list")
            }
            sawList = true
            options.mode = .list

        case "-w", "--window":
            guard !sawWindow else {
                throw CLIUsageError(message: "選項重複 / Duplicate option: --window")
            }
            let rawValue = try requiredValue(after: argument)
            guard let windowID = parseWindowID(rawValue) else {
                throw CLIUsageError(message: "無效 window ID / Invalid window ID: \(rawValue)")
            }
            sawWindow = true
            options.windowID = windowID
            index += 1

        case "-i", "--interval":
            guard !sawInterval else {
                throw CLIUsageError(message: "選項重複 / Duplicate option: --interval")
            }
            let rawValue = try requiredValue(after: argument)
            guard let interval = parsedInterval(rawValue, useDefaultForEmpty: false) else {
                throw CLIUsageError(
                    message: "無效間隔 / Invalid interval: \(rawValue)（minimum 0.5 seconds）"
                )
            }
            sawInterval = true
            options.interval = interval
            index += 1

        case "-o", "--output":
            guard !sawOutput else {
                throw CLIUsageError(message: "選項重複 / Duplicate option: --output")
            }
            let rawValue = try requiredValue(after: argument)
            guard !rawValue.isEmpty else {
                throw CLIUsageError(message: "輸出目錄不可為空 / Output directory cannot be empty")
            }
            sawOutput = true
            options.outputPath = rawValue
            index += 1

        case "-f", "--format":
            guard !sawFormat else {
                throw CLIUsageError(message: "選項重複 / Duplicate option: --format")
            }
            let rawValue = try requiredValue(after: argument)
            guard let format = CaptureFormat.parse(rawValue) else {
                throw CLIUsageError(
                    message: "不支援的圖片格式 / Unsupported image format: \(rawValue)（choose jpg, heic, or png）"
                )
            }
            sawFormat = true
            options.format = format
            index += 1

        case "-m", "--max-dimension":
            guard !sawMaxDimension else {
                throw CLIUsageError(message: "選項重複 / Duplicate option: --max-dimension")
            }
            let rawValue = try requiredValue(after: argument)
            guard let maxDimension = Int(rawValue), maxDimension > 0 else {
                throw CLIUsageError(
                    message: "無效最大尺寸 / Invalid maximum dimension: \(rawValue)（--max-dimension must be a positive integer）"
                )
            }
            sawMaxDimension = true
            options.maxDimension = maxDimension
            index += 1

        default:
            throw CLIUsageError(message: "未知選項 / Unknown option: \(argument)")
        }
        index += 1
    }

    if sawList, sawWindow || sawInterval || sawOutput || sawFormat || sawMaxDimension {
        throw CLIUsageError(
            message: "--list 不可與截圖選項同時使用 / --list cannot be combined with --window, --interval, --output, --format, or --max-dimension"
        )
    }

    return .run(options)
}

// Only the first token may name a subcommand; anything else keeps the original
// screenshot parser, so every existing command line behaves exactly as before.
func parseCommandLine(_ arguments: [String]) throws -> CLIAction {
    switch arguments.first {
    case "capture": return try parseArguments(Array(arguments.dropFirst()))
    case "record": return try parseRecordingArguments(Array(arguments.dropFirst()))
    default: return try parseArguments(arguments)
    }
}

private let recordingMinimumFPS = 1
private let recordingMaximumFPS = 60

// Plain decimal seconds such as 3600, 0.5 or .5 (no exponent, hex, nan or inf).
private func parsedRecordingDuration(_ input: String) -> Double? {
    guard input.range(of: #"^([0-9]+(\.[0-9]*)?|\.[0-9]+)$"#, options: .regularExpression) != nil,
          let value = Double(input), value.isFinite, (0.5...86_400).contains(value) else {
        return nil
    }
    return value
}

func parseRecordingArguments(_ arguments: [String]) throws -> CLIAction {
    var options = RecordingOptions()
    var seen = Set<String>()
    var index = 0

    func value(for option: String) throws -> String {
        guard !seen.contains(option) else {
            throw CLIUsageError(message: "選項重複 / Duplicate option: \(option)")
        }
        seen.insert(option)
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw CLIUsageError(message: "選項缺少值 / Missing value for \(option)")
        }
        index += 1
        return arguments[valueIndex]
    }

    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "-h", "--help":
            return .recordingHelp

        case "-w", "--window":
            let raw = try value(for: "--window")
            guard let windowID = parseWindowID(raw) else {
                throw CLIUsageError(message: "無效 window ID / Invalid window ID: \(raw)")
            }
            options.windowID = windowID

        case "--audio":
            let raw = try value(for: "--audio")
            guard let audio = AudioMode(rawValue: raw) else {
                throw CLIUsageError(message: "無效音訊模式 / Invalid audio mode: \(raw)（choose none, system, mic, or both）")
            }
            options.audio = audio

        case "--fps":
            let raw = try value(for: "--fps")
            guard let fps = Int(raw), (recordingMinimumFPS...recordingMaximumFPS).contains(fps) else {
                throw CLIUsageError(message: "無效 fps / Invalid fps: \(raw)（integer 1–60）")
            }
            options.fps = fps

        case "--codec":
            let raw = try value(for: "--codec")
            guard let codec = VideoCodec(rawValue: raw) else {
                throw CLIUsageError(message: "不支援的影片編碼 / Unsupported video codec: \(raw)（choose h264 or hevc）")
            }
            options.codec = codec

        case "--duration":
            let raw = try value(for: "--duration")
            guard let duration = parsedRecordingDuration(raw) else {
                throw CLIUsageError(message: "無效錄影長度 / Invalid duration: \(raw)（decimal seconds 0.5–86400）")
            }
            options.duration = duration

        case "-o", "--output":
            let raw = try value(for: "--output")
            guard !raw.isEmpty, (raw as NSString).pathExtension.lowercased() == "mp4" else {
                throw CLIUsageError(message: "錄影輸出必須是 .mp4 檔案 / Recording output must be a .mp4 file: \(raw)")
            }
            options.outputPath = raw

        case "-m", "--max-dimension":
            let raw = try value(for: "--max-dimension")
            guard let maxDimension = Int(raw), (2...8192).contains(maxDimension) else {
                throw CLIUsageError(message: "無效最大尺寸 / Invalid maximum dimension: \(raw)（integer 2–8192）")
            }
            options.maxDimension = maxDimension

        case "-i", "--interval", "-f", "--format", "-l", "--list", "-V", "--version":
            throw CLIUsageError(message: "record 不支援此選項 / Not supported by record: \(argument)")

        default:
            throw CLIUsageError(message: "未知選項 / Unknown option: \(argument)")
        }
        index += 1
    }

    guard options.windowID != nil else {
        throw CLIUsageError(message: "record 需要 --window；先用 snapparazzi --list 查 ID / record requires --window; find IDs with snapparazzi --list")
    }
    return .record(options)
}
