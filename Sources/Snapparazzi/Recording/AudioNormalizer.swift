import Foundation
import CoreMedia
import AudioToolbox
@preconcurrency import AVFoundation

let recordingSampleRate = 48_000
let recordingChannels = 2

// Converts one source's PCM (any rate, mono or stereo, interleaved or not) to
// 48 kHz interleaved stereo Float32. The converter is kept across buffers so
// resampling stays continuous; reset() starts a new segment after a gap.
final class AudioNormalizer {
    let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter

    init(inputFormat: AVAudioFormat) throws {
        guard let output = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: Double(recordingSampleRate),
                                         channels: AVAudioChannelCount(recordingChannels),
                                         interleaved: true),
              let converter = AVAudioConverter(from: inputFormat, to: output) else {
            throw RecordingError("不支援的音訊格式 / Unsupported audio format: \(inputFormat)")
        }
        if inputFormat.channelCount == 1 {
            converter.channelMap = [0, 0] // mono goes to both left and right
        }
        self.inputFormat = inputFormat
        self.outputFormat = output
        self.converter = converter
    }

    static func format(of sampleBuffer: CMSampleBuffer) -> AVAudioFormat? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        return AVAudioFormat(cmAudioFormatDescription: description)
    }

    func convert(_ sampleBuffer: CMSampleBuffer) throws -> [Float] {
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0 else { return [] }
        guard let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(frames)) else {
            throw RecordingError("無法配置音訊緩衝 / Cannot allocate audio buffer")
        }
        // frameLength sizes the destination buffers, so it must be set before copying.
        input.frameLength = AVAudioFrameCount(frames)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: input.mutableAudioBufferList)
        guard status == noErr else {
            throw RecordingError("無法讀取音訊資料 / Cannot read audio samples (\(status))")
        }
        return try run(input: input, endOfStream: false)
    }

    // Returns the samples still inside the converter, then resets it.
    func drain() throws -> [Float] {
        let tail = try run(input: nil, endOfStream: true)
        converter.reset()
        return tail
    }

    func reset() { converter.reset() }

    private func run(input: AVAudioPCMBuffer?, endOfStream: Bool) throws -> [Float] {
        let inputFrames = Double(input?.frameLength ?? 0)
        let capacity = AVAudioFrameCount(inputFrames * outputFormat.sampleRate / inputFormat.sampleRate) + 2048
        var result: [Float] = []
        var pending = input
        while true {
            guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
                throw RecordingError("無法配置音訊緩衝 / Cannot allocate audio buffer")
            }
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
                if let buffer = pending {
                    pending = nil
                    inputStatus.pointee = .haveData
                    return buffer
                }
                inputStatus.pointee = endOfStream ? .endOfStream : .noDataNow
                return nil
            }
            if status == .error {
                throw RecordingError("音訊轉換失敗 / Audio conversion failed: \(conversionError?.localizedDescription ?? "unknown")")
            }
            let count = Int(output.frameLength) * recordingChannels
            if count > 0, let data = output.floatChannelData?[0] {
                result.append(contentsOf: UnsafeBufferPointer(start: data, count: count))
            }
            // Keep pulling only while the converter filled the whole buffer.
            if status != .haveData || output.frameLength < capacity { break }
        }
        return result
    }
}

// Wraps interleaved 48 kHz stereo Float32 samples in a sample buffer at `start` (in samples).
final class PCMSampleBufferFactory {
    private let format: CMAudioFormatDescription

    init() throws {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: Double(recordingSampleRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(4 * recordingChannels), mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(4 * recordingChannels), mChannelsPerFrame: UInt32(recordingChannels),
            mBitsPerChannel: 32, mReserved: 0)
        var description: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &description)
        guard status == noErr, let description else {
            throw RecordingError("無法建立音訊格式 / Cannot create audio format")
        }
        format = description
    }

    func make(_ samples: ArraySlice<Float>, start: Int64) throws -> CMSampleBuffer {
        let frames = samples.count / recordingChannels
        let byteCount = samples.count * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: byteCount, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        guard status == noErr, let block else { throw RecordingError("無法配置音訊區塊 / Cannot allocate audio block") }
        status = samples.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block,
                                          offsetIntoDestination: 0, dataLength: byteCount)
        }
        guard status == noErr else { throw RecordingError("無法寫入音訊區塊 / Cannot fill audio block") }
        var buffer: CMSampleBuffer?
        status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: frames, presentationTimeStamp: CMTime(value: start, timescale: CMTimeScale(recordingSampleRate)),
            packetDescriptions: nil, sampleBufferOut: &buffer)
        guard status == noErr, let buffer else { throw RecordingError("無法建立音訊樣本 / Cannot create audio sample buffer") }
        return buffer
    }
}
