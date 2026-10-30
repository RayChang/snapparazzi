# Snapparazzi 錄影功能逐步實作計畫

狀態：**Task0獨立probe已在Mac編譯並完成部分技術gate（App範圍、時鐘、畫面縮放），其餘待測；Task2～16尚未開始。** 進度與證據範圍見[開發交接](2026-10-30-recording-progress.md)。配套：[產品／技術規格](../specs/2026-10-30-recording-design.md)、[驗證手冊](2026-10-30-recording-validation.md)。

目的：讓不熟悉此專案或影音 API 的模型，也能依明確輸入、修改範圍與完成條件逐步工作。不要一次貼入整套錄影程式。每次只執行一個 task，完成測試與交接紀錄再往下。

## A. 執行規則與依賴

1. 先讀三份文件，再讀該 task 指定原始檔。規格決定使用者行為；本計畫決定順序；驗證手冊決定證據。若發現衝突先修文件，不自行選一個容易通過的行為。
2. 使用目前 checkout；先 `git status --short` 保存原有變更狀態。不reset使用者變更或覆蓋原有檔案。使用者已明確要求worktree，本次使用`feat/recording`的獨立worktree；後續在同一worktree繼續，不另外建立。
3. 本功能已確認 macOS 15+、App 範圍音訊。Linux 可以編輯文件／code，但不能執行 Apple framework 測試；不要將 Linux syntax pass 寫成 build pass。
4. 每個 task 至少交付：修改檔案、實作要點、執行命令與 exit status、測試數、未執行項與原因、下一 task。失敗測試不能改成 skip 來通過。
5. 新測試先針對實際行為或 invariant 寫失敗案例，再實作。重構 task 不改產品行為，先跑既有測試當基準。
6. 需要 macOS SDK／實機證據的 gate 沒通過，不標成完成；可以獨立做 parser 等工作，但不可繞過未證明的音訊／時間軸假設接上正式功能。
7. 除使用者明確授權外，不推送、不tag、不合併、不發布。本次使用者已授權將規劃與Task0初版push到`feat/recording`；未授權合併或發布正式版本。版本更新與release為另一項工作；此計畫先維持原有版本字串，避免把版本改動混入機械式拆檔。
8. 保留 `-O -whole-module-optimization -warnings-as-errors` release 驗證。不能刪掉 warnings-as-errors、吞掉 errors 或用寬鬆 flags 避開 SDK 問題。
9. 不要求 superpowers 或其他未安裝的技能；本文件可以直接逐項執行。

依賴：

```text
Task 0 技術驗證 ───────────────────────────────┐
Task 1 基準 → Task 2 拆檔/建置/安裝 → Task 3 CLI │
                         → Task 4 測試接縫      │
Task 0+2+3+4 → Task 5 權限 → Task 6 檔案          │
             → Task 7 Timeline → Task 8 Writer  │
             → Task 9 畫布 → Task 10 SCK        │
             → Task 11 無聲錄影閉環 ←───────────┘
             → Task 12 單來源音訊 → Task 13 雙來源混音
             → Task 14 收尾與失敗 → Task 15 CI/文件 → Task 16 實機驗收
```

Task 0 可以在獨立 Mac 先驗證；Task 1–4 不必等所有實機測試才開始。Task 2 的 build/installer 改動須一起交付，不能留一個安裝器已壞的中間里程碑。

## B. 共用型別與介面草圖

以下是**意圖介面，不是可直接貼上的 SDK 程式碼**。task 開始前依實際 Swift 版本定義 protocol，補齊 actor／queue ownership。非 Sendable 的 CMSampleBuffer、CVPixelBuffer 不能為了編譯就到處加 `@unchecked Sendable`。

```swift
enum CLIAction {
    case help
    case recordingHelp
    case version
    case screenshot(ScreenshotOptions) // 原 run(options) 的等價路徑
    case record(RecordingOptions)
}

enum AudioMode: String { case none, system, mic, both }
enum VideoCodec: String { case h264, hevc }
struct RecordingOptions {
    var windowID: CGWindowID? = nil
    var audio: AudioMode = .none
    var fps: Int = 30
    var codec: VideoCodec = .h264
    var duration: Double? = nil
    var outputPath: String? = nil
    var maxDimension: Int? = nil
}

// 以下型別以 @available(macOS 15.0, *) 隔離。
enum RecordingStopReason {
    case interrupt, terminate, durationReached
    case windowClosed, streamFailure(Error), pipelineFailure(Error)
}
enum RecordingState { case idle, preparing, starting, recording,
                           stopping, finalizing, completed, failed }

// 所有方法的實際 queue／隔離策略要在實作時寫成註解。
protocol RecordingStream {
    func start() async throws
    func stop() async throws
    // video/system/mic callback 與 fatal-event sink 在 start 前注入
}
protocol RecordingSink {
    // callback 不可以直接跨 actor 傳 SDK 物件；由有界 queue adapter 接入。
    // append 回傳 accepted / backpressured，或 throw 真正的寫入錯誤。
    func finish(at end: CMTime) async throws -> URL
    func cancel() // 冪等，不等同成功 finish
}
```

保留 `WindowTarget.id/ownerPID/ownerName/title`。測試只需 fake stream、writer、clock、permission、filesystem adapter；不要另做一個無法代表真實 macOS 行為的 Linux recording engine。

## Task 0：用最小 probe 消除 Apple API 的不確定性

**目的：** 先證明最容易把整個方向帶錯的技術前提，避免較弱模型寫幾千行後才發現 filter 沒有目標音訊或 CLI 無法取麥克風。

**位置：** 獨立程式放 `tools/recording-probe/`，不接正式入口；binary放gitignored的`.build/recording-probe/`，個別錄影／log用私有mktemp目錄。通過的純媒體fixtures／檢查程式稍後納入tests；不能把/tmp路徑當未來依賴。

- [ ] 在 macOS 15+ 執行 `sw_vers`、`xcode-select -p`、`xcrun --show-sdk-version`、`xcrun swiftc --version`，記錄 Mac 架構與測試日期。有完整 Xcode 時另記 `xcodebuild -version`；使用 Command Line Tools 時，此命令報「requires Xcode」不單獨構成阻擋，仍以 probe 編譯與執行結果為準。
- [ ] 查閱規格最後的 Apple 文件，編譯 SCK probe：列 `SCShareableContent`、以 window ID + PID 選單窗、啟動 screen/audio/microphone callbacks。核對方法 signature／available annotations，不猜 API 名稱。
- [ ] 記錄前幾個 buffer 的 media type、PTS、duration、sample rate/channels、screen status 與 host clock 對應值。不記錄 audio payload。
- [ ] 目標 App A 與非目標 App B 播不同頻率聲音；證明 B 不被錄入。A 的第二個視窗也播聲音，確認並記錄同 App 邊界。瀏覽器另做一次，不把所有 renderer PID 當作目標外 App。
- [ ] 用含 embedded Info.plist 的 CLI 實測 mic 首次授權、拒絕、重新允許；驗證 none/system 不詢問 mic。保留實際授權歸屬說明。
- [ ] 建立 3–5 秒合成 MOV：固定尺寸 video、一條從 0 起的 tone、一條從 0.5 秒起的不同 tone。分別用 H.264、HEVC。實作規格所述 reader/audioMix/writer，輸出 MP4。
- [ ] 檢查最終只有 1 video + 1 AAC；前 0.5 秒只有來源一，其後兩者都有；video codec/尺寸/壓縮 samples 沒被改成另一 codec 或重新編碼；PTS/DTS 與順序正確。測試 44.1k mono → 48k stereo。
- [ ] 驗證 `stopCapture` 返回後 callbacks 的實際結束語意與 delegate event；找出可用的 queue barrier，禁止靠 sleep 猜收尾。
- [ ] 驗證單窗 Retina pixel size、視窗移動／縮放、minimize 與 close 的可觀測差異。
- [ ] 以原本部署 target 建置含 availability guard 的 executable，確認舊系統載入／weak linking 策略；若沒有舊機器，明確標成未驗證，不能聲稱完整舊版相容。

**完成條件：** 上述每一項有可重跑命令、觀察結果與成品檢查。若 App 範圍、共同 PTS、mic 授權或混音 remux 失敗，先修訂規格，不得在正式路徑換全桌面錄音或悄悄重新編影片。

## Task 1：建立既有行為基準

**讀取：** `README.md`、`Sources/Snapparazzi/main.swift`、`Makefile`、`install.sh`、`tests/run-tests.sh`、`tests/install-tests.sh`、`tests/fixtures/curl`、`.github/workflows/ci.yml`。

- [ ] 保存 HEAD、`git status --short`。基準版本應為 1.1.0，若 repo 已有新變更先重讀本計畫的函式對應。
- [ ] 在 Mac 跑 `make test`，保存完整 exit status 及 CLI／installer 的 checks 數。使用者已回報 53 + 7 全部通過；詳見驗證手冊，補記該次 HEAD。程式版本有變動時重跑，以實際測試數為準。
- [ ] 保存 `--help`、`--version`、`--test arguments`、`--test arguments --list`、錯誤參數輸出與 exit code，作重構前後 diff。
- [ ] 記錄原部署下限；不要把目前 macos-latest 能跑當作所有舊 macOS 都能跑。
- [ ] Linux 上只跑 CI 的四個 `sh -n`／`zsh -n`，記錄 `make test` 無法執行的原因；不製造空 binary 滿足測試。

**完成條件：** 能區分原有失敗與新改動；未有原 Mac baseline 時可以準備編輯，但不能宣稱重構已完整驗收。

## Task 2：機械式拆檔，連同本地建置與一行安裝一起修好

**目的：** 增加功能前先降低 main.swift 的耦合，且讓任何新檔案都能被正式安裝。

**修改：** `Sources/Snapparazzi/`，`Makefile`、`install.sh`、curl fixture、installer tests。這個 task 不新增 record 使用者行為。

- [ ] 建立 CLI/Core/Capture/Testing 目錄，按下表搬移既有程式。先不重新命名 public 行為，不改輸出字串、排序、預設與錯誤碼。

| 原函式／型別 | 目的地 |
|---|---|
| CaptureFormat、RunMode、CLIOptions、CLIAction、CLIUsageError | CLI/Options.swift（CLIOptions 後續改名 ScreenshotOptions） |
| parseArguments、parseWindowID、parsedInterval | CLI/CommandParser.swift |
| helpText、版本與常數 | CLI/Help.swift／適當單一 metadata 來源 |
| WindowTarget、discoverWindows、selectedWindowIsAvailable、選窗／清單 helpers | Core/WindowDiscovery.swift |
| sessionTimestamp、expandedDirectoryURL、defaultOutputRoot、makeSessionDirectory | Core/SessionManager.swift |
| StopController | Core/StopController.swift |
| ensureScreenCapturePermission | Core/Permissions.swift |
| CaptureResult/Stats、runTool、captureWindow、runCapture、圖片尺寸／參數／命名 helpers | Capture/ScreenshotEngine.swift |
| runTestCommand、testArgumentDescription | Testing/TestCommand.swift |
| run、main 的 action dispatch | AppRunner.swift；main.swift 先保留唯一 top-level 入口 |

- [ ] 跨檔使用的宣告改成 internal；檔內實作留 private。不需要 public。每個 Swift 檔補上自己使用的 imports。
- [ ] Makefile 定義完整且穩定排序的 source list，target dependencies 包含所有 production `.swift`、Makefile 與實際使用的 metadata。不要把 tests 或 probe 編進產品。
- [ ] 保留 swiftc。來源清單由 `find Sources/Snapparazzi -type f -name '*.swift'` 或等價方式產生；確認 nested 檔也納入。不要用只列目前檔名的易漏清單。
- [ ] `install.sh` 改從 `https://codeload.github.com/RayChang/snapparazzi/tar.gz/<ref>` 下載單一 archive；ref 要驗證／URL 編碼，保留 `main`、tag、SHA 與含 `/` 的分支。禁止把 ref 拼成 shell command。
- [ ] 解壓進 mktemp 私有目錄，驗證預期 Sources/Makefile，從該 checkout 呼叫同一 Makefile 編譯；不再 grep main.swift 的 private version marker。不要依賴原 repository 路徑或已存在的 `.build`。
- [ ] archive 來源為 HTTPS GitHub，同一份 archive 含所有檔；保留 TLS 驗證與 curl 失敗處理。檢查 tar members 不含絕對路徑或 `..` 逃逸，不可把 archive 解壓到使用者目錄。
- [ ] 保留 macOS gate、SNAPPARAZZI_REF/BIN、版本 smoke、同目錄 staged binary 的原子安裝、失敗保留舊 binary、PATH 行為與 trap cleanup。新需要 tar/make 時先檢查存在。
- [ ] fixture 改為從本地 repo 建立真正的來源 archive，再由 fake curl 回傳它，並記錄 URL；不能永遠只複製 main.swift。fixture 不打外網。
- [ ] installer tests 更新 URL／archive 契約，增加 archive 缺檔、下載失敗、編譯失敗、既有 binary 不被破壞、含空白安裝位置、暫存清理。
- [ ] Mac 跑 `make clean && make test`；編輯一個新 Swift 檔後 `make -n build` 確認會重編。用新 installer 隔離目的地測 `--help/--version`。

**完成條件：** 截圖契約與 task1 保存的輸出一致；本地與 installer 使用完整同版本來源、相同 flags；沒有單檔安裝殘留。這個 milestone 應可獨立合併，但本計畫不自行合併／push。

## Task 3：先完成 CLI 與無副作用驗證

**新增／修改：** CLI/Options.swift、CommandParser.swift、Help.swift、Testing/TestCommand.swift、`tests/record-cli-tests.sh`、Makefile。

- [ ] 加入 B 節的 typed RecordingOptions、AudioMode、VideoCodec；舊 CLIOptions 改名 ScreenshotOptions 時只更新引用，保留既有序列化輸出。
- [ ] 將原解析器保留為 `parseScreenshotArguments`，最外層只依第一 token dispatch；新增 `capture` alias；新增獨立 `parseRecordingArguments`。
- [ ] 照規格表逐項實作所有合法值、預設、duplicate alias、range、跨模式錯誤與 help 優先順序。先不查真實 path 存不存在。
- [ ] record第一版必填window，解析結束缺少即exit2；先處理help提前返回，因此`record --help`不要求window。沒有TTY／非TTY差異或新的readLine互動；截圖原互動不變。
- [ ] 增加 `--test record-arguments` 固定字串；原 `--test arguments`、舊 helper 的輸入／輸出不變。
- [ ] 新增中英 record help，清楚寫 audio scope、macOS15、MP4 file 路徑、both 收尾需額外時間與空間。
- [ ] AppRunner 在 record action 尚未接 engine 前可明確回報「尚未實作」，不能 return0 假成功；root help/version 路徑不觸發權限。
- [ ] 執行既有 CLI suite + 新 parser suite。新增至少：4 audio modes、2 codecs、fps 1/60 與 0/61/非整數、duration .5/3600/86400 與負數/NaN/Inf/超界、window 溢位、空 output、jpeg/HEIC 當 codec 錯誤、跨模式選項、short/long 重複。
- [ ] 加「未觸發副作用」測試：parser 純函式只回 action；help 執行前後暫存目錄不變，不呼叫 fake permission／window provider。

**完成條件：** 所有 CLI 規格可不授權、不開視窗而測試；既有 53 項 CLI 測試沒有因重構被刪掉。

## Task 4：建立可測試的錄影邊界與 async 入口

**新增：** Recording/RecordingTypes.swift、tests/RecordingTests/ 下的 runner/fakes；修改 AppRunner/main/Makefile。

- [ ] 建立 engine state、stop reason、result、stats 以及 clock/stream/writer/permission protocols。每個 fake 必須能設定失敗、事件順序與 callback late arrival。
- [ ] 建立測試 executable `.build/recording-tests`：編譯 production sources 但排除產品 main.swift，加入測試自己的唯一入口；不要把產品入口或第二個 @main 編進同一 executable。
- [ ] 測試 runner 逐 case 報結果，任一 failed exit1，零 case exit1；async case 不能用忽略 Task 結果的方式啟動。可以使用 XCTest 或簡單 throws runner，但需有 timeout 與明確 assertion 計數。
- [ ] 產品保留 `main.swift` 作唯一 top-level：用頂層 Task 呼叫 async AppRunner、完成後 exit(status)，主執行緒持續跑 dispatchMain；不使用主執行緒 semaphore 等待 async。若工具鏈需要另一種入口，整批替換而不是混用 @main 與 top-level。
- [ ] AppRunner 的 UI／permission 操作明確 main actor 隔離；writer/buffer 的序列 queue 在 adapter 裡處理，不把每個 buffer 改成新 Task。
- [ ] 加可證明的 stop reason severity 與狀態轉移單元測試；寫下 queue ownership 註解，所有跨 queue payload 都需有生命週期與容量界線。

**完成條件：** 沒有 ScreenCaptureKit 真實視窗也能 deterministic 跑測試；真實 SDK 類別用 availability 隔離，不是整個模組都提高 macOS 下限。

## Task 5：把權限、embedded metadata 與平台 gate 接好

**新增／修改：** Resources/Info.plist、Core/Permissions.swift、Makefile、AppRunner、installer tests。

- [ ] 定義穩定 CFBundleIdentifier／名稱／版本、NSMicrophoneUsageDescription；版本只有一個可維護來源，不能 help 和 plist 各自漂移。
- [ ] 以Info.plist的CFBundleShortVersionString為版本原值。Makefile讀值並驗證為預期版本格式，產生`.build/Generated/BuildMetadata.swift`中原版本常數；刪去原手寫常數，product與test編譯都顯式加入generated file（production find不會找到.build）。首次仍1.1.0；metadata改變觸發重建，未改內容不反覆改mtime。乾淨安裝不依賴已產生的檔案。
- [ ] Makefile 用 linker `-sectcreate __TEXT __info_plist`（透過正確 `-Xlinker` 參數傳遞）嵌入 plist，再以明確 stable identifier 做 ad-hoc codesign；本地與 installer 使用同一規則。flags／metadata 變更要重編。
- [ ] 以 `plutil -lint` 驗證 plist；用 `codesign -d`／Mach-O section 檢查確認 installed binary 真的含 metadata。不要只檢查原 plist 存在。
- [ ] parse 完後做 runtime macOS15 gate、無副作用 output preflight（Task6），再做 screen permission，僅 mic/both 做 `.audio` permission；fake 測試每一模式的呼叫次數與拒絕行為。
- [ ] mic/both 在開始時取預設 AVCaptureDevice uniqueID，設定 SCK microphoneCaptureDeviceID；保持該裝置，不在錄影途中隨 OS 預設切換。none/system 不列舉麥克風。確切 signature 由 Task0 查證。
- [ ] 前置失敗不建立錄影檔；permission callback 持續讓主 run loop 工作，不 blocking wait。stream 啟動的權限錯誤仍須處理，不能因 preflight 曾成功就視為不會被撤銷。
- [ ] 在乾淨 TCC 情境測新安裝、拒絕、授權、重跑與更新；更新後重新授權需求寫文件，禁止擅自清空全機 TCC 資料庫。

**完成條件：** task0 mic probe 可換用正式 installed binary，none/system 不請求 microphone；舊 root help/version 與截圖仍能啟動。

## Task 6：實作錄影檔案 session 與不可覆蓋提交

**新增／修改：** Core/SessionManager.swift、RecordingTypes、filesystem tests。

- [ ] 保留 screenshot directory API 原樣，另加 `RecordingSession`：finalURL、private stageDirectory、captureURL、mixedURL、cleanup policy。
- [ ] 路徑解析與檔案系統檢查分開：空值／副檔名是 usage error；實際存在目錄、已存在檔案／symlink、不可寫、建立親目錄失敗是 runtime error。
- [ ] 分成 `preflightOutput`（不建立任何項目，權限請求前執行）與 `createSession`（授權選窗後執行並重查路徑），避免檔案錯誤先跳出不必要的麥克風提示；後續race仍按錯誤規則處理。
- [ ] staging 放 final 同 filesystem，0700 目錄、限制檔案權限；使用隨機識別避免同 timestamp/PID 碰撞。只處理自己建立的項目。
- [ ] 加 available capacity 預檢與定期檢查 hook；兩階段預算依規格。不確定時警告，不捏造剩餘容量。
- [ ] 最後 commit 使用 macOS exclusive rename；單元測試在預檢後、commit 前建立同名 final，確認外部檔案內容完整且 commit 失敗。
- [ ] 成功移除 stage；沒有有效媒體時清空；writer/mix failure 有有效 stage 時保留並回傳 recoverableURL。不要 `defer remove stage` 無條件刪掉救援檔。
- [ ] 測正常路徑、空白中文、~、相對路徑、親目錄缺少、directory named x.mp4、symlink、existing file、磁碟不足、cleanup 與 failure preservation。

**完成條件：** 不需錄影即可證明不覆寫與不同失敗 cleanup；舊 captures 路徑測試維持通過。

## Task 7：實作共用時間軸與有界 buffer 政策

**新增：** RecordingTimeline.swift、timeline tests。

- [ ] 定義 `t0`、source→session CMTime 轉換、source kind、每來源 last accepted timestamp/sample cursor、stop endpoint；時間用 CMTime，不能串接 Double 累加影片時間。
- [ ] t0 由第一張完整畫面設定一次；video/audio/mic 同減 t0。先到 audio 最多暫存250ms，跨界 PCM 按 frame range 裁切。負時間不能原樣送 writer。
- [ ] 幀槽根據單調 clock 決定 `n/fps`；fake clock 可推進 0、1/30、5 秒等時點。落後時跳到正確槽，記 dropped slot，不反覆補100幀造成 backlog。
- [ ] audio 維持48k sample cursor；裁掉 overlap，對已過 reorder watermark 的缺口補零。watermark以共同媒體時間的hostNow減250ms前進，不等第一個audio sample；另建獨立48k stereo PCM silence generator，即使零callbacks也能建立音軌。停止且來源封閉後flush到endpoint。
- [ ] raw audio先在有界reorder queue按PTS排序，取到watermark後才交converter，接著對齊／補零／寫入。raw與normalized pending合計受同一容量上限，不能轉換後再排序來掩蓋不連續輸入。
- [ ] 固定 pending 容量：video 最新2 frames；audio 每來源最多1秒（含最多250ms reorder）。audio到硬容量即失敗收尾，不能丟棄後繼續成功；writer連續不ready超1秒也失敗。超載計時用單調host clock。
- [ ] duration／stop 同一個 endpoint；尾端 frame／audio 都不能寫過界。AAC encoding padding 的容許誤差在驗證 helper 統一定義。
- [ ] 測 sourcePTS 非零、audio 比video早、mic晚500ms、44.1→48k cursor、同timestamp／逆序、time discontinuity、timer錯過槽、duration恰好邊界、wall clock跳動不影響結果。

**完成條件：** 所有測試用 fake clock，沒有真實 sleep；單獨把 mic 歸零的錯誤實作必定被測試抓到。

## Task 8：先以合成媒體實作 AVAssetWriter

**新增：** VideoWriter.swift、writer synthetic tests、asset inspection helper。

- [ ] writer init 接收 session、固定尺寸/fps/codec、audio mode；none/system/mic→MP4，both→MOV。確認容器、video settings、audio settings 支援後才 startWriting。
- [ ] video 輸入 H.264/HEVC、SDR、規格 target bitrate；audio 0/1/2 個 AAC input。不能為未啟用來源建立多餘 tracks。
- [ ] first frame 決定 t0 後 writer `startSession(atSourceTime: .zero)`；所有 append 只在 media queue，嚴格處理 status/Bool，real-time inputs=true。
- [ ] 使用 pixel buffer adaptor 接收固定尺寸 buffer（SCK 畫面或黑畫面）；append method 區分 backpressure 與 failed，不把 !ready 當 writer永久壞掉，也不無限等待。
- [ ] `finish(at:)` 一次性：拒新工作、尾端完成、endSession、mark inputs finished、await finishWriting、確認 .completed；cancel 不能回報正常 URL。
- [ ] 合成3秒彩色幀＋帶時間定位的tone，分別建立none/system/mic/both stage，使用 AVAssetReader 檢查 tracks、codec、尺寸、timestamps、可解碼內容，而不只看 file size。
- [ ] 共用檢查邏輯放 `tests/RecordingSupport/AssetInspector.swift`，另以 `tests/RecordingInspect/main.swift` 建置 `.build/recording-inspect` 命令；產品與unit test入口都不包含它。輸出完整媒體檢查JSON，實作驗證手冊要求的欄位與非零錯誤碼。
- [ ] 注入 append/start/finish 失敗與 input not ready，確認 error 傳遞與 pending 容量，檔案符合 Task6 保留規則。

**完成條件：** 無 ScreenCaptureKit／TCC 也能得到可讀媒體；duration 收尾、codec不支援、write failure 都有測試。

## Task 9：畫布、Retina 與持續幀排程

**新增：** FrameComposer.swift，尺寸／pixel tests。

- [ ] 依 task0 證明的方法取得 backing pixels，計算不放大且偶數對齊的初始尺寸；驗證2px、odd dimensions、Retina、maxDimension與unsupported-size錯誤。
- [ ] 預先建立一個固定 W×H 的黑畫面 buffer；SCK 畫面直接 append，不建立 CIContext 或額外 pool。
- [ ] 不做縮放或置中：SCK 已等比例縮入固定畫布、貼齊左上角、不放大（Task 0 實測，使用者決定接受左上角）。驗證 resize 後 track 尺寸不變、畫面未拉伸。
- [ ] 錄影中不更新 SCStreamConfiguration 的尺寸。
- [ ] 接 Timeline 的 ticker，沒有新畫面時重複最新畫面；收到`suspended`超過1秒改黑畫面，收到`complete`恢復；未知狀態不能把其他視窗當備援。
- [ ] 測連續drop不會讓時間軸加速；source frame callback不等於輸出fps，兩者分開計數。

**完成條件：** 不必依靠肉眼即可由pixel assertions驗證aspect ratio、black、fixed size；實機Retina仍留到Task16。

## Task 10：連接 ScreenCaptureKit adapter

**新增：** ScreenStream.swift；修改 WindowDiscovery.swift 增加錄影所需查詢，保留截圖查詢契約。

- [ ] 用共用選窗結果的 ID + PID 重新對照 SCShareableContent，找不到或owner改變即失敗；不可只按App名稱找到第一個window。
- [ ] 建立單窗 content filter、SDR/BGRA/fps/cursor/queueDepth config；audio flags只依RecordingOptions，不啟動第二個display stream。
- [ ] 以正確output types加入screen、system audio、mic，明確持有delegate/output物件，避免start後被釋放。
- [ ] callback先檢查sample valid、screen frame status，再經有界adapter傳遞；保留buffer直到消費完，不能存不安全的borrowed指標。
- [ ] delegate fatal event轉成一次engine failure；start部分成功後失敗也要解除已加output／stop資源。
- [ ] 最小化以frame status `suspended`判斷，切換Space不需處理（Task 0實測）；close以SCK `didStopWithError` -3815判斷（Task 0實測），不以沒有callback判斷關閉，不需輪詢視窗清單。
- [ ] stop與callbacks barrier按Task0結果實作，測試fake late callbacks；不能將stop函式返回視為所有自己排出的queue work也完成。

**完成條件：** Mac probe改用正式adapter可以取得正確三種source；沒有main queue blocking、無界Tasks或跨queue state競爭。

## Task 11：完成無聲錄影的最小閉環

**新增／修改：** RecordingEngine.swift、AppRunner，連接Task5–10。

- [ ] engine準備順序：parse（含必填window檢查）→OS→無副作用output preflight→permission→以ID解析及重查目標視窗→重查並建立session→stream/writer→等待首完整frame→recording。record不新增互動選窗，先以既有`--list`取得ID。
- [ ] `.none`只接畫面與Ticker；first video後開始duration計時，未有首frame的啟動timeout5秒。
- [ ] 在engine進preparing前安裝SIGINT/SIGTERM DispatchSources；handler送requestStop，不印完成、不exit。權限async回覆若在取消後才到須忽略、不再start stream；source物件持有到引擎結束，清理後恢復signal設定。
- [ ] requestStop在preparing/starting/recording/finalizing各狀態都有已定義行為；完成後只回傳一個Result及exitCode。
- [ ] 跑真實 `record -w ID --audio none --duration 3 -o TEMP/out.mp4`，驗證畫面真的是指定window、0audio、固定尺寸、duration與可播放。
- [ ] 先測CtrlC可播放，再開發音訊；無聲錄影還不可靠時不要同時debug三個來源。

**完成條件：** 無聲閉環能成功、取消、失敗；權限拒絕／無視窗／零frame時不產生正常成品檔。

## Task 12：系統音訊與麥克風各自單獨完成

**新增／修改：** AudioCapture.swift、engine、audio tests。

- [ ] 每source解析實際ASBD建立converter，輸出48k stereo PCM；明確處理interleaved/non-interleaved、mono channel mapping與CMSampleBuffer生命週期。
- [ ] converter跨buffer保留狀態及小數sample cursor；converter input block不重複餵同一input，正確回報noData/endOfStream；停止時drain且裁到endpoint。
- [ ] 轉換前按sourcePTS偵測gap/overlap；overlap先裁input，gap採「drain有效尾端→reset→以新sourcePTS重新定位」，缺口交Timeline補零。不要讓AVAudioConverter將不連續資料當連續來源，測試必須實際經過converter。
- [ ] 先測system only，再mic only；writer只建一audio input，gain1.0。不可用兩來源混在同一input的交錯append代替混音。
- [ ] 將真實PCM時間交給Task7，對缺口補零但不隱藏permission／device錯誤。零RMS有效buffer要寫入；有聲驗收需實際播放／能量或頻譜證據。
- [ ] mic/both在既有有限頻率監控中檢查固定uniqueID裝置仍存在（或使用已驗證的裝置移除通知）；消失送fatal error，僅OS預設改成另一裝置時不中斷也不跟隨。none/system不安裝這個mic監控。
- [ ] 測44.1k mono、48k stereo、小buffer長時間累積、audio早於video、格式改變、no buffer靜音與append overrun；高負載時memory仍有界。
- [ ] 在正式 installed binary測targetApp audio排除非目標App、mic首次授權。若filter不符合範圍，停在這一步修設計。

**完成條件：** system/mic兩模式的最終MP4各只有一條AAC，音源正確且時間軸對齊，none不因新增mic程式而觸發麥克風提示。

## Task 13：both 的離線混音與壓縮影片轉封裝

**新增：** AudioMixer.swift、mix synthetic tests；修改engine finalizing。

- [ ] both第一階段寫MOV + video/sysAAC/micAAC，Task12的兩個source明確送到不同inputs。Stage成功前不開始mix。
- [ ] 用async asset.load讀stage tracks/formatDescriptions/preferredTransform；驗證1video與2audio契約。
- [ ] reader video outputSettings=nil；final writer video input outputSettings=nil＋sourceFormatHint；直接保留壓縮samples與DTS/PTS順序，不經pixel buffer重新encode。
- [ ] reader audioMixOutput同時讀兩audio tracks，explicit48k stereo PCM settings；AVMutableAudioMix每條gain0.5。不要建立把兩tracks都從0插入的composition。
- [ ] 最終MP4只建立一個AAC audio input；video/audio兩個readiness pumps各自有EOF flag，只有兩者完成且reader.completed才finish。offline expectsMediaDataInRealTime=false。
- [ ] pump在input不ready時返回，等下一次readiness通知；不得同步while忙等，也不能一次讀完整asset。取消會停reader/writer並保留stage。
- [ ] 用task0 fixtures測H264和HEVC、mic延500ms、零能量、不同時長、尾端音訊、錯誤sourceFormatHint、reader/append/finish失敗。比對壓縮video payload或可信等價fingerprint，證明不是重編碼。
- [ ] final asset檢查through同一helper後exclusive commit；成功清stage；mix失敗保留MOV，stderr明說兩條音軌未混成最終檔。

**完成條件：** 播放器只有一條audio track就能同時聽到兩來源，tone測試證明增益與offset；沒有「看似成功但只播system」的多音軌捷徑。

## Task 14：系統性完成停止、錯誤與資源釋放

**目的：** 將功能正常路徑擴展為可長時間使用的CLI；不是最後包一個catch就算完成。

- [ ] 逐項覆蓋：兩signal同時／重複、duration與error同時、start部分成功、晚到callback、disk full、writer不ready、source失效、close、minimize、device消失、mix取消、final path race。
- [ ] stop只跑一次，任何真實failure的exit1不能被較早的正常停止原因蓋掉；首次SIGTERM正常finish可exit0，未完成mix的第二次SIGINT取消exit1。
- [ ] 停止先固定endpoint並停ticker，在stopCapture與callback barrier完成前仍有界接收endpoint以前的在途samples；來源封閉後才拒callback，接著drain/補尾/finish。測最後250ms的tone不被誤補為靜音。
- [ ] 驗證每一state的資源釋放：stream delegate/outputs、ticker、visibility/disk timer、buffers、converter、reader/writer、signal sources與stage directory。
- [ ] mediaQueue不能等待自身callback；actor/queue相互等待需畫出呼叫方向。加timeout tests檢查deadlock，但不能以固定timeout直接宣稱MP4完成。
- [ ] 統計startup/recording/finalizing分開，frame drops與audio補零可觀察；錯誤時列明可恢復stage而非「安裝完成／錄製成功」。
- [ ] 測output file變成read-only／parent消失等commit失敗，保留已完成candidate，不刪使用者檔案。

**完成條件：** fake lifecycle fault matrix與實機interrupt cases通過；所有失敗路徑有exit code／檔案保留行為證據。

## Task 15：整合 CI、安裝回歸與使用文件

**修改：** Makefile、.github/workflows/ci.yml、README、Help、installer suites；新增tests scripts／helpers。

- [ ] 新增`make test-unit`（狀態／時間／fakes）、`make test-media`（合成AVFoundation媒體）、`make test-recording`（record parser + unit + media），這些是此task要實作的targets，不是目前已存在命令。
- [ ] 新增`make recording-inspect`建置獨立helper；一般測試可直接使用共用AssetInspector。產品runtime只需metadata及首／尾sample檢查，完整解碼保留給測試helper，不能讓每次一小時錄影在返回前又重播一小時。
- [ ] `make test`仍是標準入口：舊CLI+installer與全部不需要TCC的新tests。GUI smoke不塞進一般CI。執行任一suite要保留底層exit status，0tests不可通過。
- [ ] 固定／檢查CI的macOS與Xcode16+，輸出實際SDK版本；不靠`macos-latest`名稱推測SDK。舊baseline機器如可用，另驗證screenshot啟動／OS gate。
- [ ] 更新installer測試：archive取同ref、nested sources/Info.plist有編入、installed `record --help`可用、簽章／usage description存在、失敗保留舊binary與cleanup；不在headless安裝測試要求實際mic prompt。
- [ ] README增加截圖/record兩種output語意、四audio模式、App範圍、系統與權限需求、both兩階段成本／雙AAC品質取捨、headphones、1小時容量預算、CtrlC收尾與失敗stage恢復。
- [ ] 根help保留原中英內容並導向record help；不要無意改掉舊help assertions需要的文字。
- [ ] `make clean && make test`驗證乾淨完整來源，shell syntax checks驗證所有新增script；檢查git diff沒有probe media、憑證或不必要產出。

**完成條件：** 新使用者照README與原一行installer能建立含record的binary；CI能提供不依賴TCC的真實媒體證據。

## Task 16：按驗證手冊完成真實 Mac 驗收

- [ ] 完整執行[驗證手冊](2026-10-30-recording-validation.md)中四audio模式、兩codec、TCC、App A/B範圍、minimize/Space/close、Retina/resize、signals與recoverable stage案例。
- [ ] 執行both一小時：記錄CPU/RSS、stage+final最大空間、audio/video offset開始與結尾、finalization耗時、frame drops與補零比例。RSS需進入穩定區間，不能隨總時長線性增長。
- [ ] 合成媒體對齊誤差≤一video frame或一AAC frame的較大者；實機嘴形／click/flash相對誤差起始與結尾目標≤100ms，超過需診斷並記錄不可交付的原因，而不是修測試門檻。
- [ ] 驗證產出只有指定window畫面、一條混音audio、正codec/尺寸、檔案可播放；受保護內容限制如實列出。
- [ ] 記錄測試Mac/OS/SDK/硬體、命令、assertion數、pass/fail/skip與artifact摘要。私密錄影檔不提交repo，合成fixtures才可保留。
- [ ] 如果只有Linux與CI，完成可做項並明列實機項未驗證；不把「計畫存在」或「單元測試過」當整個功能已可用。

**完成條件：** 規格所有必需項有證據，或逐項列出確定外部阻擋；功能完成仍不自動push、tag或release。

## C. 建議交給下一個模型的工作指令

```text
請只執行 docs/superpowers/plans/2026-10-30-recording-implementation.md 的 Task N。
先讀該計畫、錄影規格及驗證手冊，確認前置 tasks 的證據，讀取 repo 當前狀態。
維持既有截圖 CLI 相容性，不擴大錄音範圍、不偷偷降級音訊、不更改其他task的契約。
實作 task 指定修改與測試；需要 Mac 但手邊只有 Linux 時，清楚回報未執行的檢查。
不要標記未驗證的 gate 已完成。不要 push/tag/release。
最後回報：修改檔、測試命令/exit code/案例數、剩餘失敗、下一步。
```

每個task的交接紀錄建議放PR描述或工作回報，不要把暫時進度散落到產品README。若API probe迫使設計變更，先同步更新規格、計畫與驗證手冊，再繼續後續task。
