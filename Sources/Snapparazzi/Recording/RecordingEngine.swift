import Foundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Darwin
@preconcurrency import AVFoundation
@preconcurrency import ScreenCaptureKit

// MARK: Entry

// Called by AppRunner for `record`: runs the async recording and exits with its status.
func runRecordCommand(_ options: RecordingOptions) -> Never {
    // Progress lines ("Recording…", "Mixing…") must appear promptly even when piped.
    setvbuf(stdout, nil, _IOLBF, 0)
    let signals = RecordingSignals()
    Task {
        let status: Int32
        if #available(macOS 15.0, *) {
            status = await RecordCommand(options: options, signals: signals).run()
        } else {
            fputs("錯誤 / Error: record 需要 macOS 15 以上 / record requires macOS 15 or later.\n", stderr)
            status = 1
        }
        exit(status)
    }
    dispatchMain()
}

// SIGINT/SIGTERM become stop requests; the handlers never exit or touch AVFoundation.
final class RecordingSignals: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (RecordingStopReason) -> Void)?
    private var received: RecordingStopReason?
    private var sources: [DispatchSourceSignal] = []

    init() {
        for (number, reason) in [(SIGINT, RecordingStopReason.interrupt), (SIGTERM, .terminate)] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global(qos: .userInitiated))
            source.setEventHandler { [weak self] in self?.deliver(reason) }
            source.resume()
            sources.append(source)
        }
    }

    var receivedReason: RecordingStopReason? {
        lock.lock(); defer { lock.unlock() }
        return received
    }

    func setHandler(_ handler: (@Sendable (RecordingStopReason) -> Void)?) {
        lock.lock(); self.handler = handler; lock.unlock()
    }

    private func deliver(_ reason: RecordingStopReason) {
        lock.lock()
        if received == nil { received = reason }
        let handler = self.handler
        lock.unlock()
        handler?(reason)
    }
}

// MARK: Preparation

@available(macOS 15.0, *)
struct RecordCommand {
    let options: RecordingOptions
    let signals: RecordingSignals

    private func error(_ message: String) -> Int32 {
        fputs("錯誤 / Error: \(message)\n", stderr)
        return 1
    }

    private var cancelledBeforeStart: Bool {
        guard signals.receivedReason != nil else { return false }
        print("已取消，沒有錄到畫面 / Cancelled before recording started.")
        return true
    }

    func run() async -> Int32 {
        let finalURL = RecordingSession.resolveOutput(options.outputPath)
        do { try RecordingSession.preflight(finalURL) } catch { return self.error(error.localizedDescription) }

        print("📸 Snapparazzi record")
        guard ensureScreenCapturePermission() else { return 1 }
        if cancelledBeforeStart { return 0 }
        if options.audio.capturesMicrophone {
            guard await ensureMicrophonePermission() else { return 1 }
            if cancelledBeforeStart { return 0 }
        }

        // A plain CLI has no window-server connection yet; ScreenCaptureKit's window
        // filter aborts (CGS_REQUIRE_INIT) unless CoreGraphics is initialized first.
        _ = CGMainDisplayID()
        guard let windowID = options.windowID,
              let target = discoverWindows().first(where: { $0.id == windowID }) else {
            return error("找不到可見 window ID \(options.windowID ?? 0) / Visible window ID \(options.windowID ?? 0) was not found.")
        }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            return self.error("無法取得可錄製內容 / Cannot list shareable content: \(error.localizedDescription)")
        }
        guard let window = content.windows.first(where: {
            $0.windowID == windowID && $0.owningApplication?.processID == target.ownerPID
        }) else {
            return error("找不到可錄製的視窗 \(windowID) / Window \(windowID) is not available for recording.")
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = Double(filter.pointPixelScale)
        let sourceWidth = Double(filter.contentRect.width) * scale
        let sourceHeight = Double(filter.contentRect.height) * scale
        let fit = options.maxDimension.map { min(1, Double($0) / max(sourceWidth, sourceHeight)) } ?? 1
        let width = Int(sourceWidth * fit / 2) * 2
        let height = Int(sourceHeight * fit / 2) * 2
        guard width >= 2, height >= 2 else {
            return error("視窗尺寸太小 / Window is too small to record (\(width)×\(height)).")
        }

        var microphoneID: String?
        if options.audio.capturesMicrophone {
            guard let device = AVCaptureDevice.default(for: .audio) else {
                return error("找不到可用的麥克風 / No microphone is available.")
            }
            microphoneID = device.uniqueID
        }

        let audioTracks = options.audio == .both ? 2 : (options.audio == .none ? 0 : 1)
        let bitsPerSecond = Double(StageWriter.videoBitRate(width: width, height: height, fps: options.fps)
                                   + 192_000 * audioTracks)
        let oneGiB: Int64 = 1 << 30
        let required = options.duration.map {
            Int64(bitsPerSecond / 8 * $0 * (options.audio == .both ? 2.2 : 1.1)) + (512 << 20)
        } ?? oneGiB
        if let available = RecordingSession.availableCapacity(for: finalURL) {
            guard available >= required else {
                return error("磁碟空間不足：需要約 \(required >> 20) MiB，可用 \(available >> 20) MiB / Not enough disk space: about \(required >> 20) MiB needed, \(available >> 20) MiB available.")
            }
        } else {
            print("警告：無法查詢可用磁碟空間 / Warning: available disk space is unknown.")
        }
        if cancelledBeforeStart { return 0 }

        let session: RecordingSession
        do {
            session = try RecordingSession.create(finalURL: finalURL, stageExtension: options.audio == .both ? "mov" : "mp4")
        } catch {
            return self.error(error.localizedDescription)
        }
        print("""
        已選擇 / selected: \(target.ownerName) — \(target.displayTitle) (ID: \(windowID))
        畫面 / video: \(width)×\(height) \(options.codec.rawValue) \(options.fps) fps
        音訊 / audio: \(options.audio.rawValue)
        輸出 / output: \(finalURL.path)
        """)
        if options.audio.capturesSystem {
            print("提醒：system 錄的是整個 App 的聲音，同 App 其他視窗也可能錄入 / Note: system records the whole app, including its other windows.")
        }
        let engine: RecordingEngine
        do {
            engine = try RecordingEngine(options: options, filter: filter, width: width, height: height,
                                         microphoneID: microphoneID, session: session, signals: signals)
        } catch {
            session.removeStage()
            return self.error(error.localizedDescription)
        }
        return await engine.run()
    }
}

// MARK: Recording

@available(macOS 15.0, *)
final class RecordingEngine: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private static let firstFrameTimeout = 5.0
    private static let lowDiskBytes: Int64 = 512 << 20

    // Everything below is confined to `queue`, which is also ScreenCaptureKit's
    // sample handler queue: samples are handled synchronously, with no extra
    // buffering beyond the pipeline's bounded audio queues.
    private let queue = DispatchQueue(label: "dev.snapparazzi.record.media", qos: .userInitiated)
    private let options: RecordingOptions
    private let session: RecordingSession
    private let signals: RecordingSignals
    private let writer: StageWriter
    private let pipeline: RecordingPipeline
    private let filter: SCContentFilter
    private let configuration: SCStreamConfiguration
    private var stream: SCStream?
    private var timer: DispatchSourceTimer?
    private var reason: RecordingStopReason?
    private var sealed = false
    private var announced = false
    private var startUptime = 0.0
    private var lastDiskCheck = 0.0
    private var lastMicrophoneCheck = 0.0
    private let microphoneID: String?
    private var stopContinuation: CheckedContinuation<Void, Never>?
    private var stopRequested = false

    init(options: RecordingOptions, filter: SCContentFilter, width: Int, height: Int,
         microphoneID: String?, session: RecordingSession, signals: RecordingSignals) throws {
        self.options = options
        self.session = session
        self.signals = signals
        self.filter = filter
        self.microphoneID = microphoneID
        var sources: [AudioSource] = []
        if options.audio.capturesSystem { sources.append(.system) }
        if options.audio.capturesMicrophone { sources.append(.microphone) }
        writer = try StageWriter(url: session.captureURL, fileType: options.audio == .both ? .mov : .mp4,
                                 width: width, height: height, fps: options.fps,
                                 codec: options.codec, audioSources: sources)
        pipeline = try RecordingPipeline(fps: options.fps, writer: writer, audioSources: sources)
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.fps))
        config.queueDepth = 6
        config.showsCursor = false
        config.capturesAudio = options.audio.capturesSystem
        config.sampleRate = recordingSampleRate
        config.channelCount = recordingChannels
        config.excludesCurrentProcessAudio = true
        config.captureMicrophone = options.audio.capturesMicrophone
        if let microphoneID { config.microphoneCaptureDeviceID = microphoneID }
        configuration = config
        super.init()
    }

    private func hostNow() -> CMTime { CMClockGetTime(CMClockGetHostTimeClock()) }
    private func uptime() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

    func run() async -> Int32 {
        let finishStarted: Double
        do {
            try queue.sync { try writer.start() }
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            if options.audio.capturesSystem { try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue) }
            if options.audio.capturesMicrophone { try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue) }
            queue.sync { self.stream = stream }
            signals.setHandler { [weak self] reason in self?.requestStop(reason) }
            if let early = signals.receivedReason { requestStop(early) }
            // Tick before startCapture returns: with audio it takes ~0.6 s to return,
            // while frames already arrive and the timeline has started.
            queue.sync { startTimer() }
            try await stream.startCapture()
        } catch {
            queue.sync { timer?.cancel(); timer = nil; writer.cancel() }
            session.removeStage()
            fputs("錯誤 / Error: 無法開始錄影 / Cannot start recording: \(error.localizedDescription)\n", stderr)
            return 1
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                if self.stopRequested { continuation.resume() } else { self.stopContinuation = continuation }
            }
        }
        finishStarted = uptime()
        return await finish(startedAt: finishStarted)
    }

    // MARK: Timer and stop requests (queue)

    private func startTimer() {
        startUptime = uptime()
        lastDiskCheck = startUptime
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer.setEventHandler { [weak self] in
            self?.onTick()
            self?.scheduleNextTick()
        }
        self.timer = timer
        scheduleNextTick()
        timer.resume()
    }

    // One-shot, re-armed every tick for the middle of the next slot (before the
    // first frame, simply every frame interval).
    private func scheduleNextTick() {
        guard let timer, !sealed else { return }
        var delay = 1.0 / Double(options.fps)
        if let next = pipeline.nextTickSeconds, let now = pipeline.sessionSeconds(hostNow()) {
            delay = min(max(next - now, 0.001), 1)
        }
        timer.schedule(deadline: .now() + delay, repeating: .never, leeway: .milliseconds(1))
    }

    private func onTick() {
        guard !sealed else { return }
        let now = hostNow()
        // Fix the endpoint before writing this tick's slot, so no frame lands at or past it.
        if let duration = options.duration, let seconds = pipeline.sessionSeconds(now), seconds >= duration {
            stopOnQueue(.durationReached)
        }
        do { try pipeline.tick(hostNow: now) } catch { return stopOnQueue(.failure(error.localizedDescription)) }
        guard pipeline.sessionSeconds(now) != nil else {
            if uptime() - startUptime > RecordingEngine.firstFrameTimeout {
                stopOnQueue(.failure("5 秒內沒有收到畫面 / No video frame within 5 seconds"))
            }
            return
        }
        if !announced {
            announced = true
            print("錄影中，按 Ctrl-C 停止 / Recording… press Ctrl-C to stop.")
        }
        // The microphone chosen at start must still exist; a removed device is an
        // error rather than a silently silent track. (A new OS default is ignored.)
        if let microphoneID, uptime() - lastMicrophoneCheck >= 1 {
            lastMicrophoneCheck = uptime()
            if AVCaptureDevice(uniqueID: microphoneID) == nil {
                stopOnQueue(.failure("麥克風已移除 / The microphone was disconnected"))
            }
        }
        if uptime() - lastDiskCheck >= 5 {
            lastDiskCheck = uptime()
            if let available = RecordingSession.availableCapacity(for: session.finalURL),
               available < RecordingEngine.lowDiskBytes {
                stopOnQueue(.diskLow)
            }
        }
    }

    func requestStop(_ reason: RecordingStopReason) {
        queue.async { self.stopOnQueue(reason) }
    }

    private func stopOnQueue(_ newReason: RecordingStopReason) {
        reason = reason.map { $0.merged(with: newReason) } ?? newReason
        if pipeline.endpointSeconds == nil, let seconds = pipeline.sessionSeconds(hostNow()) {
            let end = newReason == .durationReached ? (options.duration ?? seconds) : min(seconds, options.duration ?? seconds)
            pipeline.setEndpoint(end)
        }
        if !stopRequested {
            stopRequested = true
            if case .interrupt = newReason { print("\n正在停止 / Stopping…") }
            stopContinuation?.resume()
            stopContinuation = nil
        }
    }

    // MARK: ScreenCaptureKit callbacks (queue)

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !sealed, CMSampleBufferIsValid(sampleBuffer) else { return }
        do {
            switch type {
            case .screen:
                guard let info = (CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                                  as? [[SCStreamFrameInfo: Any]])?.first,
                      let raw = info[.status] as? Int, let status = SCFrameStatus(rawValue: raw) else { return }
                switch status {
                case .complete:
                    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    if let end = pipeline.endpointSeconds, let at = pipeline.sessionSeconds(pts), at >= end { return }
                    guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
                    try pipeline.video(pixels, hostTime: pts)
                case .suspended:
                    // Minimized (or closing: SCK then reports error -3815 within ~0.1 s).
                    pipeline.screenSuspended(hostTime: hostNow())
                default:
                    break
                }
            case .audio:
                try pipeline.audio(sampleBuffer, from: .system, arrival: hostNow())
            case .microphone:
                try pipeline.audio(sampleBuffer, from: .microphone, arrival: hostNow())
            @unknown default:
                break
            }
        } catch {
            stopOnQueue(.failure(error.localizedDescription))
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let code = (error as NSError).code
        queue.async {
            // -3815 (noCaptureSource): the window was closed.
            self.stopOnQueue(code == -3815 ? .windowClosed
                             : .failure("ScreenCaptureKit 停止 / stopped: \(error.localizedDescription)"))
        }
    }

    // MARK: Finish

    private func finish(startedAt: Double) async -> Int32 {
        signals.setHandler(nil) // repeated signals during stage finalization change nothing
        queue.sync { timer?.cancel(); timer = nil }
        let stream = queue.sync { self.stream }
        try? await stream?.stopCapture() // may already be stopped after a stream error
        // stopCapture has returned and the barrier below runs after every queued
        // callback; from here on late callbacks are ignored.
        let (hasVideo, stopReason) = queue.sync { () -> (Bool, RecordingStopReason) in
            sealed = true
            return (pipeline.hasVideo && pipeline.endpointSeconds != nil, reason ?? .interrupt)
        }
        guard hasVideo else {
            queue.sync { writer.cancel() }
            session.removeStage()
            if stopReason.isSuccess {
                print("已取消，沒有錄到畫面 / Cancelled; no video was recorded.")
                return 0
            }
            fputs("錯誤 / Error: \(stopReason.summary)\n", stderr)
            return 1
        }

        let endTime: CMTime
        do {
            endTime = try queue.sync { try pipeline.finish(waitingForWriter: { usleep(5_000) }) }
            try await writer.finish(at: endTime, on: queue)
        } catch {
            return keepStage("寫入影片失敗 / Writing the video failed: \(error.localizedDescription)",
                             file: session.captureURL)
        }
        let stats = queue.sync { pipeline.stats }

        var output = session.captureURL
        if options.audio == .both {
            print("正在混音，完成檔案中… / Mixing audio and finishing the file…")
            let mixer = AudioMixer()
            signals.setHandler { _ in mixer.cancel() }
            do {
                try await mixer.mix(session.captureURL, to: session.mixedURL)
                output = session.mixedURL
            } catch {
                signals.setHandler(nil)
                return keepStage("混音未完成；保留的 MOV 有兩條獨立音軌，尚非混好的 MP4 / Mixing did not finish; the kept MOV has two separate audio tracks and is not the mixed MP4: \(error.localizedDescription)",
                                 file: session.captureURL)
            }
            signals.setHandler(nil)
        }

        do {
            try await validate(output)
            try session.commit(output)
        } catch {
            return keepStage(error.localizedDescription, file: output)
        }
        printSummary(stats: stats, endTime: endTime, finishing: uptime() - startedAt, reason: stopReason)
        if !stopReason.isSuccess {
            fputs("錯誤 / Error: 錄影提前結束 / Recording ended early: \(stopReason.summary)\n", stderr)
            return 1
        }
        return 0
    }

    private func keepStage(_ message: String, file: URL) -> Int32 {
        fputs("錯誤 / Error: \(message)\n", stderr)
        if FileManager.default.fileExists(atPath: file.path) {
            fputs("已保留可能不完整的檔案 / Kept the possibly incomplete file: \(file.path)\n", stderr)
        } else {
            session.removeStage()
        }
        return 1
    }

    // Checks the finished file before it is moved into place: track counts, codec,
    // size, positive duration, and decodable first and last frames.
    private func validate(_ url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let expectedAudio = options.audio == .none ? 0 : 1
        guard videoTracks.count == 1, audioTracks.count == expectedAudio else {
            throw RecordingError("成品軌道數不符 / Unexpected tracks: \(videoTracks.count) video, \(audioTracks.count) audio")
        }
        guard let format = try await videoTracks[0].load(.formatDescriptions).first else {
            throw RecordingError("成品沒有影片格式 / Finished video has no format")
        }
        let codec = CMFormatDescriptionGetMediaSubType(format)
        let expectedCodec = options.codec == .hevc ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264
        let dimensions = CMVideoFormatDescriptionGetDimensions(format)
        guard codec == expectedCodec, Int(dimensions.width) == writer.width, Int(dimensions.height) == writer.height else {
            throw RecordingError("成品編碼或尺寸不符 / Unexpected codec or size")
        }
        let duration = try await asset.load(.duration)
        guard CMTimeGetSeconds(duration) > 0 else { throw RecordingError("成品長度為 0 / Finished file is empty") }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: CMTimeScale(options.fps))
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: CMTimeScale(options.fps))
        let last = CMTimeSubtract(duration, CMTime(value: 1, timescale: CMTimeScale(options.fps)))
        for time in [CMTime.zero, CMTimeMaximum(last, .zero)] {
            _ = try await generator.image(at: time)
        }
    }

    private func printSummary(stats: RecordingStats, endTime: CMTime, finishing: Double, reason: RecordingStopReason) {
        let size = (try? FileManager.default.attributesOfItem(atPath: session.finalURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        var lines = [
            "",
            "Snapparazzi 錄影完成 / recording saved.",
            "  檔案 / file: \(session.finalURL.path) (\(String(format: "%.1f", Double(size) / 1_048_576)) MiB)",
            "  長度 / length: \(String(format: "%.2f", CMTimeGetSeconds(endTime))) s；收尾 / finishing: \(String(format: "%.1f", finishing)) s",
            "  畫面 / video: \(writer.width)×\(writer.height) \(options.codec.rawValue) \(options.fps) fps；寫入 / written \(stats.writtenFrames)，略過 / skipped \(stats.droppedSlots + stats.writerBusySlots)（timing \(stats.droppedSlots)、encoder \(stats.writerBusySlots)），黑畫面 / black \(stats.blackFrames)",
            "  音訊 / audio: \(options.audio.rawValue)"
        ]
        for source in AudioSource.allCases {
            guard let audio = stats.audio[source] else { continue }
            let rate = Double(recordingSampleRate)
            lines.append("    \(source.rawValue): buffers \(audio.buffers)，補靜音 / padded \(String(format: "%.2f", Double(audio.paddedSamples) / rate)) s，裁掉 / trimmed \(String(format: "%.3f", Double(audio.trimmedSamples) / rate)) s，時鐘偏移 / clock drift \(String(format: "%+.1f", audio.drift * 1000)) ms（補償 / corrected \(audio.driftCorrection) samples）")
            if audio.buffers == 0 {
                lines.append("    警告：沒有收到任何 \(source.rawValue) 音訊資料，這條音軌是靜音 / Warning: no \(source.rawValue) audio arrived; this track is silent.")
            }
        }
        lines.append("  停止原因 / stopped by: \(reason.summary)")
        print(lines.joined(separator: "\n"))
    }
}
