import Foundation
import CoreGraphics
import CoreMedia
import CoreVideo
import AudioToolbox
@preconcurrency import AVFoundation
@preconcurrency import ScreenCaptureKit

// A short-lived diagnostic, not the production recording engine. Every mutable
// capture/writer field is confined to queue. SCK delivers samples on this same
// queue: there is no unbounded per-sample Task or additional forwarding queue.
@available(macOS 15.0, *)
final class StreamProbe: NSObject, SCStreamOutput, SCStreamDelegate {
    struct Snapshot {
        let elapsed: Double?
        let stopped: Bool
        let error: String?
    }

    private let queue = DispatchQueue(label: "dev.snapparazzi.probe.media")
    private let options: CaptureOptions
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let system: AVAssetWriterInput?
    private let microphone: AVAssetWriterInput?
    private var stream: SCStream?
    private var epoch: CMTime?
    private var endpoint: CMTime?
    private var sealed = false
    private var failure: String?
    private var seen: [String: Int] = [:]
    private var written: [String: Int] = [:]
    private var dropped: [String: Int] = [:]
    private var lastPTS: [String: CMTime] = [:]
    // Complete screen frames split by SCK's dirtyRects attachment: "unchanged"
    // means SCK reported no changed region, "missing" means no attachment.
    private var screenDirty: [String: Int] = [:]
    // Per-frame dirty area as a fraction of the canvas (rects may overlap).
    private var dirtyFractionMin = Double.infinity
    private var dirtyFractionMax = 0.0
    private var dirtyFractionSum = 0.0
    private let canvasArea: Double

    init(options: CaptureOptions, window: SCWindow, microphoneID: String?) throws {
        self.options = options
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        // Probe caps its fixed canvas at 1280px for reproducible short tests.
        // Resizing/Retina behavior is observed, not asserted as production-ready.
        let sourceWidth = filter.contentRect.width * scale
        let sourceHeight = filter.contentRect.height * scale
        guard sourceWidth.isFinite, sourceHeight.isFinite,
              sourceWidth >= 2, sourceHeight >= 2 else {
            throw ProbeFailure.message("Invalid source pixel dimensions.")
        }
        let factor = min(1, 1280 / max(sourceWidth, sourceHeight))
        let width = max(2, Int(sourceWidth * factor) / 2 * 2)
        let height = max(2, Int(sourceHeight * factor) / 2 * 2)
        canvasArea = Double(width * height)
        writer = try AVAssetWriter(outputURL: options.output, fileType: .mov)
        let codec: AVVideoCodecType = options.codec == "h264" ? .h264 : .hevc
        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec, AVVideoWidthKey: width, AVVideoHeightKey: height
        ])
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192000
        ]
        system = options.audio.system
            ? AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings) : nil
        microphone = options.audio.microphone
            ? AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings) : nil
        super.init()
        for input in [video, system, microphone].compactMap({ $0 }) {
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else {
                throw ProbeFailure.message("Cannot add \(input.mediaType.rawValue) writer input.")
            }
            writer.add(input)
        }
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 3
        config.showsCursor = false
        config.capturesAudio = options.audio.system
        config.sampleRate = 48000
        config.channelCount = 2
        config.captureMicrophone = options.audio.microphone
        if let microphoneID { config.microphoneCaptureDeviceID = microphoneID }
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if options.audio.system {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        }
        if options.audio.microphone {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue)
        }
        self.stream = stream
        emit(["event": "configured", "window_id": window.windowID,
              "owner_pid": window.owningApplication?.processID ?? 0,
              "source_pixels": [Double(sourceWidth), Double(sourceHeight)],
              "canvas_pixels": [width, height], "scale": Double(scale),
              "audio": options.audio.rawValue, "codec": options.codec,
              "warning": "Diagnostic MOV: both uses separate audio tracks; no mixing yet."])
    }

    func start() async throws {
        guard queue.sync(execute: { writer.startWriting() }) else {
            throw ProbeFailure.message(writer.error?.localizedDescription ?? "startWriting failed.")
        }
        do {
            guard let stream else { throw ProbeFailure.message("Stream not initialized.") }
            try await stream.startCapture()
        } catch {
            queue.sync { writer.cancelWriting() }
            throw error
        }
    }

    func snapshot() -> Snapshot {
        queue.sync {
            let elapsed = epoch.flatMap { seconds(CMTimeSubtract(CMClockGetTime(CMClockGetHostTimeClock()), $0)) }
            return Snapshot(elapsed: elapsed, stopped: endpoint != nil, error: failure)
        }
    }

    func requestStop() {
        queue.sync { establishEndpoint() }
    }

    private func establishEndpoint() {
        guard endpoint == nil else { return }
        if let epoch {
            let elapsed = CMTimeSubtract(CMClockGetTime(CMClockGetHostTimeClock()), epoch)
            endpoint = CMTimeMinimum(CMTimeMaximum(elapsed, .zero),
                                     CMTime(seconds: options.duration, preferredTimescale: 48000))
        } else { endpoint = .zero }
    }

    private func fail(_ message: String) {
        if failure == nil { failure = message }
        establishEndpoint()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { self.fail("SCStream: \(error.localizedDescription)") }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !sealed else { return }
        let name: String
        let input: AVAssetWriterInput?
        switch outputType {
        case .screen: name = "screen"; input = video
        case .audio: name = "system"; input = system
        case .microphone: name = "microphone"; input = microphone
        @unknown default: return
        }
        seen[name, default: 0] += 1
        guard CMSampleBufferIsValid(sampleBuffer),
              CMSampleBufferDataIsReady(sampleBuffer), let input else {
            dropped["\(name)_invalid", default: 0] += 1
            return
        }
        let sourcePTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard let sourceSeconds = seconds(sourcePTS) else {
            fail("Invalid \(name) PTS.")
            return
        }
        if seen[name, default: 0] <= 8 {
            var metadata: [String: Any] = [
                "event": "sample", "source": name, "pts": sourceSeconds,
                "host_time": seconds(CMClockGetTime(CMClockGetHostTimeClock())) as Any? ?? NSNull(),
                "duration": seconds(CMSampleBufferGetDuration(sampleBuffer)) as Any? ?? NSNull(),
                "samples": CMSampleBufferGetNumSamples(sampleBuffer)
            ]
            if outputType != .screen,
               let description = CMSampleBufferGetFormatDescription(sampleBuffer),
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description) {
                metadata["sample_rate"] = asbd.pointee.mSampleRate
                metadata["channels"] = asbd.pointee.mChannelsPerFrame
            }
            if outputType == .screen,
               let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer,
                    createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
               let frame = attachments.first {
                for (label, key) in [("frame_status", SCStreamFrameInfo.status),
                                     ("content_rect", .contentRect),
                                     ("content_scale", .contentScale),
                                     ("scale_factor", .scaleFactor)] {
                    metadata[label] = String(describing: frame[key] ?? NSNull())
                }
                metadata["dirty_rects"] = (frame[.dirtyRects] as? [Any]).map { rects in
                    rects.map { rect -> String in
                        guard let dict = rect as? NSDictionary,
                              let r = CGRect(dictionaryRepresentation: dict) else { return "?" }
                        return "\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height))"
                    }
                } as Any? ?? NSNull()
            }
            emit(metadata)
        }
        if outputType == .screen {
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer,
                       createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let rawStatus = attachments.first?[.status] as? Int,
                  let status = SCFrameStatus(rawValue: rawStatus), status == .complete else {
                dropped["screen_incomplete", default: 0] += 1
                return
            }
            let dirtyKey: String
            if let rects = attachments.first?[.dirtyRects] as? [Any] {
                dirtyKey = rects.isEmpty ? "unchanged" : "changed"
                let area = rects.reduce(0.0) { sum, rect in
                    guard let dict = rect as? NSDictionary,
                          let r = CGRect(dictionaryRepresentation: dict) else { return sum }
                    return sum + Double(r.width * r.height)
                }
                let fraction = area / canvasArea
                dirtyFractionMin = min(dirtyFractionMin, fraction)
                dirtyFractionMax = max(dirtyFractionMax, fraction)
                dirtyFractionSum += fraction
            } else { dirtyKey = "missing" }
            screenDirty[dirtyKey, default: 0] += 1
            if epoch == nil {
                epoch = sourcePTS
                writer.startSession(atSourceTime: .zero)
                emit(["event": "epoch", "source_pts": sourceSeconds])
            }
        }
        guard let epoch else {
            dropped["\(name)_before_video", default: 0] += 1
            return
        }
        let normalized = CMTimeSubtract(sourcePTS, epoch)
        guard CMTimeCompare(normalized, .zero) >= 0 else {
            // Intentionally not the production sample-accurate PCM trimmer.
            dropped["\(name)_negative_start", default: 0] += 1
            return
        }
        let limit = endpoint ?? CMTime(seconds: options.duration, preferredTimescale: 48000)
        guard CMTimeCompare(normalized, limit) < 0 else {
            dropped["\(name)_after_endpoint", default: 0] += 1
            return
        }
        if let last = lastPTS[name], CMTimeCompare(normalized, last) <= 0 {
            fail("Non-increasing \(name) PTS; inspect raw sample logs.")
            return
        }
        guard input.isReadyForMoreMediaData else {
            if outputType == .screen { dropped["screen_backpressure", default: 0] += 1 }
            else { fail("\(name) writer backpressure; audio was not silently discarded.") }
            return
        }
        do {
            let retimed = try subtractEpoch(epoch, from: sampleBuffer)
            guard input.append(retimed) else {
                fail(writer.error?.localizedDescription ?? "append failed: \(name)")
                return
            }
            lastPTS[name] = normalized
            written[name, default: 0] += 1
        } catch { fail(error.localizedDescription) }
    }

    private func dirtyAreaSummary() -> Any {
        let frames = screenDirty["changed", default: 0] + screenDirty["unchanged", default: 0]
        guard frames > 0 else { return NSNull() }
        return ["min": dirtyFractionMin, "max": dirtyFractionMax,
                "mean": dirtyFractionSum / Double(frames)]
    }

    func finish() async -> Bool {
        requestStop()
        do { try await stream?.stopCapture() }
        catch { queue.sync { fail("stopCapture: \(error.localizedDescription)") } }
        // stopCapture completes before this serial barrier. No queued callback
        // can race markAsFinished; callbacks after sealing safely do nothing.
        let hasVideo: Bool = queue.sync {
            sealed = true
            guard written["screen", default: 0] > 0, writer.status == .writing else {
                if writer.status == .writing { writer.cancelWriting() }
                return false
            }
            if let endpoint, CMTimeCompare(endpoint, .zero) > 0 {
                writer.endSession(atSourceTime: endpoint)
            }
            for input in [video, system, microphone].compactMap({ $0 }) {
                input.markAsFinished()
            }
            return true
        }
        if hasVideo {
            // AVAssetWriter is non-Sendable, so start finishing via a synchronous
            // (non-escaping) hop onto queue; finishWriting itself returns at once.
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                queue.sync { writer.finishWriting { continuation.resume() } }
            }
        }
        return queue.sync {
            let complete = hasVideo && writer.status == .completed && failure == nil
            emit(["event": "capture_result", "writer_completed": writer.status == .completed,
                  "success": complete, "seen": seen, "written": written, "dropped": dropped,
                  "screen_dirty": screenDirty,
                  "screen_dirty_area_fraction": dirtyAreaSummary(),
                  "error": (failure ?? writer.error?.localizedDescription) as Any? ?? NSNull(),
                  "output": options.output.path,
                  "note": "Completion does not prove App isolation, audible audio, or synchronization."])
            return complete
        }
    }
}

private func subtractEpoch(_ epoch: CMTime, from buffer: CMSampleBuffer) throws -> CMSampleBuffer {
    var count = 0
    var status = CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: 0,
                                                       arrayToFill: nil, entriesNeededOut: &count)
    guard status == noErr, count > 0 else { throw ProbeFailure.message("Cannot read sample timing.") }
    var timing = Array(repeating: CMSampleTimingInfo(duration: .invalid,
                        presentationTimeStamp: .invalid, decodeTimeStamp: .invalid), count: count)
    status = CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: count,
                                                   arrayToFill: &timing, entriesNeededOut: &count)
    guard status == noErr else { throw ProbeFailure.message("Cannot copy sample timing.") }
    for index in timing.indices {
        timing[index].presentationTimeStamp = CMTimeSubtract(timing[index].presentationTimeStamp, epoch)
        if timing[index].decodeTimeStamp.isValid {
            timing[index].decodeTimeStamp = CMTimeSubtract(timing[index].decodeTimeStamp, epoch)
        }
    }
    var result: CMSampleBuffer?
    status = CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault,
                 sampleBuffer: buffer, sampleTimingEntryCount: timing.count,
                 sampleTimingArray: &timing, sampleBufferOut: &result)
    guard status == noErr, let result else { throw ProbeFailure.message("Cannot normalize sample timing.") }
    return result
}
