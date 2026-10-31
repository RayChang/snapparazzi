let helpText = """
Snapparazzi — 指定一個 macOS 視窗，定時截圖或錄成影片。
Snapparazzi — take timed screenshots of one macOS window, or record it to video.

這個工具能做什麼 / WHAT IT DOES
  截圖：每隔固定秒數把同一個視窗存成一張圖片，一直到你按 Ctrl-C。
  錄影：把同一個視窗錄成 MP4 影片，可一起錄 App 的聲音與麥克風（需要 macOS 15）。
  Screenshots: save the same window as an image every few seconds until you press Ctrl-C.
  Recording:   record the window to an MP4 file, optionally with the app's audio and
               the microphone (macOS 15 or later).

用法 / USAGE
  snapparazzi [options]                        截圖 / take screenshots
  snapparazzi capture [options]                同上，capture 可省略 / same as above
  snapparazzi record --window <id> [options]   錄影，詳見 snapparazzi record --help
                                               record video; see snapparazzi record --help
  snapparazzi --list                           列出視窗與 ID / list windows and their IDs
  snapparazzi --help                           顯示這份說明 / show this help
  snapparazzi --version                        顯示版本 / show the version

  寫法：<...> 換成你要的值；[...] 可以省略；a|b 表示擇一。
  選項順序不拘，但同一個選項只能寫一次；短寫法與長寫法相同（-w 等於 --window）。
  Notation: replace <...> with a value; [...] is optional; a|b means "one of".
  Options may come in any order, each only once; short and long forms are the same.

第一步：找到視窗 ID / STEP 1: FIND THE WINDOW ID
  執行 / Run:
    snapparazzi --list

  會看到類似 / You will see something like:
    WINDOW_ID  APP — WINDOW / 應用程式 — 視窗
    41324      Google Chrome — YouTube
    35239      行事曆 — 行事曆
    46504      Google Chrome — 課程影片  [不在目前桌面 / not on this desktop]

  左邊的數字就是 window ID，給 --window 使用。標著「不在目前桌面」的視窗在其他
  桌面、全螢幕，或已最小化：錄影可以直接錄（最小化的要先還原）；截圖會等到你切換到
  那個桌面、視窗出現在畫面上才開始。App 重新開啟視窗後 ID 會改變，請重新查詢。
  The number on the left is the window ID for --window. "not on this desktop" means
  another Space, full screen, or minimized: record works right away (restore a
  minimized window first); screenshots start once the window is on screen. IDs
  change when an app reopens a window.

截圖選項 / SCREENSHOT OPTIONS
  所有選項都可以省略；省略時使用下面的預設值。
  Every option is optional; the default below applies when you leave it out.

  -w, --window <id>
        要截圖的視窗 ID（正整數，用 --list 查）。
        預設：不指定時會列出所有視窗，讓你輸入編號選擇。
        The window to capture (a positive number from --list).
        Default: you pick one from a numbered list.

  -i, --interval <seconds>
        每隔幾秒截一張，可用小數（例如 1.5），最低 0.5。
        預設：不指定時會詢問；直接按 Enter 就是 2 秒。
        Seconds between screenshots; decimals allowed (e.g. 1.5); minimum 0.5.
        Default: you are asked; just pressing Enter uses 2 seconds.

  -o, --output <directory>
        存放截圖的資料夾；每次執行會在裡面另建一個子資料夾。資料夾不存在會自動建立。
        預設：~/Snapparazzi/captures
        Folder for screenshots; every run creates its own subfolder inside it.
        Missing folders are created. Default: ~/Snapparazzi/captures

  -f, --format <jpg|heic|png>
        圖片格式：jpg 體積小、heic 最省空間、png 無損但檔案最大。jpeg 等同 jpg。
        預設：jpg
        Image format: compact jpg, smallest heic, or lossless (largest) png.
        jpeg means jpg. Default: jpg

  -m, --max-dimension <pixels>
        等比例縮小，讓圖片最長邊不超過這個像素數（正整數）；較小的圖片不會被放大。
        預設：保留原始尺寸。
        Shrink proportionally so the longest edge is at most this many pixels
        (a positive integer); smaller images are never enlarged.
        Default: original size.

  -l, --list
        列出可截取的視窗與 ID 後結束；不能和上面的截圖選項一起用。
        List capturable windows and their IDs, then exit. Cannot be combined
        with the screenshot options above.

  -h, --help       顯示這份說明。Show this help.
  -V, --version    顯示版本。Show the version.

互動模式 / INTERACTIVE MODE
  只輸入 snapparazzi（不加選項）時：先列出視窗讓你選一個，再詢問間隔秒數，
  接著開始截圖。按 Ctrl-C 會乾淨停止並顯示執行摘要。
  With no options, Snapparazzi lists the visible windows, lets you pick one, asks
  for the interval, then starts. Press Ctrl-C to stop cleanly and print a summary.

範例 / EXAMPLES
  snapparazzi
      互動模式：選視窗、輸入間隔。
      Interactive: pick a window and an interval.
  snapparazzi --list
      查詢視窗 ID。
      Find window IDs.
  snapparazzi --window 41324 --interval 1.5
      每 1.5 秒截一張視窗 41324，存成 JPG。
      Capture window 41324 every 1.5 seconds as JPG.
  snapparazzi -w 41324 -i 2 -o ~/Pictures/Snapparazzi
      每 2 秒一張，存到 ~/Pictures/Snapparazzi。
      Every 2 seconds, saved under ~/Pictures/Snapparazzi.
  snapparazzi -w 41324 -i 60 -f heic
      每分鐘一張，用最省空間的 HEIC。
      Once a minute, using space-saving HEIC.
  snapparazzi -w 41324 -i 1 -f jpg -m 1280
      每秒一張，最長邊縮到 1280 像素，適合長時間拍攝。
      Every second, resized to at most 1280 px; good for long sessions.
  snapparazzi record --window 41324 --duration 10
      錄影 10 秒（更多錄影用法見 snapparazzi record --help）。
      Record for 10 seconds (see snapparazzi record --help for more).

輸出 / OUTPUT
  每次執行會建立：<output>/YYYYMMDD-HHMMSS-<PID>/
  檔名格式：<app_name>_<YYYYMMDD-HHMMSS>_<sequence>.<format>
  只有成功寫入的圖片才會遞增六位數流水號。
  Each run creates: <output>/YYYYMMDD-HHMMSS-<PID>/
  Files use: <app_name>_<YYYYMMDD-HHMMSS>_<sequence>.<format>
  The six-digit sequence advances only after an image is written successfully.

  截圖途中視窗最小化、移到其他桌面或關閉時會暫停，同一個視窗回來後自動繼續。
  If the window is minimized, moved to another Space or closed, capture pauses and
  resumes when the same window comes back.

螢幕錄製 / Screen Recording
  首次執行時，請在「系統設定 → 隱私權與安全性 → 螢幕與系統錄音」
  允許目前使用的 Terminal App，然後重新執行命令。
  On first use, allow your terminal app under System Settings → Privacy & Security →
  Screen & System Audio Recording, then run the command again.

同時處理多個視窗 / SEVERAL WINDOWS
  一個程序只處理一個視窗。若要同時截取多個視窗，請在 multiple Terminal tabs/windows
  中各啟動一個程序；每個程序可使用不同間隔與輸出資料夾。
  One process handles one window. To capture several at once, run one process in
  each of multiple Terminal tabs/windows, each with its own interval and folder.

結束碼 / EXIT STATUS
  0  正常完成、顯示 help/version/list，或由 Ctrl-C 停止。
     Success, help/version/list output, or a clean Ctrl-C stop.
  1  權限、視窗、資料夾或截圖執行錯誤。
     Permission, window, folder or capture failure.
  2  命令寫錯：未知選項、缺少值、值不合法或選項互相衝突。
     Invalid command line: unknown option, missing or invalid value, or a conflict.
"""

let recordingHelpText = """
Snapparazzi record — 把一個視窗錄成 MP4 影片（需要 macOS 15 以上）。
Snapparazzi record — record one window to an MP4 video (requires macOS 15 or later).

用法 / USAGE
  snapparazzi record --window <id> [--audio <none|system|mic|both>]
                     [--duration <seconds>] [--output <file.mp4>]
                     [--fps <1-60>] [--codec <h264|hevc>] [--max-dimension <pixels>]
  snapparazzi record --help

  只有 --window 是必填，其他選項都有預設值。最簡單的寫法：
  Only --window is required; everything else has a default. The simplest form:
    snapparazzi record --window 41324

  寫法：<...> 換成你要的值；[...] 可以省略；a|b 表示擇一。選項順序不拘，同一個選項
  只能寫一次；短寫法與長寫法相同（-w 等於 --window）。
  Notation: replace <...> with a value; [...] is optional; a|b means "one of".
  Options may come in any order, each only once; -w and --window are the same.

怎麼錄 / HOW TO RECORD
  1. 找視窗 ID：snapparazzi --list，左邊的數字就是 ID（在其他桌面或全螢幕也可以，
     但不能是最小化）。
  2. 開始錄影：snapparazzi record --window <id>。第一次會要求權限（見「權限」）。
  3. 停止：按 Ctrl-C；或事先用 --duration 指定秒數，時間到自動停止。
  4. 等到出現「錄影完成 / recording saved」，影片才算存好，摘要會顯示檔案位置。
  1. Find the window ID with snapparazzi --list (another Space or full screen is
     fine; a minimized window is not).
  2. Start: snapparazzi record --window <id>. The first run asks for permission.
  3. Stop with Ctrl-C, or give --duration to stop automatically.
  4. Wait for "recording saved"; the summary shows where the file is.

選項 / OPTIONS
  -w, --window <id>
        要錄的視窗 ID（正整數，用 snapparazzi --list 查）。必填，沒有預設值。
        The window to record (a positive number from snapparazzi --list).
        Required; there is no default.

  --audio <none|system|mic|both>
        要不要錄聲音，錄哪一種：
          none    不錄聲音，只有畫面。
          system  錄目標視窗所屬 App 播放的聲音（不是整台 Mac，見「聲音範圍」）。
          mic     錄麥克風（錄影開始時的預設輸入裝置）。
          both    App 聲音加麥克風，停止後混成一條音軌；收尾需要額外時間。
        預設：none
        Which audio to include:
          none    no audio, video only
          system  the target window's app (not the whole Mac; see AUDIO SCOPE)
          mic     the microphone (the default input when recording starts)
          both    app audio and microphone, mixed into one track after you stop
        Default: none

  --duration <seconds>
        錄到幾秒自動停止，可用小數，範圍 0.5–86400（24 小時）。
        預設：不限時間，按 Ctrl-C 停止。
        Stop automatically after this many seconds (decimals allowed, 0.5–86400).
        Default: no limit; stop with Ctrl-C.

  -o, --output <file.mp4>
        影片的存放路徑，必須以 .mp4 結尾，而且檔案不能已經存在（不會覆蓋）。
        可用相對路徑或 ~；不存在的資料夾會自動建立。
        預設：~/Snapparazzi/recordings/YYYYMMDD-HHMMSS-<PID>.mp4
        Where to save the video. Must end in .mp4 and must not exist yet (nothing
        is overwritten). Relative paths and ~ work; missing folders are created.
        Default: ~/Snapparazzi/recordings/YYYYMMDD-HHMMSS-<PID>.mp4

  --fps <1-60>
        每秒畫面數，整數 1–60。數字越大越流暢、檔案越大。
        預設：30
        Frames per second, a whole number from 1 to 60. Higher is smoother and larger.
        Default: 30

  --codec <h264|hevc>
        影片編碼：h264 相容性最好；hevc 檔案較小，但部分舊裝置或軟體不支援。
        預設：h264
        Video codec: h264 plays almost everywhere; hevc is smaller but not supported
        by some older devices or apps. Default: h264

  -m, --max-dimension <pixels>
        等比例縮小影片，讓最長邊不超過這個像素數（整數 2–8192）；不會放大。
        視窗很大（例如 5K 螢幕）而無法錄製時可用它縮小。
        預設：視窗的原始像素尺寸（Retina 螢幕上是點數的兩倍）。
        Shrink proportionally so the longest edge is at most this many pixels
        (2–8192); never enlarges. Use it if a very large window cannot be recorded.
        Default: the window's native pixel size (twice its points on Retina).

  -h, --help
        顯示這份錄影說明。
        Show this recording help.

  --interval、--format、--list、--version 是截圖用的選項，不能和 record 一起用。
  --interval, --format, --list and --version belong to screenshots, not record.

聲音範圍 / AUDIO SCOPE
  system 只錄目標視窗所屬 App 的聲音，其他 App 的聲音不會錄進來；但同一 App 的
  其他視窗或分頁（例如 Chrome 的其他分頁）的聲音可能一起錄入。DRM／受保護的內容
  可能錄不到。
  system records only the target window's app; other apps are not included. Audio
  from the same app's other windows or tabs (for example other Chrome tabs) may be
  included. Protected (DRM) content may be silent.

  both 會把 App 聲音與麥克風混成一條音軌；喇叭外放的聲音會被麥克風再錄一次，
  建議戴耳機。mic／both 使用開始錄影時的預設麥克風，錄影中更改系統預設不會切換。
  both mixes app audio and the microphone into one track; use headphones to avoid
  echo. mic/both keep the microphone that was the default when recording started.

錄影中與停止時 / WHILE RECORDING AND STOPPING
  錄影中終端機會顯示「錄影中 / Recording…」。停止後會先完成檔案（both 還要混音，
  一小時的錄影約需數十秒），完成後顯示摘要：檔案位置、長度、尺寸與音訊狀況。
  錄影時檔案先寫在輸出位置旁的隱藏暫存資料夾（.<檔名>.snapparazzi-*），檢查完成
  後才出現在指定路徑。
  While recording the terminal shows "Recording…". After you stop, the file is
  finished first (both also mixes audio, tens of seconds for an hour) and a summary
  shows the path, length, size and audio. The file is written to a hidden staging
  folder next to the output and appears at the final path only once it is checked.

  開始前會檢查磁碟空間（有 --duration 時依預估大小，否則至少 1 GiB）；錄影中剩餘
  空間低於 512 MiB 會停止並保留已錄內容。both 混音時再按一次 Ctrl-C 會取消混音，
  保留一個含兩條獨立音軌的 MOV 檔並顯示位置。
  Free space is checked first (from the estimated size with --duration, otherwise
  at least 1 GiB); recording stops, keeping what it has, below 512 MiB. A second
  Ctrl-C while both is mixing cancels the mix and keeps a MOV with two audio tracks.

視窗狀態 / WINDOW STATE
  最小化：超過 1 秒改錄黑畫面，還原後自動繼續。
  移到其他桌面、進入全螢幕：照常錄製。
  調整大小：影片尺寸不變，畫面等比例縮放並貼齊左上角，多出的部分補黑。
  關閉視窗或結束 App：錄影停止並保留已錄內容（結束碼 1）。
  Minimized: black after 1 second, resumes when restored.
  Another Space or full screen: keeps recording.
  Resized: the video size stays fixed; the picture is scaled to fit, top-left.
  Closed window or quit app: recording stops and keeps what it has (exit 1).

權限 / PERMISSIONS
  需要「螢幕與系統錄音」權限；--audio mic 或 both 另需「麥克風」權限。第一次執行會
  跳出詢問，也可到「系統設定 → 隱私權與安全性」開啟。權限通常記在你使用的
  Terminal App（例如 Terminal、iTerm2）名下。麥克風權限被拒絕時不會改錄成無聲，
  而是直接結束（結束碼 1）。
  Needs Screen & System Audio Recording permission, plus Microphone for --audio mic
  or both. macOS asks on first use, or enable it under System Settings → Privacy &
  Security; it is usually granted to your terminal app. If Microphone is denied,
  record exits with status 1 instead of recording silence.

範例 / EXAMPLES
  snapparazzi record -w 41324
      錄視窗 41324（只有畫面），按 Ctrl-C 停止。
      Record window 41324 (video only); stop with Ctrl-C.
  snapparazzi record -w 41324 --duration 10
      錄 10 秒後自動停止。
      Record for 10 seconds.
  snapparazzi record -w 41324 --audio system -o ~/Movies/demo.mp4
      連同 App 的聲音一起錄，存到 ~/Movies/demo.mp4。
      Include the app's audio and save to ~/Movies/demo.mp4.
  snapparazzi record -w 41324 --audio both --duration 3600
      錄一小時，App 聲音加麥克風混成一條音軌（建議戴耳機）。
      One hour with app audio and microphone mixed (use headphones).
  snapparazzi record -w 41324 --codec hevc --fps 60 -m 1920
      60 fps、HEVC，最長邊不超過 1920 像素。
      60 fps HEVC, longest edge at most 1920 px.

常見問題 / TROUBLESHOOTING
  找不到 window ID：先用 snapparazzi --list 確認 ID；視窗關閉後重新開啟，ID 會改變。
  Window ID not found: check it with snapparazzi --list; a reopened window has a new ID.
  5 秒內沒有收到畫面：視窗可能已最小化，請先還原。
  No video frame within 5 seconds: the window is probably minimized; restore it.
  輸出檔已存在：換一個檔名，或不加 --output 使用自動檔名。
  Output already exists: choose another name, or omit --output for an automatic one.
  需要權限或錄不到聲音：見上方「權限」與「聲音範圍」。
  Permission prompts or missing audio: see PERMISSIONS and AUDIO SCOPE above.
  無法開始寫入影片（尺寸太大）：加上 -m，例如 -m 3840。
  Cannot start writing (window too large): add -m, for example -m 3840.

結束碼 / EXIT STATUS
  0  錄影完成，或由 Ctrl-C／SIGTERM／--duration 正常停止。
     Finished, or stopped normally by Ctrl-C, SIGTERM or --duration.
  1  權限、視窗、檔案、磁碟空間、錄製或混音錯誤（含視窗關閉、麥克風被拔除）。
     Permission, window, file, disk space, recording or mixing failure (including a
     closed window or a disconnected microphone).
  2  命令寫錯：未知選項、缺少 --window、值不合法或用了截圖選項。
     Invalid command line: unknown option, missing --window, invalid value, or a
     screenshot option.
"""
