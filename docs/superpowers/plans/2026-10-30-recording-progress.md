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
| Retina | 內建螢幕：`pointPixelScale`＝2，`filter.contentRect`×2＝3456×1482像素，計算正確。**`contentRect`單位是points**（畫布1278×548時回報639×274），需乘`scaleFactor`；`dirtyRects`則是像素 |
| 關閉視窗 | ⌘W後先1張`suspended`（同最小化），接著1張`stopped`（PTS無效），約0.12秒內`didStopWithError` **-3815**（`noCaptureSource`）。已寫入的5.4秒writer正常完成可播放。→ 關閉由SCK錯誤判斷，不需輪詢視窗清單；非`complete`畫面的PTS不可用於時間軸。App整個結束（⌘Q）未測 |
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
- Task 10：關閉以SCK錯誤-3815判斷（不需輪詢）；最小化以`suspended`狀態判斷（之後不再有callback，需由ticker補畫面）；切換桌面不是「不可見」，照常錄製。規格5.1「最小化／其他Space都改黑畫面」需修訂。

接續工作：

1. mic拒絕／重新允許；錄影中切換預設麥克風（應維持起始裝置）與拔除裝置；終端機前景Ctrl-C（已以`kill -INT/-TERM`驗證signal路徑）。
2. App整個結束（⌘Q）時的行為。
3. 閃光＋click素材的實際音畫同步；舊系統weak linking。Task0未全部完成前不標為完成。

## Task 1：既有行為基準（完成）

- HEAD `c8e9e14`，工作目錄乾淨；macOS 26.5.2、SDK 26.5、Swift 6.3.3、arm64、Command Line Tools。
- `make clean && make test` exit 0：CLI 53／53、installer 7／7。
- 以不需權限的42個案例（help／version／錯誤參數／`--test`各子命令）保存stdout、stderr與exit code作為重構前後比對基準。
- **部署下限**：Makefile未指定`-target`，binary `minos`＝編譯機系統（本機26.0）。一行安裝在使用者自己的Mac上編譯，實際下限永遠是使用者的系統，不存在「提高既有下限」的問題；要注意的是在macOS 15以前的系統或舊SDK上編譯時，`record`用到的SCK API必須以`#available`隔離，否則截圖功能也會無法編譯。

## Task 2：拆檔、建置與安裝（完成）

- `main.swift`依計畫表以行號機械式搬到`CLI/`、`Core/`、`Capture/`、`Testing/`與`AppRunner.swift`（腳本檢查原檔每行恰好搬一次）。跨檔宣告改internal，其餘維持private；唯一改名是`main()`→`appMain()`，`main.swift`只剩`exit(appMain())`。
- 拆檔後42個基準案例的輸出與exit code逐字相同；CLI 53／53通過；warnings-as-errors無警告。
- Makefile以`find`收集所有`.swift`（含子目錄、穩定排序）；另有`.build/build-inputs.txt`記錄編譯器、flags與檔案清單，只在內容改變時更新。實測：無變更不重編；修改、新增、刪除檔案及改flags都會重編。（GNU Make 3.81只比對到秒，同一秒內的連續操作可能漏判。）
- `install.sh`改下載`https://codeload.github.com/RayChang/snapparazzi/tar.gz/<ref>`（實測main、`feat/recording`、SHA皆200），ref限`[A-Za-z0-9._/-]`且拒絕`..`、開頭`-`／`/`；拒絕含絕對路徑或`..`的壓縮檔成員；解壓略過最上層資料夾，檢查Makefile與main.swift存在後以同一Makefile編譯。其餘行為不變。
- 安裝測試由7項擴充為25項：tag、含`/`的分支、含空白的安裝路徑、非法ref不呼叫curl、下載失敗／缺檔／編譯失敗皆保留舊binary、危險路徑、無暫存殘留。假curl改為回傳由工作目錄打包的壓縮檔。
- `make clean && make test` exit 0：CLI 53／53、installer 25／25。
- 補驗（push `3b1fe3f`後）：以新`install.sh`從GitHub實際安裝`feat/recording`到暫存目錄成功，安裝出的binary 42個基準案例逐字相同、`~/.zshrc`未改、無暫存殘留；GitHub Actions CI通過（53＋25）。需權限的路徑以拆檔前（`c8e9e14`）binary對照：`--list`輸出相同；`-w 35239 -i 1 -f png -m 640`截3.5秒後SIGINT，兩者皆exit 0、4張連號檔名、摘要相同、圖片皆640×401。

## Task 3：record CLI（完成，`2985378`）

- `record`獨立parser與RecordingOptions；`capture`為截圖別名；子命令只認第一個token。截圖模式行為不變，根help只多3行指向`record --help`（其餘42個基準案例輸出逐字相同）。
- `--test record-arguments`；`tests/record-cli-tests.sh` 109項（四種audio、兩codec、fps／duration／window／output／max-dimension邊界、重複與跨模式選項、help優先順序、help與參數錯誤不建立檔案）。

## Task 4–14：錄影實作（完成，`99373fa`、`4cefe23`、`e8ff9e8`）

依規格實作，架構有合併（見規格第4節）：`RecordingPipeline`（時間軸、幀槽、黑畫面、音訊對齊／補零／裁切）、`AudioNormalizer`、`StageWriter`、`AudioMixer`（移植Task 0 probe）、`RecordingSession`、`RecordingEngine`（SCK、signals、停止順序、驗證、提交）。

- Task 5：`Resources/Info.plist`嵌入`__TEXT,__info_plist`、ad-hoc簽章identifier `dev.snapparazzi.cli`；版本只寫在plist，Makefile驗證格式並產生`.build/Generated/BuildMetadata.swift`（內容不變不改寫）。installer要求plist；installer tests檢查嵌入的麥克風用途說明、identifier與`record --help`（30項）。
- 停止順序：endpoint →（tick停）→ `stopCapture`（期間仍收endpoint前在途樣本）→ queue barrier封閉來源 → pipeline補尾 → `finishWriting` → both混音 → 驗證（軌道數、codec、尺寸、長度、首尾可解碼）→ `renamex_np(RENAME_EXCL)`。失敗保留stage；混音時第二次SIGINT取消並保留雙音軌MOV。
- 合成測試（`make test-recording`，CI也跑）：9案例60項，以真AVFoundation寫檔／混音並解碼量測——both的offset（0.12／0.5秒）與0.5增益、44.1k mono→雙聲道、缺口補零、重複trim、t0前音訊裁切、最小化1秒後黑畫面、晚到tick跳槽不爆量、endpoint精確裁切、session不覆寫與權限0700、stop reason嚴重度。抓到3個bug：PCM複製前未設frameLength、浮點幀槽取整、endpoint後補零無窮迴圈。
- 實錄後修正：tick timer原本在`startCapture`返回後才啟動（開音訊約0.6秒，造成開頭跳槽）、duration那次tick先寫了落在終點的幀、輸出導向檔案時進度訊息被緩衝。

## Task 15：CI、文件（完成）

- `make test`＝build＋recording tests＋三組shell suites；CI另印toolchain版本並檢查所有新腳本語法。GitHub macOS runner上合成媒體測試（H.264／HEVC編碼）通過。
- README新增錄影章節（用法、App範圍與同App限制、both取捨與耳機、權限歸屬、視窗狀態、停止與失敗、macOS 15／SDK需求）與開發章節的opt-in測試說明。

## Task 16：實機驗收

`make recording-acceptance`（需權限與GUI）以獨立`.app`的fixture視窗（`tests/RecordingFixtureApp`：音調、每2秒白閃＋1 kHz嗶聲、排程最小化／改大小／結束）錄製並以`recording-inspect`檢查，71項全過（macOS 26.5.2、arm64）：

| 項目 | 結果 |
|---|---|
| none／system／mic／both × h264（none、both另測hevc），6秒 | 軌道數、codec、180幀、長度6.00秒、音軌48 kHz stereo AAC且涵蓋全長 |
| 音畫同步（白閃 vs 嗶聲） | system／both 各次10～35 ms，無漂移（遠低於100 ms） |
| App範圍 | fixture 440 Hz 錄到0.099；同時另一程序`afplay`的880 Hz為0.0000 |
| 最小化2→5秒 | 固定240幀；最小化期間亮度0（黑），前後為畫面 |
| 改大小兩次 | 180幀、尺寸不變、無錯誤 |
| macOS 全螢幕（第3秒進入、第9秒離開） | 同一視窗移到全螢幕 Space，持續錄到真實畫面（0黑畫面、約420幀）、全螢幕期間的同步標記仍<100 ms；內容等比例縮入原畫布 |
| App結束 | exit 1、「window closed」、保留可播放的約2秒檔 |
| SIGINT／SIGTERM | exit 0、檔長3–4秒 |
| both混音時第二次SIGINT | exit 1、不產生MP4、保留雙音軌MOV並說明 |
| 輸出已存在／未知視窗 | exit 1、既有檔不變、無stage殘留 |
| 磁碟空間（700 MB磁碟映像） | 未給`--duration`需1 GiB → exit 1且不建立任何檔案；30秒錄影中塞入200 MB讓可用量低於512 MiB → 約5秒內停止、保留已錄部分、exit 1 |

觀察：fixture若只呼叫`NSWindow.close()`，視窗在window server仍存在，SCK視為暫時不可見（黑畫面、繼續錄），不會報-3815；真正銷毀視窗（Task 0 Finder ⌘W）或App結束才停止。音高驗證：曾錄到404 Hz，經player-node對照證實是fixture的source node以44.1 kHz運作，錄影端音高正確。

一小時`both`長錄（`DURATION=3600 make recording-long-run`，1280×864 H.264 30 fps，fixture標記＋外接螢幕USB麥克風）：

| 項目 | 第一次（`9243867`） |
|---|---|
| 長度／幀數 | 3600.00 秒、107853幀（99.86%，147個時序跳槽、0個encoder忙碌） |
| 音畫同步（system軌標記） | 首尾1分鐘皆−3～+40 ms（幀量化），漂移0.3 ms |
| CPU／記憶體 | 平均17%；RSS 5分鐘53.5 MiB、結束52.3 MiB、最高63 MiB |
| 收尾／空間 | 收尾＋混音約24秒；成品123 MiB；stage＋成品峰值257 MiB |
| system軌 | 補零0.04秒、裁掉0 |
| **麥克風軌** | **補零784秒、裁掉784秒**——見下 |

**發現：麥克風時鐘漂移。** 外接螢幕USB麥克風的時間戳依取樣數遞增，實測比host clock慢約90 ppm（每2分鐘最小延遲增加約10 ms）。時間戳約45分鐘後落後超過250 ms watermark，之後每個buffer都晚於已補零的游標而被裁掉，約13分鐘麥克風聲音被換成靜音；同時麥克風與畫面的同步也逐漸偏移（一小時約0.3秒）。自動檢查沒抓到，因為同步標記在system軌。修正（`28e2fd3`）：每音軌以每2秒窗口的（送達時間−時間戳）最小值估計漂移，依「時間戳＋漂移」定位，並在誤差超過1 ms時插入（鄰點平均）或刪去單一取樣以跟上；合成測試以±1000 ppm裝置驗證20秒時真實時間標記誤差≤9 ms（未補償18 ms）。實機60秒量到+5.1 ms漂移、補償197個取樣、無丟資料。長錄腳本加上各音軌補零＜2秒、裁掉＜1秒的檢查。

**發現：可用空間判斷。** `volumeAvailableCapacityForImportantUsage`在磁碟映像（也可能在部分外接磁碟）回報0，導致所有錄影被拒；改取它與一般可用空間的較大值（`28e2fd3`）。

第二次一小時長錄（含漂移補償，`28e2fd3`），7項檢查全過：

| 項目 | 第二次 |
|---|---|
| 長度／幀數 | 3600.00 秒、107837幀（99.85%，163個時序跳槽、0個encoder忙碌） |
| 音畫同步（system軌標記） | 首尾1分鐘最大30 ms，首尾差−5.1 ms |
| CPU／記憶體 | 平均18%；RSS 5分鐘52.6 MiB、結束48.3 MiB、最高59 MiB |
| 收尾／空間 | 收尾＋混音約20秒；成品130 MiB；峰值255 MiB |
| system軌 | 補零0.04秒、裁掉0；漂移+0.1 ms |
| 麥克風軌 | 補零0.36秒（啟動）、裁掉0；量到漂移+335.3 ms，補償16046個取樣（334.3 ms） |

## 麥克風、權限與舊系統的補驗

- **麥克風軌音畫同步**（`make recording-microphone`）：fixture只把自己的輸出導到MacBook喇叭，暫時以MacBook麥克風為預設輸入，錄`--audio mic` 20秒：10個嗶聲全部配對，offset 23～67 ms（含喇叭輸出、空氣與麥克風延遲），<100 ms。外接螢幕麥克風聽不到同一喇叭（可能距離或降噪），故改用內建麥克風。
- **錄影中切換系統預設麥克風**（同上）：以包住內建麥克風的暫時 aggregate device 作為預設輸入開始錄`--audio mic`，第4秒把預設改成另一個輸入：錄影繼續、麥克風軌連續（728個buffer，只有啟動0.51秒補零）；第8秒刪除起始裝置後以「麥克風已移除」停止、exit 1——證明錄影綁定開始時的裝置，沒有跟隨新的預設（若跟隨會錄到20秒結束）。當時外接螢幕已拔除、只剩一支實體麥克風，所以以「刪除起始裝置是否停止」判斷綁定，而非比對兩支麥克風的聲音內容。
- **錄影中麥克風消失**（同上）：以CoreAudio建立包住目前預設輸入的公開aggregate device並設為預設輸入，錄`--audio mic`第4秒刪除：1秒內以「麥克風已移除」停止、exit 1、保留約4.3秒可播放的檔案；結束時刪除裝置並還原原本的預設輸入。
- **真實的麥克風權限拒絕**（2026-10-30 22:55，使用者在系統設定關閉 iTerm2 的麥克風；TCC `auth_value` 2→0）：`--audio mic`、`--audio both` 皆不再詢問、直接 exit 1 並說明如何開啟，輸出位置連父資料夾都沒有建立；同時 `--audio none` 與 `--audio system` 照常 exit 0 錄成（system 軌錄到 fixture 的 440 Hz）。測完由使用者重新開啟。
- **麥克風權限決策**：`ensureMicrophonePermission`與`RecordCommand`的權限檢查可注入；合成測試證明 denied／restricted 直接失敗且不跳詢問、notDetermined 只詢問一次並依結果、none／system 完全不詢問麥克風、mic／both 被拒時 exit 1 且輸出位置不產生任何檔案。
- **macOS 14 相容**：以`-target arm64-apple-macosx14.0`、warnings-as-errors 編譯成功（availability checker 確認所有 macOS 15 API 都在`#available`之後）；binary `minos 14.0`，ScreenCaptureKit 只以 12.3 即有的類別與 Objective-C selector 引用，比 14 新的 Swift 符號皆為 weak import，故可在 14 載入；此 build 在本機正常執行。

- **5秒內沒有完整畫面**（`make recording-acceptance` 8b）：ScreenCaptureKit 對靜止視窗也持續送畫面，沒有自然方式讓它不送，因此以測試用環境變數`SNAPPARAZZI_TEST_IGNORE_VIDEO=1`讓 record 丟棄所有畫面，其餘為正式流程：約5秒後以「No video frame within 5 seconds」exit 1，輸出與 stage 資料夾都不留下。
- 麥克風軌同步檢查在 MacBook 喇叭低於 20% 時會暫時把音量設為 30%，測完還原。外接螢幕拔除、喇叭為 6% 的狀態下重跑：10/10 嗶聲配對，offset 18～67 ms，喇叭還原為 0.0625（`make recording-microphone` 12項全過）。

- **macOS 14 實機**（CI `macos14` job，GitHub `macos-14` runner，未在使用者電腦安裝任何東西）：macOS 14.8.9、Xcode 16（SDK 15.2、Swift 6.0.3）以本機預設目標編譯（`minos 14.0`，即一行安裝在 macOS 14 會得到的 binary）；截圖 CLI 53項、record 參數 109項全過；`record` 實際執行 exit 1、顯示「record requires macOS 15 or later」、不產生檔案。此 job 首次執行抓到 Xcode 16 編譯器無法在合理時間內推斷`RecordingPipeline.nudge`中一行`map`的型別而整個建置失敗（Swift 6.3 可編），代表 macOS 14／Xcode 16 使用者的一行安裝會失敗；已改寫為明確型別的迴圈（`4974db5`）。

## 未驗證項目

無。下列為文件化的限制。

## 文件化的限制（非待驗證項）

- 以 macOS 14 SDK（Xcode 15／對應 CLT）編譯：錄影用到 macOS 15 SDK 才有的 ScreenCaptureKit 麥克風 API，舊 SDK 無法編譯；README 已寫明需要 macOS 15 以上 SDK。
- DRM／受保護內容可能錄不到聲音或畫面：規格要求「如實列出」，已寫入 README 與 `record --help`，沒有可合法取得的受保護測試素材。
- 多程序 App：Task 0 以 Chrome（多程序瀏覽器）驗證了 App 範圍與同 App 其他視窗會錄入；其他多程序 App 依同一機制，未逐一測試。
- 網頁影片的全螢幕：若瀏覽器以另一個視窗播放全螢幕影片，錄影仍綁定原本的 window ID（錄到原視窗，被藏起時為黑畫面）；App 視窗本身進入 macOS 全螢幕已驗證會持續錄製。
