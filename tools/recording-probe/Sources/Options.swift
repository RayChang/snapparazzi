import Foundation
import CoreMedia
import Darwin

enum ProbeFailure: Error, LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

enum ProbeAudio: String {
    case none, system, mic, both
    var system: Bool { self == .system || self == .both }
    var microphone: Bool { self == .mic || self == .both }
}

struct CaptureOptions {
    let windowID: UInt32
    let audio: ProbeAudio
    let duration: Double
    let codec: String
    let output: URL
}

enum ProbeCommand {
    case help, list
    case capture(CaptureOptions)
    case inspect(URL)
    case mixTest(codec: String, directory: URL)
    case mix(input: URL, output: URL)

    static func parse(_ arguments: [String]) throws -> ProbeCommand {
        if arguments.isEmpty || arguments == ["--help"] { return .help }
        if arguments == ["list"] { return .list }
        if arguments.first == "inspect", arguments.count == 2 {
            return .inspect(fileURL(arguments[1]))
        }
        if arguments.first == "mix", arguments.count == 3 {
            guard (arguments[2] as NSString).pathExtension.lowercased() == "mp4" else {
                throw ProbeFailure.message("mix output must be .mp4")
            }
            return .mix(input: fileURL(arguments[1]), output: fileURL(arguments[2]))
        }
        if arguments.first == "mix-test" {
            guard arguments.count == 5, arguments[1] == "--codec", ["h264", "hevc"].contains(arguments[2]),
                  arguments[3] == "--dir" else {
                throw ProbeFailure.message("Usage: mix-test --codec h264|hevc --dir EXISTING_DIR")
            }
            return .mixTest(codec: arguments[2], directory: fileURL(arguments[4]))
        }
        guard arguments.first == "capture" else {
            throw ProbeFailure.message("Expected list, capture, inspect, or --help.")
        }
        var values: [String: String] = [:]
        var index = 1
        let allowed: Set<String> = ["--window", "--audio", "--duration", "--codec", "--output"]
        while index < arguments.count {
            let key = arguments[index]
            guard allowed.contains(key), values[key] == nil, index + 1 < arguments.count else {
                throw ProbeFailure.message("Unknown, duplicate, or missing-value option: \(key)")
            }
            values[key] = arguments[index + 1]
            index += 2
        }
        guard let rawID = values["--window"], let id = UInt32(rawID), id > 0,
              let audio = ProbeAudio(rawValue: values["--audio"] ?? "none"),
              let duration = Double(values["--duration"] ?? "10"),
              duration.isFinite, (1...60).contains(duration),
              let output = values["--output"], !output.isEmpty,
              (output as NSString).pathExtension.lowercased() == "mov" else {
            throw ProbeFailure.message("Require --window ID, --output FILE.mov, audio none/system/mic/both, duration 1...60.")
        }
        let codec = values["--codec"] ?? "h264"
        guard ["h264", "hevc"].contains(codec) else {
            throw ProbeFailure.message("Codec must be h264 or hevc.")
        }
        return .capture(CaptureOptions(windowID: id, audio: audio, duration: duration,
                                       codec: codec, output: fileURL(output)))
    }
}

func fileURL(_ path: String) -> URL {
    URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL
}

// JSON lines contain metadata only, never PCM payloads or microphone identifiers.
func emit(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
          let text = String(data: data, encoding: .utf8) else { return }
    print(text)
    fflush(stdout)
}

func seconds(_ time: CMTime) -> Double? {
    let value = CMTimeGetSeconds(time)
    return value.isFinite ? value : nil
}
