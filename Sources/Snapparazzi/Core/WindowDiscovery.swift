import Foundation
import CoreGraphics

struct WindowTarget {
    let id: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let title: String
    // false for windows on another Space, in full screen elsewhere, or minimized.
    var isOnScreen = true

    var listNote: String {
        isOnScreen ? "" : "  [不在目前桌面 / not on this desktop]"
    }

    var displayTitle: String {
        let normalized = title
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        return normalized.isEmpty ? "無標題 / Untitled" : normalized
    }
}

func parsedSelection(_ input: String, itemCount: Int) -> Int? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.contains(","),
          let selection = Int(trimmed),
          (1...itemCount).contains(selection) else {
        return nil
    }
    return selection
}

private func intValue(_ value: Any?) -> Int? {
    if let number = value as? NSNumber { return number.intValue }
    return value as? Int
}

private func doubleValue(_ value: Any?) -> Double? {
    if let number = value as? NSNumber { return number.doubleValue }
    return value as? Double
}

// Every window on any Space (including full-screen windows), not just the current one.
func discoverWindows() -> [WindowTarget] {
    let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
    guard let rawWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    return windowTargets(from: rawWindows)
}

// Keeps normal app windows. Off-screen windows (other Spaces, full screen elsewhere,
// minimized) are kept only if they have a title: the untitled ones are toolbars,
// menus and other helper windows. On-screen windows are listed first.
func windowTargets(from rawWindows: [[String: Any]]) -> [WindowTarget] {
    rawWindows.compactMap { info in
        guard intValue(info[kCGWindowLayer as String]) == 0,
              (doubleValue(info[kCGWindowAlpha as String]) ?? 1) > 0,
              let sharingState = intValue(info[kCGWindowSharingState as String]),
              sharingState != 0,
              let windowNumber = intValue(info[kCGWindowNumber as String]),
              windowNumber > 0,
              let ownerPIDValue = intValue(info[kCGWindowOwnerPID as String]),
              let ownerName = info[kCGWindowOwnerName as String] as? String,
              !ownerName.isEmpty,
              let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
              bounds.width > 1,
              bounds.height > 1 else {
            return nil
        }
        let title = (info[kCGWindowName as String] as? String) ?? ""
        let onScreen = (info[kCGWindowIsOnscreen as String] as? Bool) ?? false
        guard onScreen || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return WindowTarget(
            id: CGWindowID(windowNumber),
            ownerPID: pid_t(ownerPIDValue),
            ownerName: ownerName,
            title: title,
            isOnScreen: onScreen
        )
    }
    .sorted {
        if $0.isOnScreen != $1.isOnScreen { return $0.isOnScreen }
        let ownerComparison = $0.ownerName.localizedStandardCompare($1.ownerName)
        if ownerComparison != .orderedSame { return ownerComparison == .orderedAscending }
        let titleComparison = $0.displayTitle.localizedStandardCompare($1.displayTitle)
        if titleComparison != .orderedSame { return titleComparison == .orderedAscending }
        return $0.id < $1.id
    }
}

func printWindowList(_ windows: [WindowTarget]) {
    print("WINDOW_ID\tAPP — WINDOW / 應用程式 — 視窗")
    for window in windows {
        print("\(window.id)\t\(window.ownerName) — \(window.displayTitle)\(window.listNote)")
    }
}

// Screenshots need the window on screen now: screencapture cannot capture a window on
// another Space, so capture pauses until the user brings it back.
func selectedWindowIsAvailable(_ target: WindowTarget) -> Bool {
    discoverWindows().contains {
        $0.id == target.id && $0.ownerPID == target.ownerPID && $0.isOnScreen
    }
}

func promptForWindow(from windows: [WindowTarget]) -> WindowTarget? {
    print("\n目前可截取的視窗 / Capturable windows:")
    for (index, window) in windows.enumerated() {
        print("  [\(index + 1)] \(window.ownerName) — \(window.displayTitle) (ID: \(window.id))\(window.listNote)")
    }

    while true {
        print("\n請輸入視窗編號 / Select a window number: ", terminator: "")
        fflush(stdout)
        guard let input = readLine() else {
            print("\n未收到輸入，已取消 / No input; cancelled.")
            return nil
        }
        if let selection = parsedSelection(input, itemCount: windows.count) {
            return windows[selection - 1]
        }
        print("請輸入 1 到 \(windows.count) 之間的一個編號 / Enter one number from 1 to \(windows.count).")
    }
}
