# Snapparazzi 📸

Snapparazzi is a native macOS CLI for one specific app window: it either takes a screenshot of it at a fixed interval, or records it to MP4 with the app's audio and/or the microphone. Pick a window interactively or pass its window ID, and press `Ctrl-C` when you are done.

Snapparazzi 是一個原生 macOS CLI，專門處理一個指定的 App 視窗：可以定時截圖，也可以錄成 MP4，並可錄入 App 聲音與麥克風。你可以從互動清單選擇視窗，或直接傳入 window ID；按下 `Ctrl-C` 即可停止。

| | 截圖 / Screenshots | 錄影 / Recording |
|---|---|---|
| 命令 / Command | `snapparazzi`（或 `snapparazzi capture`） | `snapparazzi record` |
| 輸出 / Output | JPG／HEIC／PNG | MP4（H.264／HEVC，AAC 音訊） |
| 系統 / macOS | 14 以上 / 14 or later | 15 以上 / 15 or later |

## 安裝 / Install

需要 macOS 14 以上，以及含 macOS 15 SDK 的 Xcode 16 或其 Command Line Tools（即使只用截圖，也需要這個 SDK 才能編譯）：

Requires macOS 14 or later and Xcode 16 or its Command Line Tools, which include the macOS 15 SDK (needed to build even if you only take screenshots):

```sh
xcode-select --install
```

一行下載原始碼、在本機編譯並安裝到 `~/.local/bin/snapparazzi`：

Download the source, build it locally, and install it to `~/.local/bin/snapparazzi`:

```sh
curl -fsSL https://raw.githubusercontent.com/RayChang/snapparazzi/main/install.sh | sh
```

重新執行同一命令即可更新。安裝程式會下載指定版本的完整原始碼壓縮檔，以同一份 Makefile 在本機編譯；失敗時不會動到已安裝的版本。安裝特定 tag／分支／commit 或自訂 bin 目錄：

Run the same command again to update. The installer downloads the full source archive for one ref and builds it with the same Makefile; a failed install leaves the installed version untouched. To install a specific tag, branch or commit, or choose another bin directory:

```sh
curl -fsSL https://raw.githubusercontent.com/RayChang/snapparazzi/main/install.sh \
  | SNAPPARAZZI_REF=v1.2.0 sh

curl -fsSL https://raw.githubusercontent.com/RayChang/snapparazzi/main/install.sh \
  | SNAPPARAZZI_BIN="$HOME/bin" sh
```

## 快速開始 / Quick start

```sh
snapparazzi --list                  # 列出視窗與 ID（含其他桌面、全螢幕）/ list window IDs, incl. other Spaces

# 截圖 / Screenshots
snapparazzi                         # 互動選擇視窗與間隔 / interactive mode
snapparazzi -w 12345 -i 1.5         # 指定視窗與間隔 / window and interval
snapparazzi -w 12345 -i 60 -f heic  # 更省空間 / use less storage
snapparazzi -w 12345 -i 1 -m 1280   # 最長邊限制為 1280 px / limit the longest edge

# 錄影 / Recording (macOS 15+)
snapparazzi record -w 12345 --duration 10              # 只錄畫面 10 秒 / 10 s, video only
snapparazzi record -w 12345 --audio system             # 加上 App 聲音，Ctrl-C 停止 / with app audio
snapparazzi record -w 12345 --audio both -o ~/Movies/demo.mp4

snapparazzi --help
snapparazzi record --help
```

若想同時截取或錄製多個視窗，請開啟多個 Terminal 分頁，每個程序選一個視窗。

To capture or record several windows at once, run one Snapparazzi process per Terminal tab.

## 截圖選項 / Screenshot options

`snapparazzi` 與 `snapparazzi capture` 相同。

`snapparazzi` and `snapparazzi capture` are the same.

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

## 錄影 / Recording

錄影需要 macOS 15 以上；在 macOS 14 上 `record` 會說明需要 macOS 15 並以結束碼 1 結束。

Recording needs macOS 15 or later; on macOS 14, `record` explains this and exits with status 1.

| Option | 說明 / Description |
|---|---|
| `-w`, `--window <id>` | 必填，先用 `--list` 查 / Required; find it with `--list` |
| `--audio <none\|system\|mic\|both>` | 預設 `none` / Default `none` |
| `--fps <1-60>` | 預設 30 / Default 30 |
| `--codec <h264\|hevc>` | 預設 `h264` / Default `h264` |
| `--duration <seconds>` | 0.5–86400；省略時按 Ctrl-C 停止 / Omit to stop with Ctrl-C |
| `-o`, `--output <file.mp4>` | 不可已存在 / Must not exist (see [Output](#輸出--output)) |
| `-m`, `--max-dimension <pixels>` | 等比例縮小，不放大；預設為視窗原始像素 / Fit the longest edge, never upscale; native pixels by default |
| `-h`, `--help` | 錄影專用說明 / Recording help |

**聲音範圍 / Audio scope.** `system` 錄的是目標視窗所屬 App 的聲音，不是整台 Mac：其他 App 的聲音不會錄入，但**同一 App 其他視窗或分頁的聲音可能一起錄入**（例如 Chrome 的其他分頁）。DRM 等受保護內容可能錄不到。`system` records the target window's app, not the whole Mac: other apps are excluded, but the same app's other windows or tabs may be included. Protected (DRM) content may not be captured.

**both.** App 聲音與麥克風先錄成兩條音軌，停止後再離線混成一條音軌（各 0.5 增益），影片不重新編碼。代價是停止後還要幾秒到幾十秒收尾、收尾期間暫時需要約兩倍空間，且音訊多經過一次 AAC 編碼。外放聲音會被麥克風再錄一次，建議戴耳機。`both` records two tracks, then mixes them into one after you stop (0.5 gain each) without re-encoding video. Finishing takes extra seconds and about twice the space, and the audio is AAC-encoded twice. Use headphones to avoid echo.

**麥克風 / Microphone.** 使用開始錄影時的預設輸入裝置，錄影中切換系統預設不會跟著換；該裝置被拔除時錄影停止並保留已錄內容。USB 麥克風的時鐘若與系統有些微偏差，Snapparazzi 會持續補償，長時間錄影也能保持同步。The default input at start is used for the whole recording, even if the system default changes; if that device is unplugged the recording stops and keeps what it has. Small clock drift of USB microphones is corrected continuously, so long recordings stay in sync.

**視窗狀態 / Window state.** 視窗最小化超過 1 秒時改錄黑畫面，還原後繼續；切換到其他桌面或視窗進入 macOS 全螢幕時照常錄製。網頁影片的全螢幕要看瀏覽器：若另外開新視窗播放（例如部分 Safari 影片），錄到的是原視窗而非全螢幕影片。視窗被關閉或 App 結束時，錄影停止、保留已錄內容並以結束碼 1 結束。調整視窗大小時影片尺寸不變，內容等比例縮放並貼齊左上角。Minimized windows record black after 1 second and resume on restore; other Spaces and macOS full screen keep recording. Browser video full screen depends on the browser: if it plays in a separate window (e.g. some Safari videos), the original window is what gets recorded. Closing the window or quitting the app stops, keeps the recording and exits 1. Resizing keeps the video size; content is scaled to fit, anchored top-left.

**停止與失敗 / Stopping and failures.** `Ctrl-C`、`SIGTERM` 或 `--duration` 會正常收尾，結束碼 0。開始前會檢查磁碟空間（指定 `--duration` 時依預估大小，否則至少 1 GiB），錄影中剩餘空間低於 512 MiB 會停止並保留已錄內容。寫入或混音失敗時保留暫存檔並顯示路徑；`both` 混音時再按一次 `Ctrl-C` 會取消混音，保留含兩條獨立音軌的 MOV。`Ctrl-C`, `SIGTERM` and `--duration` finish normally (exit 0). Free space is checked before starting (from the estimated size with `--duration`, otherwise at least 1 GiB), and recording stops, keeping what it has, below 512 MiB. Failures keep the staged file and print its path; a second `Ctrl-C` while `both` is mixing cancels the mix and keeps a MOV with two separate audio tracks.

**實測 / Measured.** 在 Apple silicon、macOS 26.5 錄 1280×864、30 fps、H.264、`--audio both` 一小時（兩次）：檔案約 123–130 MiB，停止後收尾與混音約 20–24 秒，錄影期間暫存加成品最多約 257 MiB，CPU 平均約 17–18%，記憶體約 50–60 MiB 且不隨時間增加，音畫同步誤差在 40 ms 以內。檔案大小會隨畫面內容與尺寸改變。Two one-hour runs of 1280×864, 30 fps, H.264 with `--audio both` on Apple silicon: about 123–130 MiB, 20–24 s to finish and mix after stopping, ~257 MiB peak temporary disk, ~17–18% CPU, 50–60 MiB of memory that does not grow, and audio/video within 40 ms. Sizes vary with content and window size.

## 截圖的壓縮與效能 / Screenshot compression and performance

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

## 權限 / Permissions

第一次執行時，macOS 會要求權限。截圖與錄影都需要「螢幕與系統錄音」；`record --audio mic` 或 `both` 另需「麥克風」：

On first use macOS asks for permission. Screenshots and recordings need Screen & System Audio Recording; `record --audio mic` or `both` also needs Microphone:

```text
系統設定 → 隱私權與安全性 → 螢幕與系統錄音 ／ 麥克風
System Settings → Privacy & Security → Screen & System Audio Recording / Microphone
```

macOS 通常把權限記在你用來執行 Snapparazzi 的 Terminal App 名下（例如 Terminal、iTerm2 或 Ghostty），而不是 snapparazzi 本身；換一個 Terminal 可能要重新允許。麥克風權限被拒絕時，`mic`／`both` 會直接以結束碼 1 結束，不會改錄成無聲。Snapparazzi 執行時不會上傳任何資料；圖片與影片只寫入本機。

macOS usually grants these to the terminal app that launches Snapparazzi (for example Terminal, iTerm2 or Ghostty), not to snapparazzi itself; another terminal may need its own permission. If Microphone is denied, `mic` and `both` exit with status 1 rather than recording silence. Snapparazzi does not upload anything; screenshots and recordings stay on your Mac.

## 輸出 / Output

截圖：每次執行在輸出根目錄（預設 `~/Snapparazzi/captures/`）建立獨立 session，副檔名依 `--format`：

Screenshots: every process creates a session under the output root (default `~/Snapparazzi/captures/`); the extension follows `--format`:

```text
~/Snapparazzi/captures/YYYYMMDD-HHMMSS-PID/
└── App_Name_YYYYMMDD-HHMMSS_000001.jpg
```

錄影：一個 MP4 檔，預設路徑如下；`-o` 可指定其他 `.mp4` 路徑（不存在的資料夾會自動建立）。錄影中先寫入同一資料夾下的隱藏暫存資料夾（`.<檔名>.snapparazzi-*`），完成並檢查後才以不覆寫的方式移到最終路徑；目標檔已存在時不會開始錄影。

Recording: one MP4 at the path below by default; `-o` chooses another `.mp4` path (missing folders are created). While recording it is written to a hidden staging folder next to it (`.<name>.snapparazzi-*`) and moved into place only after it is checked, never overwriting; recording does not start if the target exists.

```text
~/Snapparazzi/recordings/YYYYMMDD-HHMMSS-PID.mp4
```

`--list` 也會列出在其他桌面或全螢幕的視窗，並標上「不在目前桌面」。錄影可以直接錄這些視窗；截圖則要等視窗出現在畫面上才會開始，因為 macOS 只能截取目前桌面上的視窗。截圖時若視窗最小化、切換到其他 Space 或關閉，該程序會暫停產圖；同一 window ID 恢復時會繼續。App 重建視窗後通常會取得新的 ID，這時請重新啟動 Snapparazzi 並選擇新視窗。

`--list` also shows windows on other desktops or in full screen, marked "not on this desktop". Recording works on them directly; screenshots wait until the window is on screen, because macOS can only screenshot a window on the current desktop. While taking screenshots, a minimized, hidden or closed window pauses capture until the same window ID is visible again. A recreated window usually receives a new ID; restart Snapparazzi and select it again.

## 開發 / Development

```sh
git clone https://github.com/RayChang/snapparazzi.git
cd snapparazzi
make test
make install
```

`make test` compiles a release binary with warnings treated as errors and runs every suite that needs no permissions or windows: the screenshot CLI contract, record argument parsing, recording tests that drive the timeline, writer and mixer with synthetic frames and tones through real AVFoundation, and the installer in an isolated temporary destination. CI runs it on the latest macOS and also builds on macOS 14 with Xcode 16, checking that `record` refuses there.

Real recordings are opt-in because they need Screen Recording/Microphone permission and a logged-in desktop:

```sh
make recording-acceptance        # every audio mode/codec, A/V sync, app-only audio, minimize, resize,
                                 # full screen, app quit, signals, low disk, no-frame timeout
DURATION=3600 make recording-long-run   # one hour of --audio both: drift, memory, finishing time, disk
make recording-microphone        # mic-track sync (audible beeps), default-input switch, mic removal;
                                 # temporarily changes and then restores the default input
make recording-inspect && .build/recording-inspect FILE.mp4 [--sync]
```

They drive a scripted fixture app (`tests/RecordingFixtureApp`) and check results with `recording-inspect`. `tools/recording-probe` is the standalone ScreenCaptureKit research probe used before the feature was built; design notes and test evidence are in `docs/superpowers/`.

## 解除安裝 / Uninstall

```sh
rm ~/.local/bin/snapparazzi
```

截圖與錄影不會自動刪除。如不再需要，可自行移除 `~/Snapparazzi/captures` 與 `~/Snapparazzi/recordings`。

Screenshots and recordings are never deleted automatically. Remove `~/Snapparazzi/captures` and `~/Snapparazzi/recordings` yourself if you no longer need them.

## License

[MIT](LICENSE)
