let snapparazziVersion = "1.1.0"

let helpText = """
Snapparazzi — a polite paparazzo for your macOS windows.
Snapparazzi — 專門定時捕捉 macOS 視窗的 CLI 工具。

用法 / USAGE
  snapparazzi [options]
  snapparazzi --list
  snapparazzi --window <id> [--interval <seconds>] [--output <directory>]
               [--format <jpg|heic|png>] [--max-dimension <pixels>]
  snapparazzi record --window <id> [options]
               錄製視窗影片；詳見 snapparazzi record --help
               Record a window to MP4; see snapparazzi record --help

選項 / OPTIONS
  -l, --list                 列出目前可截取的視窗與 ID 後退出。
                             List capturable windows and their IDs, then exit.
  -w, --window <id>          直接選擇 window ID；未提供時顯示互動選單。
                             Select a window ID; omit it for the interactive picker.
  -i, --interval <seconds>   截圖間隔，最低 0.5 秒；未提供時互動詢問，預設 2 秒。
                             Capture interval, minimum 0.5 seconds. If omitted,
                             Snapparazzi prompts interactively with a 2-second default.
  -o, --output <directory>   Session 輸出根目錄。
                             Session output root. Default: ~/Snapparazzi/captures
  -f, --format <jpg|heic|png>
                             圖片格式；jpg 體積較小、heic 最省空間、png 無損。
                             Image format: compact jpg, smaller heic, or lossless png.
                             Default: jpg
  -m, --max-dimension <pixels>
                             等比例縮小，讓最長邊不超過指定像素；不會放大圖片。
                             Fit the longest edge within this size without upscaling.
                             By default, the original dimensions are preserved.
  -h, --help                 顯示這份完整說明並退出。
                             Show this full help and exit.
  -V, --version              顯示版本並退出。
                             Show the version and exit.

互動模式 / INTERACTIVE MODE
  不帶參數執行時，Snapparazzi 會列出所有可見視窗，讓你單選一個視窗，
  再詢問截圖間隔。按 Ctrl-C 會乾淨停止並顯示執行摘要。

  With no options, Snapparazzi lists all visible windows, prompts for one window,
  then asks for the interval. Press Ctrl-C to stop cleanly and print a summary.

螢幕錄製 / Screen Recording
  首次執行時，請在「系統設定 → 隱私權與安全性 → 螢幕與系統錄音」
  允許目前使用的 Terminal，然後重新執行命令。

  On first use, allow your terminal app under System Settings → Privacy & Security →
  Screen & System Audio Recording, then run the command again.

輸出 / OUTPUT
  每次執行會建立：<output>/YYYYMMDD-HHMMSS-<PID>/
  檔名格式：<app_name>_<YYYYMMDD-HHMMSS>_<sequence>.<format>
  只有成功寫入的圖片才會遞增六位數流水號。

  Each run creates: <output>/YYYYMMDD-HHMMSS-<PID>/
  Files use: <app_name>_<YYYYMMDD-HHMMSS>_<sequence>.<format>
  The six-digit sequence advances only after an image is written successfully.

範例 / EXAMPLES
  snapparazzi
  snapparazzi --list
  snapparazzi --window 12345 --interval 1.5
  snapparazzi -w 12345 -i 2 -o ~/Pictures/Snapparazzi
  snapparazzi -w 12345 -i 60 -f heic
  snapparazzi -w 12345 -i 1 -f jpg -m 1280

  若要同時截取多個視窗，請在 multiple Terminal tabs/windows 中各啟動一個程序；
  每個程序可使用不同間隔與輸出根目錄。

  To capture several windows at once, run one process in each of multiple Terminal
  tabs/windows. Every process may use a different interval and output root.

結束碼 / EXIT STATUS
  0  正常完成、顯示 help/version/list，或由 Ctrl-C 停止。
     Success, help/version/list output, or clean Ctrl-C shutdown.
  1  權限、視窗、目錄或截圖執行錯誤。
     Permission, window, directory, or capture runtime failure.
  2  無效或互相衝突的命令列參數。
     Invalid or conflicting command-line arguments.
"""

let recordingHelpText = """
Snapparazzi record — 把一個視窗錄成 MP4。需要 macOS 15 以上。
Snapparazzi record — record one window to an MP4 file. Requires macOS 15 or later.

用法 / USAGE
  snapparazzi record --window <id> [--audio <none|system|mic|both>] [--fps <1-60>]
                     [--codec <h264|hevc>] [--duration <seconds>]
                     [--output <file.mp4>] [--max-dimension <pixels>]

選項 / OPTIONS
  -w, --window <id>          必填。先用 snapparazzi --list 查 window ID。
                             Required. Find window IDs with snapparazzi --list.
      --audio <mode>         none（預設）、system（目標 App 的聲音）、mic（麥克風）、both（兩者混成一條音軌）。
                             none (default), system (the target app's audio), mic, or
                             both (mixed into one audio track).
      --fps <1-60>           影格率，預設 30。Frame rate, default 30.
      --codec <h264|hevc>    影片編碼，預設 h264。Video codec, default h264.
      --duration <seconds>   錄到指定秒數後停止（0.5–86400）；未指定時按 Ctrl-C 停止。
                             Stop after this many seconds (0.5–86400); otherwise press Ctrl-C.
  -o, --output <file.mp4>    輸出檔案，不可已存在。
                             Output file; must not already exist.
                             Default: ~/Snapparazzi/recordings/YYYYMMDD-HHMMSS-<PID>.mp4
  -m, --max-dimension <pixels>
                             等比例縮小，讓最長邊不超過指定像素（2–8192）；不會放大。
                             Fit the longest edge within this size (2–8192) without upscaling.
  -h, --help                 顯示錄影說明。Show this help.

聲音範圍 / AUDIO SCOPE
  system 只錄目標視窗所屬 App 的聲音，不是整台 Mac 的聲音；同一 App 其他視窗或分頁的
  聲音可能一起錄入。DRM／受保護內容可能錄不到聲音。
  system captures the target window's app only, not the whole Mac. Audio from the same
  app's other windows or tabs may be included. Protected content may be silent.

  both 會把 App 聲音與麥克風混成一條音軌；外放聲音會被麥克風再錄一次，建議戴耳機。
  停止後還需要額外時間與暫存空間完成混音。
  both mixes app audio and the microphone into one track. Use headphones to avoid echo.
  Mixing needs extra time and temporary disk space after you stop.

權限 / PERMISSIONS
  需要「螢幕與系統錄音」權限；mic 與 both 另需「麥克風」權限。授權對象通常是你使用的
  Terminal App。
  Requires Screen & System Audio Recording permission; mic and both also need Microphone
  permission. macOS usually grants these to your terminal app.

視窗狀態 / WINDOW STATE
  視窗最小化超過 1 秒時改錄黑畫面，還原後繼續；視窗關閉時停止並保留已錄內容（結束碼 1）。
  Minimizing records black frames after 1 second and resumes on restore. Closing the
  window stops recording and keeps what was recorded (exit status 1).

結束碼 / EXIT STATUS
  0  正常完成，或由 Ctrl-C／SIGTERM／--duration 停止。
     Finished, or stopped by Ctrl-C, SIGTERM, or --duration.
  1  權限、視窗、檔案、錄製或混音錯誤。
     Permission, window, file, recording, or mixing failure.
  2  無效或互相衝突的命令列參數。
     Invalid or conflicting command-line arguments.

範例 / EXAMPLES
  snapparazzi --list
  snapparazzi record -w 12345 --duration 10
  snapparazzi record -w 12345 --audio system -o ~/Movies/demo.mp4
  snapparazzi record -w 12345 --audio both --fps 30 --codec hevc --duration 3600
"""
