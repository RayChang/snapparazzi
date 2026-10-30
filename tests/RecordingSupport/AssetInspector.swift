import Foundation
import CoreMedia
import CoreImage
import CoreVideo
@preconcurrency import AVFoundation

// Shared by the recording tests and the recording-inspect helper. Reads finished
// media with AVFoundation only (which honors edit lists; afconvert does not).

struct TrackReport {
    let mediaType: String
    let codec: String
    let width: Int
    let height: Int
    let sampleRate: Double
    let channels: Int
    let samples: Int
    let leadingEmptyEdit: Double

    var json: [String: Any] {
        var value: [String: Any] = ["media_type": mediaType, "codec": codec, "samples": samples,
                                    "leading_empty_edit": leadingEmptyEdit]
        if mediaType == "video" { value["pixels"] = [width, height] }
        if mediaType == "audio" { value["sample_rate"] = sampleRate; value["channels"] = channels }
        return value
    }
}

struct AssetReport {
    let duration: Double
    let tracks: [TrackReport]

    var video: [TrackReport] { tracks.filter { $0.mediaType == "video" } }
    var audio: [TrackReport] { tracks.filter { $0.mediaType == "audio" } }
}

func fourCharacterCode(_ value: FourCharCode) -> String {
    let bytes = [UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)]
    return String(bytes: bytes, encoding: .ascii) ?? String(value)
}

func inspectAsset(_ url: URL) async throws -> AssetReport {
    let asset = AVURLAsset(url: url)
    let duration = CMTimeGetSeconds(try await asset.load(.duration))
    var reports: [TrackReport] = []
    for track in try await asset.load(.tracks) where track.mediaType == .video || track.mediaType == .audio {
        guard let format = try await track.load(.formatDescriptions).first else { continue }
        let segments = try await track.load(.segments)
        let leading = segments.first.map { $0.isEmpty ? CMTimeGetSeconds($0.timeMapping.target.duration) : 0 } ?? 0
        // Count compressed samples without decoding.
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.startReading()
        var samples = 0
        while let buffer = output.copyNextSampleBuffer() { samples += CMSampleBufferGetNumSamples(buffer) }
        let isVideo = track.mediaType == .video
        let dimensions = isVideo ? CMVideoFormatDescriptionGetDimensions(format) : CMVideoDimensions(width: 0, height: 0)
        let asbd = isVideo ? nil : CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
        reports.append(TrackReport(
            mediaType: isVideo ? "video" : "audio",
            codec: fourCharacterCode(CMFormatDescriptionGetMediaSubType(format)),
            width: Int(dimensions.width), height: Int(dimensions.height),
            sampleRate: asbd?.mSampleRate ?? 0, channels: Int(asbd?.mChannelsPerFrame ?? 0),
            samples: samples, leadingEmptyEdit: leading))
    }
    return AssetReport(duration: duration, tracks: reports)
}

// The first audio track decoded to interleaved 48 kHz stereo Float32 on the presentation timeline.
func decodeStereo48k(_ url: URL, trackIndex: Int = 0) async throws -> [Float] {
    let asset = AVURLAsset(url: url)
    let tracks = try await asset.loadTracks(withMediaType: .audio)
    guard trackIndex < tracks.count else { return [] }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: tracks[trackIndex], outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false
    ])
    reader.add(output)
    guard reader.startReading() else { throw reader.error ?? NSError(domain: "inspect", code: 1) }
    var samples: [Float] = []
    while let buffer = output.copyNextSampleBuffer() {
        guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
        let length = CMBlockBufferGetDataLength(block)
        var chunk = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
        _ = chunk.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!)
        }
        samples += chunk
    }
    return samples
}

// Hann-windowed Goertzel amplitude of `frequency` in [start, start+length) seconds of one channel.
func toneAmplitude(_ samples: [Float], channel: Int, start: Double, length: Double, frequency: Double) -> Double {
    let rate = 48_000.0
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
    return 2 * sqrt(max(s1 * s1 + s2 * s2 - coefficient * s1 * s2, 0)) / windowSum
}

// Center of the first 20 ms window (stepping 1 ms) whose level reaches half of `steady`.
func toneOnset(_ samples: [Float], frequency: Double, from: Double, to: Double, steady: Double) -> Double? {
    var start = from
    while start < to {
        let level = max(toneAmplitude(samples, channel: 0, start: start, length: 0.02, frequency: frequency),
                        toneAmplitude(samples, channel: 1, start: start, length: 0.02, frequency: frequency))
        if level >= steady / 2 { return start + 0.01 }
        start += 0.001
    }
    return nil
}

// Mean RGB (0–255) of the decoded frame at `seconds`.
func frameMeanColor(_ url: URL, at seconds: Double) async throws -> (red: Int, green: Int, blue: Int) {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
    let ciImage = CIImage(cgImage: image)
    let average = ciImage.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: ciImage.extent)])
    var pixel = [UInt8](repeating: 0, count: 4)
    CIContext().render(average, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
    return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
}
