# 錄影開發交接

## 工作位置與範圍

- 使用者明確要求建立新分支與worktree；本次在 `feat/recording`、`/workspace/worktrees/snapparazzi-recording` 工作。
- 起點：`6cb3de2a404730af77d794d8960b83a4d5ded1f3`。
- 三份規劃文件從原工作目錄複製進本worktree，原檔保留。
- 正式 `Sources/`、Makefile、installer、既有tests皆未修改。本次使用者已授權將規劃與Task0初版提交、push到`feat/recording`；未合併主幹或建立release，提交與遠端狀態以Git紀錄為準。

## Task 0：已開始，尚未完成

已準備 `tools/recording-probe/`：獨立build.sh、embedded microphone用途描述、list/capture/inspect入口、SCK三來源callback與格式／PTS診斷、短片MOV writer、完整解碼檢查器。操作見[probe README](../../../tools/recording-probe/README.md)。

`both`目前只產出兩條分離音軌的diagnostic MOV，還不是規格要求的混音MP4；不標記混音、scope或sync gate通過。

初版在雲端Linux撰寫，當時沒有swiftc/macOS SDK，未編譯Swift、未執行Apple APIs。以下為之後在Mac上的實測。

### 2026-10-30 Mac 實測

環境：macOS 26.5.2（25F84）、SDK 26.5、Apple Swift 6.3.3、Command Line Tools、arm64。probe以原flags（`-O -whole-module-optimization -warnings-as-errors`、Swift 5 mode、target macOS 15）建置。測試視窗皆位於一台scale 1.0的外接螢幕，**Retina尚未測**。

建置／執行修正（commit `9aeb31f`）：

- `finish()`以`queue.async`捕捉非Sendable的probe／`AVAssetWriter`，Swift 6.3.3報錯；改為`queue.sync`進media queue呼叫`finishWriting`，未加`@unchecked Sendable`。
- **純CLI必須先初始化CoreGraphics連線**：未初始化時`SCContentFilter(desktopIndependentWindow:)`在`SLSGetDisplaysWithRect`觸發`CGS_REQUIRE_INIT` assertion（exit 134）。`list`不建filter故正常。先呼叫一次`CGMainDisplayID()`即解決（已用最小程式對照驗證）。正式`record`使用SCK前也必須做同樣初始化。

實測結果（10秒短片，h264；錄影檔不入repo）：

| 項目 | 結果 |
|---|---|
| 權限 | `list`觸發螢幕錄製授權後可列視窗；LINE等App有多個無標題輔助程序視窗，各自PID |
| 畫面時鐘 | screen PTS與`CMClockGetHostTimeClock`同域，PTS比callback抵達早約0.5～6ms |
| App音訊時鐘 | 48kHz、2ch、每buffer 960 samples（20ms）；PTS同host clock域，抵達延遲約60～113ms且常成批到達，在250ms reorder window內 |
| 起點 | 首個audio PTS比首個完整畫面晚約107.5ms；writer保留此offset，未移到0 |
| **讀回時的offset** | `AVAssetReaderTrackOutput`解碼該音軌時**從0開始並自動補靜音**（寫入474240 samples、讀出479402，差≈107.5ms）。檢查延遲音軌不能用解碼後first PTS，須看track timeRange／edit list或前段靜音 |
| 非目標App排除 | 錄Chrome視窗、同時以`say`（另一process）播放：與`say`參考音的正規化互相關峰值0.064，等同無`say`的基準0.073；人工混入`say`在0／−6／−12／−20dB時分別為0.733／0.475／0.262／0.109。→ 比目標音量低20dB以內的非目標App漏音皆可偵測，實測無漏音 |
| 同App其他視窗 | 錄無聲的Chrome視窗A、另一Chrome視窗B播YouTube：RMS 0.033；暫停B後RMS 0（peak 0）。→ **同App其他視窗聲音會被錄入**，與規格3.3的預告一致 |
| 安靜時的音訊 | 目標App完全無聲時仍持續收到buffer（10秒492個），內容為0；靜音不等於資料缺口 |
| 畫面縮放 | `config.width/height`與視窗比例不同時，SCK等比例縮入畫布並以`contentRect`／`contentScale`回報實際內容（例：1440×843→畫布1280×748，內容約1277.7×748，scale≈0.887） |
| 靜止畫面 | 行事曆完全不動仍收到約28fps的`complete`畫面；解碼後1秒後的247張中僅18張差值>20（多為編碼雜訊），YouTube播放中則263／264。→ macOS 26.5上靜止內容仍按設定頻率送`complete`畫面 |
| dirtyRects | 同一靜止視窗：首張為`0,0 0x0`，其後每張皆為一個`0,0 1279x962`（＝contentRect，單位為輸出畫布像素）；面積比例mean 0.996／max 0.999。→ **單窗模式下SCK每張都把整個內容標為dirty，不做變動偵測**；dirtyRects不能用來判斷靜止或省略編碼。probe的`screen_dirty`只看陣列是否為空，零面積首張被計為changed |
| 媒體檢查 | 所有短片exit 0、writer completed、完整解碼；none為1 video、system為1 video＋1 AAC |

對規格／計畫的影響：

- Task 5／10：SCK使用前必須初始化CoreGraphics（見上）。
- Task 7／8／13與驗證手冊：延遲音軌的檢查依「讀回時的offset」一列，不能以解碼first PTS判斷。
- Task 9：ticker仍需要（規格不依賴callback），但實務上很少需重複畫面；靜止畫面也持續耗用編碼資源，L4效能需計入。不得依dirtyRects跳過編碼或判斷視窗可見性。
- help／README：明寫同App其他視窗聲音會錄入。

接續工作：

1. mic授權（首次／拒絕／重新允許）、`mic`與`both`、HEVC、Ctrl-C收尾。
2. Retina（內建螢幕）、resize、最小化／Space／關閉的可觀測差異。
3. 合成fixture、雙AAC混音與壓縮video passthrough；驗證H264/HEVC及延遲音軌。
4. 閃光＋click素材的實際音畫同步；舊系統weak linking。Task0未全部完成前不標為完成。

## Task 1：使用者已回報的本地基準

使用者的Mac為macOS26.5.2、SDK26.5、Swift6.3.3、arm64、Command Line Tools；`make test`原生release build成功，CLI 53／53、installer 7／7通過。這是使用者貼出的結果，不是雲端執行結果；該次Mac HEAD尚未提供，仍需補記。

## 其他 Tasks

Task2～16尚未開始。不要在沒有Mac技術gate的情況下把prototype搬入production或宣稱錄影功能可用。
