import CoreGraphics
@preconcurrency import AVFoundation

func ensureScreenCapturePermission() -> Bool {
    if CGPreflightScreenCaptureAccess() { return true }
    print("Snapparazzi 需要螢幕錄製權限 / Snapparazzi needs Screen Recording permission.")
    if CGRequestScreenCaptureAccess() { return true }
    print("""

    尚未取得權限。請前往：
      系統設定 → 隱私權與安全性 → 螢幕與系統錄音

    Permission was not granted. Open:
      System Settings → Privacy & Security → Screen & System Audio Recording

    允許目前使用的 Terminal 後重新執行 / Allow your terminal app, then run Snapparazzi again.
    """)
    return false
}

// Microphone access for record --audio mic|both. Denied or restricted access is an
// error; recording never silently falls back to no microphone.
func ensureMicrophonePermission() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
        return true
    case .notDetermined:
        print("Snapparazzi 需要麥克風權限 / Snapparazzi needs Microphone permission.")
        if await AVCaptureDevice.requestAccess(for: .audio) { return true }
    default:
        break
    }
    fputs("""
    尚未取得麥克風權限。請前往：系統設定 → 隱私權與安全性 → 麥克風，允許目前使用的 Terminal 後重新執行。
    Microphone permission was not granted. Allow your terminal app under System Settings →
    Privacy & Security → Microphone, then run Snapparazzi again.

    """, stderr)
    return false
}
