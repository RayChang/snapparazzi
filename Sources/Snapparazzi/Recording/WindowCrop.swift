import Foundation
import CoreGraphics
import CoreMedia
import CoreVideo
@preconcurrency import ScreenCaptureKit

// What ScreenCaptureKit captures of a window can be larger than the window's frame.
// Chrome in macOS full screen keeps its toolbar area above the frame, and SCK
// includes it, so the picture is shrunk to fit the canvas and leaves black bars on
// the top and right. Measured on a 1728×1117 pt display:
//   toolbar hidden: frame 1728×1084, captured 1728×1230 (the extra 146 pt is empty)
//   toolbar shown:  frame 1728×996,  captured 1728×1084 (the extra 88 pt is the toolbar)
// In both cases the width matches and the extra area is above the frame. Recording
// only the frame fills the canvas again. Sizes are in points.

// The captured content's size, from a frame's SCStreamFrameInfo: contentRect is
// where the content sits in the output, contentScale how much it was shrunk.
func capturedContentSize(contentRect: CGRect, contentScale: Double) -> CGSize? {
    guard contentScale > 0, contentRect.width > 0, contentRect.height > 0 else { return nil }
    return CGSize(width: contentRect.width / contentScale, height: contentRect.height / contentScale)
}

// The part of the captured content to record (SCStreamConfiguration.sourceRect:
// points, top-left origin), or nil when nothing should be cut. Only the measured
// shape is cropped: same width, extra height on top. Anything else (including a
// frame from just before a size change) is recorded as is, scaled to fit.
func windowCrop(captured: CGSize, frame: CGSize) -> CGRect? {
    let tolerance: CGFloat = 1
    guard frame.width > 0, frame.height > 0,
          abs(captured.width - frame.width) <= tolerance,
          captured.height > frame.height + tolerance else {
        return nil
    }
    return CGRect(x: 0, y: captured.height - frame.height, width: captured.width, height: frame.height)
}

// The crop a complete frame calls for, from its SCStreamFrameInfo.
func neededWindowCrop(_ info: [SCStreamFrameInfo: Any], frame: CGSize) -> CGRect? {
    guard let rectInfo = info[.contentRect] as? NSDictionary,
          let rect = CGRect(dictionaryRepresentation: rectInfo as CFDictionary),
          let scale = (info[.contentScale] as? NSNumber)?.doubleValue,
          let captured = capturedContentSize(contentRect: rect, contentScale: scale) else { return nil }
    return windowCrop(captured: captured, frame: frame)
}

// Captures one frame with a short-lived stream to see whether the window needs a
// crop. nil when it does not, or when no frame arrives (e.g. a minimized window:
// the real stream then reports that).
func measureWindowCrop(filter: SCContentFilter) async -> CGRect? {
    let scale = Double(filter.pointPixelScale)
    let config = SCStreamConfiguration()
    config.width = max(2, Int(Double(filter.contentRect.width) * scale))
    config.height = max(2, Int(Double(filter.contentRect.height) * scale))
    config.pixelFormat = kCVPixelFormatType_32BGRA
    config.showsCursor = false
    config.queueDepth = 3
    let output = FirstFrameInfo()
    let stream = SCStream(filter: filter, configuration: config, delegate: nil)
    do {
        try stream.addStreamOutput(output, type: .screen,
                                   sampleHandlerQueue: DispatchQueue(label: "dev.snapparazzi.record.measure"))
        try await stream.startCapture()
    } catch {
        return nil
    }
    var waited = 0.0
    while output.result == nil, waited < 2 {
        try? await Task.sleep(nanoseconds: 20_000_000)
        waited += 0.02
    }
    try? await stream.stopCapture()
    guard case .frame(let info)? = output.result else { return nil }
    return neededWindowCrop(info, frame: filter.contentRect.size)
}

private final class FirstFrameInfo: NSObject, SCStreamOutput, @unchecked Sendable {
    enum Result { case frame([SCStreamFrameInfo: Any]), suspended }
    private let lock = NSLock()
    private var stored: Result?

    var result: Result? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let info = (CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                          as? [[SCStreamFrameInfo: Any]])?.first,
              let raw = info[.status] as? Int, let status = SCFrameStatus(rawValue: raw) else { return }
        lock.lock(); defer { lock.unlock() }
        guard stored == nil else { return }
        switch status {
        case .complete: stored = .frame(info)
        case .suspended: stored = .suspended
        default: break
        }
    }
}

// The window's current frame size from the window server, or nil if it is gone.
func windowFrameSize(_ windowID: CGWindowID) -> CGSize? {
    // The API takes window IDs stored directly as the array's pointer values.
    var value = UnsafeRawPointer(bitPattern: UInt(windowID))
    guard let ids = CFArrayCreate(nil, &value, 1, nil),
          let info = (CGWindowListCreateDescriptionFromArray(ids) as? [[String: Any]])?.first,
          let bounds = info[kCGWindowBounds as String] as? NSDictionary,
          let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else {
        return nil
    }
    return rect.size
}
