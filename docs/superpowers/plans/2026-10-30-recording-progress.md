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
| **讀回時的offset** | `AVAssetReaderTrackOutput`解碼該音軌時**從0開始並自動補靜音**（寫入474240 samples、讀出479402，差≈107.5ms）。檢查延遲音軌不能用解碼後first PTS，須看edit list（`segments`的leading empty edit）或前段靜音 |
| 非目標App排除 | 錄Chrome視窗、同時以`say`（另一process）播放：與`say`參考音的正規化互相關峰值0.064，等同無`say`的基準0.073；人工混入`say`在0／−6／−12／−20dB時分別為0.733／0.475／0.262／0.109。→ 比目標音量低20dB以內的非目標App漏音皆可偵測，實測無漏音 |
| 同App其他視窗 | 錄無聲的Chrome視窗A、另一Chrome視窗B播YouTube：RMS 0.033；暫停B後RMS 0（peak 0）。→ **同App其他視窗聲音會被錄入**，與規格3.3的預告一致 |
| 安靜時的音訊 | 目標App完全無聲時仍持續收到buffer（10秒492個），內容為0；靜音不等於資料缺口 |
| 畫面縮放 | `config.width/height`與視窗比例不同時，SCK等比例縮入畫布並以`contentRect`／`contentScale`回報實際內容（例：1440×843→畫布1280×748，內容約1277.7×748，scale≈0.887） |
| 靜止畫面 | 行事曆完全不動仍收到約28fps的`complete`畫面；解碼後1秒後的247張中僅18張差值>20（多為編碼雜訊），YouTube播放中則263／264。→ macOS 26.5上靜止內容仍按設定頻率送`complete`畫面 |
| dirtyRects | 同一靜止視窗：首張為`0,0 0x0`，其後每張皆為一個`0,0 1279x962`（＝contentRect，單位為輸出畫布像素）；面積比例mean 0.996／max 0.999。→ **單窗模式下SCK每張都把整個內容標為dirty，不做變動偵測**；dirtyRects不能用來判斷靜止或省略編碼。probe的`screen_dirty`只看陣列是否為空，零面積首張被計為changed |
| mic授權歸屬 | 首次`--audio mic`彈出授權並允許後，使用者TCC.db新增的是`com.googlecode.iterm2`（啟動此工作階段的終端機），**不是**probe binary（即使已嵌入Info.plist與穩定identifier）。→ 授權歸「負責的App」；換終端機或由其他App啟動需重新授權。拒絕／重新允許尚未測 |
| mic（內建麥克風） | **48kHz、mono**、每buffer 512 samples（約10.7ms）；PTS同host clock域，抵達延遲約13～23ms；**首個mic PTS比首張畫面晚704ms**；尾端buffer越過終點約6ms（probe未做sample級裁切）。音量包絡顯示說話段−29～−35dB、底噪約−55dB |
| both（換成藍牙耳機） | 1 video＋2 AAC（track2 system、track3 mic），無backpressure或掉資料。**mic變成24kHz、mono、每buffer 480 samples**（使用者此時改用藍牙耳機，推測為耳機通話模式）；mic晚238ms、system晚120ms開始。system peak 0.88，接近滿刻度 |
| 停止（SIGINT） | `both`、`--duration 60`、5秒後`kill -INT`：exit 0、success、檔長4.508秒（啟動約0.5秒後才有首張畫面）；system seen＝written 219，音軌止於4.5067秒（距終點1.7ms），stopCapture期間仍收進終點前的在途音訊；screen／mic各1個越過終點被丟棄並計數 |
| 停止（SIGTERM）＋HEVC | 同上改`kill -TERM`、`--codec hevc`：exit 0、video `hvc1`、1 video＋2 AAC、檔長4.530秒。mic止於終點，**system止於4.511秒，比終點少約20ms（一個buffer）**：停止時正在錄的那個system buffer不會送出。→ stopCapture返回不保證終點前音訊全部送達，規格5.3第8條的尾端補靜音是必要的 |
| 媒體檢查 | 所有短片exit 0、writer completed、完整解碼；none為1 video、system／mic為1 video＋1 AAC、both為1 video＋2 AAC |
| 混音（合成） | `mix-test` h264／hevc皆通過：1 video＋1 AAC 48k stereo；壓縮影片bytes hash相同、播放時間戳差0；440Hz前後段皆0.250（＝0.5×0.5）；880Hz在0.5秒前≈0、之後0.250，起點量得0.500秒；44.1k mono被均等放到左右聲道。→ 規格第6節的reader audioMix＋video passthrough方案可行 |
| 混音（實錄） | `both.mov`（h264）與`sigterm-hevc.mov`混成單音軌MP4，影片完全相同；音軌偏移保留（0.12／0.24秒）；system peak 0.88→混後0.44。10秒片混音約0.2秒 |
| H.264 B-frame與MP4 | 實錄與fixture的H.264都有frame reordering。MP4不允許負的composition offset，passthrough後**整條video media time往後移2幀，再以edit list對回0**；HEVC無此現象。比對passthrough須用套用edit後的播放時間，不能直接比原始PTS |
| 延遲音軌的offset | **在leading empty edit，不在`timeRange.start`**（延遲0.5秒的音軌timeRange.start仍是0），用`track.load(.segments)`讀 |
| 最小化 | 按⌘M時收到1張`suspended`，之後**完全沒有screen callback**（6.6秒、9.9秒兩次皆同），無錯誤、stream持續；還原後自動恢復`complete`，尺寸不變 |
| 切換桌面 | 切換瞬間1張`idle`，之後**持續送`complete`畫面**，抽格確認是視窗真實內容而非黑畫面（靜止視窗，無法分辨是否即時更新） |
| 調整大小 | 畫布固定（config未更新）時，SCK自動等比例縮入畫布：窄高→597×962、寬矮→1280×402；視窗小於畫布時contentScale＝1.0，**不放大、不拉伸**；全程`complete`無中斷。**內容貼齊左上角**，右／下補黑，不置中 |
| 工具陷阱 | `afconvert`轉出的WAV**忽略音軌前段的empty edit**（mic.mov轉出9.37秒，而非10秒），會把延遲音軌移到0；AVAssetReader則保留offset並補靜音。驗證工具只能用遵守edit list的AVFoundation |

對規格／計畫的影響：

- Task 5／10：SCK使用前必須初始化CoreGraphics（見上）。
- Task 7／8／13與驗證手冊：延遲音軌的檢查依「讀回時的offset」一列，不能以解碼first PTS判斷。
- Task 9：ticker仍需要（規格不依賴callback），但實務上很少需重複畫面；靜止畫面也持續耗用編碼資源，L4效能需計入。不得依dirtyRects跳過編碼或判斷視窗可見性。
- help／README：明寫同App其他視窗聲音會錄入。
- Task 5／README：mic（推測螢幕錄製也是）授權歸啟動終端機等負責App，不是CLI本身；文件要教使用者到對應App授權。
- Task 7／12：mic取樣率會隨裝置改變（48k→24k），起始延遲也不固定（0.24～0.7秒）。每來源獨立converter正規化為48k stereo、以實際PTS定位而非假設固定延遲，皆有實測依據。
- Task 13：system peak可接近滿刻度，both混音的0.5增益是必要的。
- Task 9：resize不需更新SCStreamConfiguration或自行縮放，SCK已等比例縮入固定畫布並以contentRect回報位置；規格要求「置中」，只需依contentRect平移（不必縮放），或改規格接受左上角對齊。
- Task 10：最小化以`suspended`狀態判斷（之後不再有callback，需由ticker補畫面）；切換桌面不是「不可見」，照常錄製。規格5.1「最小化／其他Space都改黑畫面」需修訂。

接續工作：

1. mic拒絕／重新允許；錄影中切換預設麥克風（應維持起始裝置）與拔除裝置；終端機前景Ctrl-C（已以`kill -INT/-TERM`驗證signal路徑）。
2. Retina（內建螢幕）、視窗關閉時的行為。
3. 閃光＋click素材的實際音畫同步；舊系統weak linking。Task0未全部完成前不標為完成。

## Task 1：使用者已回報的本地基準

使用者的Mac為macOS26.5.2、SDK26.5、Swift6.3.3、arm64、Command Line Tools；`make test`原生release build成功，CLI 53／53、installer 7／7通過。這是使用者貼出的結果，不是雲端執行結果；該次Mac HEAD尚未提供，仍需補記。

## 其他 Tasks

Task2～16尚未開始。不要在沒有Mac技術gate的情況下把prototype搬入production或宣稱錄影功能可用。
