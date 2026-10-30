import Foundation
import CoreMedia
@preconcurrency import AVFoundation

// Deterministic recording tests: synthetic buffers, a fake clock and real
// AVFoundation writing/mixing. No ScreenCaptureKit, windows or permissions.

final class Results: @unchecked Sendable {
    static let shared = Results()
    var checks = 0
    var failures = 0
    var currentCase = 0
    var directories: [URL] = []
}

setvbuf(stdout, nil, _IOLBF, 0)

// Each case gets 60 s; a hang fails the run instead of blocking it forever.
func armWatchdog(_ caseNumber: Int, name: String) {
    DispatchQueue.global().asyncAfter(deadline: .now() + 60) {
        guard Results.shared.currentCase == caseNumber else { return }
        print("FAIL: \(name) timed out after 60 s")
        exit(1)
    }
}

func check(_ condition: Bool, _ message: @autoclosure () -> String) {
    Results.shared.checks += 1
    if !condition {
        Results.shared.failures += 1
        print("  FAIL: \(message())")
    }
}

func near(_ actual: Double, _ expected: Double, _ tolerance: Double, _ label: String) {
    check(abs(actual - expected) <= tolerance,
          "\(label): \(String(format: "%.4f", actual)) not within \(tolerance) of \(expected)")
}

func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("snapparazzi-recording-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    Results.shared.directories.append(url)
    return url
}

let frameTolerance = 1.0 / 30
let aacFrame = 1024.0 / 48_000
let alignmentTolerance = max(frameTolerance, aacFrame) // validation handbook: one video or AAC frame

var cases: [(String, () async throws -> Void)] = []

cases.append(("both: offsets, 0.5 gain and one mixed track (h264)", {
    let directory = temporaryDirectory()
    let stage = directory.appendingPathComponent("stage.mov")
    let mixed = directory.appendingPathComponent("mixed.mp4")
    let result = try await simulate(url: stage, fileType: .mov, duration: 3, audio: [
        SimulatedAudio(source: .system, frequency: 440, start: 0.12),
        SimulatedAudio(source: .microphone, frequency: 880, sampleRate: 44_100, channels: 1,
                       interleaved: true, start: 0.5, chunkFrames: 441)
    ])
    let stageReport = try await inspectAsset(stage)
    check(stageReport.video.count == 1 && stageReport.audio.count == 2, "stage has 1 video + 2 audio tracks")
    check(stageReport.video.first?.samples == 90, "stage has 90 frames, got \(stageReport.video.first?.samples ?? -1)")
    near(CMTimeGetSeconds(result.endpoint), 3, 0.0001, "endpoint")

    try await AudioMixer().mix(stage, to: mixed)
    let report = try await inspectAsset(mixed)
    check(report.video.count == 1 && report.audio.count == 1, "final has 1 video + 1 audio track")
    check(report.audio.first?.codec == "aac " && report.audio.first?.sampleRate == 48_000
          && report.audio.first?.channels == 2, "final audio is AAC 48 kHz stereo")
    near(report.duration, 3, aacFrame, "final duration")
    let pcm = try await decodeStereo48k(mixed)
    for channel in 0...1 {
        near(toneAmplitude(pcm, channel: channel, start: 0.2, length: 0.25, frequency: 440), 0.25, 0.025, "440 Hz before mic, ch\(channel)")
        check(toneAmplitude(pcm, channel: channel, start: 0.2, length: 0.25, frequency: 880) < 0.01, "no 880 Hz before 0.5 s, ch\(channel)")
        near(toneAmplitude(pcm, channel: channel, start: 1, length: 1.5, frequency: 440), 0.25, 0.025, "440 Hz after, ch\(channel)")
        near(toneAmplitude(pcm, channel: channel, start: 1, length: 1.5, frequency: 880), 0.25, 0.025, "880 Hz (mono mic) after, ch\(channel)")
    }
    let onset440 = toneOnset(pcm, frequency: 440, from: 0, to: 0.4, steady: 0.25) ?? -1
    let onset880 = toneOnset(pcm, frequency: 880, from: 0.3, to: 0.8, steady: 0.25) ?? -1
    near(onset440, 0.12, alignmentTolerance, "system onset keeps its 0.12 s offset")
    near(onset880, 0.5, alignmentTolerance, "mic onset keeps its 0.5 s offset")
}))

cases.append(("none: video only, hevc", {
    let url = temporaryDirectory().appendingPathComponent("none.mp4")
    let result = try await simulate(url: url, fileType: .mp4, codec: .hevc, duration: 2.5, audio: [])
    let report = try await inspectAsset(url)
    check(report.video.count == 1 && report.audio.isEmpty, "1 video, 0 audio")
    check(report.video.first?.codec == "hvc1", "codec hvc1, got \(report.video.first?.codec ?? "-")")
    check(report.video.first?.samples == 75, "75 frames for 2.5 s at 30 fps, got \(report.video.first?.samples ?? -1)")
    check(result.stats.droppedSlots == 0, "no dropped slots")
    near(report.duration, 2.5, 0.001, "duration")
}))

cases.append(("mic: 44.1 kHz mono starting late lands in both channels", {
    let url = temporaryDirectory().appendingPathComponent("mic.mp4")
    _ = try await simulate(url: url, fileType: .mp4, duration: 3, audio: [
        SimulatedAudio(source: .microphone, frequency: 1000, sampleRate: 44_100, channels: 1,
                       interleaved: true, start: 0.7, latency: 0.02, chunkFrames: 441)
    ])
    let report = try await inspectAsset(url)
    check(report.video.count == 1 && report.audio.count == 1, "1 video, 1 audio")
    near(report.duration, 3, aacFrame, "duration")
    let pcm = try await decodeStereo48k(url)
    for channel in 0...1 {
        check(toneAmplitude(pcm, channel: channel, start: 0.1, length: 0.4, frequency: 1000) < 0.01, "silence before the mic starts, ch\(channel)")
        near(toneAmplitude(pcm, channel: channel, start: 1, length: 1.5, frequency: 1000), 0.5, 0.05, "mic level (gain 1), ch\(channel)")
    }
    near(toneOnset(pcm, frequency: 1000, from: 0.4, to: 1, steady: 0.5) ?? -1, 0.7, alignmentTolerance, "mic onset at 0.7 s")
}))

cases.append(("system: gap is silence, duplicate is trimmed, audio before t0 is cut", {
    let url = temporaryDirectory().appendingPathComponent("system.mp4")
    let result = try await simulate(url: url, fileType: .mp4, duration: 3, audio: [
        SimulatedAudio(source: .system, frequency: 440, start: -0.1, gaps: [1.0...1.5], duplicateChunk: 40)
    ])
    let pcm = try await decodeStereo48k(url)
    near(toneAmplitude(pcm, channel: 0, start: 0.05, length: 0.3, frequency: 440), 0.5, 0.05, "tone from the start (pre-t0 audio trimmed, not shifted)")
    check(toneAmplitude(pcm, channel: 0, start: 1.1, length: 0.3, frequency: 440) < 0.01, "gap is silent")
    near(toneAmplitude(pcm, channel: 0, start: 1.7, length: 1, frequency: 440), 0.5, 0.05, "tone after the gap")
    near(toneOnset(pcm, frequency: 440, from: 1.3, to: 1.8, steady: 0.5) ?? -1, 1.52, alignmentTolerance, "tone resumes at its own time after the gap")
    let audio = result.audio[.system]
    check((audio?.trimmedSamples ?? 0) >= 960, "duplicate chunk trimmed (\(audio?.trimmedSamples ?? 0) samples)")
    check((audio?.paddedSamples ?? 0) >= 24_000, "gap padded with silence (\(audio?.paddedSamples ?? 0) samples)")
    check(pcm.count / 2 >= 143_000 && pcm.count / 2 <= 145_100, "audio length ≈ 3 s, got \(pcm.count / 2) samples")
}))

cases.append(("minimize: last frame held 1 s, then black, then resumes", {
    let url = temporaryDirectory().appendingPathComponent("minimize.mp4")
    let result = try await simulate(url: url, fileType: .mp4, duration: 4, audio: [], screen: { now in
        if now < 1 { return .color(220, 30, 30) }
        if now < 3 { return .suspended }
        return .color(30, 30, 220)
    })
    let held = try await frameMeanColor(url, at: 1.5)
    let black = try await frameMeanColor(url, at: 2.5)
    let resumed = try await frameMeanColor(url, at: 3.5)
    check(held.red > 150 && held.blue < 80, "last frame held at 1.5 s: \(held)")
    check(black.red < 20 && black.green < 20 && black.blue < 20, "black at 2.5 s: \(black)")
    check(resumed.blue > 150 && resumed.red < 80, "new frames after restore at 3.5 s: \(resumed)")
    check(result.stats.blackFrames >= 25 && result.stats.blackFrames <= 31, "about 1 s of black frames, got \(result.stats.blackFrames)")
    let report = try await inspectAsset(url)
    check(report.video.first?.samples == 120, "constant 30 fps through the gap, got \(report.video.first?.samples ?? -1)")
}))

cases.append(("late ticks skip slots instead of bursting", {
    let url = temporaryDirectory().appendingPathComponent("skip.mp4")
    let result = try await simulate(url: url, fileType: .mp4, duration: 2, audio: [], skipTicks: 0.5...0.99)
    check(result.stats.droppedSlots >= 14 && result.stats.droppedSlots <= 16, "about 15 slots skipped, got \(result.stats.droppedSlots)")
    let report = try await inspectAsset(url)
    near(report.duration, 2, 0.001, "duration is unchanged (time is not compressed)")
}))

cases.append(("endpoint clips audio and video exactly", {
    let url = temporaryDirectory().appendingPathComponent("end.mp4")
    _ = try await simulate(url: url, fileType: .mp4, duration: 1.75, audio: [SimulatedAudio(source: .system, start: 0.05)])
    let report = try await inspectAsset(url)
    check(report.video.first?.samples == 53, "53 frames for 1.75 s (slots 0–52), got \(report.video.first?.samples ?? -1)")
    near(report.duration, 1.75, aacFrame, "duration")
    let pcm = try await decodeStereo48k(url)
    check(abs(pcm.count / 2 - 84_000) <= 1_024, "audio is 1.75 s (84000 samples ± one AAC frame), got \(pcm.count / 2)")
}))

// A device clock 1000 ppm slow (or fast) puts its timestamps 18 ms off real time after
// 18 s. The marker switches frequency at real time 18 s and must land there.
for (label, error) in [("slow", -0.001), ("fast", 0.001)] {
    cases.append(("mic clock \(label) by 1000 ppm: audio follows real time", {
        let url = temporaryDirectory().appendingPathComponent("drift-\(label).mp4")
        let result = try await simulate(url: url, fileType: .mp4, duration: 20, audio: [
            SimulatedAudio(source: .microphone, frequency: 440, channels: 1, interleaved: true,
                           start: 0.3, latency: 0.02, chunkFrames: 512, clockError: error,
                           switchFrequency: (to: 1000, atRealTime: 18))
        ])
        let pcm = try await decodeStereo48k(url)
        // Tracking lags about one 2 s window plus the 1 ms deadband (a few ms at this
        // exaggerated rate, under 1 ms at a real ~90 ppm); 9 ms is half the uncorrected error.
        near(toneOnset(pcm, frequency: 1000, from: 17.8, to: 18.2, steady: 0.5) ?? -1, 18, 0.009,
             "marker at real time 18 s (uncorrected it would be \(error < 0 ? "18 ms early" : "18 ms late"))")
        let audio = result.audio[.microphone]
        near(Double(audio?.driftCorrection ?? 0) / 48_000, error < 0 ? 0.018 : -0.018, 0.006, "about 18 ms corrected")
        check((audio?.trimmedSamples ?? 0) == 0, "no audio dropped (\(audio?.trimmedSamples ?? 0) samples)")
        check((audio?.paddedSamples ?? 0) < 48_000 / 2, "only start-up silence padded (\(audio?.paddedSamples ?? 0) samples)")
        // The device's 440 Hz is really 440 × (1 + error) Hz in real time, which is what a
        // corrected track plays; a 0.5 s window (2 Hz wide) measures it.
        near(toneAmplitude(pcm, channel: 0, start: 5, length: 0.5, frequency: 440 * (1 + error)), 0.5, 0.05, "tone level unaffected by corrections")
    }))
}

cases.append(("session: preflight, exclusive commit, cleanup", {
    let directory = temporaryDirectory()
    let existing = directory.appendingPathComponent("taken.mp4")
    try Data("keep".utf8).write(to: existing)
    check((try? RecordingSession.preflight(existing)) == nil, "existing output is rejected")
    let folder = directory.appendingPathComponent("folder.mp4")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    check((try? RecordingSession.preflight(folder)) == nil, "a directory named *.mp4 is rejected")
    let nested = directory.appendingPathComponent("new folder/子資料夾/clip.mp4")
    check((try? RecordingSession.preflight(nested)) != nil, "missing parents are allowed")
    check(!FileManager.default.fileExists(atPath: nested.deletingLastPathComponent().path), "preflight creates nothing")

    let session = try RecordingSession.create(finalURL: nested, stageExtension: "mp4")
    let mode = (try FileManager.default.attributesOfItem(atPath: session.stageDirectory.path)[.posixPermissions] as? NSNumber)?.intValue
    check(mode == 0o700, "stage folder is private (0700), got \(String(mode ?? 0, radix: 8))")
    try Data("video".utf8).write(to: session.captureURL)
    try Data("someone else".utf8).write(to: nested) // appears after preflight
    check((try? session.commit(session.captureURL)) == nil, "commit refuses to overwrite")
    check((try? String(contentsOf: nested, encoding: .utf8)) == "someone else", "the other file is untouched")
    check(FileManager.default.fileExists(atPath: session.captureURL.path), "the recording is kept after a failed commit")
    try FileManager.default.removeItem(at: nested)
    try session.commit(session.captureURL)
    check((try? String(contentsOf: nested, encoding: .utf8)) == "video", "commit moves the file into place")
    check(!FileManager.default.fileExists(atPath: session.stageDirectory.path), "commit removes the stage folder")
}))

cases.append(("microphone permission: denied or restricted never prompts and fails", {
    var requests = 0
    let deny = { () async -> Bool in requests += 1; return false }
    let allow = { () async -> Bool in requests += 1; return true }
    check(await ensureMicrophonePermission(status: .authorized, request: deny), "authorized passes without asking")
    check(requests == 0, "authorized does not prompt")
    check(!(await ensureMicrophonePermission(status: .denied, request: allow)), "denied fails")
    check(!(await ensureMicrophonePermission(status: .restricted, request: allow)), "restricted fails")
    check(requests == 0, "denied and restricted do not prompt (\(requests))")
    check(!(await ensureMicrophonePermission(status: .notDetermined, request: deny)), "a declined prompt fails")
    check(await ensureMicrophonePermission(status: .notDetermined, request: allow), "an accepted prompt passes")
    check(requests == 2, "not-determined prompts once per call (\(requests))")
}))

cases.append(("record: microphone asked only for mic/both; denial stops before any file", {
    let signals = RecordingSignals()
    for mode in AudioMode.allCases {
        let directory = temporaryDirectory()
        let output = directory.appendingPathComponent("out/clip.mp4")
        var options = RecordingOptions()
        options.windowID = 4_294_967_000 // no such window
        options.audio = mode
        options.outputPath = output.path
        var asked = 0
        var command = RecordCommand(options: options, signals: signals)
        command.screenAccess = { true }
        command.microphoneAccess = { asked += 1; return false }
        let status = await command.run()
        check(status == 1, "\(mode.rawValue): exit 1 (\(status))")
        check(asked == (mode.capturesMicrophone ? 1 : 0), "\(mode.rawValue): microphone asked \(asked) time(s)")
        check((try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.isEmpty == true,
              "\(mode.rawValue): nothing created next to the output")
    }
}))

cases.append(("stop reasons: failures are never hidden by a normal stop", {
    check(RecordingStopReason.interrupt.merged(with: .windowClosed) == .windowClosed, "window closed outranks Ctrl-C")
    check(RecordingStopReason.windowClosed.merged(with: .terminate) == .windowClosed, "a later SIGTERM keeps the failure")
    check(RecordingStopReason.durationReached.merged(with: .failure("x")) == .failure("x"), "a runtime failure outranks duration")
    check(RecordingStopReason.interrupt.isSuccess && RecordingStopReason.durationReached.isSuccess, "normal stops succeed")
    check(!RecordingStopReason.diskLow.isSuccess, "low disk is a failure")
}))

for (number, (name, body)) in cases.enumerated() {
    Results.shared.currentCase = number + 1
    armWatchdog(number + 1, name: name)
    print("CASE: \(name)")
    let before = Results.shared.failures
    do {
        try await body()
    } catch {
        check(false, "\(name) threw: \(error.localizedDescription)")
    }
    print(Results.shared.failures == before ? "PASS: \(name)" : "FAIL: \(name)")
}
let results = Results.shared
guard results.checks > 0 else {
    print("FAIL: no checks ran")
    exit(1)
}
if results.failures > 0 {
    print("\(results.failures)/\(results.checks) recording checks failed; files kept for diagnosis:")
    results.directories.forEach { print("  \($0.path)") }
    exit(1)
}
results.directories.forEach { try? FileManager.default.removeItem(at: $0) }
print("All \(results.checks) recording checks passed (\(cases.count) cases)")
