import Foundation

// recording-inspect FILE — prints a JSON report of a recording: tracks, codecs,
// sizes, duration, leading audio offsets, audio levels, and when audio first
// becomes audible. Exits 1 if the file cannot be read or has no video track.

setvbuf(stdout, nil, _IOLBF, 0)
let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    fputs("usage: recording-inspect FILE\n", stderr)
    exit(2)
}
let url = URL(fileURLWithPath: arguments[1])

do {
    let report = try await inspectAsset(url)
    var audioReports: [[String: Any]] = []
    for (index, track) in report.audio.enumerated() {
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
    let json: [String: Any] = [
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
