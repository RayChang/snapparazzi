import Foundation
import CoreGraphics
import ImageIO
import Dispatch
import Darwin

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

func sanitizedFileComponent(_ value: String) -> String {
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

func screenshotFilename(
    appName: String,
    timestamp: String,
    sequence: Int,
    format: CaptureFormat
) -> String {
    "\(sanitizedFileComponent(appName))_\(timestamp)_\(String(format: "%06d", sequence)).\(format.rawValue)"
}

func screenshotArguments(
    windowID: CGWindowID,
    format: CaptureFormat,
    destination: URL
) -> [String] {
    ["-x", "-o", "-t\(format.rawValue)", "-l\(windowID)", destination.path]
}

func resizeArguments(maxDimension: Int, destination: URL) -> [String] {
    ["-Z", String(maxDimension), destination.path]
}

func dimensionsNeedResize(width: Int, height: Int, maxDimension: Int) -> Bool {
    max(width, height) > maxDimension
}

private func imageDimensions(at url: URL) -> (width: Int, height: Int)? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
          let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
        return nil
    }
    return (width.intValue, height.intValue)
}

func nextTickOffset(interval: Double, elapsed: Double) -> Double {
    (floor(elapsed / interval) + 1) * interval
}

func stableNumber(_ value: Double) -> String {
    String(format: "%.15g", locale: Locale(identifier: "en_US_POSIX"), value)
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
        guard let dimensions = imageDimensions(at: destination) else {
            try? FileManager.default.removeItem(at: destination)
            return .failure("無法讀取圖片尺寸 / Cannot read image dimensions")
        }
        if dimensionsNeedResize(
            width: dimensions.width,
            height: dimensions.height,
            maxDimension: maxDimension
        ) {
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

func runCapture(options: CLIOptions, windows: [WindowTarget]) -> Int32 {
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
                print("視窗目前看不到（已最小化，或在其他桌面／全螢幕）；回到畫面上後會繼續截圖 / Window not visible (minimized, or on another Space / full screen); capture resumes when it is back on screen.")
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
