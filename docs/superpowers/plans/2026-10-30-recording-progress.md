# 錄影開發交接

## 工作位置與範圍

- 使用者明確要求建立新分支與worktree；本次在 `feat/recording`、`/workspace/worktrees/snapparazzi-recording` 工作。
- 起點：`6cb3de2a404730af77d794d8960b83a4d5ded1f3`。
- 三份規劃文件從原工作目錄複製進本worktree，原檔保留。
- 正式 `Sources/`、Makefile、installer、既有tests皆未修改。本次使用者已授權將規劃與Task0初版提交、push到`feat/recording`；未合併主幹或建立release，提交與遠端狀態以Git紀錄為準。

## Task 0：已開始，尚未完成

已準備 `tools/recording-probe/`：獨立build.sh、embedded microphone用途描述、list/capture/inspect入口、SCK三來源callback與格式／PTS診斷、短片MOV writer、完整解碼檢查器。操作見[probe README](../../../tools/recording-probe/README.md)。

`both`目前只產出兩條分離音軌的diagnostic MOV，還不是規格要求的混音MP4；不標記混音、scope或sync gate通過。

現有雲端是Linux且沒有swiftc/macOS SDK；已檢查Shell語法、plist解析、文件連結與Linux平台拒絕行為，**未編譯Swift、未執行Apple APIs、未驗證真實授權或媒體輸出**。Mac編譯錯誤需保留原flags與完整log診斷，不跳過warnings-as-errors。

接續工作：

1. 將此worktree內容帶到Mac，在repo root跑 `sh tools/recording-probe/build.sh`。
2. 依README完成list與四種audio的短片，保存toolchain、exit statuses及JSON；有編譯錯誤先修probe。
3. 驗證目標App／非目標App範圍、mic權限、raw PTS clock與Ctrl-C收尾。
4. 依實際格式與時間軸結果補上synthetic fixture、雙AAC混音與壓縮video passthrough；驗證H264/HEVC及延遲音軌。
5. Task0其餘Retina／resize／visibility與舊系統gate仍待Mac證據，不能把這份交接標成Task0完成。

## Task 1：使用者已回報的本地基準

使用者的Mac為macOS26.5.2、SDK26.5、Swift6.3.3、arm64、Command Line Tools；`make test`原生release build成功，CLI 53／53、installer 7／7通過。這是使用者貼出的結果，不是雲端執行結果；該次Mac HEAD尚未提供，仍需補記。

## 其他 Tasks

Task2～16尚未開始。不要在沒有Mac技術gate的情況下把prototype搬入production或宣稱錄影功能可用。
