# Snapparazzi 📸

Snapparazzi is a native macOS CLI that repeatedly captures one specific app window. Pick a visible window interactively or pass its window ID, choose the interval, and let your tiny terminal paparazzo work until you press `Ctrl-C`.

Snapparazzi 是一個原生 macOS CLI，可定時截取指定的 App 視窗。你可以從互動清單選擇目前可見視窗，也可以直接傳入 window ID 與時間間隔；按下 `Ctrl-C` 即可停止。macOS 15 以上也可以用 `snapparazzi record` 把視窗錄成 MP4，並可錄入 App 聲音與麥克風。

Snapparazzi can also record a window to MP4 with `snapparazzi record` on macOS 15 or later, optionally with the app's audio and the microphone.

## 安裝 / Install

需要 macOS 與 Xcode Command Line Tools：

Requires macOS and Xcode Command Line Tools:

```sh
xcode-select --install
```

一行下載原始碼、在本機編譯並安裝到 `~/.local/bin/snapparazzi`：

Download the source, build it locally, and install it to `~/.local/bin/snapparazzi`:

```sh
curl -fsSL https://raw.githubusercontent.com/RayChang/snapparazzi/main/install.sh | sh
```

重新執行同一命令即可更新。安裝程式會下載同一版本的完整原始碼並在本機編譯。安裝特定 tag／分支／commit 或自訂 bin 目錄：

Run the same command again to update. The installer downloads the full source for one ref and builds it locally. To install a specific tag, branch or commit, or choose another bin directory:

```sh
curl -fsSL https://raw.githubusercontent.com/RayChang/snapparazzi/main/install.sh \
  | SNAPPARAZZI_REF=v1.1.0 sh

curl -fsSL https://raw.githubusercontent.com/RayChang/snapparazzi/main/install.sh \
  | SNAPPARAZZI_BIN="$HOME/bin" sh
```

## 快速開始 / Quick start

```sh
snapparazzi                         # 互動選擇視窗與間隔 / interactive mode
snapparazzi --list                  # 列出可見 window ID / list visible window IDs
snapparazzi --window 12345          # 指定視窗，再詢問間隔 / choose window, prompt for interval
snapparazzi -w 12345 -i 1.5         # 完全指定視窗與間隔 / provide window and interval
snapparazzi -w 12345 -i 2 -o ~/Pictures/Snapparazzi
snapparazzi -w 12345 -i 60 -f heic  # 更省空間 / use less storage
snapparazzi -w 12345 -i 1 -m 1280   # 最長邊限制為 1280 px / limit longest edge
snapparazzi --help
```

若想同時截取多個視窗，請開啟多個 Terminal 分頁，每個程序選一個視窗。不同程序可以使用不同間隔與輸出目錄。

To capture multiple windows concurrently, start one Snapparazzi process per Terminal tab. Each process can use a different interval and output directory.

## 命令列選項 / CLI options

| Option | 說明 / Description |
|---|---|
| `-l`, `--list` | 列出可截取視窗與 ID 後退出 / List capturable windows and IDs, then exit |
| `-w`, `--window <id>` | 指定 window ID；省略時互動選擇 / Choose a window ID; omit for interactive selection |
| `-i`, `--interval <seconds>` | 最低 0.5 秒；省略時詢問，預設 2 秒 / Minimum 0.5; omit to be prompted, default 2 seconds |
| `-o`, `--output <directory>` | Session 輸出根目錄 / Session output root |
| `-f`, `--format <jpg\|heic\|png>` | 圖片格式，預設 `jpg` / Image format; default: `jpg` |
| `-m`, `--max-dimension <pixels>` | 等比例縮小到最長邊限制；預設保留原尺寸 / Limit the longest edge while preserving aspect ratio; original dimensions by default |
| `-h`, `--help` | 完整中英雙語說明 / Full bilingual help |
| `-V`, `--version` | 顯示版本 / Show version |

完整說明、錯誤碼與更多範例：

For complete usage, exit statuses, and more examples:

```sh
snapparazzi --help
```

## 錄影 / Recording

```sh
snapparazzi --list                                    # 先查 window ID / find the window ID
snapparazzi record -w 12345 --duration 10             # 只錄畫面 / video only
snapparazzi record -w 12345 --audio system -o ~/Movies/demo.mp4
snapparazzi record -w 12345 --audio both --codec hevc --duration 3600
snapparazzi record --help
```

| Option | 說明 / Description |
|---|---|
| `-w`, `--window <id>` | 必填 / Required |
| `--audio <none\|system\|mic\|both>` | 預設 `none` / Default `none` |
| `--fps <1-60>` | 預設 30 / Default 30 |
| `--codec <h264\|hevc>` | 預設 `h264` / Default `h264` |
| `--duration <seconds>` | 0.5–86400；省略時按 Ctrl-C 停止 / Omit to stop with Ctrl-C |
| `-o`, `--output <file.mp4>` | 不可已存在；預設 `~/Snapparazzi/recordings/YYYYMMDD-HHMMSS-PID.mp4` / Must not exist |
| `-m`, `--max-dimension <pixels>` | 等比例縮小，不放大 / Fit the longest edge, never upscale |

**聲音範圍 / Audio scope.** `system` 錄的是目標視窗所屬 App 的聲音，不是整台 Mac：其他 App 的聲音不會錄入，但**同一 App 其他視窗或分頁的聲音可能一起錄入**（例如 Chrome 的其他分頁）。DRM 等受保護內容可能錄不到。`system` records the target window's app, not the whole Mac: other apps are excluded, but the same app's other windows or tabs may be included.

**both.** App 聲音與麥克風先錄成兩條音軌，停止後再離線混成一條音軌（各 0.5 增益），影片不重新編碼。代價是停止後還要幾秒收尾、暫時需要約兩倍空間，且音訊多經過一次 AAC 編碼。外放聲音會被麥克風再錄一次，建議戴耳機。`both` records two tracks, then mixes them into one after you stop (0.5 gain each) without re-encoding video. It takes a few extra seconds and about twice the space while finishing, and the audio is AAC-encoded twice. Use headphones to avoid echo.

**實測 / Measured.** 在 Apple silicon、macOS 26.5 錄 1280×864、30 fps、H.264、`--audio both` 一小時：檔案約 123 MiB，停止後收尾與混音約 24 秒，錄影期間暫存加成品最多約 257 MiB，CPU 平均約 17%，記憶體約 55 MiB 且不隨時間增加。檔案大小會隨畫面內容與尺寸改變。One hour of 1280×864, 30 fps, H.264 with `--audio both` on Apple silicon: about 123 MiB, ~24 s to finish and mix after stopping, ~257 MiB peak temporary disk, ~17% CPU and ~55 MiB of memory that does not grow. Sizes vary with content and window size.

**權限 / Permissions.** 需要「螢幕與系統錄音」；`mic`、`both` 另需「麥克風」。macOS 通常把權限記在你用的 Terminal App 名下，而不是 snapparazzi 本身；換一個 Terminal 可能要重新允許。Requires Screen & System Audio Recording, plus Microphone for `mic`/`both`. macOS usually grants these to your terminal app, not to snapparazzi itself.

**視窗狀態 / Window state.** 視窗最小化超過 1 秒時改錄黑畫面，還原後繼續；切換到其他桌面或視窗進入 macOS 全螢幕時照常錄製。網頁影片的全螢幕要看瀏覽器：若另外開新視窗播放（例如部分 Safari 影片），錄到的是原視窗而非全螢幕影片。視窗被關閉或 App 結束時，錄影停止、保留已錄內容並以結束碼 1 結束。調整視窗大小時影片尺寸不變，內容等比例縮放並貼齊左上角。Minimized windows record black after 1 second and resume on restore; other Spaces and macOS full screen keep recording. Browser video full screen depends on the browser: if it plays in a separate window (e.g. some Safari videos), the original window is what gets recorded. Closing the window or quitting the app stops, keeps the recording and exits 1. Resizing keeps the video size; content is scaled to fit, anchored top-left.

**停止與失敗 / Stopping and failures.** `Ctrl-C`、`SIGTERM` 或 `--duration` 會正常收尾，結束碼 0。錄影期間先寫入輸出位置旁的暫存資料夾（`.<檔名>.snapparazzi-*`），完成檢查後才以不覆寫的方式移到最終路徑。寫入或混音失敗時會保留暫存檔並顯示路徑；`both` 混音時再按一次 `Ctrl-C` 會取消混音，保留含兩條獨立音軌的 MOV。`Ctrl-C`, `SIGTERM` and `--duration` finish normally (exit 0). Recording goes to a staging folder next to the output and is moved into place only after it is checked, never overwriting. Failures keep the staged file and print its path; a second `Ctrl-C` while `both` is mixing cancels the mix and keeps a MOV with two separate audio tracks.

**需求 / Requirements.** 錄影需要 macOS 15 以上；本機編譯需要 macOS 15 以上的 SDK（Xcode 16 或對應的 Command Line Tools）。截圖功能不受影響。Recording needs macOS 15+, and building needs a macOS 15+ SDK (Xcode 16 or matching Command Line Tools).

## 壓縮與效能 / Compression and performance

Snapparazzi 預設直接輸出完整解析度 JPG，不會先建立大型 PNG 再轉檔。若需要更小檔案，可改用 HEIC；若要無損圖片，則選 PNG。`--max-dimension` 會在截圖後使用 macOS 內建工具等比例縮小，而且不會放大較小的圖片。

Snapparazzi writes full-resolution JPG files directly by default, without creating a large intermediate PNG. Choose HEIC for smaller files or PNG for lossless output. `--max-dimension` uses a built-in macOS tool after capture to resize proportionally and never upscales smaller images.

以下是在一組 35 張、約 2560×1410 的 Chrome 視窗樣本上的實測。16 小時估算採每秒一張（57,600 張）；實際大小會隨畫面內容改變。

The figures below were measured from 35 Chrome window samples around 2560×1410. The 16-hour estimate assumes one frame per second (57,600 images); actual sizes vary with screen content.

| 設定 / Setting | 平均每張 / Average | 16 小時、每秒一張 / 16 h at 1 fps |
|---|---:|---:|
| PNG（無損 / lossless） | 1.30 MB | 74.9 GB |
| JPG（預設 / default） | 404 KB | 23.3 GB |
| HEIC | 213 KB | 12.3 GB |
| JPG + `--max-dimension 1280` | 136 KB | 7.9 GB |

每分鐘一張時，三種格式的效能負擔通常都可忽略。每秒一張時，JPG 是速度與大小最均衡的選擇；HEIC 編碼較慢，而 `--max-dimension` 會多一次縮圖處理。若優先考量空間，可使用：

At one frame per minute, the performance cost of all three formats is normally negligible. At one frame per second, JPG offers the best balance of speed and size; HEIC encoding is slower, and `--max-dimension` adds a resize pass. For storage-first capture, use:

```sh
snapparazzi -w 12345 -i 1 -f jpg -m 1280
```

## 螢幕錄製權限 / Screen Recording permission

第一次執行時，macOS 會要求螢幕錄製權限。請前往：

```text
系統設定 → 隱私權與安全性 → 螢幕與系統錄音
System Settings → Privacy & Security → Screen & System Audio Recording
```

允許你用來執行 Snapparazzi 的 Terminal（例如 Terminal 或 Ghostty），然後重新執行命令。Snapparazzi 執行時不會上傳任何資料；圖片只寫入本機目錄。

Allow the terminal app that launches Snapparazzi (for example Terminal or Ghostty), then run the command again. Snapparazzi does not upload anything at runtime; screenshots are written only to local storage.

## 輸出 / Output

預設輸出根目錄：

Default output root:

```text
~/Snapparazzi/captures/
```

每次執行會建立獨立 session：

Every process creates a separate session:

```text
~/Snapparazzi/captures/YYYYMMDD-HHMMSS-PID/
└── App_Name_YYYYMMDD-HHMMSS_000001.jpg
```

副檔名會依 `--format` 變成 `.jpg`、`.heic` 或 `.png`。

The extension follows `--format`: `.jpg`, `.heic`, or `.png`.

若視窗最小化、切換到其他 Space 或關閉，該程序會暫停產圖；同一 window ID 恢復時會繼續。App 重建視窗後通常會取得新的 ID，這時請重新啟動 Snapparazzi 並選擇新視窗。

If a window is minimized, moved to another Space, or closed, capture pauses. It resumes if the same window ID becomes visible again. A recreated window usually receives a new ID; restart Snapparazzi and select it again.

## 開發 / Development

```sh
git clone https://github.com/RayChang/snapparazzi.git
cd snapparazzi
make test
make install
```

`make test` compiles a release binary with warnings treated as errors and runs every suite that needs no permissions or windows: the screenshot CLI contract, record argument parsing, recording tests that drive the timeline, writer and mixer with synthetic frames and tones through real AVFoundation, and the installer in an isolated temporary destination.

Real recordings are opt-in because they need Screen Recording/Microphone permission and a logged-in desktop:

```sh
make recording-acceptance        # every audio mode/codec, A/V sync, app-only audio, minimize, resize, quit, signals
DURATION=3600 make recording-long-run   # one hour of --audio both: drift, memory, finishing time, disk
make recording-microphone        # mic-track sync (audible beeps) and a mic removed mid-recording; restores the default input
make recording-inspect && .build/recording-inspect FILE.mp4 [--sync]
```

They drive a scripted fixture app (tests/RecordingFixtureApp) and check results with `recording-inspect`. `tools/recording-probe` is the standalone ScreenCaptureKit research probe used before the feature was built.

## 解除安裝 / Uninstall

```sh
rm ~/.local/bin/snapparazzi
```

截圖與錄影不會自動刪除。如不再需要，可自行移除 `~/Snapparazzi/captures` 與 `~/Snapparazzi/recordings`。

Screenshots and recordings are never deleted automatically. Remove `~/Snapparazzi/captures` and `~/Snapparazzi/recordings` yourself if you no longer need them.

## License

[MIT](LICENSE)
