import Foundation
import CoreGraphics
import Darwin

private func testArgumentDescription(_ action: CLIAction) -> String {
    switch action {
    case .help:
        return "mode=help"
    case .version:
        return "mode=version"
    case .run(let options):
        let window = options.windowID.map(String.init) ?? "nil"
        let interval = options.interval.map(stableNumber) ?? "nil"
        let output = options.outputPath ?? "default"
        let maxDimension = options.maxDimension.map(String.init) ?? "nil"
        return "mode=\(options.mode.rawValue);window=\(window);interval=\(interval);output=\(output);format=\(options.format.rawValue);maxDimension=\(maxDimension)"
    }
}

func runTestCommand(arguments: [String]) -> Never {
    guard arguments.count >= 3, arguments[1] == "--test" else {
        fputs("Invalid test command\n", stderr)
        exit(2)
    }

    switch arguments[2] {
    case "sanitize":
        guard arguments.count == 4 else { exit(2) }
        print(sanitizedFileComponent(arguments[3]))
    case "filename":
        guard arguments.count == 7,
              let sequence = Int(arguments[5]),
              let format = CaptureFormat.parse(arguments[6]) else { exit(2) }
        print(screenshotFilename(
            appName: arguments[3],
            timestamp: arguments[4],
            sequence: sequence,
            format: format
        ))
    case "interval":
        guard arguments.count == 4 else { exit(2) }
        print(parsedInterval(arguments[3]).map(stableNumber) ?? "INVALID")
    case "selection":
        guard arguments.count == 5, let itemCount = Int(arguments[3]) else { exit(2) }
        print(parsedSelection(arguments[4], itemCount: itemCount).map(String.init) ?? "INVALID")
    case "next-tick":
        guard arguments.count == 5,
              let interval = Double(arguments[3]),
              let elapsed = Double(arguments[4]) else { exit(2) }
        print(stableNumber(nextTickOffset(interval: interval, elapsed: elapsed)))
    case "arguments":
        do {
            let action = try parseArguments(Array(arguments.dropFirst(3)))
            print(testArgumentDescription(action))
        } catch let error as CLIUsageError {
            print("ERROR: \(error.message)")
            exit(2)
        } catch {
            exit(2)
        }
    case "capture-arguments":
        guard arguments.count == 6,
              let windowID = parseWindowID(arguments[3]),
              let format = CaptureFormat.parse(arguments[4]) else { exit(2) }
        let destination = URL(fileURLWithPath: arguments[5])
        print(screenshotArguments(
            windowID: windowID,
            format: format,
            destination: destination
        ).joined(separator: "|"))
    case "resize-arguments":
        guard arguments.count == 5,
              let maxDimension = Int(arguments[3]),
              maxDimension > 0 else { exit(2) }
        let destination = URL(fileURLWithPath: arguments[4])
        print(resizeArguments(
            maxDimension: maxDimension,
            destination: destination
        ).joined(separator: "|"))
    case "resize-needed":
        guard arguments.count == 6,
              let width = Int(arguments[3]), width > 0,
              let height = Int(arguments[4]), height > 0,
              let maxDimension = Int(arguments[5]), maxDimension > 0 else { exit(2) }
        print(dimensionsNeedResize(
            width: width,
            height: height,
            maxDimension: maxDimension
        ) ? "RESIZE" : "SKIP")
    default:
        fputs("Unknown test command\n", stderr)
        exit(2)
    }
    exit(0)
}
