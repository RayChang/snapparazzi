import Foundation
import CoreMedia
import AudioToolbox
@preconcurrency import AVFoundation

// Second stage for `both`: copies the compressed video samples unchanged and mixes
// every audio track into one AAC track (gain 0.5 each), keeping each track's
// offset. Verified in the Task 0 probe for H.264 and HEVC.
@available(macOS 15.0, *)
final class AudioMixer: @unchecked Sendable {
    // All mutable state is confined to `queue`; both readiness pumps run on it.
    private let queue = DispatchQueue(label: "dev.snapparazzi.mix")
    private var reader: AVAssetReader?
    private var writer: AVAssetWriter?
    private var pairs: [(name: String, output: AVAssetReaderOutput, input: AVAssetWriterInput)] = []
    private var closed: Set<String> = []
    private var continuation: CheckedContinuation<Void, Error>?
    private var cancelled = false

    func cancel() {
        queue.async {
            self.cancelled = true
            self.finish(RecordingError("混音已取消 / Mixing cancelled"))
        }
    }

    func mix(_ input: URL, to output: URL) async throws {
        let asset = AVURLAsset(url: input)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard videoTracks.count == 1, !audioTracks.isEmpty else {
            throw RecordingError("暫存檔軌道不完整 / Stage file must have 1 video and at least 1 audio track")
        }
        let video = videoTracks[0]
        guard let videoFormat = try await video.load(.formatDescriptions).first else {
            throw RecordingError("暫存影片沒有格式資訊 / Stage video has no format description")
        }
        let transform = try await video.load(.preferredTransform)

        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderTrackOutput(track: video, outputSettings: nil)
        videoOutput.alwaysCopiesSampleData = false
        let audioOutput = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: recordingSampleRate,
            AVNumberOfChannelsKey: recordingChannels, AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false
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
            guard reader.canAdd(readerOutput) else { throw RecordingError("無法讀取暫存檔 / Cannot read the stage file") }
            reader.add(readerOutput)
        }

        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormat)
        videoInput.transform = transform
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: recordingSampleRate,
            AVNumberOfChannelsKey: recordingChannels, AVEncoderBitRateKey: 192_000
        ])
        for writerInput in [videoInput, audioInput] {
            writerInput.expectsMediaDataInRealTime = false
            guard writer.canAdd(writerInput) else { throw RecordingError("無法建立混音檔 / Cannot configure the mixed file") }
            writer.add(writerInput)
        }

        // Hand the AVFoundation objects to the queue that owns them from now on.
        queue.sync {
            self.reader = reader
            self.writer = writer
            self.pairs = [("video", videoOutput, videoInput), ("audio", audioOutput, audioInput)]
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { self.start(continuation) }
        }
    }

    private func start(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
        guard let reader, let writer, !cancelled else {
            return finish(RecordingError("混音已取消 / Mixing cancelled"))
        }
        guard reader.startReading() else {
            return finish(reader.error ?? RecordingError("無法讀取暫存檔 / Cannot read the stage file"))
        }
        guard writer.startWriting() else {
            return finish(writer.error ?? RecordingError("無法寫入混音檔 / Cannot write the mixed file"))
        }
        writer.startSession(atSourceTime: .zero)
        for pair in pairs {
            let name = pair.name
            pair.input.requestMediaDataWhenReady(on: queue) { self.pump(name) }
        }
    }

    private func pump(_ name: String) {
        guard let pair = pairs.first(where: { $0.name == name }), let reader, let writer else { return }
        while pair.input.isReadyForMoreMediaData, continuation != nil, !closed.contains(name) {
            if let sample = pair.output.copyNextSampleBuffer() {
                guard pair.input.append(sample) else {
                    return finish(writer.error ?? RecordingError("混音寫入失敗 / Mix append failed (\(name))"))
                }
            } else {
                if reader.status == .failed {
                    return finish(reader.error ?? RecordingError("讀取暫存檔失敗 / Reading the stage file failed"))
                }
                pair.input.markAsFinished()
                closed.insert(name)
                if closed.count == pairs.count { complete() }
                return
            }
        }
    }

    private func complete() {
        guard let reader, let writer else { return }
        guard reader.status == .completed else {
            return finish(reader.error ?? RecordingError("讀取暫存檔未完成 / Reading the stage file did not complete"))
        }
        writer.finishWriting {
            self.queue.async {
                let status = self.writer?.status
                self.finish(status == .completed ? nil
                            : self.writer?.error ?? RecordingError("混音檔收尾失敗 / Finishing the mixed file failed"))
            }
        }
    }

    private func finish(_ error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if let error {
            reader?.cancelReading()
            if writer?.status == .writing { writer?.cancelWriting() }
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}
