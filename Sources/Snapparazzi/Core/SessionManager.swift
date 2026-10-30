import Foundation

func sessionTimestamp() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = .current
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: Date())
}

func expandedDirectoryURL(_ path: String) -> URL {
    let expanded = NSString(string: path).expandingTildeInPath
    if expanded.hasPrefix("/") {
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
    }
    return URL(
        fileURLWithPath: expanded,
        isDirectory: true,
        relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    ).standardizedFileURL
}

func defaultOutputRoot() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Snapparazzi", isDirectory: true)
        .appendingPathComponent("captures", isDirectory: true)
}

func makeSessionDirectory(timestamp: String, outputRoot: URL) throws -> URL {
    let directory = outputRoot.appendingPathComponent(
        "\(timestamp)-\(ProcessInfo.processInfo.processIdentifier)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
