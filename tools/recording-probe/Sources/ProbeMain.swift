import Foundation
import Darwin
import CoreGraphics
@preconcurrency import AVFoundation
@preconcurrency import ScreenCaptureKit

private let help = """
Standalone recording probe — macOS 15+, NOT the Snapparazzi record command.

  recording-probe list
  recording-probe capture --window ID --audio none|system|mic|both \\
      --duration 10 --codec h264|hevc --output /existing-directory/probe.mov
  recording-probe inspect /path/to/probe.mov

Defaults: audio=none, duration=10 (1...60 seconds), codec=h264.
JSON lines describe source formats/PTS and decode results; save with shell redirection.
Output must not exist. both writes TWO SEPARATE audio tracks for diagnostics.
No mix/remux, silence padding, static-frame ticker or production resize handling yet.
Actual App-audio scope and sync are UNVERIFIED until tested on a Mac.
"""

@main
struct ProbeMain {
    @MainActor
    static func main() async {
        let command: ProbeCommand
        do { command = try ProbeCommand.parse(Array(CommandLine.arguments.dropFirst())) }
        catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(2)
        }
        if case .help = command { print(help); return }
        guard #available(macOS 15.0, *) else {
            fputs("Requires macOS 15 or newer.\n", stderr)
            exit(1)
        }
        do { try await run(command) }
        catch {
            emit(["event": "error", "message": error.localizedDescription])
            exit(1)
        }
    }

    @available(macOS 15.0, *)
    @MainActor
    private static func run(_ command: ProbeCommand) async throws {
        if case .inspect = command {} else {
            // A plain CLI has no window-server connection yet; SCContentFilter
            // queries displays and aborts (CGS_REQUIRE_INIT) unless CG is initialized.
            _ = CGMainDisplayID()
        }
        switch command {
        case .help: return
        case .inspect(let url): try await inspect(url)
        case .list:
            try screenPermission()
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            for window in content.windows where window.windowLayer == 0 {
                emit(["event": "window", "window_id": window.windowID,
                      "pid": window.owningApplication?.processID ?? 0,
                      "app": window.owningApplication?.applicationName ?? "Unknown",
                      "title": window.title ?? ""])
            }
        case .capture(let options): try await capture(options)
        }
    }

    @available(macOS 15.0, *)
    @MainActor
    private static func capture(_ options: CaptureOptions) async throws {
        let path = options.output.path
        let parent = options.output.deletingLastPathComponent()
        // attributesOfItem also rejects an existing dangling symlink.
        if (try? FileManager.default.attributesOfItem(atPath: path)) != nil {
            throw ProbeFailure.message("Refusing to overwrite output: \(path)")
        }
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw ProbeFailure.message("Output parent must exist and be writable: \(parent.path)")
        }
        try screenPermission()
        var microphoneID: String?
        if options.audio.microphone {
            let granted: Bool
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: granted = true
            case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .audio)
            default: granted = false
            }
            guard granted else { throw ProbeFailure.message("Microphone permission denied.") }
            guard let device = AVCaptureDevice.default(for: .audio) else {
                throw ProbeFailure.message("No default microphone available.")
            }
            microphoneID = device.uniqueID
        }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let target = content.windows.first(where: { $0.windowID == options.windowID }) else {
            throw ProbeFailure.message("Visible window not found: \(options.windowID)")
        }
        let probe = try StreamProbe(options: options, window: target, microphoneID: microphoneID)
        let priorINT = signal(SIGINT, SIG_IGN)
        let priorTERM = signal(SIGTERM, SIG_IGN)
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        interrupt.setEventHandler { probe.requestStop() }
        terminate.setEventHandler { probe.requestStop() }
        interrupt.resume()
        terminate.resume()
        defer {
            interrupt.cancel()
            terminate.cancel()
            signal(SIGINT, priorINT)
            signal(SIGTERM, priorTERM)
        }
        try await probe.start()
        let started = DispatchTime.now().uptimeNanoseconds
        var startupError: String?
        while true {
            let state = probe.snapshot()
            if state.stopped || state.error != nil { break }
            if let elapsed = state.elapsed {
                // A huge mismatch is clock-domain evidence, not a one-hour wait.
                if elapsed < -1 || elapsed > options.duration + 5 {
                    startupError = "Source PTS and host clock need investigation; inspect sample logs."
                    break
                }
                if elapsed >= options.duration { break }
            } else if DispatchTime.now().uptimeNanoseconds - started > 5_000_000_000 {
                startupError = "No complete video frame within 5 seconds."
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let completed = await probe.finish()
        if let startupError { throw ProbeFailure.message(startupError) }
        guard completed else {
            throw ProbeFailure.message("Capture incomplete; preserve MOV and JSON log for diagnosis.")
        }
        try await inspect(options.output)
    }
}

@MainActor
private func screenPermission() throws {
    guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
        throw ProbeFailure.message("Allow Screen Recording for the launching app/terminal or probe in System Settings, then retry.")
    }
}
