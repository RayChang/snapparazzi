# 錄影與音訊驗證計畫、Mac 操作手冊

日期：2026-10-30。狀態：**規劃文件，錄影功能及下列新增測試尚未實作、尚未執行。** 本文件用來驗收後續實作，不代表目前 binary 已經支援 `record`。

## 1. 如何使用這份文件

先閱讀[錄影規格](../specs/2026-10-30-recording-design.md)與[實作計畫](2026-10-30-recording-implementation.md)，再依實作階段執行本文件。CLI 接受的值、混音增益、buffer 上限等，以規格為唯一來源；若這裡與規格衝突，先修正文件，不要讓測試各自定義另一種產品行為。

每個案例都記錄：案例 ID、Git commit、macOS 版本、CPU 架構、Xcode／Swift 版本、完整命令、exit status、實際結果、產物路徑、失敗診斷。只把實際完成的案例標示為通過；`skipped`、缺權限、無設備、未執行要分別記錄。

使用者提供的 Mac 執行輸出顯示：`tests/run-tests.sh` 的 53 項測試及 `tests/install-tests.sh` 的 7 項測試全部通過，release build 使用 warnings-as-errors 也成功。環境為 macOS 26.5.2、SDK 26.5、Apple Swift 6.3.3、arm64，使用 Command Line Tools，沒有選用完整 Xcode。這是使用者回報的既有功能基準，不是雲端代理在 Mac 親自執行的結果，也尚未驗證錄影 API。該次輸出未含 commit SHA；重構前須補記當次 HEAD，並在程式版本有變動時重跑。先前靜態盤點的 55／9 為誤計，已更正；後續不得刪除測試來消除回歸。

以下 `make test-recording`、`make recording-inspect`、`.build/recording-inspect` 都是**待實作的測試介面**，目前不能當成已存在的命令。`make test` 是既有介面。實機 smoke 採本文件手動操作，不另要求尚未定義的 smoke target。

## 2. 驗證層級與交付門檻

| 層級 | 執行環境 | 內容 | 是否需要 TCC／可見視窗 | 通過能證明的範圍 |
|---|---|---|---|---|
| L0 | Linux 或 Mac | 文件、Shell 語法 | 否 | Shell 可解析；不能證明 Swift、影音或錄製可用 |
| L1 | Mac CI | 舊 CLI 53 tests、installer 7 tests、release build | 否 | 既有 CLI、重構與安裝相容性 |
| L2 | macOS 15+ CI | 新 parser、狀態機、時間軸、合成影音、混音與檔案錯誤測試 | 否 | 媒體寫入與控制邏輯；不包括 ScreenCaptureKit 真實授權與設備 |
| L3 | macOS 15+ 實機 | 真實 ScreenCaptureKit、四種 audio 模式、兩個 App 音訊範圍、權限、視窗狀態 | 是 | 真正的視窗及音訊擷取行為 |
| L4 | macOS 15+ 實機 | 一小時影音同步、空間、效能與收尾 | 是 | 本版本在記錄的硬體／設備下長時間可用 |

功能交付要求 L1、L2 全部通過；L3 必須完成；宣稱支援使用者範例的 `--duration 3600 --audio both` 前還要完成 L4。若 CI 沒有互動桌面或 TCC，L3／L4 應顯示未執行，不可用零測試成功取代。

不需要為測試上傳使用者畫面、麥克風或錄影成品。CI 使用合成圖樣與合成聲音；實機使用專門測試內容。

## 3. Mac 測試前準備

### 3.1 工具與環境

目的：確認使用真正支援錄影功能的 runtime 與 SDK，避免把平台錯誤誤判為應用程式錯誤。

1. 使用 macOS 15 或更新版本、Xcode Command Line Tools／專案規定的 SDK。錄影的最低版本與既有截圖功能的相容範圍分開驗證。
2. 使用既有 checkout，不為這個驗證任務建立 worktree。確認 `git status --short`，保留原有改動。
3. 從 repo root 記錄以下輸出。不要記錄完整 process environment 或任何 credential。

```sh
sw_vers
uname -m
xcode-select -p
xcrun --show-sdk-version
xcrun swiftc --version
git rev-parse HEAD
git status --short
```

4. 建置並執行現有驗證，保留原始 exit status；若用 `tee` 擷取 log，在支援的 shell 啟用 `set -o pipefail`。

```sh
make test
```

5. 實作完成新測試後再執行以下**規劃中的**介面：

```sh
make test-recording
```

預期：L1、L2 不要求 Screen Recording／Microphone 權限、不開啟實體麥克風、不連到外網。合成媒體測試確實產生並解碼媒體；不能只檢查設定字典或檔案存在。

### 3.2 實機錄影測試資料

目的：能判斷錄到的是哪個 App、哪些音軌，以及有沒有音畫不同步。

1. 開啟測試 App A，視窗 A1 顯示大字計時器／遞增 frame 編號，播放可辨識的 440 Hz 測試音。App A 再開 A2 視窗播放另一個可辨識訊號。
2. 開啟**不同 App／不同擷取應用程式身分**的 App B，播放 880 Hz 測試音。不能只用同一瀏覽器的另一個分頁代表 App B。
3. 準備視覺閃光＋同時 click 的素材，用來測量 system audio 對 video 的偏移；不要以人手點擊與肉耳估計作為唯一證據。
4. 使用耳機播放 system audio，讓麥克風不會經空氣再次收到測試音。否則在 `mic`／`both` 錄到 App B 聲音可能只是物理收音，不是 audio filter 失效。
5. 準備可用的內建或 USB 麥克風，記錄型號與系統預設輸入。準備固定讀句或拍手事件，驗證 mic 有可辨識內容。
6. 使用一般、非 DRM 素材；DRM 黑畫面／靜音不能用來證明程式過濾或混音正確。
7. 為每次 run 建立新目錄，避免覆寫規則讓後續命令失敗：

```sh
recordingRunDir="$(mktemp -d "${TMPDIR:-/tmp}/snapparazzi-recording.XXXXXX")"
recordingBinary="$PWD/.build/snapparazzi"
"$recordingBinary" --list
```

8. 從清單確認 A1 的 window ID，設定以下變數。範例的 ID 必須換成當次真實值：

```sh
recordingWindowID=12345
```

保留 `$recordingRunDir` 中的結果到人工檢查完成；不要在失敗時直接刪除唯一證據。

### 3.3 產物檢查器的實作要求

目的：以機器可判斷的資料驗證真正可解碼的影片，不以 QuickTime 能開啟或檔案大小大於零作為唯一標準。

新增獨立測試 helper `.build/recording-inspect`，接受檔案路徑，以 AVFoundation／AVAssetReader 讀取輸出；它是測試工具，不是執行時依賴。建議輸出 JSON，欄位至少包含：

- container、video／audio track 數、每軌 codec、video width／height。
- asset duration、各軌第一與最後有效 PTS、解碼 sample 數與最後 sample end time。
- 每軌解碼後的 presentation timeline 是否單調、是否有負時間、是否有無效時間／無法解碼 sample；壓縮 video 的 reader decode-order另查 DTS，B-frame 的 PTS 不可要求在 decode-order也單調，更不能為通過檢查而排序壓縮 samples。
- audio sample rate、channels、RMS／peak、已知測試音頻段能量；區分「有音軌但全靜音」與「有可辨識音訊」。
- 必須讀完整份檔案，直到正常 end of stream；中途 reader failure 令 helper exit 非零。

規劃中的用法：

```sh
make recording-inspect
.build/recording-inspect "$recordingRunDir/system.mp4"
```

若測試機已裝 `ffprobe`，可補充以下證據，但不得把 FFmpeg 列為 Snapparazzi 安裝／執行的必要條件：

```sh
ffprobe -v error -show_format -show_streams -of json "$recordingRunDir/system.mp4"
```

## 4. L0：目前 Linux 能執行的檢查

從 repo root 執行：

```sh
/bin/sh -n install.sh
/bin/zsh -n tests/run-tests.sh
/bin/zsh -n tests/install-tests.sh
/bin/sh -n tests/fixtures/curl
git diff --check
```

新增其他 shell scripts 後也依各自 shebang 加入語法檢查。這些命令只能檢查 shell／patch 格式；不等於 `make test`、Swift type check 或媒體驗證。不要用 Linux Swift、mock binary 或刪除 macOS import 來宣稱原生功能通過。

## 5. L1：相容性、建置與安裝

| ID | 操作 | 通過條件 | 失敗時保留的證據 |
|---|---|---|---|
| LEG-01 | 重構前後在 Mac 跑 `make test` | 原有 53＋7 tests 都有執行；原有輸出、錯誤碼、預設值不變 | 兩次測試 log、commit、assertion 數 |
| LEG-02 | `snapparazzi -w ID -i 2 -o DIR`，截三張後 Ctrl-C | 仍是 JPG screenshot，session 目錄與命名不變，exit 0 | 圖片、summary、exit status |
| LEG-03 | 舊 `--list`、`--help`、`--version`、`--test` helpers | 既有契約仍成立；help/version 不要求權限 | stdout/stderr、無 TCC 提示紀錄 |
| BUILD-01 | release build，warnings-as-errors | 所有新 Swift 檔都參與編譯，沒有遺漏 symbol 或警告 | 完整 swiftc 命令與編譯 log |
| BUILD-02 | 修改一個新 Swift 檔，再 `make build`，還原改動 | make 正確重建 binary；不能只追蹤 main.swift | timestamp／make log，還原後 diff |
| BUILD-03 | 比對本地 build 與 installer build | 相同來源集合、deployment target、Info.plist／usage description 及重要 linker flags | 兩條命令與 metadata 檢查結果 |
| INST-01 | 本機 fixture archive 的安裝測試 | 安裝取得同一 ref 的完整來源；新目錄與 metadata 不遺漏 | fixture archive 清單、URL log、exit |
| INST-02 | 指定 `SNAPPARAZZI_REF`／`SNAPPARAZZI_BIN`，暫存目的地安裝 | 指定 ref 真正生效；安裝 binary 可跑 version/help | URL／ref、binary version、help |
| INST-03 | 注入下載失敗、缺來源、編譯失敗 | exit 非零；已安裝舊 binary checksum 不變；staged／tmp 清乾淨 | before/after checksum、錯誤 log |
| INST-04 | 乾淨 Mac 從已存在的測試 ref 安裝 | 不依賴本機 checkout／未追蹤檔案，麥克風 usage metadata 存在 | 安裝 log、ref、metadata；不自行推送新 ref |
| OS-01 | macOS 15+ 的 record | 可進入錄影 preflight | OS／SDK、正常錯誤或成功結果 |
| OS-02 | 低於 15、仍在截圖支援範圍內的 Mac | help/version/capture 仍可用；record 明確報不支援且 exit 1，不崩潰 | OS 版本、dyld／availability 錯誤若有 |

OS-02 若沒有測試機，必須保留為未執行。單純檢查 `#available` 不足以證明舊 macOS 可以載入 binary；還要檢查 deployment target 與 weak linking。

## 6. L2：不依賴 TCC 的確定性測試

### 6.1 CLI parser

測試直接呼叫純 parser 或 CLI test helper，不觸發視窗發現、權限、檔案建立及 media capture。新的 `RecordingOptions` 序列化不得改寫舊截圖 helper 的輸出格式。

| ID | 輸入 | 預期 |
|---|---|---|
| CLI-01 | `record -w 42` | fps=30、codec=h264、audio=none、cursor off、duration 無限制、output 自動 |
| CLI-02 | 使用者提供的兩條完整 record 範例 | system／both、30 fps、h264、3600 秒、指定 MP4 路徑正確解析 |
| CLI-03 | `record -w 42 --audio none/system/mic/both` 分四次 | 四值皆接受；未知值拒絕，exit 2 |
| CLI-04 | `record -w 42 --duration 0.5`、`86400` | 接受含兩端點；負數、0、0.49、86400.01、NaN、Infinity、空字串拒絕 |
| CLI-05 | fps／codec／max-dimension 的所有合法邊界與非法值 | 嚴格符合規格；錯誤 exit 2；不默默截斷小數或套回預設 |
| CLI-06 | `record -w 42 -i 2`、`record -w 42 --format png`、capture 加 `--audio both` | 跨模式參數拒絕，exit 2；斷言錯誤指出跨模式選項，不能只驗exit2而誤以缺window通過 |
| CLI-07 | 長／短別名重複、缺值、未知子命令、額外 positional argument | 明確錯誤，exit 2；不進入錄製 |
| CLI-08 | output 為空、非 .mp4 副檔名；有效含空白／中文／相對／`~` 路徑 | 非法輸入依規格拒絕；合法路徑不以 shell 字串拼接 |
| CLI-09 | `record --help`、頂層 help/version | exit 0；中英說明包含 App audio 範圍、both 收尾、版本需求；不請求權限 |
| CLI-10 | 無 window 的 record，模擬 TTY 與非 TTY | 兩者都exit2要求window，不讀stdin；`record --help`仍可成功且無權限要求 |

### 6.2 Lifecycle 與故障注入

將 ScreenStream、writer、clock、file operations 抽換為可控制的 fake；測試對真實協作介面注入，不在產品程式加入「永遠成功」分支。

| ID | 注入事件 | 必須觀察到的行為 |
|---|---|---|
| LIFE-01 | start 成功、收到首幀、duration 到期 | 一次 start、一次 stop、一次 finish、exit 0；finish completion 前不得回報完成 |
| LIFE-02 | start 尚在等待首幀時 Ctrl-C／SIGTERM | 沒有 sample 時不發布空 MP4；結果依無有效影片規則回報，無 deadlock |
| LIFE-03 | 錄製中連續多個停止原因 | stop/finalize 各執行一次；保留第一個 runtime failure，不能被後來 Ctrl-C 改成成功 |
| LIFE-04 | stop 期間仍到達 callback | 接受策略符合截止時間；writer finish 後不得 append；無 use-after-free |
| LIFE-05 | startCapture、addStreamOutput、writer start/append/finish 分別失敗 | exit 1，列出可理解原因；不發布 final path；清理策略可檢查 |
| LIFE-06 | system/mic requested 但資料來源回報 fatal error | exit 1；不靜默降級成少一種來源的成功錄影 |
| LIFE-07 | writer 背壓持續、queue 達上限 | 有界記憶體；video 可依策略丟幀並計數，audio 超過容忍時明確失敗；不無限堆積 |
| LIFE-08 | 目標 close、PID 消失或同 ID 換 PID | stop、嘗試完成有效片段、exit 1；不自動改錄另一個視窗 |
| LIFE-09 | 使用者正常停錄後 writer 或第二階段 mix 失敗 | exit 1；不能因最初停止原因正常而回報成功 |
| LIFE-10 | 權限拒絕、輸出路徑失敗 | 不 start stream；不啟動麥克風；無殘留開啟 file handle |

### 6.3 時間軸與 sample 契約

採可指定 CMTime 的合成 sample；禁止用牆鐘 sleep 與隨機 callback 排程作為唯一測試方式。測試首個有效 video PTS 定義共同 epoch，audio 不可各自歸零。

| ID | 合成資料 | 通過條件 |
|---|---|---|
| TIME-01 | video 從 10 秒起，audio 從 9.98 秒起 | 輸出 video 從 0 起；audio 跨 epoch 的 buffer 正確裁切；無負 PTS |
| TIME-02 | mic 比 video 晚 0.4 秒 | mic 在共同時間軸的 0.4 秒才發聲；不可被搬到 0 秒 |
| TIME-03 | callback 到達順序與 PTS 順序不同 | 使用來源 PTS 與規定的排序／丟棄政策；不使用 callback 到達時間當媒體時間 |
| TIME-04 | audio 跨越 duration 截止點 | 裁到允許的最後 sample；沒有超出截止後的長尾音訊 |
| TIME-05 | video 靜態、變動、短暫缺幀 | 時間軸持續；不因 sample 稀疏縮短整段影片 |
| TIME-06 | unavailable 超過 1 秒後恢復 | 從規定時點輸出黑畫面直到恢復；audio 保持原 PTS；沒有壓縮掉空白期間 |
| TIME-07 | nonnumeric／invalid／重複或逆序 sample time | 250ms reorder window內的逆序raw audio可排序接受；已提交cursor前的重疊裁掉／過期資料丟棄並計數，持續超限失敗；invalid time拒絕；writer不接倒退時間 |
| TIME-08 | 首幀遲遲不到、無有效 video sample | 啟動 timeout／取消可結束；不得發布只有音訊或零幀的成功 MP4 |

### 6.4 真正的合成媒體整合測試

以 AVAssetWriter 產生 staging，再透過產品 VideoWriter／AudioMixer 路徑完成輸出，以 AVAssetReader 解碼斷言。不要只 mock writer 來驗證 writer。

1. 產生 3 秒測試圖樣，frame 包含遞增編號；固定畫布、H.264、30 fps。產生 48 kHz 測試 audio：system 440 Hz，mic 880 Hz，並設定 mic 延遲 0.4 秒。
2. 分別測 none、system、mic、both。final MP4 必須是一個 video track；none 沒有 audio track，其餘恰好一個 AAC track。both 的 staging MOV 才是 video＋兩個 AAC tracks。
3. both 解析輸出 audio：0～0.4 秒只有 system 成分，之後兩個頻段皆存在；依規格的固定增益計算期望 RMS／peak。加入同相高振幅測試，檢查沒有溢位 wraparound、NaN 或未定義 clipping。
4. 測 44.1 kHz／mono 與 48 kHz／stereo 輸入、來源格式不同、其中一軌合法靜音及音軌延遲開始。混音輸出 format 必須固定且 duration 不被較短音軌截斷；合法靜音與來源錯誤分開。
5. 第二階段 video 使用壓縮 sample passthrough。比對 staging 與 final 的 codec、尺寸、sample 數、sample PTS／duration；必要時比對壓縮 payload。不可用第二次 video 編碼掩蓋時間軸錯誤。
6. 驗證 0.5 秒短片也有可解碼 video；長片尾端輸入不整除 video frame period／audio frame size 時，末尾差值在規格容許範圍。
7. 以 sample 級斷言驗證共同 epoch、延遲與裁切。AAC 編碼 priming／padding 需以有效解碼時間與 edit metadata 解釋；不能忽略整段固定偏移。
8. 用 1001×777、極窄／高、Retina 尺寸測試幾何：canvas 兩邊皆偶數、保持比例、左上角對齊補黑、never upscale，`--max-dimension` 限制的是實際輸出 pixels。錄製中 resize 不改已建立 writer 的 track 尺寸。
9. 注入磁碟寫入／mix reader／mix writer／最終發布失敗，確認 output final path 不存在且 staging 依規格保存或清理，不把損毀 MP4 當成功。

## 7. L3：真實錄影操作

### 7.1 四種音訊模式

目的：確認實際 ScreenCaptureKit samples、權限與成品，不只驗證合成資料。

在 App A／B 都持續播放各自測試音、使用耳機且麥克風可用時，依次執行：

```sh
"$recordingBinary" record -w "$recordingWindowID" --audio none --duration 10 --output "$recordingRunDir/none.mp4"
"$recordingBinary" record -w "$recordingWindowID" --audio system --duration 10 --output "$recordingRunDir/system.mp4"
"$recordingBinary" record -w "$recordingWindowID" --audio mic --duration 10 --output "$recordingRunDir/mic.mp4"
"$recordingBinary" record -w "$recordingWindowID" --audio both --duration 10 --output "$recordingRunDir/both.mp4"
```

每條命令立即記錄 exit status；在 mic／both 的 3～6 秒讀出固定句子。用檢查器與播放器完成下表，保留各 run 的 summary。

| ID | 模式 | 權限及產物必須滿足 |
|---|---|---|
| REAL-01 | none | 不要求麥克風權限；video 一軌、audio 零軌；不是有一條靜音軌 |
| REAL-02 | system | 不要求麥克風權限；video 一軌＋AAC 一軌；有 App A 音，無 App B 的數位音訊 |
| REAL-03 | mic | video 一軌＋AAC 一軌；可辨識測試人聲；耳機隔離下無 system 音的數位直入 |
| REAL-04 | both | video 一軌＋**混成的一軌 AAC**；一般播放器直接聽到 system 與 mic，不需要手動選 track |
| REAL-05 | both 收尾 | 停錄後顯示處理中，mix 完成才發布 final MP4／exit 0；不把 staging MOV 當交付物 |

另外實機驗證HEVC，確保兩階段passthrough並非只在合成H.264情境可用：

```sh
"$recordingBinary" record -w "$recordingWindowID" --audio both --codec hevc --fps 30 --duration 10 --output "$recordingRunDir/both-hevc.mp4"
.build/recording-inspect "$recordingRunDir/both-hevc.mp4"
```

預期exit0、HEVC video一軌、AAC混音一軌、固定尺寸、兩種已知聲音皆存在且offset符合門檻；檢查解碼相容性與收尾，不能偷偷fallback為H.264。

### 7.2 system 的範圍必須是目標 App

目的：避免把 `--audio system` 實作成整台 Mac 的聲音，或錯誤承諾單一視窗能隔離同 App 音訊。

1. 只讓 App A 的 A1 發聲，App B 靜音；錄 system。預期包含 A1。
2. 讓 A1 靜音，**同 App** 的 A2 發聲；仍錄 A1。預期可包含 A2，與「目標 App 音訊」規格一致；CLI/help 必須清楚告知此範圍。
3. A1、A2 靜音，App B 發聲；仍錄 A1。預期不包含 App B 音訊。
4. A1、A2、B 同時發不同辨識音；錄 system，再錄 both。兩種模式的 system 部分都必須只包含目標 App 的來源。
5. 記錄 SCK 識別到的應用程式／PID 與目標 window owner。瀏覽器、多程序播放器若無法完全按預期歸屬，保留實際結果並列出限制，不能用「聽起來差不多」標示通過。

### 7.3 權限與輸入設備

| ID | 操作 | 預期 |
|---|---|---|
| PERM-01 | Screen Recording 未授權，執行 record | 有可操作的中英提示；拒絕後 exit 1；沒有成功 MP4 |
| PERM-02 | mic 未授權，分別 record none／system | 兩者不要求 mic；不讀取預設輸入 |
| PERM-03 | mic 未授權，執行 mic／both 並拒絕 | 不 crash；明確拒絕原因、exit 1；不靜默降級 |
| PERM-04 | 允許 mic，再次執行 mic／both | 正常得到可辨識 audio；所需 usage description 包含於實際安裝 binary |
| PERM-05 | 錄製中拔除已選定外接 mic／切換預設裝置，分開測 | 選定裝置消失須錯誤收尾；只切換OS預設則仍使用開始時固定的裝置，不自動跟隨 |
| PERM-06 | 錄製中撤銷權限 | 停止並報 runtime error；能完成的有效片段與失敗狀態清楚區分 |

不要假設每次 CLI 重編譯後 TCC 決策與舊 binary 相同。記錄實際啟動 Terminal、binary 路徑與簽章方式。權限測試使用專用測試帳號；不以廣泛重設使用者 TCC 當成標準前置步驟。

### 7.4 視窗、尺寸與時間連續性

1. 錄 both 30 秒，期間遮住目標視窗，再恢復；確認是否仍擷取目標內容，而非把遮擋 App 錄進去。
2. 目標最小化 5 秒後還原：收到 `suspended` 超過 1 秒後畫面轉黑，audio 繼續；恢復後接續同一固定畫布與時間軸，不跳過 5 秒。另一次切到其他 Space 5 秒後切回：持續錄到視窗內容，不轉黑。
3. 錄製中 resize 視窗、移到不同 DPI 螢幕。video track width/height 不變，畫面保持比例、貼齊左上角、右／下補黑、不 upscale；沒有 writer format change crash。
4. 目標視窗關閉、App 結束分開測。程式停止，嘗試完成已有有效片段，exit 1；不自動接到另一個 window ID 或重啟 App 的 PID。
5. 在畫面移動滑鼠，確認預設不包含 cursor。
6. 使用超過 max-dimension 的 Retina 來源錄 `--max-dimension 1280`，檢查檔案 pixel 尺寸而非螢幕 points。再用小視窗測不會放大。

### 7.5 正常與失敗停止

目的：證明 stop/finalize 一次、音訊不遺失尾端，以及錯誤碼反映最後產物狀態。

1. `--duration 10` 自動停止：檢查 final 影片可完整解碼，時間軸從 0 開始，末端符合 frame／audio sample 容許誤差，exit 0。
2. 不給 duration，在可見 terminal 前景錄製至少 5 秒後按 Ctrl-C：等待完成收尾，exit 0，尾端可播放。
3. 同樣方式錄製，從另一個 terminal 對**這次測試啟動的 PID**送 SIGTERM：結果同正常停止；不要用 `pkill` 影響其他工作。
4. 停止後立即再送一次停止訊號，檢查不重複 finish、不 deadlock；若規格允許第二次強制中止，須按該規格分開驗證，不誤判成功。
5. 在等待授權／首幀時停止：可結束，不發布零幀 MP4。
6. 檢查 SIGKILL 的結果時，明確記錄它不能保證 MP4 完成；不得把作業系統強制終止當成可保證恢復的正常收尾。

### 7.6 檔案安全與錯誤路徑

1. 在 `$recordingRunDir/existing.mp4` 建立固定內容，記錄 checksum，指定同一路徑錄製。預期拒絕覆寫、exit 1、checksum 不變；也測目錄與 dangling symlink 佔用 final path。
2. 在無寫入權限的測試目錄錄製。預期 preflight 失敗，不請求不必要設備、不留下成功產物。
3. 同時啟動兩次錄影到相同 final path；驗證至多一個可發布，另一個失敗，不能最後一次 rename 靜默覆寫。
4. 用獨立、可丟棄的小容量測試 volume，分別在 capture 及 both 第二階段耗盡空間。不要填滿使用者或 CI 系統磁碟。預期 exit 1、沒有假成功檔案，staging 處理與訊息符合規格。
5. both 成功後確認產品管理的中介檔已清理；失敗時若規格保存 staging，訊息給出其路徑，測試應檢查其實際存在與是否可讀。

## 8. L4：同步、長時間與資源

### 8.1 短時間同步基準

1. 使用同一素材中同時發生的閃光＋click 錄 system 60 秒，每 10 秒一個可測事件。
2. 用檢查器或分析工具量出每個 video 事件 PTS 與 audio click PTS，不使用播放器操作延遲當作檔案偏移。
3. 建議驗收：短片 system audio 對 video 偏移絕對值不超過 100 ms；所有事件之間無持續增加的漂移。若規格採更嚴格門檻，使用較嚴格值。
4. mic 使用相同可辨識事件做量測時，記錄裝置／聲學延遲；合成測試應先證明程式不額外錯移 0.4 秒等偏移。

### 8.2 一小時 both 錄製

目的：驗證使用者 `--duration 3600` 範例，包括兩階段混音的空間、收尾與長時間同步。

1. 預估空間：both 可能同時保留 staging MOV 與 final MP4，至少預留兩份 video 的容量加上音訊與餘裕。使用實測短片 bitrate 估算；不要假設錄一小時只占最終檔大小。
2. 記錄起始磁碟可用空間、程式常駐記憶體與 CPU；不要求所有硬體達到相同絕對效能數字，但記憶體不能隨時間無界增加。
3. 在 App A 持續播測試素材，mic 以固定方式提供訊號。執行：

```sh
"$recordingBinary" record -w "$recordingWindowID" --audio both --fps 30 --codec h264 --duration 3600 --output "$recordingRunDir/hour-both.mp4"
```

4. 在 0、10、30、60 分鐘附近保留閃光＋click 事件；記錄開始、capture stop、mix finish 的實際時間。duration 指錄製時間，both 收尾耗時不算進錄製 3600 秒。
5. 每 5 分鐘記錄本 PID 的 RSS、CPU、磁碟使用量與 summary counter。只採集本次程序；不要 dump 全系統環境或敏感 process arguments。
6. 完成後完整解碼最終 MP4，檢查一個 video＋一個 AAC、duration、前中後內容、單調 PTS、無 truncated tail、沒有仍被當交付物的多音軌 staging。
7. 驗收：起始、結尾與中間可測事件的音畫偏移絕對值不超過100 ms，起始至結尾的相對漂移變化也不超過100 ms，沒有持續線性增長；若不符合，保留各事件 PTS 與硬體資料，先診斷時鐘／retiming，不以重編 video 掩蓋。
8. 若丟幀，summary 必須如實報告；不能把 `--fps 30` 誤當成每個來源在所有負載下保證 CFR 30。若 queue／audio policy 超限，應明確失敗而非無聲音但 exit 0。
9. 記錄第二階段 mix wall time、尖峰空間、尖峰 RSS。預期 video passthrough；不能因一小時長度而把整份 video 或 audio 載入記憶體。

## 9. 測試證據格式與完成定義

每次測試可使用以下紀錄模板：

```text
Case IDs:
Commit:
macOS / architecture / SDK / Swift:
Terminal / binary path / signing identity:
Audio input / headphones / target App identity:
Command:
Exit status:
Expected:
Observed:
Artifact paths and inspector JSON:
Capture duration / finalization duration:
PASS / FAIL / SKIPPED / UNRUN:
Failure diagnosis or missing prerequisite:
```

一個案例通過必須同時滿足它的功能、產物與退出狀態要求。若程序exit0但缺少模式要求的audio track、已知有聲fixture未錄到預期訊號、MP4不能完整解碼，或both只有可選的兩條獨立音軌，仍然失敗。none應沒有audio track；合法安靜來源可以有靜音軌，依規格記錄補零與警告，不誤判為必須有聲。

交付報告分開列出：已通過的舊相容性測試、新確定性測試、實機測試、長時間測試、尚未驗證的硬體／OS。只提交文件或在 Linux 跑語法檢查時，必須明說原生錄製尚未驗證。這份計畫不授權推送、建立 Release、部署或發布環境。
