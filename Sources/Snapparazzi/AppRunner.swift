import Foundation
import Darwin

private func run(options: CLIOptions) -> Int32 {
    print("📸 Snapparazzi — 專業地打擾你的視窗 / professionally bothering your windows")
    guard ensureScreenCapturePermission() else { return 1 }
    let windows = discoverWindows()
    guard !windows.isEmpty else {
        fputs("目前找不到可截取視窗 / No capturable visible windows were found.\n", stderr)
        return 1
    }

    if options.mode == .list {
        printWindowList(windows)
        return 0
    }
    return runCapture(options: options, windows: windows)
}

func appMain() -> Int32 {
    let arguments = CommandLine.arguments
    if arguments.count > 1, arguments[1] == "--test" {
        runTestCommand(arguments: arguments)
    }

    do {
        switch try parseCommandLine(Array(arguments.dropFirst())) {
        case .help:
            print(helpText)
            return 0
        case .version:
            print("snapparazzi \(snapparazziVersion)")
            return 0
        case .run(let options):
            return run(options: options)
        case .recordingHelp:
            print(recordingHelpText)
            return 0
        case .record(let options):
            runRecordCommand(options)
        case .updateHelp:
            print(updateHelpText)
            return 0
        case .update(let checkOnly):
            return runUpdate(checkOnly: checkOnly)
        }
    } catch let error as CLIUsageError {
        fputs("錯誤 / Error: \(error.message)\n", stderr)
        fputs("執行 snapparazzi --help 查看說明 / Run snapparazzi --help for usage.\n", stderr)
        return 2
    } catch {
        fputs("錯誤 / Error: \(error.localizedDescription)\n", stderr)
        return 2
    }
}
