let snapparazziVersion = "1.1.0"

let helpText = """
Snapparazzi — a polite paparazzo for your macOS windows.
Snapparazzi — 專門定時捕捉 macOS 視窗的 CLI 工具。

用法 / USAGE
  snapparazzi [options]
  snapparazzi --list
  snapparazzi --window <id> [--interval <seconds>] [--output <directory>]
               [--format <jpg|heic|png>] [--max-dimension <pixels>]

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
