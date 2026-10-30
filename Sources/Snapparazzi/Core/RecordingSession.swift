import Foundation
import Darwin

// Where a recording is written: a private staging folder next to the final file
// (same file system), committed with an exclusive rename that never overwrites.
struct RecordingSession {
    let finalURL: URL
    let stageDirectory: URL
    let captureURL: URL
    let mixedURL: URL

    static func defaultOutputURL(timestamp: String = sessionTimestamp()) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Snapparazzi", isDirectory: true)
            .appendingPathComponent("recordings", isDirectory: true)
            .appendingPathComponent("\(timestamp)-\(ProcessInfo.processInfo.processIdentifier).mp4")
    }

    static func resolveOutput(_ path: String?) -> URL {
        guard let path else { return defaultOutputURL() }
        let expanded = NSString(string: path).expandingTildeInPath
        let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return URL(fileURLWithPath: expanded, relativeTo: expanded.hasPrefix("/") ? nil : base).standardizedFileURL
    }

    // Side-effect free: run before asking for any permission.
    static func preflight(_ finalURL: URL) throws {
        if (try? FileManager.default.attributesOfItem(atPath: finalURL.path)) != nil {
            throw RecordingError("輸出檔已存在 / Output already exists: \(finalURL.path)")
        }
        var ancestor = finalURL.deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: ancestor.path) {
            let parent = ancestor.deletingLastPathComponent()
            guard parent.path != ancestor.path else { break }
            ancestor = parent
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: ancestor.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw RecordingError("輸出位置不是資料夾 / Output parent is not a directory: \(ancestor.path)")
        }
        guard FileManager.default.isWritableFile(atPath: ancestor.path) else {
            throw RecordingError("無法寫入輸出資料夾 / Cannot write to: \(ancestor.path)")
        }
    }

    // Bytes available on the volume that will hold the output, if known.
    static func availableCapacity(for finalURL: URL) -> Int64? {
        var probe = finalURL.deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: probe.path) {
            let parent = probe.deletingLastPathComponent()
            guard parent.path != probe.path else { return nil }
            probe = parent
        }
        // "Important usage" also counts purgeable space but is 0 on some volumes (disk
        // images, some external drives), so take the larger of it and the plain figure.
        let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                                          .volumeAvailableCapacityKey])
        let important = values?.volumeAvailableCapacityForImportantUsage
        let plain = values?.volumeAvailableCapacity.map(Int64.init)
        guard important != nil || plain != nil else { return nil }
        return max(important ?? 0, plain ?? 0)
    }

    // Creates missing parents and the private staging folder (after permissions).
    static func create(finalURL: URL, stageExtension: String) throws -> RecordingSession {
        try preflight(finalURL)
        let parent = finalURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let random = UUID().uuidString.prefix(8)
        let stage = parent.appendingPathComponent(".\(finalURL.lastPathComponent).snapparazzi-\(random)", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        return RecordingSession(finalURL: finalURL, stageDirectory: stage,
                                captureURL: stage.appendingPathComponent("capture.\(stageExtension)"),
                                mixedURL: stage.appendingPathComponent("mixed.mp4"))
    }

    // Moves `file` to the final path only if nothing exists there (renamex_np RENAME_EXCL).
    func commit(_ file: URL) throws {
        guard renamex_np(file.path, finalURL.path, UInt32(RENAME_EXCL)) == 0 else {
            let reason = String(cString: strerror(errno))
            throw RecordingError("無法完成輸出檔 / Cannot create \(finalURL.path): \(reason)")
        }
        removeStage()
    }

    func removeStage() {
        try? FileManager.default.removeItem(at: stageDirectory)
    }
}
