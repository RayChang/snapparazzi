import Foundation
import CoreMedia
import CoreVideo
import AudioToolbox
@preconcurrency import AVFoundation

// Task 0 mix/remux probe: build a synthetic two-audio-track MOV, then mix it
// the way spec section 6 describes (compressed video passthrough + one AAC
// track from AVAssetReaderAudioMixOutput at gain 0.5 each) and check the result.

private struct Tone {
    let frequency: Double
    let amplitude: Float
    let sampleRate: Int
    let channels: Int
    let start: Double // seconds; a whole number of frames at sampleRate
}

private let fixtureSeconds = 4
private let fixtureFPS = 30
private let fixtureWidth = 320
private let fixtureHeight = 240
private let toneA = Tone(frequency: 440, amplitude: 0.5, sampleRate: 48000, channels: 2, start: 0)
private let toneB = Tone(frequency: 880, amplitude: 0.5, sampleRate: 44100, channels: 1, start: 0.5)
private let chunkFrames = 1024

private func makeTone(_ tone: Tone, from first: Int, frames: Int) throws -> CMSampleBuffer {
    var asbd = AudioStreamBasicDescription(
        mSampleRate: Double(tone.sampleRate), mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: UInt32(4 * tone.channels), mFramesPerPacket: 1,
        mBytesPerFrame: UInt32(4 * tone.channels), mChannelsPerFrame: UInt32(tone.channels),
        mBitsPerChannel: 32, mReserved: 0)
    var format: CMAudioFormatDescription?
    var status = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd,
        layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil,
        formatDescriptionOut: &format)
    guard status == noErr, let format else { throw ProbeFailure.message("Cannot create PCM format.") }
    var samples = [Float](repeating: 0, count: frames * tone.channels)
    for index in 0..<frames {
        let time = Double(first + index) / Double(tone.sampleRate)
        let value = tone.amplitude * Float(sin(2 * Double.pi * tone.frequency * time))
        for channel in 0..<tone.channels { samples[index * tone.channels + channel] = value }
    }
    let byteCount = samples.count * MemoryLayout<Float>.size
    var block: CMBlockBuffer?
    status = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
        blockLength: byteCount, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
        offsetToData: 0, dataLength: byteCount, flags: kCMBlockBufferAssureMemoryNowFlag,
        blockBufferOut: &block)
    guard status == noErr, let block else { throw ProbeFailure.message("Cannot allocate PCM block.") }
    status = samples.withUnsafeBytes {
        CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block,
                                      offsetIntoDestination: 0, dataLength: byteCount)
    }
    guard status == noErr else { throw ProbeFailure.message("Cannot fill PCM block.") }
    let startFrame = Int(tone.start * Double(tone.sampleRate))
    let pts = CMTime(value: CMTimeValue(startFrame + first), timescale: CMTimeScale(tone.sampleRate))
    var buffer: CMSampleBuffer?
    status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault,
        dataBuffer: block, formatDescription: format, sampleCount: frames,
        presentationTimeStamp: pts, packetDescriptions: nil, sampleBufferOut: &buffer)
    guard status == noErr, let buffer else { throw ProbeFailure.message("Cannot create PCM sample buffer.") }
    return buffer
}

// Every mutable field is touched only from blocks on `queue`; all writer
// readiness callbacks are scheduled on that same serial queue.
@available(macOS 15.0, *)
private final class FixtureJob: @unchecked Sendable {
    let queue = DispatchQueue(label: "dev.snapparazzi.probe.fixture")
    let writer: AVAssetWriter
    let video: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let audio: [(input: AVAssetWriterInput, tone: Tone)]
    var nextFrame = 0
    var nextSample: [Int]
    var closed: Set<String> = []
    var continuation: CheckedContinuation<Void, Error>?

    init(url: URL, codec: AVVideoCodecType) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec, AVVideoWidthKey: fixtureWidth, AVVideoHeightKey: fixtureHeight
        ])
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: fixtureWidth,
            kCVPixelBufferHeightKey as String: fixtureHeight
        ])
        audio = [toneA, toneB].map { tone in
            (AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: tone.sampleRate,
                AVNumberOfChannelsKey: tone.channels, AVEncoderBitRateKey: 64000 * tone.channels
            ]), tone)
        }
        nextSample = Array(repeating: 0, count: audio.count)
        for input in [video] + audio.map(\.input) {
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { throw ProbeFailure.message("Cannot add fixture input.") }
            writer.add(input)
        }
    }

    func run() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                self.continuation = continuation
                guard self.writer.startWriting() else {
                    return self.finish(self.writer.error ?? ProbeFailure.message("Fixture startWriting failed."))
                }
                self.writer.startSession(atSourceTime: .zero)
                self.video.requestMediaDataWhenReady(on: self.queue) { self.pumpVideo() }
                for index in self.audio.indices {
                    self.audio[index].input.requestMediaDataWhenReady(on: self.queue) { self.pumpAudio(index) }
                }
            }
        }
    }

    private func pumpVideo() {
        let total = fixtureSeconds * fixtureFPS
        while video.isReadyForMoreMediaData, continuation != nil, !closed.contains("video") {
            guard nextFrame < total else {
                video.markAsFinished()
                return close("video")
            }
            do {
                let time = CMTime(value: CMTimeValue(nextFrame), timescale: CMTimeScale(fixtureFPS))
                guard adaptor.append(try frame(nextFrame), withPresentationTime: time) else {
                    return finish(writer.error ?? ProbeFailure.message("Fixture video append failed."))
                }
                nextFrame += 1
            } catch { return finish(error) }
        }
    }

    private func pumpAudio(_ index: Int) {
        let (input, tone) = audio[index]
        let name = "audio\(index)"
        let total = (fixtureSeconds * tone.sampleRate) - Int(tone.start * Double(tone.sampleRate))
        while input.isReadyForMoreMediaData, continuation != nil, !closed.contains(name) {
            let first = nextSample[index]
            guard first < total else {
                input.markAsFinished()
                return close(name)
            }
            do {
                let frames = min(chunkFrames, total - first)
                guard input.append(try makeTone(tone, from: first, frames: frames)) else {
                    return finish(writer.error ?? ProbeFailure.message("Fixture audio append failed."))
                }
                nextSample[index] += frames
            } catch { return finish(error) }
        }
    }

    // A moving bar over a gradient, so every frame differs and inter-frame coding is exercised.
    private func frame(_ index: Int) throws -> CVPixelBuffer {
        guard let pool = adaptor.pixelBufferPool else { throw ProbeFailure.message("No fixture pixel pool.") }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else {
            throw ProbeFailure.message("Cannot create fixture frame.")
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else {
            throw ProbeFailure.message("Cannot map fixture frame.")
        }
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let bar = (index * 8) % fixtureWidth
        for y in 0..<fixtureHeight {
            for x in 0..<fixtureWidth {
                let pixel = base + y * row + x * 4
                let inBar = abs(x - bar) < 12
                pixel[0] = inBar ? 255 : UInt8((x + index * 3) & 255)
                pixel[1] = UInt8(y * 255 / fixtureHeight)
                pixel[2] = inBar ? 255 : UInt8((index * 7) & 255)
                pixel[3] = 255
            }
        }
        return buffer
    }

    private func close(_ name: String) {
        guard closed.insert(name).inserted, closed.count == 1 + audio.count else { return }
        writer.finishWriting {
            self.queue.async {
                self.finish(self.writer.status == .completed ? nil
                            : self.writer.error ?? ProbeFailure.message("Fixture finishWriting failed."))
            }
        }
    }

    private func finish(_ error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if let error {
            if writer.status == .writing { writer.cancelWriting() }
            continuation.resume(throwing: error)
        } else { continuation.resume() }
    }
}

// Same confinement rule as FixtureJob: both pumps and all state live on `queue`.
@available(macOS 15.0, *)
private final class MixJob: @unchecked Sendable {
    let queue = DispatchQueue(label: "dev.snapparazzi.probe.mix")
    let reader: AVAssetReader
    let writer: AVAssetWriter
    let pairs: [(name: String, output: AVAssetReaderOutput, input: AVAssetWriterInput)]
    var counts: [String: Int] = [:]
    var closed: Set<String> = []
    var continuation: CheckedContinuation<Void, Error>?

    init(reader: AVAssetReader, writer: AVAssetWriter,
         pairs: [(name: String, output: AVAssetReaderOutput, input: AVAssetWriterInput)]) {
        self.reader = reader
        self.writer = writer
        self.pairs = pairs
    }

    func run() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                self.continuation = continuation
                guard self.reader.startReading() else {
                    return self.finish(self.reader.error ?? ProbeFailure.message("Mix startReading failed."))
                }
                guard self.writer.startWriting() else {
                    return self.finish(self.writer.error ?? ProbeFailure.message("Mix startWriting failed."))
                }
                self.writer.startSession(atSourceTime: .zero)
                for pair in self.pairs {
                    let name = pair.name
                    pair.input.requestMediaDataWhenReady(on: self.queue) { self.pump(name) }
                }
            }
        }
    }

    private func pump(_ name: String) {
        guard let pair = pairs.first(where: { $0.name == name }) else { return }
        while pair.input.isReadyForMoreMediaData, continuation != nil, !closed.contains(name) {
            if let sample = pair.output.copyNextSampleBuffer() {
                guard pair.input.append(sample) else {
                    return finish(writer.error ?? ProbeFailure.message("Mix append failed: \(name)"))
                }
                counts[name, default: 0] += 1
            } else {
                if reader.status == .failed {
                    return finish(reader.error ?? ProbeFailure.message("Mix reader failed."))
                }
                pair.input.markAsFinished()
                closed.insert(name)
                if closed.count == pairs.count { complete() }
                return
            }
        }
    }

    private func complete() {
        guard reader.status == .completed else {
            return finish(reader.error ?? ProbeFailure.message("Mix reader ended in status \(reader.status.rawValue)."))
        }
        writer.finishWriting {
            self.queue.async {
                self.finish(self.writer.status == .completed ? nil
                            : self.writer.error ?? ProbeFailure.message("Mix finishWriting failed."))
            }
        }
    }

    private func finish(_ error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if let error {
            reader.cancelReading()
            if writer.status == .writing { writer.cancelWriting() }
            continuation.resume(throwing: error)
        } else { continuation.resume() }
    }
}

@available(macOS 15.0, *)
private func writeFixture(_ url: URL, codec: String) async throws {
    let job = try FixtureJob(url: url, codec: codec == "hevc" ? .hevc : .h264)
    try await job.run()
}

// Spec section 6: compressed video passthrough, all audio tracks mixed into one AAC.
@available(macOS 15.0, *)
func mixStage(_ input: URL, to output: URL) async throws {
    let asset = AVURLAsset(url: input)
    let videoTracks = try await asset.loadTracks(withMediaType: .video)
    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    guard videoTracks.count == 1, !audioTracks.isEmpty else {
        throw ProbeFailure.message("Stage must have 1 video and at least 1 audio track.")
    }
    let video = videoTracks[0]
    guard let videoFormat = try await video.load(.formatDescriptions).first else {
        throw ProbeFailure.message("Stage video has no format description.")
    }
    let transform = try await video.load(.preferredTransform)
    // A delayed track keeps timeRange.start at 0; its offset is a leading empty edit.
    var offsets: [Double] = []
    for track in audioTracks {
        let segments = try await track.load(.segments)
        offsets.append(segments.first.flatMap { $0.isEmpty ? seconds($0.timeMapping.target.duration) : 0 } ?? 0)
    }

    let reader = try AVAssetReader(asset: asset)
    let videoOutput = AVAssetReaderTrackOutput(track: video, outputSettings: nil)
    videoOutput.alwaysCopiesSampleData = false
    let audioOutput = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false
    ])
    let gain: Float = audioTracks.count > 1 ? 0.5 : 1
    let mix = AVMutableAudioMix()
    mix.inputParameters = audioTracks.map { track in
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.setVolume(gain, at: .zero)
        return parameters
    }
    audioOutput.audioMix = mix
    for readerOutput in [videoOutput, audioOutput] as [AVAssetReaderOutput] {
        guard reader.canAdd(readerOutput) else { throw ProbeFailure.message("Cannot add mix reader output.") }
        reader.add(readerOutput)
    }

    let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormat)
    videoInput.transform = transform
    let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000,
        AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192000
    ])
    for writerInput in [videoInput, audioInput] {
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else { throw ProbeFailure.message("Cannot add mix writer input.") }
        writer.add(writerInput)
    }

    let job = MixJob(reader: reader, writer: writer, pairs: [
        ("video", videoOutput, videoInput), ("audio", audioOutput, audioInput)
    ])
    let started = Date()
    try await job.run()
    let counts = await withCheckedContinuation { (continuation: CheckedContinuation<[String: Int], Never>) in
        job.queue.async { continuation.resume(returning: job.counts) }
    }
    emit(["event": "mixed", "input": input.path, "output": output.path,
          "source_audio_tracks": audioTracks.count, "source_audio_offsets": offsets,
          "gain_per_track": Double(gain), "appended": counts,
          "seconds": Date().timeIntervalSince(started)])
}

struct VideoFingerprint {
    let codec: String
    let width: Int32
    let height: Int32
    let pts: [Double]
    let dts: [Double]
    let hash: UInt64
    let editShift: Double
}

// Hash of every compressed video sample's bytes plus its timing, read without decoding.
@available(macOS 15.0, *)
func videoFingerprint(_ url: URL) async throws -> VideoFingerprint {
    let asset = AVURLAsset(url: url)
    guard let track = try await asset.loadTracks(withMediaType: .video).first,
          let format = try await track.load(.formatDescriptions).first else {
        throw ProbeFailure.message("No video track: \(url.path)")
    }
    // Compressed samples come back in media time. MP4 has no negative composition
    // offsets, so H.264 with B-frames is shifted later and mapped back by an edit;
    // subtract that shift so PTS are compared on the presentation timeline.
    let segments = try await track.load(.segments)
    let editShift = segments.first(where: { !$0.isEmpty }).map {
        (seconds($0.timeMapping.source.start) ?? 0) - (seconds($0.timeMapping.target.start) ?? 0)
    } ?? 0
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    output.alwaysCopiesSampleData = false
    reader.add(output)
    guard reader.startReading() else { throw reader.error ?? ProbeFailure.message("Cannot read video.") }
    var hash: UInt64 = 0xcbf29ce484222325
    var pts: [Double] = []
    var dts: [Double] = []
    while let sample = output.copyNextSampleBuffer() {
        guard CMSampleBufferGetNumSamples(sample) > 0 else { continue }
        let presentation = seconds(CMSampleBufferGetPresentationTimeStamp(sample)) ?? .nan
        pts.append(presentation - editShift)
        dts.append(seconds(CMSampleBufferGetDecodeTimeStamp(sample)) ?? presentation)
        guard let block = CMSampleBufferGetDataBuffer(sample) else {
            throw ProbeFailure.message("Compressed video sample has no data.")
        }
        let length = CMBlockBufferGetDataLength(block)
        var bytes = [UInt8](repeating: 0, count: length)
        guard CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &bytes) == noErr else {
            throw ProbeFailure.message("Cannot copy compressed video bytes.")
        }
        for byte in bytes { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        hash = (hash ^ UInt64(length)) &* 0x100000001b3
    }
    guard reader.status == .completed else { throw reader.error ?? ProbeFailure.message("Video read incomplete.") }
    let dimensions = CMVideoFormatDescriptionGetDimensions(format)
    return VideoFingerprint(codec: fourCC(CMFormatDescriptionGetMediaSubType(format)),
                            width: dimensions.width, height: dimensions.height,
                            pts: pts, dts: dts, hash: hash, editShift: editShift)
}

func comparePassthrough(_ source: VideoFingerprint, _ mixed: VideoFingerprint) -> (identical: Bool, report: [String: Any]) {
    func maxDelta(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return .infinity }
        return zip(a, b).map { abs($0 - $1) }.max() ?? 0
    }
    let ptsDelta = maxDelta(source.pts, mixed.pts)
    let dtsDelta = maxDelta(source.dts, mixed.dts)
    let reordered = zip(source.pts, source.dts).contains { abs($0 + source.editShift - $1) > 0.0001 }
    let identical = source.codec == mixed.codec && source.width == mixed.width
        && source.height == mixed.height && source.hash == mixed.hash
        && ptsDelta <= 0.0001 && dtsDelta <= 0.0001
    return (identical, [
        "identical": identical, "codec": [source.codec, mixed.codec],
        "pixels": [[source.width, source.height], [mixed.width, mixed.height]],
        "samples": [source.pts.count, mixed.pts.count],
        "bytes_hash_equal": source.hash == mixed.hash,
        "max_presentation_pts_delta": ptsDelta.isFinite ? ptsDelta : -1,
        "edit_shift": [source.editShift, mixed.editShift],
        "max_dts_delta": dtsDelta.isFinite ? dtsDelta : -1,
        "source_has_frame_reordering": reordered
    ])
}

// Decoded 48 kHz interleaved stereo; AVAssetReader honors edit lists (leading offsets become silence).
@available(macOS 15.0, *)
private func decodeStereo(_ url: URL) async throws -> [Float] {
    let asset = AVURLAsset(url: url)
    guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
        throw ProbeFailure.message("No audio track to decode.")
    }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false
    ])
    reader.add(output)
    guard reader.startReading() else { throw reader.error ?? ProbeFailure.message("Cannot decode audio.") }
    var samples: [Float] = []
    while let sample = output.copyNextSampleBuffer() {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
        let length = CMBlockBufferGetDataLength(block)
        var chunk = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
        let status = chunk.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!)
        }
        guard status == noErr else { throw ProbeFailure.message("Cannot copy decoded audio.") }
        samples += chunk
    }
    guard reader.status == .completed else { throw reader.error ?? ProbeFailure.message("Audio decode incomplete.") }
    return samples
}

// Hann-windowed Goertzel amplitude of one frequency in [start, start+length) of one channel.
private func toneAmplitude(_ samples: [Float], channel: Int, start: Double, length: Double,
                           frequency: Double) -> Double {
    let rate = 48000.0
    let first = Int(start * rate)
    let count = Int(length * rate)
    guard first >= 0, count > 1, (first + count) * 2 <= samples.count else { return .nan }
    let coefficient = 2 * cos(2 * Double.pi * frequency / rate)
    var s1 = 0.0, s2 = 0.0, windowSum = 0.0
    for index in 0..<count {
        let window = 0.5 - 0.5 * cos(2 * Double.pi * Double(index) / Double(count - 1))
        windowSum += window
        let value = Double(samples[(first + index) * 2 + channel]) * window
        let s = value + coefficient * s1 - s2
        s2 = s1
        s1 = s
    }
    let power = s1 * s1 + s2 * s2 - coefficient * s1 * s2
    return 2 * sqrt(max(power, 0)) / windowSum
}

@available(macOS 15.0, *)
func mixTest(codec: String, directory: URL) async throws {
    let stage = directory.appendingPathComponent("fixture-\(codec).mov")
    let final = directory.appendingPathComponent("mixed-\(codec).mp4")
    for url in [stage, final] where (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil {
        throw ProbeFailure.message("Refusing to overwrite: \(url.path)")
    }
    try await writeFixture(stage, codec: codec)
    emit(["event": "fixture", "file": stage.path, "codec": codec,
          "video": "\(fixtureWidth)x\(fixtureHeight) \(fixtureFPS)fps \(fixtureSeconds)s",
          "tone_a": "440Hz 48k stereo amp 0.5 from 0s", "tone_b": "880Hz 44.1k mono amp 0.5 from 0.5s"])
    try await mixStage(stage, to: final)

    let asset = AVURLAsset(url: final)
    let videoCount = try await asset.loadTracks(withMediaType: .video).count
    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    var audioFormat = "missing"
    if let track = audioTracks.first, let format = try await track.load(.formatDescriptions).first,
       let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format) {
        audioFormat = "\(fourCC(asbd.pointee.mFormatID)) \(Int(asbd.pointee.mSampleRate)) \(asbd.pointee.mChannelsPerFrame)ch"
    }
    let tracksOK = videoCount == 1 && audioTracks.count == 1 && audioFormat == "aac  48000 2ch"
    let duration = seconds(try await asset.load(.duration)) ?? 0

    let (videoOK, videoReport) = comparePassthrough(try await videoFingerprint(stage),
                                                    try await videoFingerprint(final))

    let pcm = try await decodeStereo(final)
    func amp(_ channel: Int, _ start: Double, _ length: Double, _ frequency: Double) -> Double {
        toneAmplitude(pcm, channel: channel, start: start, length: length, frequency: frequency)
    }
    let expected = 0.5 * 0.5 // tone amplitude x mix gain
    let pre440 = [amp(0, 0.1, 0.3, 440), amp(1, 0.1, 0.3, 440)]
    let pre880 = [amp(0, 0.1, 0.3, 880), amp(1, 0.1, 0.3, 880)]
    let post440 = [amp(0, 1.0, 2.5, 440), amp(1, 1.0, 2.5, 440)]
    let post880 = [amp(0, 1.0, 2.5, 880), amp(1, 1.0, 2.5, 880)]
    // Onset: centre of the first 20 ms window whose 880 Hz level reaches half its steady level.
    let steady880 = post880.max() ?? 0
    var onset: Double?
    var start = 0.3
    while start < 0.8, onset == nil {
        if max(amp(0, start, 0.02, 880), amp(1, start, 0.02, 880)) >= steady880 / 2 { onset = start + 0.01 }
        start += 0.001
    }
    let tolerance = max(1.0 / Double(fixtureFPS), 1024.0 / 48000.0)
    let onsetOK = onset.map { abs($0 - toneB.start) <= tolerance } ?? false
    let gainOK = (pre440 + post440).allSatisfy { abs($0 - expected) <= expected * 0.1 }
    let separationOK = pre880.allSatisfy { $0 < 0.01 } && post880.allSatisfy { $0 > 0.1 }
    let durationOK = abs(duration - Double(fixtureSeconds)) <= 0.05
    let pass = tracksOK && videoOK && onsetOK && gainOK && separationOK && durationOK
    emit(["event": "mix_test", "codec": codec, "file": final.path, "pass": pass,
          "tracks": ["ok": tracksOK, "video": videoCount, "audio": audioTracks.count, "audio_format": audioFormat],
          "duration": ["ok": durationOK, "seconds": duration],
          "video_passthrough": videoReport,
          "levels": ["ok": gainOK && separationOK, "expected_per_tone": expected,
                     "pre_440_LR": pre440, "pre_880_LR": pre880,
                     "post_440_LR": post440, "post_880_LR": post880],
          "tone_b_onset": ["ok": onsetOK, "seconds": onset as Any? ?? NSNull(),
                           "expected": toneB.start, "tolerance": tolerance]])
    guard pass else { throw ProbeFailure.message("mix-test \(codec) failed; see mix_test event.") }
}

@available(macOS 15.0, *)
func mixRecording(_ input: URL, to output: URL) async throws {
    if (try? FileManager.default.attributesOfItem(atPath: output.path)) != nil {
        throw ProbeFailure.message("Refusing to overwrite: \(output.path)")
    }
    try await mixStage(input, to: output)
    let (identical, report) = comparePassthrough(try await videoFingerprint(input),
                                                 try await videoFingerprint(output))
    emit(["event": "video_passthrough", "report": report])
    try await inspect(output)
    guard identical else { throw ProbeFailure.message("Video was not passed through unchanged.") }
}
