import Foundation
import Darwin

// `snapparazzi update`: asks GitHub for the latest release and, when it is newer than
// this build, runs that release's install.sh to build it and replace this binary in
// place. The installer is the same one the README's curl | sh line runs.

private let releaseAPI = "https://api.github.com/repos/RayChang/snapparazzi/releases/latest"
private let installerURLPrefix = "https://raw.githubusercontent.com/RayChang/snapparazzi/"

// "1.3.1" or "v1.3.1" → [1, 3, 1]; anything else → nil.
func parsedVersion(_ text: String) -> [Int]? {
    let trimmed = text.hasPrefix("v") ? String(text.dropFirst()) : text
    let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3 else { return nil }
    var numbers: [Int] = []
    for part in parts {
        guard !part.isEmpty, part.allSatisfy(\.isASCII), part.allSatisfy(\.isNumber), let number = Int(part) else {
            return nil
        }
        numbers.append(number)
    }
    return numbers
}

func isNewerVersion(_ candidate: [Int], than current: [Int]) -> Bool {
    current.lexicographicallyPrecedes(candidate)
}

// The release tag from the GitHub "latest release" JSON, if it is a plain version tag.
func latestReleaseTag(fromJSON data: Data) -> String? {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tag = object["tag_name"] as? String, parsedVersion(tag) != nil else {
        return nil
    }
    return tag
}

private struct CurlResult {
    let status: Int32
    let output: Data
    let error: String
}

private func curl(_ arguments: [String]) -> CurlResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
    process.arguments = ["-fsSL", "--max-time", "30"] + arguments
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    do { try process.run() } catch {
        return CurlResult(status: 127, output: Data(), error: error.localizedDescription)
    }
    // Read before waiting, so a large body cannot fill the pipe and block curl.
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let message = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    return CurlResult(status: process.terminationStatus, output: data,
                      error: message.trimmingCharacters(in: .whitespacesAndNewlines))
}

private func updateError(_ message: String) -> Int32 {
    fputs("錯誤 / Error: \(message)\n", stderr)
    return 1
}

func runUpdate(checkOnly: Bool) -> Int32 {
    setvbuf(stdout, nil, _IOLBF, 0)
    let environment = ProcessInfo.processInfo.environment
    print("目前版本 / current version: \(snapparazziVersion)")

    let api = environment["SNAPPARAZZI_TEST_RELEASE_URL"] ?? releaseAPI
    let response = curl(["-H", "Accept: application/vnd.github+json", api])
    guard response.status == 0 else {
        return updateError("無法查詢最新版本，請確認網路連線 / Cannot check the latest release; check your connection. (\(response.error))")
    }
    guard let tag = latestReleaseTag(fromJSON: response.output), let latest = parsedVersion(tag) else {
        return updateError("無法讀取最新版本資訊 / Cannot read the latest release information.")
    }
    guard let current = parsedVersion(snapparazziVersion), isNewerVersion(latest, than: current) else {
        print("已是最新版本 / Already up to date (latest release: \(tag)).")
        return 0
    }
    if checkOnly {
        print("有新版本 / Update available: \(tag)")
        print("執行 snapparazzi update 更新 / Run snapparazzi update to install it.")
        return 0
    }

    // Replace the binary that is running, wherever it was installed.
    guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath(),
          executable.lastPathComponent == "snapparazzi" else {
        return updateError("找不到目前安裝的 snapparazzi 位置 / Cannot tell where snapparazzi is installed. Reinstall with the curl command in the README.")
    }
    let binDirectory = executable.deletingLastPathComponent().path
    guard access(binDirectory, W_OK) == 0 else {
        return updateError("沒有權限寫入 \(binDirectory) / No permission to write to \(binDirectory).")
    }

    print("正在更新到 / Updating to \(tag)（下載原始碼並在本機編譯，約需一分鐘 / downloading and building, about a minute）…")
    let installerURL = environment["SNAPPARAZZI_TEST_INSTALLER_URL"] ?? "\(installerURLPrefix)\(tag)/install.sh"
    let script = FileManager.default.temporaryDirectory
        .appendingPathComponent("snapparazzi-update-\(getpid()).sh")
    defer { try? FileManager.default.removeItem(at: script) }
    let download = curl(["-o", script.path, installerURL])
    guard download.status == 0 else {
        return updateError("無法下載安裝程式 / Cannot download the installer. (\(download.error))")
    }

    let installer = Process()
    installer.executableURL = URL(fileURLWithPath: "/bin/sh")
    installer.arguments = [script.path]
    var installEnvironment = environment
    installEnvironment["SNAPPARAZZI_REF"] = tag
    installEnvironment["SNAPPARAZZI_BIN"] = binDirectory
    installer.environment = installEnvironment
    do { try installer.run() } catch {
        return updateError("無法執行安裝程式 / Cannot run the installer: \(error.localizedDescription)")
    }
    installer.waitUntilExit()
    guard installer.terminationReason == .exit, installer.terminationStatus == 0 else {
        return updateError("更新失敗，原本的版本沒有變動 / Update failed; the installed version is unchanged.")
    }
    print("已更新到 / Updated to \(tag): \(binDirectory)/snapparazzi")
    return 0
}
