# Task 0：獨立錄影驗證工具

**目前狀態：已在 macOS 26.5.2 編譯並完成部分實測（none／system／mic／both、h264／hevc、SIGINT／SIGTERM、App 範圍、時鐘、混音 passthrough），結果見[開發交接](../../docs/superpowers/plans/2026-10-30-recording-progress.md)；Retina、resize、mic 拒絕等仍待測。** 這是研究工具，不是正式 `snapparazzi record`，也不代表 Task 0 已通過。正式 CLI、Makefile、installer 與截圖測試保持原樣。

此工具先驗證單一 SCStream 的畫面／App audio／microphone 回呼、原始格式與 PTS，以及 AVAssetWriter 的短片寫入。使用 ScreenCaptureKit 單視窗 filter；**音訊是否確實限定目標 App 必須實測，不能由 filter 名稱推論。**

## 1. 在 Mac 建置

先把此 worktree 的內容帶到 Mac；雲端建立分支不會自動同步你的本機 checkout。以下命令均在包含本目錄的 repo root 執行。

```sh
sw_vers
xcode-select -p
xcrun --show-sdk-version
xcrun swiftc --version
git rev-parse HEAD
git status --short
sh tools/recording-probe/build.sh
.build/recording-probe/recording-probe --help
```

需要 macOS 15+ 及 macOS 15+ SDK。Command Line Tools 可以先嘗試，不要求先安裝完整 Xcode。建置採 Swift 5 language mode（保留既有 swiftc 預設語意）、warnings-as-errors，binary deployment target 為 macOS 15；這個獨立 probe **不驗證正式 CLI 的舊系統 weak linking**。

build.sh 嵌入 Info.plist 並做具穩定 identifier 的 ad-hoc 簽章；不安裝全域 binary、不變更 PATH、不重設 TCC。重新建置後可能需要重新授權。若編譯出現 SDK signature／deprecation 錯誤，保留完整錯誤與工具鏈資訊再修正，不拿掉 warnings-as-errors。

## 2. 列視窗與準備測試

```sh
probeBinary="$PWD/.build/recording-probe/recording-probe"
probeResults="$(mktemp -d "${TMPDIR:-/tmp}/snapparazzi-probe.XXXXXX")"
"$probeBinary" list > "$probeResults/windows.jsonl"
cat "$probeResults/windows.jsonl"
```

首次 list/capture 會請求螢幕錄製權限。依系統提示允許實際啟動它的 Terminal／App／probe，必要時重開終端；help、inspect 不請求擷取權限。

選定視窗後，將以下數字換成該次列出的真實 ID：

```sh
probeWindowID=12345
```

準備測試 App A（目標）與不同 App B（非同瀏覽器另一分頁）。A 播 440Hz 或可辨識語音，B 播 880Hz 或不同語音；用耳機避免聲音經空氣進入 mic。內容使用非 DRM 測試素材，不含私密資料。

## 3. 各音源分別測試

以下每條命令執行後，立即記錄 `$?`；不能只看有沒有 MOV。已存在的 output 會被拒絕，再測請換檔名或另建測試目錄。stdout 是 JSON lines，可用重導向保存；如使用 tee，先開 `set -o pipefail`。

```sh
"$probeBinary" capture --window "$probeWindowID" --audio none --duration 10 --output "$probeResults/none.mov" > "$probeResults/none.jsonl"
echo $?
"$probeBinary" capture --window "$probeWindowID" --audio system --duration 10 --output "$probeResults/system.mov" > "$probeResults/system.jsonl"
echo $?
"$probeBinary" capture --window "$probeWindowID" --audio mic --duration 10 --output "$probeResults/mic.mov" > "$probeResults/mic.jsonl"
echo $?
"$probeBinary" capture --window "$probeWindowID" --audio both --duration 10 --output "$probeResults/both.mov" > "$probeResults/both.jsonl"
echo $?
```

mic/both 才請求 microphone permission，固定開始時的預設裝置 uniqueID，不列印裝置識別碼。system/none 不列舉 mic。請在 mic/both 期間說出固定測試句。

每次 capture 結束會完整解碼檔案並輸出 inspection；也可獨立重跑：

```sh
"$probeBinary" inspect "$probeResults/system.mov"
```

檢查：

| 證據 | 預期／用途 |
|---|---|
| configured | 目標 ID/PID、source backing pixels、1280px 以內的固定畫布、codec/audio mode |
| sample | 每來源前8個buffer的原始PTS、host clock、duration、samples；audio的實際ASBD取樣率／聲道數；screen狀態與幾何附件 |
| epoch | 第一個完整video的sourcePTS；三來源都減同一epoch，不各自歸零 |
| capture_result | 每來源seen/written、丟棄原因（含超過終點的`*_after_endpoint`）、`screen_dirty`（完整畫面依dirtyRects分為changed／unchanged／missing）與`screen_dirty_area_fraction`（每張dirty面積／畫布，min／max／mean）、writer完成／error；不能只看success就宣稱scope與sync通過 |
| inspection | 全檔decode完成、每軌codec／大小／first/last PTS、audio RMS與peak |

none應1video、0audio；system/mic應1video、1audio；both此階段是1video、**2條獨立audio tracks**。預期音源完全沒有written buffers、要求的track消失、或已知有聲來源RMS為0，都需要診斷；合法安靜與擷取錯誤分開記錄。能量不是音源歸屬證據。

**both MOV只是diagnostic stage，不是規格要求的單音軌MP4。** 不以播放器只播其中一軌當成混音成功；混成單音軌MP4見第6節。

## 4. App 範圍與短片同步

1. A播音／B靜音，錄system；確認有A。
2. A靜音／B播音，錄system到另一檔；確認沒有B。
3. A、B同時播不同聲音，錄system；確認只包含A。
4. 同一App A第二視窗播音，仍錄A第一視窗；記錄是否包含。help／規格不能承諾隔離同App其他視窗。
5. 以閃光與click同時發生的素材錄60秒，保存原始PTS、影片與事件位置。先檢查PTS與host相同量級；若完全不同，工具會報需調查時鐘。量級相同仍不能證明同步，需後續事件分析，不能以callback抵達時間替代PTS。

播放器聽音只作初步檢查；正式App範圍／100ms同步gate仍需要已知訊號分析與可重現的事件PTS證據。此版本的inspect只解碼、檢查時間及音量，不自動判斷440/880Hz歸屬或閃光位置。

## 5. 停止與格式測試

```sh
"$probeBinary" capture --window "$probeWindowID" --audio both --codec hevc --duration 10 --output "$probeResults/both-hevc.mov" > "$probeResults/both-hevc.jsonl"
echo $?
```

另開一個60秒capture，在數秒後按Ctrl-C，確認JSON有capture_result/inspection且檔案可完整解碼。signal handler只送停止請求；stopCapture後經serial queue barrier封閉來源，再finish writer。實際SDK的callback收尾語意仍待Mac輸出驗證；不能將此程式存在當成已證明。

## 6. 混音與 passthrough

```sh
"$probeBinary" mix-test --codec h264 --dir "$probeResults"   # 合成fixture→混音→自動檢查，失敗exit 1
"$probeBinary" mix-test --codec hevc --dir "$probeResults"
"$probeBinary" mix "$probeResults/both.mov" "$probeResults/both-mixed.mp4"
```

`mix-test`產生4秒fixture（440Hz 48k stereo從0秒、880Hz 44.1k mono從0.5秒），依規格第6節混音，檢查：1 video＋1 AAC 48k stereo、壓縮影片bytes與播放時間不變、各音調音量＝0.25、880Hz起點0.5秒。`mix`對實錄MOV做同樣混音並比對影片。

## 7. 目前刻意未實作的項目

- 合成fixture、延遲500ms音軌／44.1k mono連續轉換與sample級音訊裁切。
- 靜態frame ticker、來源缺口補零、resize/Space/minimize的正式畫布處理與可見性監控。
- 一小時效能／漂移、裝置拔除策略、舊macOS載入／weak linking。

這個probe直接append SCK樣本，由writer處理輸入格式；不代表production AudioCapture的AVAudioConverter已實作。epoch以前或負時間buffer會丟棄並計數，不能拿這種簡化代替正式裁切。固定SCK畫布可能在resize時拉伸，因此先別用它證明正式resize規格已達成。

下一步先讓Mac編譯並跑出source format／PTS／App範圍的真實證據；再依結果寫混音與synthetic media probe。未完成上述Task0 gate，不進入正式record整合。將log與錯誤回傳即可，無需提交私人錄音或影片。
