import CoreGraphics

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
