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
