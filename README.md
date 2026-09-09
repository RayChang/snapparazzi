# Snapparazzi 📸

Snapparazzi is a native macOS CLI that repeatedly captures one specific app window. Pick a visible window interactively or pass its window ID, choose the interval, and let your tiny terminal paparazzo work until you press `Ctrl-C`.

Snapparazzi 是一個原生 macOS CLI，可定時截取指定的 App 視窗。你可以從互動清單選擇目前可見視窗，也可以直接傳入 window ID 與時間間隔；按下 `Ctrl-C` 即可停止。

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

重新執行同一命令即可更新。安裝特定 tag 或自訂 bin 目錄：

Run the same command again to update. To install a specific tag or choose another bin directory:

```sh
curl -fsSL https://raw.githubusercontent.com/RayChang/snapparazzi/main/install.sh \
  | SNAPPARAZZI_REF=v1.0.0 sh

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
| `-h`, `--help` | 完整中英雙語說明 / Full bilingual help |
| `-V`, `--version` | 顯示版本 / Show version |

完整說明、錯誤碼與更多範例：

For complete usage, exit statuses, and more examples:

```sh
snapparazzi --help
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
└── App_Name_YYYYMMDD-HHMMSS_000001.png
```

若視窗最小化、切換到其他 Space 或關閉，該程序會暫停產圖；同一 window ID 恢復時會繼續。App 重建視窗後通常會取得新的 ID，這時請重新啟動 Snapparazzi 並選擇新視窗。

If a window is minimized, moved to another Space, or closed, capture pauses. It resumes if the same window ID becomes visible again. A recreated window usually receives a new ID; restart Snapparazzi and select it again.

## 開發 / Development

```sh
git clone https://github.com/RayChang/snapparazzi.git
cd snapparazzi
make test
make install
```

`make test` compiles a release binary with warnings treated as errors, runs the CLI contract suite, and tests the installer in an isolated temporary destination.

## 解除安裝 / Uninstall

```sh
rm ~/.local/bin/snapparazzi
```

截圖不會自動刪除。如不再需要，可自行移除 `~/Snapparazzi/captures`。

Screenshots are never deleted automatically. Remove `~/Snapparazzi/captures` yourself if you no longer need them.

## License

[MIT](LICENSE)
