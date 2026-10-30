import Foundation
import CoreMedia

// recording-inspect FILE — prints a JSON report of a recording: tracks, codecs,
// sizes, duration, leading audio offsets, audio levels, and when audio first
// becomes audible. Exits 1 if the file cannot be read or has no video track.
// With --sync, also pairs white flashes with 1 kHz beeps (fixture app markers)
// and reports audio-minus-video offsets; --sync START LENGTH limits that to a time
// window (for long recordings, which are too large to decode whole).

// Also:
//   recording-inspect --levels FILE HZ...      tone amplitude per frequency (from 1 s to 1 s before the end)
//   recording-inspect --luma FILE SECONDS...   mean frame luminance (0–255) at each time

setvbuf(stdout, nil, _IOLBF, 0)
let arguments = CommandLine.arguments
if arguments.count >= 4, arguments[1] == "--levels" || arguments[1] == "--luma" {
    let file = URL(fileURLWithPath: arguments[2])
    let values = arguments.dropFirst(3).compactMap(Double.init)
    do {
        var results: [String] = []
        if arguments[1] == "--levels" {
            let pcm = try await decodeStereo48k(file)
            let length = Double(pcm.count / 2) / 48_000 - 2
            for frequency in values {
                let level = max(toneAmplitude(pcm, channel: 0, start: 1, length: length, frequency: frequency),
                                toneAmplitude(pcm, channel: 1, start: 1, length: length, frequency: frequency))
                results.append(String(format: "%.4f", level))
            }
        } else {
            for seconds in values {
                let color = try await frameMeanColor(file, at: seconds)
                results.append(String(format: "%.1f", 0.299 * Double(color.red) + 0.587 * Double(color.green) + 0.114 * Double(color.blue)))
            }
        }
        print(results.joined(separator: " "))
        exit(0)
    } catch {
        fputs("recording-inspect: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}
guard arguments.count == 2 || (arguments.count >= 3 && arguments[2] == "--sync") else {
    fputs("usage: recording-inspect FILE [--sync [START LENGTH]]\n", stderr)
    exit(2)
}
let url = URL(fileURLWithPath: arguments[1])
let measureSync = arguments.count >= 3
let syncRange: CMTimeRange? = arguments.count == 5
    ? CMTimeRange(start: CMTime(seconds: Double(arguments[3]) ?? 0, preferredTimescale: 600),
                  duration: CMTime(seconds: Double(arguments[4]) ?? 60, preferredTimescale: 600))
    : nil
let summaryOnly = syncRange != nil

do {
    let report = try await inspectAsset(url)
    var audioReports: [[String: Any]] = []
    for (index, track) in report.audio.enumerated() where !summaryOnly {
        let pcm = try await decodeStereo48k(url, trackIndex: index)
        var sum = 0.0
        var peak = 0.0
        for value in pcm {
            sum += Double(value) * Double(value)
            peak = max(peak, abs(Double(value)))
        }
        // First 50 ms window louder than -40 dBFS.
        var audibleAt: Double?
        let window = 2_400 * 2
        var start = 0
        while start + window <= pcm.count {
            var energy = 0.0
            for value in pcm[start..<(start + window)] { energy += Double(value) * Double(value) }
            if sqrt(energy / Double(window)) > 0.01 { audibleAt = Double(start / 2) / 48_000; break }
            start += window
        }
        var entry = track.json
        entry["decoded_seconds"] = Double(pcm.count / 2) / 48_000
        entry["rms"] = pcm.isEmpty ? 0 : sqrt(sum / Double(pcm.count))
        entry["peak"] = peak
        entry["first_audible"] = audibleAt as Any? ?? NSNull()
        audioReports.append(entry)
    }
    var syncReport: Any = NSNull()
    if measureSync {
        let flashes = try await flashOnsets(url, range: syncRange)
        let offset = syncRange.map { CMTimeGetSeconds($0.start) } ?? 0
        let beeps = toneBurstOnsets(try await decodeStereo48k(url, range: syncRange), frequency: 1000).map { $0 + offset }
        var pairs: [[String: Double]] = []
        for flash in flashes {
            guard let beep = beeps.min(by: { abs($0 - flash) < abs($1 - flash) }), abs(beep - flash) < 0.5 else { continue }
            pairs.append(["video": flash, "audio": beep, "offset": beep - flash])
        }
        let offsets = pairs.compactMap { $0["offset"] }
        syncReport = [
            "flashes": flashes.count, "beeps": beeps.count, "pairs": pairs,
            "first_offset": offsets.first as Any? ?? NSNull(),
            "last_offset": offsets.last as Any? ?? NSNull(),
            "max_abs_offset": offsets.map(abs).max() as Any? ?? NSNull()
        ]
    }
    let json: [String: Any] = [
        "sync": syncReport,
        "file": url.path, "duration": report.duration,
        "video": report.video.map(\.json), "audio": audioReports
    ]
    let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .prettyPrinted])
    print(String(data: data, encoding: .utf8)!)
    exit(report.video.count == 1 ? 0 : 1)
} catch {
    fputs("recording-inspect: \(error.localizedDescription)\n", stderr)
    exit(1)
}
