import Foundation
import CoreGraphics
import Dispatch
import Darwin

private let snapparazziVersion = "1.1.0"
private let defaultInterval = 2.0
private let minimumInterval = 0.5

private enum CaptureFormat: String {
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

private let helpText = """
Snapparazzi — a polite paparazzo for your macOS windows.
Snapparazzi — 專門定時捕捉 macOS 視窗的 CLI 工具。

用法 / USAGE
  snapparazzi [options]
  snapparazzi --list
  snapparazzi --window <id> [--interval <seconds>] [--output <directory>]
               [--format <jpg|heic|png>] [--max-dimension <pixels>]

選項 / OPTIONS
  -l, --list                 列出目前可截取的視窗與 ID 後退出。
                             List capturable windows and their IDs, then exit.
  -w, --window <id>          直接選擇 window ID；未提供時顯示互動選單。
                             Select a window ID; omit it for the interactive picker.
  -i, --interval <seconds>   截圖間隔，最低 0.5 秒；未提供時互動詢問，預設 2 秒。
                             Capture interval, minimum 0.5 seconds. If omitted,
                             Snapparazzi prompts interactively with a 2-second default.
  -o, --output <directory>   Session 輸出根目錄。
                             Session output root. Default: ~/Snapparazzi/captures
  -f, --format <jpg|heic|png>
                             圖片格式；jpg 體積較小、heic 最省空間、png 無損。
                             Image format: compact jpg, smaller heic, or lossless png.
                             Default: jpg
  -m, --max-dimension <pixels>
                             等比例縮小，讓最長邊不超過指定像素；不會放大圖片。
                             Fit the longest edge within this size without upscaling.
                             By default, the original dimensions are preserved.
  -h, --help                 顯示這份完整說明並退出。
                             Show this full help and exit.
  -V, --version              顯示版本並退出。
                             Show the version and exit.

互動模式 / INTERACTIVE MODE
  不帶參數執行時，Snapparazzi 會列出所有可見視窗，讓你單選一個視窗，
  再詢問截圖間隔。按 Ctrl-C 會乾淨停止並顯示執行摘要。

  With no options, Snapparazzi lists all visible windows, prompts for one window,
  then asks for the interval. Press Ctrl-C to stop cleanly and print a summary.

螢幕錄製 / Screen Recording
  首次執行時，請在「系統設定 → 隱私權與安全性 → 螢幕與系統錄音」
  允許目前使用的 Terminal，然後重新執行命令。

  On first use, allow your terminal app under System Settings → Privacy & Security →
  Screen & System Audio Recording, then run the command again.

輸出 / OUTPUT
  每次執行會建立：<output>/YYYYMMDD-HHMMSS-<PID>/
  檔名格式：<app_name>_<YYYYMMDD-HHMMSS>_<sequence>.<format>
  只有成功寫入的圖片才會遞增六位數流水號。

  Each run creates: <output>/YYYYMMDD-HHMMSS-<PID>/
  Files use: <app_name>_<YYYYMMDD-HHMMSS>_<sequence>.<format>
  The six-digit sequence advances only after an image is written successfully.

範例 / EXAMPLES
  snapparazzi
  snapparazzi --list
  snapparazzi --window 12345 --interval 1.5
  snapparazzi -w 12345 -i 2 -o ~/Pictures/Snapparazzi
  snapparazzi -w 12345 -i 60 -f heic
  snapparazzi -w 12345 -i 1 -f jpg -m 1280

  若要同時截取多個視窗，請在 multiple Terminal tabs/windows 中各啟動一個程序；
  每個程序可使用不同間隔與輸出根目錄。

  To capture several windows at once, run one process in each of multiple Terminal
  tabs/windows. Every process may use a different interval and output root.

結束碼 / EXIT STATUS
  0  正常完成、顯示 help/version/list，或由 Ctrl-C 停止。
     Success, help/version/list output, or clean Ctrl-C shutdown.
  1  權限、視窗、目錄或截圖執行錯誤。
     Permission, window, directory, or capture runtime failure.
  2  無效或互相衝突的命令列參數。
     Invalid or conflicting command-line arguments.
"""

private enum RunMode: String {
    case capture
    case list
}

private struct CLIOptions {
    var mode: RunMode = .capture
    var windowID: CGWindowID?
    var interval: Double?
    var outputPath: String?
    var format: CaptureFormat = .jpg
    var maxDimension: Int?
}

private enum CLIAction {
    case help
    case version
    case run(CLIOptions)
}

private struct CLIUsageError: Error {
    let message: String
}

private struct WindowTarget {
    let id: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let title: String

    var displayTitle: String {
        let normalized = title
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        return normalized.isEmpty ? "無標題 / Untitled" : normalized
    }
}

private enum CaptureResult {
    case success
    case failure(String)
    case cancelled
}

private struct CaptureStats {
    var succeeded = 0
    var failed = 0
    var unavailable = 0
    var scheduleTicksSkipped = 0
}

private final class StopController: @unchecked Sendable {
    private let lock = NSLock()
    private let wakeSemaphore = DispatchSemaphore(value: 0)
    private var stopRequested = false
    private var activeProcess: Process?

    var shouldStop: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopRequested
    }

    @discardableResult
    func requestStop() -> Bool {
        lock.lock()
        let isFirstRequest = !stopRequested
        stopRequested = true
        let process = activeProcess
        lock.unlock()

        process?.interrupt()
        wakeSemaphore.signal()
        return isFirstRequest
    }

    func register(_ process: Process) {
        lock.lock()
        activeProcess = process
        let shouldInterrupt = stopRequested
        lock.unlock()

        if shouldInterrupt {
            process.interrupt()
        }
    }

    func unregister(_ process: Process) {
        lock.lock()
        if activeProcess === process {
            activeProcess = nil
        }
        lock.unlock()
    }

    func wait(until deadline: DispatchTime) {
        guard !shouldStop else { return }
        _ = wakeSemaphore.wait(timeout: deadline)
    }
}

private func parsedInterval(_ input: String, useDefaultForEmpty: Bool = true) -> Double? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty, useDefaultForEmpty {
        return defaultInterval
    }

    guard let value = Double(trimmed), value.isFinite, value >= minimumInterval else {
        return nil
    }
    return value
}

private func parseWindowID(_ input: String) -> CGWindowID? {
    guard let value = UInt32(input), value > 0 else { return nil }
    return CGWindowID(value)
}

private func parseArguments(_ arguments: [String]) throws -> CLIAction {
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

private func sanitizedFileComponent(_ value: String) -> String {
    let controls = CharacterSet.controlCharacters
    var result = ""
    for scalar in value.unicodeScalars {
        if scalar == "/" || scalar == ":" || controls.contains(scalar) {
            result.append("_")
        } else {
            result.unicodeScalars.append(scalar)
        }
    }

    result = result.trimmingCharacters(in: .whitespacesAndNewlines)
    let hasMeaningfulCharacter = result.unicodeScalars.contains {
        $0 != "_" && !CharacterSet.whitespacesAndNewlines.contains($0)
    }
    if result.isEmpty || result == "." || result == ".." || !hasMeaningfulCharacter {
        return "UnknownApp"
    }
    return result
}

private func screenshotFilename(
    appName: String,
    timestamp: String,
    sequence: Int,
    format: CaptureFormat
) -> String {
    "\(sanitizedFileComponent(appName))_\(timestamp)_\(String(format: "%06d", sequence)).\(format.rawValue)"
}

private func screenshotArguments(
    windowID: CGWindowID,
    format: CaptureFormat,
    destination: URL
) -> [String] {
    ["-x", "-o", "-t\(format.rawValue)", "-l\(windowID)", destination.path]
}

private func resizeArguments(maxDimension: Int, destination: URL) -> [String] {
    ["-Z", String(maxDimension), destination.path]
}

private func parsedSelection(_ input: String, itemCount: Int) -> Int? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.contains(","),
          let selection = Int(trimmed),
          (1...itemCount).contains(selection) else {
        return nil
    }
    return selection
}

private func nextTickOffset(interval: Double, elapsed: Double) -> Double {
    (floor(elapsed / interval) + 1) * interval
}

private func stableNumber(_ value: Double) -> String {
    String(format: "%.15g", locale: Locale(identifier: "en_US_POSIX"), value)
}

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

private func runTestCommand(arguments: [String]) -> Never {
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
    default:
        fputs("Unknown test command\n", stderr)
        exit(2)
    }
    exit(0)
}

private func intValue(_ value: Any?) -> Int? {
    if let number = value as? NSNumber { return number.intValue }
    return value as? Int
}

private func doubleValue(_ value: Any?) -> Double? {
    if let number = value as? NSNumber { return number.doubleValue }
    return value as? Double
}

private func discoverWindows() -> [WindowTarget] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let rawWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return []
    }

    return rawWindows.compactMap { info in
        guard intValue(info[kCGWindowLayer as String]) == 0,
              (doubleValue(info[kCGWindowAlpha as String]) ?? 1) > 0,
              let sharingState = intValue(info[kCGWindowSharingState as String]),
              sharingState != 0,
              let windowNumber = intValue(info[kCGWindowNumber as String]),
              windowNumber > 0,
              let ownerPIDValue = intValue(info[kCGWindowOwnerPID as String]),
              let ownerName = info[kCGWindowOwnerName as String] as? String,
              !ownerName.isEmpty,
              let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
              bounds.width > 1,
              bounds.height > 1 else {
            return nil
        }

        return WindowTarget(
            id: CGWindowID(windowNumber),
            ownerPID: pid_t(ownerPIDValue),
            ownerName: ownerName,
            title: (info[kCGWindowName as String] as? String) ?? ""
        )
    }
    .sorted {
        let ownerComparison = $0.ownerName.localizedStandardCompare($1.ownerName)
        if ownerComparison != .orderedSame { return ownerComparison == .orderedAscending }
        let titleComparison = $0.displayTitle.localizedStandardCompare($1.displayTitle)
        if titleComparison != .orderedSame { return titleComparison == .orderedAscending }
        return $0.id < $1.id
    }
}

private func printWindowList(_ windows: [WindowTarget]) {
    print("WINDOW_ID\tAPP — WINDOW / 應用程式 — 視窗")
    for window in windows {
        print("\(window.id)\t\(window.ownerName) — \(window.displayTitle)")
    }
}

private func selectedWindowIsAvailable(_ target: WindowTarget) -> Bool {
    discoverWindows().contains {
        $0.id == target.id && $0.ownerPID == target.ownerPID
    }
}

private func promptForWindow(from windows: [WindowTarget]) -> WindowTarget? {
    print("\n目前可截取的視窗 / Capturable windows:")
    for (index, window) in windows.enumerated() {
        print("  [\(index + 1)] \(window.ownerName) — \(window.displayTitle) (ID: \(window.id))")
    }

    while true {
        print("\n請輸入視窗編號 / Select a window number: ", terminator: "")
        fflush(stdout)
        guard let input = readLine() else {
            print("\n未收到輸入，已取消 / No input; cancelled.")
            return nil
        }
        if let selection = parsedSelection(input, itemCount: windows.count) {
            return windows[selection - 1]
        }
        print("請輸入 1 到 \(windows.count) 之間的一個編號 / Enter one number from 1 to \(windows.count).")
    }
}

private func promptForInterval() -> Double? {
    while true {
        print("截圖間隔秒數 / Interval in seconds [default 2, minimum 0.5]: ", terminator: "")
        fflush(stdout)
        guard let input = readLine() else {
            print("\n未收到輸入，已取消 / No input; cancelled.")
            return nil
        }
        if let interval = parsedInterval(input) { return interval }
        print("請輸入大於或等於 0.5 的數字 / Enter a number greater than or equal to 0.5.")
    }
}

private func sessionTimestamp() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = .current
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: Date())
}

private func expandedDirectoryURL(_ path: String) -> URL {
    let expanded = NSString(string: path).expandingTildeInPath
    if expanded.hasPrefix("/") {
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
    }
    return URL(
        fileURLWithPath: expanded,
        isDirectory: true,
        relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    ).standardizedFileURL
}

private func defaultOutputRoot() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Snapparazzi", isDirectory: true)
        .appendingPathComponent("captures", isDirectory: true)
}

private func makeSessionDirectory(timestamp: String, outputRoot: URL) throws -> URL {
    let directory = outputRoot.appendingPathComponent(
        "\(timestamp)-\(ProcessInfo.processInfo.processIdentifier)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func ensureScreenCapturePermission() -> Bool {
    if CGPreflightScreenCaptureAccess() { return true }
    print("Snapparazzi 需要螢幕錄製權限 / Snapparazzi needs Screen Recording permission.")
    if CGRequestScreenCaptureAccess() { return true }
    print("""

    尚未取得權限。請前往：
      系統設定 → 隱私權與安全性 → 螢幕與系統錄音

    Permission was not granted. Open:
      System Settings → Privacy & Security → Screen & System Audio Recording

    允許目前使用的 Terminal 後重新執行 / Allow your terminal app, then run Snapparazzi again.
    """)
    return false
}

private func runTool(
    executablePath: String,
    arguments: [String],
    discardStandardOutput: Bool = false,
    stopController: StopController
) -> CaptureResult {
    guard !stopController.shouldStop else { return .cancelled }

    let process = Process()
    let errorPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = arguments
    process.standardError = errorPipe
    if discardStandardOutput {
        process.standardOutput = FileHandle.nullDevice
    }

    do {
        try process.run()
        stopController.register(process)
        process.waitUntilExit()
        stopController.unregister(process)
    } catch {
        return .failure(error.localizedDescription)
    }

    if stopController.shouldStop {
        return .cancelled
    }

    guard process.terminationStatus == 0 else {
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let message, !message.isEmpty { return .failure(message) }
        let toolName = URL(fileURLWithPath: executablePath).lastPathComponent
        return .failure("\(toolName) exit status \(process.terminationStatus)")
    }

    return .success
}

private func captureWindow(
    _ target: WindowTarget,
    destination: URL,
    format: CaptureFormat,
    maxDimension: Int?,
    stopController: StopController
) -> CaptureResult {
    let captureResult = runTool(
        executablePath: "/usr/sbin/screencapture",
        arguments: screenshotArguments(
            windowID: target.id,
            format: format,
            destination: destination
        ),
        stopController: stopController
    )
    switch captureResult {
    case .success:
        break
    case .failure, .cancelled:
        try? FileManager.default.removeItem(at: destination)
        return captureResult
    }

    if let maxDimension {
        let resizeResult = runTool(
            executablePath: "/usr/bin/sips",
            arguments: resizeArguments(
                maxDimension: maxDimension,
                destination: destination
            ),
            discardStandardOutput: true,
            stopController: stopController
        )
        switch resizeResult {
        case .success:
            break
        case .failure, .cancelled:
            try? FileManager.default.removeItem(at: destination)
            return resizeResult
        }
    }

    guard let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path),
          let size = attributes[.size] as? NSNumber,
          size.intValue > 0 else {
        try? FileManager.default.removeItem(at: destination)
        return .failure("沒有產生有效圖片 / No valid image was produced")
    }
    return .success
}

private func durationSince(_ start: DispatchTime) -> Double {
    let now = DispatchTime.now().uptimeNanoseconds
    guard now >= start.uptimeNanoseconds else { return 0 }
    return Double(now - start.uptimeNanoseconds) / 1_000_000_000
}

private func printSummary(stats: CaptureStats, elapsed: Double, directory: URL) {
    print("""

    Snapparazzi 已停止 / stopped.
      成功 / succeeded: \(stats.succeeded)
      失敗 / failed: \(stats.failed)
      視窗不可用 / unavailable: \(stats.unavailable)
      排程略過 / schedule ticks skipped: \(stats.scheduleTicksSkipped)
      執行時間 / elapsed: \(String(format: "%.1f", elapsed)) seconds
      輸出目錄 / output: \(directory.path)
    """)
}

private func runCapture(options: CLIOptions, windows: [WindowTarget]) -> Int32 {
    let target: WindowTarget
    if let requestedID = options.windowID {
        guard let requestedWindow = windows.first(where: { $0.id == requestedID }) else {
            fputs("找不到可見 window ID \(requestedID) / Visible window ID \(requestedID) was not found.\n", stderr)
            return 1
        }
        target = requestedWindow
    } else {
        guard let selected = promptForWindow(from: windows) else { return 0 }
        target = selected
    }

    let interval: Double
    if let configuredInterval = options.interval {
        interval = configuredInterval
    } else {
        guard let selectedInterval = promptForInterval() else { return 0 }
        interval = selectedInterval
    }

    let timestamp = sessionTimestamp()
    let outputRoot = options.outputPath.map(expandedDirectoryURL) ?? defaultOutputRoot()
    let directory: URL
    do {
        directory = try makeSessionDirectory(timestamp: timestamp, outputRoot: outputRoot)
    } catch {
        fputs("無法建立輸出目錄 / Cannot create output directory: \(error.localizedDescription)\n", stderr)
        return 1
    }

    print("""

    已選擇 / selected: \(target.ownerName) — \(target.displayTitle) (ID: \(target.id))
    間隔 / interval: \(stableNumber(interval)) seconds
    格式 / format: \(options.format.rawValue)
    最大尺寸 / max dimension: \(options.maxDimension.map(String.init) ?? "original")
    輸出 / output: \(directory.path)
    按 Ctrl-C 停止 / Press Ctrl-C to stop.
    """)

    let stopController = StopController()
    signal(SIGINT, SIG_IGN)
    let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global(qos: .userInitiated))
    signalSource.setEventHandler {
        if stopController.requestStop() { print("\n正在停止 / Stopping…") }
    }
    signalSource.resume()

    let monotonicStart = DispatchTime.now()
    var scheduledOffset = 0.0
    var sequence = 1
    var stats = CaptureStats()
    var wasUnavailable = false

    while !stopController.shouldStop {
        if selectedWindowIsAvailable(target) {
            if wasUnavailable {
                print("視窗已恢復 / Window restored; resuming capture.")
                wasUnavailable = false
            }

            let filename = screenshotFilename(
                appName: target.ownerName,
                timestamp: timestamp,
                sequence: sequence,
                format: options.format
            )
            let destination = directory.appendingPathComponent(filename)
            switch captureWindow(
                target,
                destination: destination,
                format: options.format,
                maxDimension: options.maxDimension,
                stopController: stopController
            ) {
            case .success:
                stats.succeeded += 1
                sequence += 1
                print("✓ \(filename)")
            case .failure(let message):
                stats.failed += 1
                fputs("截圖失敗 / Capture failed: \(message)\n", stderr)
            case .cancelled:
                break
            }
        } else {
            stats.unavailable += 1
            if !wasUnavailable {
                print("視窗目前不可用；同一視窗恢復後會繼續 / Window unavailable; waiting for the same window to return.")
                wasUnavailable = true
            }
        }

        guard !stopController.shouldStop else { break }
        let elapsed = durationSince(monotonicStart)
        let nextOffset = nextTickOffset(interval: interval, elapsed: elapsed)
        let intervalsAdvanced = Int(round((nextOffset - scheduledOffset) / interval))
        if intervalsAdvanced > 1 { stats.scheduleTicksSkipped += intervalsAdvanced - 1 }
        scheduledOffset = nextOffset
        let deadlineNanoseconds = monotonicStart.uptimeNanoseconds
            + UInt64((scheduledOffset * 1_000_000_000).rounded())
        stopController.wait(until: DispatchTime(uptimeNanoseconds: deadlineNanoseconds))
    }

    signalSource.cancel()
    printSummary(stats: stats, elapsed: durationSince(monotonicStart), directory: directory)
    return 0
}

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

private func main() -> Int32 {
    let arguments = CommandLine.arguments
    if arguments.count > 1, arguments[1] == "--test" {
        runTestCommand(arguments: arguments)
    }

    do {
        switch try parseArguments(Array(arguments.dropFirst())) {
        case .help:
            print(helpText)
            return 0
        case .version:
            print("snapparazzi \(snapparazziVersion)")
            return 0
        case .run(let options):
            return run(options: options)
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

exit(main())
