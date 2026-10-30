import Foundation
import CoreMedia
import CoreVideo
@preconcurrency import AVFoundation

// Synthetic ScreenCaptureKit-like input for driving RecordingPipeline with a fake clock.

let testWidth = 320
let testHeight = 240
let hostBase = CMTime(seconds: 1_450_000, preferredTimescale: 1_000_000_000) // non-zero, like SCK

func host(_ seconds: Double) -> CMTime {
    CMTimeAdd(hostBase, CMTime(seconds: seconds, preferredTimescale: 1_000_000_000))
}

func makeFrame(red: UInt8, green: UInt8, blue: UInt8) -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(kCFAllocatorDefault, testWidth, testHeight, kCVPixelFormatType_32BGRA,
                        [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &buffer)
    let frame = buffer!
    CVPixelBufferLockBaseAddress(frame, [])
    let base = CVPixelBufferGetBaseAddress(frame)!
    let rowBytes = CVPixelBufferGetBytesPerRow(frame)
    let pixel = UInt32(blue) | UInt32(green) << 8 | UInt32(red) << 16 | 0xFF00_0000
    for row in 0..<testHeight {
        let line = base.advanced(by: row * rowBytes).assumingMemoryBound(to: UInt32.self)
        for column in 0..<testWidth { line[column] = pixel }
    }
    CVPixelBufferUnlockBaseAddress(frame, [])
    return frame
}

// A Float32 tone buffer in the given layout, phase-continuous across chunks.
func makeTone(frequency: Double, amplitude: Float, sampleRate: Double, channels: UInt32,
              interleaved: Bool, firstFrame: Int, frames: Int, pts: CMTime) -> CMSampleBuffer {
    makeTone(frequencyAt: { _ in frequency }, amplitude: amplitude, sampleRate: sampleRate, channels: channels,
             interleaved: interleaved, firstFrame: firstFrame, frames: frames, pts: pts)
}

// `frequencyAt` takes the source's sample index, so a tone can change at a chosen sample.
func makeTone(frequencyAt: (Int) -> Double, amplitude: Float, sampleRate: Double, channels: UInt32,
              interleaved: Bool, firstFrame: Int, frames: Int, pts: CMTime) -> CMSampleBuffer {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                               channels: channels, interleaved: interleaved)!
    let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
    pcm.frameLength = AVAudioFrameCount(frames)
    let data = pcm.floatChannelData!
    for index in 0..<frames {
        let value = amplitude * Float(sin(2 * Double.pi * frequencyAt(firstFrame + index) * Double(firstFrame + index) / sampleRate))
        for channel in 0..<Int(channels) {
            if interleaved { data[0][index * Int(channels) + channel] = value } else { data[channel][index] = value }
        }
    }
    var description: CMAudioFormatDescription?
    CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: format.streamDescription,
                                   layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
                                   extensions: nil, formatDescriptionOut: &description)
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
                                    presentationTimeStamp: pts, decodeTimeStamp: .invalid)
    var sampleBuffer: CMSampleBuffer?
    CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
                         makeDataReadyCallback: nil, refcon: nil, formatDescription: description,
                         sampleCount: frames, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                         sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sampleBuffer)
    CMSampleBufferSetDataBufferFromAudioBufferList(sampleBuffer!, blockBufferAllocator: kCFAllocatorDefault,
                                                   blockBufferMemoryAllocator: kCFAllocatorDefault,
                                                   flags: 0, bufferList: pcm.audioBufferList)
    return sampleBuffer!
}

struct SimulatedAudio {
    let source: AudioSource
    var frequency = 440.0
    var amplitude: Float = 0.5
    var sampleRate = 48_000.0
    var channels: UInt32 = 2
    var interleaved = false
    var start = 0.0                       // session seconds of the first sample
    var gaps: [ClosedRange<Double>] = []  // chunks starting inside are never delivered
    var latency = 0.06                    // delivered this long after their PTS
    var chunkFrames = 960
    var duplicateChunk: Int?              // deliver this chunk twice
    // Device clock error, e.g. -0.001 = 1000 ppm slow: timestamps count samples at the
    // nominal rate, but the samples really arrive at sampleRate × (1 + clockError).
    var clockError = 0.0
    var switchFrequency: (to: Double, atRealTime: Double)?
}

enum SimulatedScreen {
    case color(UInt8, UInt8, UInt8)
    case suspended
    case nothing
}

struct SimulationResult {
    let stats: RecordingStats
    let audio: [AudioSource: AudioTrackStats]
    let endpoint: CMTime
}

// Runs a recording through RecordingPipeline + StageWriter in fake time. Each step:
// deliver due audio, then the screen event, then tick. Audio keeps arriving for
// 0.15 s after the endpoint, like buffers in flight while stopCapture finishes.
func simulate(url: URL, fileType: AVFileType, fps: Int = 30, codec: VideoCodec = .h264,
              duration: Double, audio: [SimulatedAudio],
              screen: (Double) -> SimulatedScreen = { _ in .color(200, 40, 40) },
              skipTicks: ClosedRange<Double>? = nil) async throws -> SimulationResult {
    let queue = DispatchQueue(label: "test.media")
    let writer = try StageWriter(url: url, fileType: fileType, width: testWidth, height: testHeight,
                                 fps: fps, codec: codec, audioSources: audio.map(\.source))
    try writer.start()
    let pipeline = try RecordingPipeline(fps: fps, writer: writer, audioSources: audio.map(\.source))
    var nextChunk = Array(repeating: 0, count: audio.count)
    var suspendedSent = false
    var step = 0
    while true {
        let now = Double(step) / Double(fps)
        if now > duration + 0.15 { break }
        for (index, source) in audio.enumerated() {
            while true {
                let chunk = nextChunk[index]
                let first = chunk * source.chunkFrames
                let start = source.start + Double(first) / source.sampleRate  // timestamp (device clock)
                let realRate = source.sampleRate * (1 + source.clockError)
                let realEnd = source.start + Double(first + source.chunkFrames) / realRate
                guard realEnd + source.latency <= now else { break }
                nextChunk[index] += 1
                if source.gaps.contains(where: { $0.contains(start) }) { continue }
                let times = source.duplicateChunk == chunk ? 2 : 1
                let switchSample = source.switchFrequency.map { Int(($0.atRealTime - source.start) * realRate) }
                for _ in 0..<times {
                    let buffer = makeTone(frequencyAt: { sample in
                                              if let switchSample, let target = source.switchFrequency, sample >= switchSample {
                                                  return target.to
                                              }
                                              return source.frequency
                                          },
                                          amplitude: source.amplitude, sampleRate: source.sampleRate,
                                          channels: source.channels, interleaved: source.interleaved,
                                          firstFrame: first, frames: source.chunkFrames, pts: host(start))
                    try pipeline.audio(buffer, from: source.source, arrival: host(now))
                }
            }
        }
        if now < duration {
            switch screen(now) {
            case .color(let red, let green, let blue):
                suspendedSent = false
                try pipeline.video(makeFrame(red: red, green: green, blue: blue), hostTime: host(now))
            case .suspended:
                if !suspendedSent { pipeline.screenSuspended(hostTime: host(now)); suspendedSent = true }
            case .nothing:
                break
            }
        } else {
            pipeline.setEndpoint(duration)
        }
        if !(skipTicks?.contains(now) ?? false) {
            var waited = 0
            while !writer.videoReady, waited < 500 { usleep(1_000); waited += 1 }
            try pipeline.tick(hostNow: host(now))
        }
        step += 1
    }
    pipeline.setEndpoint(duration)
    let endpoint = try pipeline.finish(waitingForWriter: { usleep(2_000) })
    try await writer.finish(at: endpoint, on: queue)
    return SimulationResult(stats: pipeline.stats, audio: pipeline.audioStats(), endpoint: endpoint)
}
