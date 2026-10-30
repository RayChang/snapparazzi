import Foundation
import CoreMedia
import CoreVideo
import AudioToolbox
@preconcurrency import AVFoundation

// Real-time AVAssetWriter for the first stage: MP4 with 0–1 AAC tracks, or MOV
// with one AAC track per source for `both`. Every call must come from the same
// serial media queue.
final class StageWriter {
    let url: URL
    let width: Int
    let height: Int
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audio: [AudioSource: AVAssetWriterInput]
    private(set) lazy var blackFrame: CVPixelBuffer? = makeBlackFrame()

    static func videoBitRate(width: Int, height: Int, fps: Int) -> Int {
        min(max(Int(Double(width * height * fps) * 0.12), 2_000_000), 40_000_000)
    }

    init(url: URL, fileType: AVFileType, width: Int, height: Int, fps: Int,
         codec: VideoCodec, audioSources: [AudioSource]) throws {
        self.url = url
        self.width = width
        self.height = height
        writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: StageWriter.videoBitRate(width: width, height: height, fps: fps),
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps * 2
            ]
        ])
        video.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ])
        var inputs: [AudioSource: AVAssetWriterInput] = [:]
        for source in audioSources {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: recordingSampleRate,
                AVNumberOfChannelsKey: recordingChannels,
                AVEncoderBitRateKey: 192_000
            ])
            input.expectsMediaDataInRealTime = true
            inputs[source] = input
        }
        audio = inputs
        for input in [video] + audioSources.compactMap({ inputs[$0] }) {
            guard writer.canAdd(input) else {
                throw RecordingError("無法建立影片寫入器（尺寸 \(width)×\(height) 可能超出編碼器限制，可用 -m 縮小）/ Cannot configure the writer (\(width)×\(height) may exceed the encoder; try -m)")
            }
            writer.add(input)
        }
    }

    func start() throws {
        guard writer.startWriting() else {
            throw RecordingError("無法開始寫入影片（尺寸 \(width)×\(height) 可能超出編碼器限制，可用 -m 縮小）/ Cannot start writing (\(width)×\(height) may exceed the encoder; try -m): \(writer.error?.localizedDescription ?? "unknown")")
        }
        writer.startSession(atSourceTime: .zero)
    }

    var failure: Error? {
        writer.status == .failed ? (writer.error ?? RecordingError("writer failed")) : nil
    }

    // false means "not ready, try later"; a broken writer throws.
    func appendVideo(_ pixelBuffer: CVPixelBuffer, at time: CMTime) throws -> Bool {
        if let failure { throw failure }
        guard video.isReadyForMoreMediaData else { return false }
        guard adaptor.append(pixelBuffer, withPresentationTime: time) else {
            throw failure ?? RecordingError("影片寫入失敗 / Video append failed")
        }
        return true
    }

    var videoReady: Bool { video.isReadyForMoreMediaData }

    func audioReady(_ source: AudioSource) -> Bool {
        audio[source]?.isReadyForMoreMediaData ?? false
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer, from source: AudioSource) throws {
        if let failure { throw failure }
        guard let input = audio[source], input.append(sampleBuffer) else {
            throw failure ?? RecordingError("音訊寫入失敗 / Audio append failed (\(source.rawValue))")
        }
    }

    // Marks every input finished, ends the session at `end`, and waits for the file.
    func finish(at end: CMTime, on queue: DispatchQueue) async throws {
        queue.sync {
            writer.endSession(atSourceTime: end)
            video.markAsFinished()
            audio.values.forEach { $0.markAsFinished() }
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.sync { writer.finishWriting { continuation.resume() } }
        }
        let status = queue.sync { writer.status }
        guard status == .completed else {
            throw queue.sync { writer.error } ?? RecordingError("影片收尾失敗 / Finishing the file failed")
        }
    }

    func cancel() {
        if writer.status == .writing { writer.cancelWriting() }
    }

    private func makeBlackFrame() -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                  [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary,
                                  &buffer) == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        for row in 0..<height {
            let line = base.advanced(by: row * rowBytes).assumingMemoryBound(to: UInt32.self)
            for column in 0..<width { line[column] = 0xFF00_0000 } // BGRA black, opaque
        }
        return buffer
    }
}
