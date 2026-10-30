import Foundation
import AudioToolbox
import CoreMedia
import CoreVideo
@preconcurrency import AVFoundation

// Full decoding, one track and one sample buffer at a time. Kept outside the
// application so a probe can fail without changing the screenshot workflow.
@available(macOS 15.0, *)
func inspect(_ url: URL) async throws {
    let asset = AVURLAsset(url: url)
    let duration = try await asset.load(.duration)
    let tracks = try await asset.load(.tracks)
    var reports: [[String: Any]] = []
    for track in tracks {
        let mediaType = track.mediaType
        guard mediaType == .video || mediaType == .audio else { continue }
        let formats = try await track.load(.formatDescriptions)
        guard let format = formats.first else { throw ProbeFailure.message("Track has no format description.") }
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any]
        if mediaType == .video {
            settings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        } else {
            settings = [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMIsFloatKey: true,
                        AVLinearPCMBitDepthKey: 32, AVLinearPCMIsNonInterleaved: false,
                        AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2]
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw ProbeFailure.message("Cannot add decode output.") }
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? ProbeFailure.message("Cannot start reading.")
        }
        var count = 0
        var frames = 0
        var first: Double?
        var last: Double?
        var end: Double?
        var squaredEnergy = 0.0
        var values = 0
        var peak = 0.0
        while let sample = output.copyNextSampleBuffer() {
            guard let pts = seconds(CMSampleBufferGetPresentationTimeStamp(sample)), pts >= 0 else {
                throw ProbeFailure.message("Invalid/negative decoded PTS.")
            }
            if let last, pts < last { throw ProbeFailure.message("Decoded presentation time moved backwards.") }
            if first == nil { first = pts }
            last = pts
            end = pts + (seconds(CMSampleBufferGetDuration(sample)) ?? 0)
            count += 1
            frames += CMSampleBufferGetNumSamples(sample)
            if mediaType == .audio {
                guard let block = CMSampleBufferGetDataBuffer(sample) else {
                    throw ProbeFailure.message("Decoded audio has no PCM data buffer.")
                }
                let byteCount = CMBlockBufferGetDataLength(block)
                if byteCount == 0 { continue }
                guard byteCount % MemoryLayout<Float>.size == 0 else {
                    throw ProbeFailure.message("Unexpected decoded PCM layout.")
                }
                var samples = [Float](repeating: 0, count: byteCount / MemoryLayout<Float>.size)
                let status = samples.withUnsafeMutableBytes {
                    CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: byteCount,
                                               destination: $0.baseAddress!)
                }
                guard status == noErr else { throw ProbeFailure.message("Cannot read decoded PCM.") }
                for value in samples {
                    guard value.isFinite else { throw ProbeFailure.message("Nonfinite PCM sample.") }
                    squaredEnergy += Double(value) * Double(value)
                    peak = max(peak, abs(Double(value)))
                }
                values += samples.count
            }
        }
        guard reader.status == .completed, count > 0 else {
            throw reader.error ?? ProbeFailure.message("Reader did not fully decode a nonempty track.")
        }
        var report: [String: Any] = [
            "track_id": track.trackID, "media_type": mediaType.rawValue,
            "codec": fourCC(CMFormatDescriptionGetMediaSubType(format)),
            "decoded_buffers": count, "decoded_samples": frames,
            "first_pts": first as Any? ?? NSNull(),
            "last_pts": last as Any? ?? NSNull(), "last_end": end as Any? ?? NSNull()
        ]
        if mediaType == .video {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format)
            report["pixels"] = [dimensions.width, dimensions.height]
        } else {
            if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format) {
                report["source_sample_rate"] = asbd.pointee.mSampleRate
                report["source_channels"] = asbd.pointee.mChannelsPerFrame
            }
            report["decoded_rms"] = values > 0 ? sqrt(squaredEnergy / Double(values)) : 0
            report["decoded_peak"] = peak
            report["warning"] = "Energy does not establish which App or microphone was captured."
        }
        reports.append(report)
    }
    guard reports.contains(where: { $0["media_type"] as? String == AVMediaType.video.rawValue }) else {
        throw ProbeFailure.message("No decoded video track.")
    }
    emit(["event": "inspection", "file": url.path,
          "duration": seconds(duration) as Any? ?? NSNull(), "tracks": reports])
}

private func fourCC(_ value: FourCharCode) -> String {
    let bytes = [UInt8((value >> 24) & 255), UInt8((value >> 16) & 255),
                 UInt8((value >> 8) & 255), UInt8(value & 255)]
    return String(bytes: bytes, encoding: .ascii) ?? String(value)
}
