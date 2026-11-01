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
//
// More generally, SCK captures the window together with its app's helper windows
// (Chrome's full-screen toolbar strips) and the capture is their bounding box. On a
// 2560×1440 pt external display at 1x, full-screen Chrome has a helper at
// (0, -693, 2560×41), next to the window at (-2560, -652, 2560×1440), and another at
// (-2560, -733, 2560×81). The capture is 5120×1521 pt, so the picture shrinks to a
// quarter of the canvas. Knowing where the app's windows are gives the window's
// place in that box: (0, 81) here.

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

// Where the window is, and the frames of its app's other windows, in global points
// (top-left origin).
struct WindowGeometry: Equatable {
    var frame: CGRect
    var appWindows: [CGRect]
}

// The window's place in a capture that is the bounding box of the window and some of
// its app's windows, or nil when that cannot be told for sure. The box's left and
// top edges must come from window edges and its right and bottom edges must match
// window edges too, so a stale frame from before a size change finds no box. Two
// different answers also give nil.
func appWindowsCrop(captured: CGSize, geometry: WindowGeometry) -> CGRect? {
    let tolerance: CGFloat = 1
    let frame = geometry.frame
    guard frame.width > 0, frame.height > 0,
          captured.width >= frame.width - tolerance, captured.height >= frame.height - tolerance,
          captured.width > frame.width + tolerance || captured.height > frame.height + tolerance else {
        return nil
    }
    let rects = [frame] + geometry.appWindows
    func edge(_ value: CGFloat, in values: [CGFloat]) -> Bool { values.contains { abs($0 - value) <= tolerance } }
    var found: [CGRect] = []
    for left in Set(rects.map(\.minX))
    where left <= frame.minX + tolerance && left + captured.width >= frame.maxX - tolerance
        && edge(left + captured.width, in: rects.map(\.maxX)) {
        for top in Set(rects.map(\.minY))
        where top <= frame.minY + tolerance && top + captured.height >= frame.maxY - tolerance
            && edge(top + captured.height, in: rects.map(\.maxY)) {
            let crop = CGRect(x: frame.minX - left, y: frame.minY - top, width: frame.width, height: frame.height)
            if !found.contains(where: { abs($0.minX - crop.minX) <= tolerance && abs($0.minY - crop.minY) <= tolerance }) {
                found.append(crop)
            }
        }
    }
    return found.count == 1 ? found[0] : nil
}

// The crop for a capture: the measured toolbar shape first, then the app's windows.
func windowCrop(captured: CGSize, geometry: WindowGeometry) -> CGRect? {
    windowCrop(captured: captured, frame: geometry.frame.size)
        ?? appWindowsCrop(captured: captured, geometry: geometry)
}

// The crop a complete frame calls for, from its SCStreamFrameInfo, and the window
// size it is for. The frame's own screenRect says where the window was when it was
// drawn, so a frame from just before a size change is judged by its own size.
func neededWindowCrop(_ info: [SCStreamFrameInfo: Any], geometry: WindowGeometry) -> (crop: CGRect, frame: CGSize)? {
    guard let rectInfo = info[.contentRect] as? NSDictionary,
          let rect = CGRect(dictionaryRepresentation: rectInfo as CFDictionary),
          let scale = (info[.contentScale] as? NSNumber)?.doubleValue,
          let captured = capturedContentSize(contentRect: rect, contentScale: scale) else { return nil }
    var current = geometry
    if let screenInfo = info[.screenRect] as? NSDictionary,
       let screenRect = CGRect(dictionaryRepresentation: screenInfo as CFDictionary),
       screenRect.width > 0, screenRect.height > 0 {
        current.frame = screenRect
    }
    return windowCrop(captured: captured, geometry: current).map { ($0, current.frame.size) }
}

// Captures one frame with a short-lived stream to see whether the window needs a
// crop. nil when it does not, or when no frame arrives (e.g. a minimized window:
// the real stream then reports that).
func measureWindowCrop(filter: SCContentFilter, windowID: CGWindowID) async -> CGRect? {
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
    let geometry = windowGeometry(windowID) ?? WindowGeometry(frame: filter.contentRect, appWindows: [])
    return neededWindowCrop(info, geometry: geometry)?.crop
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

// The window's frame and its app's other windows, from the window server, or nil if
// the window is gone. Windows on other desktops count too: a full-screen window keeps
// its helpers when the user switches away.
func windowGeometry(_ windowID: CGWindowID) -> WindowGeometry? {
    guard let all = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]],
          let window = all.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID }),
          let frame = windowBounds(window) else {
        return nil
    }
    let pid = window[kCGWindowOwnerPID as String] as? NSNumber
    let others = all.filter {
        $0[kCGWindowOwnerPID as String] as? NSNumber == pid
            && ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value != windowID
    }
    return WindowGeometry(frame: frame, appWindows: others.compactMap(windowBounds))
}

private func windowBounds(_ info: [String: Any]) -> CGRect? {
    guard let bounds = info[kCGWindowBounds as String] as? NSDictionary,
          let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
          rect.width > 0, rect.height > 0 else { return nil }
    return rect
}
