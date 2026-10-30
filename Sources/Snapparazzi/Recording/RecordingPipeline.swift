import Foundation
import CoreMedia
import CoreVideo
@preconcurrency import AVFoundation

// The recording timeline, independent of ScreenCaptureKit so it can be driven by
// synthetic buffers and a fake clock in tests.
//
// - t0 is the host-clock PTS of the first complete video frame; every source is
//   placed at (sourcePTS - t0). Nothing is shifted to start at zero on its own.
// - Video is written on a fixed grid of slots n/fps chosen from the host clock,
//   repeating the latest frame when nothing new arrived and skipping slots that
//   are already late instead of bursting to catch up.
// - Each audio source is converted to 48 kHz stereo and written at a sample cursor.
//   A gap is filled with silence, an overlap is trimmed, and a source that falls
//   more than `audioWatermark` behind the clock is padded with silence.
//
// Not thread-safe: every method must be called on the same serial queue.
final class RecordingPipeline {
    static let audioWatermark = 0.25
    static let preStartAudioLimit = 0.25
    static let pendingAudioLimit = Int64(recordingSampleRate) // one second
    static let blackAfterSuspend = 1.0
    static let continuityTolerance = Int64(recordingSampleRate / 100) // 10 ms

    let fps: Int32
    let writer: StageWriter
    private(set) var t0: CMTime?
    private(set) var stats = RecordingStats()
    private var latestFrame: CVPixelBuffer?
    private var suspendedAt: Double?
    private var nextSlot: Int64 = 0
    private var endpoint: Double?
    private var tracks: [AudioSource: AudioTrack] = [:]
    private let pcm: PCMSampleBufferFactory

    private final class AudioTrack {
        var normalizer: AudioNormalizer?
        var cursor: Int64 = 0
        var pending: [CMSampleBuffer] = []
        var pendingSamples: Int64 = 0
        var preStart: [CMSampleBuffer] = []
        var stats = AudioTrackStats()
    }

    init(fps: Int, writer: StageWriter, audioSources: [AudioSource]) throws {
        self.fps = Int32(fps)
        self.writer = writer
        pcm = try PCMSampleBufferFactory()
        for source in audioSources { tracks[source] = AudioTrack() }
    }

    var hasVideo: Bool { stats.writtenFrames > 0 }

    func sessionSeconds(_ hostTime: CMTime) -> Double? {
        guard let t0 else { return nil }
        return CMTimeGetSeconds(CMTimeSubtract(hostTime, t0))
    }

    // MARK: Video

    func video(_ pixelBuffer: CVPixelBuffer, hostTime: CMTime) throws {
        stats.sourceFrames += 1
        latestFrame = pixelBuffer
        suspendedAt = nil
        guard t0 == nil else { return }
        t0 = hostTime
        try writeSlot(0)
        nextSlot = 1
        for (source, track) in tracks {
            let early = track.preStart
            track.preStart = []
            for buffer in early { try place(buffer, on: track, source: source) }
        }
    }

    func screenSuspended(hostTime: CMTime) {
        guard suspendedAt == nil, let seconds = sessionSeconds(hostTime) else { return }
        suspendedAt = seconds
    }

    // Called on a timer: writes the current video slot and pads lagging audio.
    func tick(hostNow: CMTime) throws {
        guard let now = sessionSeconds(hostNow) else { return }
        let limit = endpoint.map { min(now, $0) } ?? now
        var target = slot(at: limit)
        if let endpoint { target = min(target, Int64((endpoint * Double(fps)).rounded(.up)) - 1) }
        if target >= nextSlot {
            stats.droppedSlots += Int(target - nextSlot)
            try writeSlot(target, sessionNow: limit)
            nextSlot = target + 1
        }
        let watermark = Int64(((limit - RecordingPipeline.audioWatermark) * Double(recordingSampleRate)).rounded(.down))
        for (source, track) in tracks {
            if watermark > track.cursor { try pad(track, source: source, to: watermark) }
            try drain(track, source: source)
        }
    }

    // The epsilon keeps 0.1 s × 30 (= 2.9999…) on slot 3 instead of falling back to slot 2.
    // Session time of the middle of the next video slot. Ticking there keeps timer
    // jitter far from slot boundaries, so no tick lands two slots at once.
    var nextTickSeconds: Double? {
        t0 == nil ? nil : (Double(nextSlot) + 0.5) / Double(fps)
    }

    private func slot(at seconds: Double) -> Int64 {
        Int64((seconds * Double(fps) + 1e-6).rounded(.down))
    }

    private func writeSlot(_ slot: Int64, sessionNow: Double = 0) throws {
        let black = suspendedAt.map { sessionNow - $0 > RecordingPipeline.blackAfterSuspend } ?? false
        guard let frame = black ? writer.blackFrame : latestFrame else { return }
        if try writer.appendVideo(frame, at: CMTime(value: slot, timescale: fps)) {
            stats.writtenFrames += 1
            if black { stats.blackFrames += 1 }
        } else {
            stats.writerBusySlots += 1
        }
    }

    // MARK: Audio

    func audio(_ sampleBuffer: CMSampleBuffer, from source: AudioSource) throws {
        guard let track = tracks[source] else { return }
        track.stats.buffers += 1
        guard t0 != nil else {
            // Keep at most ~250 ms of audio that arrives before the first frame.
            track.preStart.append(sampleBuffer)
            while let first = track.preStart.first,
                  let last = track.preStart.last,
                  CMTimeGetSeconds(CMTimeSubtract(CMSampleBufferGetPresentationTimeStamp(last),
                                                  CMSampleBufferGetPresentationTimeStamp(first)))
                    > RecordingPipeline.preStartAudioLimit {
                track.preStart.removeFirst()
            }
            return
        }
        try place(sampleBuffer, on: track, source: source)
        try drain(track, source: source)
    }

    private func place(_ sampleBuffer: CMSampleBuffer, on track: AudioTrack, source: AudioSource) throws {
        guard let t0, let format = AudioNormalizer.format(of: sampleBuffer) else { return }
        if track.normalizer == nil || track.normalizer?.inputFormat != format {
            if let old = track.normalizer { try write(old.drain(), to: track, source: source) }
            track.normalizer = try AudioNormalizer(inputFormat: format)
        }
        guard let normalizer = track.normalizer else { return }
        let start = CMTimeGetSeconds(CMTimeSubtract(CMSampleBufferGetPresentationTimeStamp(sampleBuffer), t0))
        let position = Int64((start * Double(recordingSampleRate)).rounded())
        if position - track.cursor > RecordingPipeline.continuityTolerance {
            // A gap: finish the previous segment, then fill the gap with silence.
            try write(normalizer.drain(), to: track, source: source)
            if position > track.cursor { try pad(track, source: source, to: position) }
        }
        var samples = try normalizer.convert(sampleBuffer)
        let overlap = track.cursor - position
        if overlap > RecordingPipeline.continuityTolerance {
            // Already covered (by silence or earlier data): drop the overlapping part.
            let drop = min(Int(overlap) * recordingChannels, samples.count)
            samples.removeFirst(drop)
            track.stats.trimmedSamples += Int64(drop / recordingChannels)
        }
        try write(samples, to: track, source: source)
    }

    private func pad(_ track: AudioTrack, source: AudioSource, to requested: Int64) throws {
        let chunk = Int64(recordingSampleRate / 10)
        // Never past the endpoint: write() clips there, so the cursor would stop moving.
        let position = endpoint.map { min(requested, Int64(($0 * Double(recordingSampleRate)).rounded())) } ?? requested
        while track.cursor < position {
            let frames = min(chunk, position - track.cursor)
            track.stats.paddedSamples += frames
            try write([Float](repeating: 0, count: Int(frames) * recordingChannels), to: track, source: source)
        }
    }

    // Appends samples at the cursor, clipped to the endpoint once it is known.
    private func write(_ samples: [Float], to track: AudioTrack, source: AudioSource) throws {
        var frames = Int64(samples.count / recordingChannels)
        guard frames > 0 else { return }
        if let endpoint {
            let end = Int64((endpoint * Double(recordingSampleRate)).rounded())
            frames = max(0, min(frames, end - track.cursor))
            guard frames > 0 else { return }
        }
        let buffer = try pcm.make(samples[0..<Int(frames) * recordingChannels], start: track.cursor)
        track.cursor += frames
        track.pending.append(buffer)
        track.pendingSamples += frames
        if track.pendingSamples > RecordingPipeline.pendingAudioLimit {
            throw RecordingError("音訊寫入跟不上（超過 1 秒）/ Audio writer fell more than 1 second behind (\(source.rawValue))")
        }
    }

    private func drain(_ track: AudioTrack, source: AudioSource) throws {
        while let next = track.pending.first, writer.audioReady(source) {
            try writer.appendAudio(next, from: source)
            track.pending.removeFirst()
            track.pendingSamples -= Int64(CMSampleBufferGetNumSamples(next))
        }
    }

    // MARK: Stop

    // Fixes the end of the recording (seconds from t0). Later video and audio is clipped.
    func setEndpoint(_ seconds: Double) {
        if endpoint == nil { endpoint = max(0, seconds) }
    }

    var endpointSeconds: Double? { endpoint }

    // After the sources are closed: write the last video slot and pad or flush
    // every audio track exactly to the endpoint. Returns the endpoint time.
    func finish(waitingForWriter wait: () -> Void) throws -> CMTime {
        guard let endpoint else { throw RecordingError("沒有設定終點 / Endpoint not set") }
        // The last slot that starts strictly before the endpoint.
        let lastSlot = Int64((endpoint * Double(fps)).rounded(.up)) - 1
        if lastSlot >= nextSlot, latestFrame != nil {
            try writeSlot(lastSlot, sessionNow: endpoint)
            nextSlot = lastSlot + 1
        }
        let end = Int64((endpoint * Double(recordingSampleRate)).rounded())
        for (source, track) in tracks {
            if let normalizer = track.normalizer { try write(normalizer.drain(), to: track, source: source) }
            if track.cursor < end { try pad(track, source: source, to: end) }
            var waited = 0
            while !track.pending.isEmpty {
                try drain(track, source: source)
                if track.pending.isEmpty { break }
                waited += 1
                guard waited < 400 else {
                    throw RecordingError("音訊收尾逾時 / Timed out flushing audio (\(source.rawValue))")
                }
                wait()
            }
            stats.audio[source] = track.stats
        }
        return CMTime(value: end, timescale: CMTimeScale(recordingSampleRate))
    }

    func audioStats() -> [AudioSource: AudioTrackStats] {
        tracks.mapValues(\.stats)
    }
}
