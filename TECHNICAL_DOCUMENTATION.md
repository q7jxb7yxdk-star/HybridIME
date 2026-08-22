# HybridIME 技術文件

本文件描述目前工作樹中的實際原始碼、Xcode 設定與資料資產。它不以舊版發行結果、檔名推測或先前實機結果代替本次證據。

狀態用語：

- **已實作**：原始碼已存在並接入正常執行路徑。
- **已有測試涵蓋**：儲存庫有相應的測試工具，但不表示本次已執行。
- **本次工作已驗證**：本次文件工作確實執行並成功完成驗證。
- **尚未經外部驗證**：需要安裝、真實文字用戶端、模擬器／裝置、憑證或外部系統才能確認。
- **實驗性／未啟用**：存在，但目前不能作為正常保證路徑。
- **規劃中／尚未實作**：只有合理的擴充點，尚未實作。

## 1. 系統概覽

HybridIME 在一個 Xcode 專案中提供兩套平台配接器：

- macOS `HybridIME`：經典的 InputMethodKit 應用程式，`IMKInputController` 接收事件並用 `IMKTextInput` 更新宿主應用程式。
- iOS／iPadOS `HybridIMEKeyboard`：`UIInputViewController` 鍵盤延伸功能，以 `UITextDocumentProxy` 插入、刪除與移動游標；由 SwiftUI 宿主應用程式 `HybridIMEiOS` 嵌入。

兩平台各有自己的控制器、詞典包裝層、聯想邏輯與學習儲存庫，沒有獨立的共享 Swift 模組。它們共用已納入儲存庫的倉頡 TSV 和同一份生成後的 SQLite 詞彙資產，但原始碼有重複實作。

正常執行期完全離線：

1. 載入隨附的倉頡 TSV。
2. 以隨附的唯讀 SQLite 查詢雙語與聯想資料。
3. 由平台控制器管理組字狀態、候選及宿主文字替換。
4. 把使用者選擇寫入建置目標容器的本機 SQLite 學習資料庫。

沒有執行期後端、HTTP 提供者、登入、APNs、iCloud、Keychain 或遙測路徑。

## 2. 架構

```mermaid
flowchart LR
    subgraph staticSources["靜態來源"]
        C[倉頡 TSV]
        T[CC-CEDICT / Rime Essay / Tatoeba TSV]
        B[build_static_lexicon.py]
        L[(hybridime-lexicon.sqlite3)]
        T --> B --> L
    end

    subgraph macOS
        IMK[IMKServer + InputMethodController]
        MC[CangjieDecoder / StaticLexicon]
        MW[(UserLearningStore SQLite)]
        MP[CandidateWindowController]
        C --> MC
        L --> MC
        MC --> IMK
        MW <--> IMK
        IMK --> MP
        IMK -->|IMKTextInput| MH[宿主應用程式]
    end

    subgraph iOS
        KVC[KeyboardViewController]
        IC[CangjieDecoder / OfflineLexicon]
        IW[(KeyboardUserLearningStore SQLite)]
        C --> IC
        L --> IC
        IC --> KVC
        IW <--> KVC
        KVC -->|UITextDocumentProxy| IH[宿主應用程式]
    end
```

### 依賴方向

- 平台控制器擁有生命週期與組字狀態。
- 解碼器／詞彙／聯想／排序器不會呼叫 UI 程式碼。
- 候選 UI 使用控制器產生的呈現資料。
- 學習儲存庫負責 SQLite 結構與持久化；儲存庫無法使用時，呼叫端會收到空結果。
- 建置腳本讀取來源資料並產生已納入儲存庫的執行期資產；執行期絕不讀取原始 CC-CEDICT／聯想 TSV。

沒有相依性注入框架。macOS `InputResources` 與 iOS 控制器屬性充當組字根。正式執行使用共用的單例學習儲存庫；接受資料庫 URL 的初始化器支援獨立測試。

## 3. 專案結構

| 路徑 | 職責 |
| --- | --- |
| `HybridIME/HybridIMEApp.swift` | macOS `NSApplication` 入口、`IMKServer`、共用資源預載入 |
| `HybridIME/InputMethodController.swift` | macOS 事件狀態機、候選、提交、標點與聯想 |
| `HybridIME/CandidateWindowController.swift` | 不啟用的 macOS 候選面板與插入點定位 |
| `HybridIME/CangjieDecoder.swift` | macOS 倉頡 TSV 解析器與字形過濾器 |
| `HybridIME/StaticLexicon.swift` | macOS 唯讀 SQLite 雙語／聯想查詢 |
| `HybridIME/BilingualDictionary.swift` | macOS 雙語詞彙查詢的領域包裝層 |
| `HybridIME/AssociationDictionary.swift` | macOS 靜態與學習聯想的合併／排序 |
| `HybridIME/SmartCandidateRanker.swift` | macOS 最近使用智慧候選選擇 |
| `HybridIME/UserLearningStore.swift` | macOS 可寫入的 SQLite 學習結構 |
| `HybridIMEKeyboard/KeyboardViewController.swift` | iOS 鍵盤 UI、文字代理操作與組字狀態 |
| `HybridIMEKeyboard/OfflineLexicon.swift` | iOS 具有限制快取的唯讀 SQLite 查詢 |
| `HybridIMEKeyboard/KeyboardAssociationDictionary.swift` | iOS 聯想合併／排序 |
| `HybridIMEKeyboard/KeyboardUserLearningStore.swift` | iOS 可寫入的 SQLite 學習結構 |
| `HybridIMEKeyboard/PunctuationStrategy.swift` | iOS 標點定義、上下文與顯示標籤 |
| `HybridIMEKeyboard/PrivacyInfo.xcprivacy` | 鍵盤延伸功能隱私權資訊清單：不追蹤／無收集資料，以及 SystemBootTime 理由 `35F9.1` |
| `HybridIMEiOS/ContentView.swift` | 宿主應用程式設定、離線本機學習與第三方鍵盤系統限制說明 |
| `HybridIME/CangjieData/` | 執行期倉頡資料表、上游快照、變更記錄與聲明 |
| `HybridIME/DictionaryData/` | 用於產生 SQLite 的 CC-CEDICT 來源索引、覆寫項目、授權與聲明 |
| `HybridIME/AssociationData/` | 中文／英文聯想來源索引、授權與聲明 |
| `HybridIMEKeyboard/CangjieData/` | iOS 執行期倉頡資料表與 Rime Cangjie 授權／聲明 |
| `HybridIMEKeyboard/LexiconData/` | 鍵盤延伸功能使用的隨附 SQLite 詞彙與複製的聲明 |
| `Scripts/` | 資料集建置器、驗證器、獨立測試與發行工具 |

專案使用 Xcode 檔案系統同步群組。macOS 建置目標明確排除原始詞典／聯想 TSV 資源，並明確包含 `HybridIMEKeyboard/LexiconData/hybridime-lexicon.sqlite3`；因此兩個平台建置目標都使用儲存庫中同一份生成的詞彙檔案。

## 4. 資料流程

### 靜態資料產生

`Scripts/build_cedict_index.swift`、`Scripts/build_chinese_associations.swift` 與 `Scripts/build_english_associations.swift` 產生來源 TSV 索引。接著由 `Scripts/build_static_lexicon.py`：

1. 建立 `bilingual(direction, key, candidates)` 與 `association(language, key, candidates)` WITHOUT ROWID 資料表。
2. 將英文鍵值正規化為小寫，並保留以定位字元分隔的候選順序。
3. 套用 `HybridIME/DictionaryData/dictionary-overrides.tsv` 的 `add-e`、`add-z`、`replace-e`、`replace-z` 操作。
4. 設定 `PRAGMA user_version=1`、清理資料庫，並將第三方聲明複製到 `LexiconData/`。

目前已納入儲存庫的資料庫回報 177,594 個雙語資料列與 244,887 個聯想資料列。這些數量是儲存庫快照，不是服務狀態。

### macOS 輸入流程

1. `HybridIMEApp` 建立 `IMKServer`；`InputResources` 建立 `StaticLexicon`、詞典包裝層與聯想詞典，接著在分離的工作中載入倉頡。
2. `InputMethodController.handle` 接受 `keyDown`；Command／Control／Option 與不支援的系統事件會返回宿主應用程式。
3. ASCII 字母附加到記憶體中的緩衝區，並更新標記文字。
4. 最多五個字母會查詢倉頡；完整緩衝區也會查詢英譯中的 SQLite 項目。
5. 每個倉頡候選最多可加入兩個中譯英結果，使用前方中文加目前候選的最長尾綴。
6. 結果會去除重複、限制為十個，並可選擇依最近學習的候選重新排序。
7. 提交透過 `IMKTextInput` 插入文字、清除組字，並可能開始聯想查詢。

在倉頡預載入完成前，原始英文仍可使用；倉頡結果為空。SQLite 包裝層會同步建立，因此可用的詞典結果不必等待分離的倉頡工作。

### iOS 鍵盤流程

iOS 無法透過目前實作的路徑使用標記文字。`enterLetter` 立即呼叫 `textDocumentProxy.insertText`，將相同字元附加到 `buffer`，再推導候選。只有當 `documentContextBeforeInput` 仍以該緩衝區結尾時，選取候選才會成功；控制器會刪除那些字元並插入替換文字。

這項「失敗即拒絕」的尾綴檢查也保護翻譯與標點替換。如果宿主應用程式不提供上下文，或文字在插入與選取之間改變，系統會拒絕替換，而不會刪除無關內容。

### 聯想流程

- 中文查詢會嘗試最長的靜態尾綴與最長的學習尾綴，接著選取較長的鍵值；長度相同時優先使用靜態查詢鍵值，再合併學習候選。
- 英文查詢使用最後一個以空白分隔的小寫單字。
- 排序順序為最近選取、學習次數、靜態權重，最後是字典序。
- 中文提交序列會儲存最近上下文最多八個字元的一字元延續，並為每個上下文保留最多十個學習候選。
- 英文聯想提交會加入尾端空格；中文提交不會。

## 5. 核心元件

### macOS 生命週期與 UI

`HybridIMEApp` 以 `.accessory` 啟用策略執行 `NSApplication`，且沒有一般視窗。它從 `Info.plist` 讀取 `InputMethodConnectionName` 與套件識別碼；缺少值會觸發 `assertionFailure` 並阻止建立伺服器。

`CandidateWindowController` 使用位於 `.statusBar` 層級的無邊框 `NSPanel`，不取得鍵盤焦點，也不成為主視窗。它忽略滑鼠事件、加入所有 Spaces，並在可能時定位於插入點上方，否則放在下方或螢幕中央附近。候選寬度有限，超過十個項目不會分頁。

### macOS InputMethodKit 生命週期

此套件是經典的 InputMethodKit 應用程式，而不是文字輸入應用程式延伸功能。`LSUIElement=true` 與 `LSBackgroundOnly=false` 都是刻意設定。啟動時不會呼叫 `TISRegisterInputSource` 或自行啟用。

僅憑建置輸出無法驗證已安裝的輸入來源。對於已安裝、已選取但沒有回應的已簽署應用程式，請檢查統一日誌中是否有 `NO Endpoint` 或無法辨識的 `InputMethodConnectionName`。開發環境的復原順序如下：

```sh
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$HOME/Library/Input Methods/HybridIME.app"
killall HybridIME
killall TextInputMenuAgent
open "$HOME/Library/Input Methods/HybridIME.app"
```

成功復原後仍需要真實文字用戶端檢查；僅有程序存在並不足夠。這些指令會變更本機執行期狀態，不屬於一般未簽署建置驗證。

### 詞彙包裝層

macOS `StaticLexicon` 以 `SQLITE_OPEN_FULLMUTEX` 唯讀開啟資料庫、啟用 `query_only`、每批最多處理 32 個鍵值，並維持 256 項 FIFO 快取。iOS `OfflineLexicon` 在主 actor 上使用唯讀 `SQLITE_OPEN_NOMUTEX` 與 128 項 FIFO 快取。

傳入 SQL 輔助程式的所有資料表與欄位名稱都是內部常數。使用者衍生的鍵值會使用繫結參數。

### 平台控制器

`InputMethodController` 是 macOS 組字與事件的負責者。`KeyboardViewController` 同時是 iOS UI 與狀態機的負責者，負責按鍵版面、候選、標點、聯想上下文、游標手勢、鍵盤切換、顏色及 Return 鍵標籤。大型 iOS 控制器是目前的耦合點。

iOS 控制器固定建立以 `handleInputModeList(from:with:)` 為目標的地球鍵，並處理所有觸控事件；如此 iOS 能同時處理切換與長按顯示已啟用鍵盤清單，而不需因 `needsInputModeSwitchKey` 變化重建鍵盤。目前鍵盤 UI 不包含表情符號目錄、搜尋預留位置或表情符號頁面。

### iOS 版面模式與替代符號

`KeyboardViewController` 在版面配置後，若裝置是 iPad、水平尺寸類別為 `regular` 且鍵盤檢視寬度至少 700 點，便選取 `wideIPad`；否則使用 `compact`。初始的版面配置前選擇接受任何非 `compact` 的 iPad 水平尺寸類別，接著由 `viewWillLayoutSubviews()` 依最終寬度重新協調。寬版模式使用 353 點鍵盤高度、等比分配各列以及固定的 11 格列；`compact` 模式使用 260 點。寬版字母列將 Delete 放在第一列、Return 放在第二列，並在第三列兩端放置 Shift，另有逗號與句號標點控制。

鍵盤根視圖使用透明且非不透明的 surface，讓 iOS 宿主提供的鍵盤背景材質延伸至自訂內容區，視覺上銜接由系統管理的底部地球／咪高峰區。按鍵與游標觸控板覆蓋層仍使用自己的動態顏色。系統底部區不屬於 extension，程式不能直接設定其顏色。

寬版數字模式呈現上下堆疊的主要／替代配對：`@／¥`、`#／€`、`$／£`、`&／_`、`*／^`、`(／[`、`)／]`、`'／{`、`"／}`、`%／§`、`-／|`、`+／~`、`=／…`、`/／\\`、`;／<`、`:／>`、`,／!` 與 `.／?`。單指平移只有在向下位移達到 12 點且大於水平位移時才會選取替代符號。選取期間會隱藏堆疊標籤、顯示置中的替代預覽並反白按鍵；結束手勢會提交替代符號，取消則還原一般標籤。主要按鍵 `@`、`#`、`$`、`&`、`(`、`)`、`'`、`"` 與 `/` 使用零堆疊間距與邊緣內縮；其餘配對使用 -5 點堆疊間距與 2 點邊緣內縮。寬版字母標點控制也會將 `!` 與 `?` 作為逗號與句號的向下輕掃替代符號。

## 6. 資料模型與狀態管理

重要的暫時狀態包括緩衝區文字、候選動作陣列、選取的聯想上下文、標點替換中繼資料，以及最近使用的預測。兩個控制器都將 UI 狀態限制在主 actor／平台主執行緒。

候選動作保留行為邊界：

- 倉頡提交：符合智慧學習資格。
- 原始英文提交：保留輸入的大小寫，並可能取代該代碼的學習資料。
- 詞典提交：英譯中結果，不會作為倉頡選擇進行智慧學習。
- 翻譯：中譯英結果，以及可選的前置字首替換。
- 聯想：記錄聯想選擇並繼續鏈結。

### 靜態資料庫

`hybridime-lexicon.sqlite3` 結構版本為 `1`。它隨附於產品並以唯讀方式開啟，不包含任何使用者資料。

### 使用者學習資料庫

macOS 與 iOS 儲存庫各自建立：

- `smart_candidate(code, candidate, last_used)`.
- `association_selection(language, context, candidate, selection_count, last_selected)`.
- `learned_chinese(context, candidate, position)`.

它們使用 WAL、`synchronous=NORMAL`、`SQLITE_OPEN_FULLMUTEX` 與結構版本 `1`。檔案命名為 `hybridime-user-learning.sqlite3`，位於建置目標容器的使用者域 Application Support `HybridIME/` 目錄下。

沒有從舊版 `UserDefaults` 智慧／聯想鍵值遷移的機制，也沒有跨建置目標的 App Group。因此 macOS 與鍵盤的學習資料維持分離。由於靜態詞彙在程序存續期間不可變，因此沒有快取失效處理。

## 7. 重要邏輯與演算法

### 倉頡

執行期資料表將小寫 ASCII 代碼對應到有順序的單字元候選。每個代碼會移除重複值。Rime 的基本與擴充來源檔案可使用 `Scripts/build_hybrid_cangjie_dict.swift` 合併；本機修正存放於生成的執行期 TSV，並手動記錄在 `HybridIME/CangjieData/cangjie-change-log.tsv`。

兩個解碼器都使用 Core Text 拒絕替換字型為 `LastResort` 或沒有非零字形的候選。可用性會依字元快取。結果取決於作業系統字型，不能保證普遍支援 Unicode。

### 智慧候選排序

正規化的小寫代碼對應到帶有時間戳記的候選選擇。預測掃描最新記錄，選取仍存在於目前允許候選中的第一個值。這是以最近使用為基礎，不是機率、百分比或具上下文的語言模型。

透過 macOS `Shift + Space`，或 iOS 非小寫 Shift 狀態加 Space 選擇原始英文時，會以保持大小寫的原始字串取代該代碼的所有學習候選。

### 標點

兩個平台都從最近的非空白字元判定上下文，遇到句末標點即停止。中文字元涵蓋常見的 CJK 統一表意文字、相容表意文字與擴充純量範圍。在中文上下文中，某些字元刻意優先維持半形；貨幣、斜線、括號與箭頭替代符號使用固定候選清單。

macOS 將預設標點候選作為標記文字插入，並在替換前驗證用戶端選取／範圍。iOS 立即插入，並在刪除與替換前驗證前方完全相符的尾綴。

### iOS 游標移動

長按 Space 會進入觸控板覆蓋層。水平距離除以 5 點閾值後傳給 `adjustTextPosition`。垂直移動首先使用實際換行上下文與偏好的欄位；看不到邏輯換行時，會估算每行十個字元。此備援機制刻意採用近似值。

## 8. 外部依賴

| 依賴 | 用途 | 版本來源 | 必要性 |
| --- | --- | --- | --- |
| AppKit + InputMethodKit | macOS 服務、事件與候選視窗 | 平台 SDK | 僅 macOS |
| UIKit | 自訂鍵盤與文字代理 | 平台 SDK | iOS 鍵盤 |
| SwiftUI | iOS 宿主指示 | 平台 SDK | iOS 宿主 |
| Foundation | 檔案、字串、套件與生命週期輔助程式 | 平台 SDK | 所有建置目標 |
| CoreText | 字形可用性檢查 | 平台 SDK | 兩個輸入建置目標 |
| SQLite3 | 隨附的詞彙與學習儲存庫 | 系統函式庫；未鎖定套件版本 | 兩個輸入建置目標 |
| Rime Cangjie 資料 | 倉頡代碼表 | 聲明中記錄的提交版本 | 執行期資料 |
| CC-CEDICT | 雙語索引 | 聲明中記錄的日期／項目數 | 執行期資料 |
| Rime Essay | 中文聯想權重 | 聲明，無套件相依性 | 生成資料 |
| Tatoeba 英文 CC0 匯出資料 | 英文雙詞組 | 聲明，無套件相依性 | 生成資料 |

不會呼叫非官方的執行期端點。聲明中的外部 URL 僅用於識別資料集來源，不代表目前仍可用。

## 9. 設定

### 建置目標

| 建置目標 | 產品 | 套件識別碼 | 部署目標 | 版本 |
| --- | --- | --- | --- | --- |
| `HybridIME` | macOS 應用程式／輸入法 | `com.sunny.inputmethod.hybridime` | macOS 26.0 | 1.2.0（組建編號 20260821） |
| `HybridIMEiOS` | iOS／iPadOS 應用程式 | `com.sunny.inputmethod.hybridime.ios` | iOS 26.0 | 1.2.0（組建編號 20260821） |
| `HybridIMEKeyboard` | 鍵盤延伸功能 | `com.sunny.inputmethod.hybridime.ios.keyboard` | iOS 26.0 | 1.2.0（組建編號 20260821） |

所有建置目標都將 Swift 語言版本設定為 5.0。專案沒有 `.xcconfig`、`.swift-version`、`.xcode-version`、CI 矩陣或套件鎖定檔。中繼資料記錄以 Xcode 26.5／26.6 建立或升級，但這不是正式的最低 Xcode 宣告。

兩個 iOS 產品都以裝置系列 `1,2`（iPhone 與 iPad）為建置目標，並使用 iPhoneOS SDK。`HybridIMEiOS` 與 `HybridIMEKeyboard` 均明確將 `SUPPORTED_PLATFORMS` 限制為 `iphoneos iphonesimulator`，並停用 Mac Catalyst、Designed for iPhone／iPad on Mac，以及 Designed for iPhone／iPad on visionOS。

### macOS Info.plist 與權限設定

重要名稱包括 `InputMethodConnectionName=com.sunny.inputmethod.hybridime_Connection`、輸入模式 ID `com.sunny.inputmethod.hybridime.input`、`zh-Hant` 語言與美式鍵盤配置。Debug 使用包含 `get-task-allow` 的 `HybridIME/HybridIMEDebug.entitlements`；Release 沒有權限設定檔。兩種設定都停用 App Sandbox 並啟用強化執行期。

### 鍵盤 Info.plist

延伸功能端點是 `com.apple.keyboard-service`，主要類別是 `KeyboardViewController`，主要語言是 `zh-Hant`，`IsASCIICapable=true` 且 `RequestsOpenAccess=false`。

### 鍵盤隱私權資訊清單與歸屬聲明

`HybridIMEKeyboard/PrivacyInfo.xcprivacy` 宣告 `NSPrivacyTracking=false`、空的資料收集清單，以及 `NSPrivacyAccessedAPICategorySystemBootTime` 理由 `35F9.1`。這與 `KeyboardViewController` 僅使用 `ProcessInfo.systemUptime` 判斷 Shift 雙擊相符；不會傳送衍生值。採用檔案系統同步群組的 `HybridIMEKeyboard` 建置目標，會將此資訊清單與延伸功能資源一併包含。

延伸功能的 `CangjieData/` 包含生成的 Rime Cangjie 資料表，以及 `NOTICE-Rime-Cangjie.txt` 與 `LICENSE-Rime-Cangjie.txt`。`LexiconData/` 另行保留隨附 SQLite 詞彙所使用的 CC-CEDICT、Rime Essay 與 Tatoeba 聲明／授權。

### 環境變數

執行期原始碼不會讀取環境變數。`Scripts/release.sh` 辨識 `HYBRIDIME_NOTARY_PROFILE`、`HYBRIDIME_RESUME_AFTER_APP_NOTARIZATION` 與 `HYBRIDIME_RELEASE_ROOT_OVERRIDE`；這些是僅供發行使用的控制項。公證設定檔會命名一個 Keychain 項目，不得將其記錄為秘密值。

發行腳本解析 `HybridIME` macOS scheme 的 Debug 與 Release 建置設定，除非兩者都使用版本 `1.2.0`、組建編號 `20260821`、部署目標 `26.0`，以及預期的 macOS 建置目標與套件識別碼，否則會硬停止。此預檢不會執行或證明簽署、公證、封裝釘選或發佈。

## 10. 錯誤處理與記錄

- 缺少倉頡或靜態詞彙資源時會以 `NSLog` 記錄；查詢會降級為空結果，原始英文仍可使用。
- 建立或開啟學習資料庫失敗時會記錄錯誤，學習操作會變成無操作／空查詢。
- 無效 TSV 資料列會略過，不會逐列記錄。
- 大多數 SQLite 準備、繫結與步驟執行失敗都會靜默回傳空值；沒有具型別的公開錯誤模型、重試或退避機制。
- macOS 缺少伺服器識別碼時，Debug 會觸發斷言且不建立 `IMKServer`。
- 候選替換會檢查目前宿主的範圍／尾綴，文字狀態過期時採取失敗即拒絕。
- 沒有面向使用者的錯誤橫幅、診斷畫面、日誌編修層或自動復原 UI。

記錄的錯誤包含資源名稱或本機錯誤描述；原始碼不會刻意記錄輸入文字、候選或憑證。

## 11. 安全性與隱私

- 執行期離線，沒有驗證、權杖、Keychain、TLS、WebView、雲端或分析程式碼。
- iOS 不要求開放存取，也沒有 App Group 權限；延伸功能儲存空間保留在自己的容器中。
- 靜態 SQLite 是唯讀；學習 SQLite 位於本機，但沒有應用程式層級加密。
- 鍵盤的隱私權資訊清單宣告不追蹤且不收集資料，並依 SystemBootTime 理由 `35F9.1` 使用 `systemUptime` 進行本機 Shift 雙擊時間判斷。
- 宿主應用程式說明學習資料保留在鍵盤延伸功能的本機容器、不會傳送，且刪除應用程式（及其延伸功能）後會移除。它也說明在安全欄位、電話／姓名-電話欄位，或宿主停用第三方鍵盤的欄位中，iOS 會使用系統鍵盤。
- macOS App Sandbox 是目前 InputMethodKit 建置目標設定的一部分，且已停用。強化執行期已啟用，但本文件不將此設定等同於已驗證的簽署發行版。
- SQL 查詢值使用準備好的繫結。資料集資料表／欄位選擇器是內部固定字串。
- 只有在候選上下文與替換防護所需時才讀取宿主文字；原始碼沒有上傳路徑。
- 沒有可檢視或清除學習資料的 UI，也沒有針對不同代碼／上下文的文件化保留期限。只有每個已學習中文上下文的候選數量受到限制。
- `Scripts/release.sh` 中存在發行簽署、公證、封裝釘選與 Gatekeeper 檢查；一般開發不會執行這些外部驗證，其存在也不代表發行版已完成。

## 12. 測試

Xcode 專案沒有測試建置目標。測試涵蓋由獨立腳本提供：

| 測試工具 | 涵蓋範圍 | 外部服務 |
| --- | --- | --- |
| `Scripts/test_static_lexicon.swift` | 雙語查詢、批次最長比對、中文／英文聯想測試資料 | 無 |
| `Scripts/test_user_learning_store.swift` | macOS 學習結構與讀寫行為 | 無；暫存 SQLite |
| `Scripts/test_mac_dictionary.swift` | macOS 詞彙 + 聯想整合與學習重新排序 | 無；暫存 SQLite |
| `Scripts/test_keyboard_user_learning_store.swift` | iOS 學習結構、替換與完整性 | 無；暫存 SQLite |
| `Scripts/verify_static_lexicon.py` | 完整性與來源至資料庫完全相等 | 無；以唯讀方式開啟隨附 DB |

代表性指令只使用 `/tmp` 輸出：

```sh
python3 Scripts/verify_static_lexicon.py

swiftc -module-cache-path /tmp/hybridime-module-cache-static \
  HybridIME/StaticLexicon.swift Scripts/test_static_lexicon.swift \
  -lsqlite3 -o /tmp/hybridime-test-static
/tmp/hybridime-test-static HybridIMEKeyboard/LexiconData/hybridime-lexicon.sqlite3

swiftc -module-cache-path /tmp/hybridime-module-cache-learning \
  HybridIME/UserLearningStore.swift Scripts/test_user_learning_store.swift \
  -lsqlite3 -o /tmp/hybridime-test-learning
/tmp/hybridime-test-learning

swiftc \
  -module-cache-path /tmp/hybridime-module-cache-mac \
  HybridIME/StaticLexicon.swift \
  HybridIME/UserLearningStore.swift \
  HybridIME/BilingualDictionary.swift \
  HybridIME/AssociationDictionary.swift \
  Scripts/test_mac_dictionary.swift \
  -lsqlite3 -o /tmp/hybridime-test-mac-dictionary
/tmp/hybridime-test-mac-dictionary \
  HybridIMEKeyboard/LexiconData/hybridime-lexicon.sqlite3

swiftc -module-cache-path /tmp/hybridime-module-cache-keyboard \
  HybridIMEKeyboard/KeyboardUserLearningStore.swift \
  Scripts/test_keyboard_user_learning_store.swift \
  -lsqlite3 -o /tmp/hybridime-test-keyboard-learning
/tmp/hybridime-test-keyboard-learning
```

### 本次工作已驗證

本節記錄文件工作期間實際執行、並產生以下歷史結果的指令。這不是後續工作樹變更已建置或測試的證據。

- `xcodebuild -list` 找到全部三個建置目標與 scheme。沙盒執行也回報 CoreSimulator 服務不可用；仍完成 scheme 探索。
- SQLite 唯讀檢查回傳 `integrity_check=ok`、`user_version=1`、177,594 個雙語資料列與 244,887 個聯想資料列。
- `python3 Scripts/verify_static_lexicon.py` 通過完整的雙語與聯想來源相等性檢查。
- 四個獨立測試工具全部通過：`StaticLexicon`、`UserLearningStore`、macOS 詞典整合與 `KeyboardUserLearningStore`。它們的二進位檔與暫存資料庫建立於 `/tmp`；受限制的環境要求將編譯器模組快取重新導向 `/tmp`。
- 未簽署的 macOS Debug 建置通過 arm64 與 x86_64。建置出的應用程式回報版本 1.2.0（組建編號 20260821），包含 `integrity_check=ok` 的結構版本 1 SQLite，並封裝預期的生成詞彙，而非被排除的原始雙語／聯想 TSV 檔案。
- 未簽署的通用 iOS 模擬器 Debug 建置通過 `HybridIMEiOS` 及其 `HybridIMEKeyboard` 相依項目。兩個產品都回報版本 1.2.0；嵌入的延伸功能包含倉頡 TSV、聲明與 `integrity_check=ok` 的結構版本 1 SQLite。
- 文件編輯後，`git diff --check`、plist／權限設定靜態檢查與 Markdown 程式碼圍欄檢查通過。

在 HEAD `56fcaa7` 的 2026-08-22 文件更新中，未簽署的通用 iOS 模擬器 Debug 建置再次通過 `HybridIMEiOS` 與 `HybridIMEKeyboard`，並編譯 arm64 與 x86_64 切片。這僅是編譯與套件驗證；未執行模擬器鍵盤啟用或手勢互動。

後續在 iOS 26 Simulator 與實體 iPhone 進行有限鍵盤切換診斷：宿主會在轉場期間以 required 高度約束暫時把 extension 根視圖由最終 260 點配置為較高 frame；最小空白鍵盤亦能重現，故不能歸因於 SQLite、解碼器或完整按鍵樹。公開 API 只能以 primary view 的 Auto Layout 約束要求最終高度，不能控制宿主的中途 frame。透明根視圖在 Simulator 的視覺檢查中可與系統底部材質銜接；這不代表跨裝置、外觀與宿主均已驗證。

### 外部未驗證

- 已安裝 macOS InputMethodKit 的註冊、端點與真實文字輸入。
- 第三方 macOS 用戶端間的候選定位與替換。
- iOS 鍵盤的完整跨裝置、方向、外觀、記憶體使用量與宿主相容性矩陣。
- 簽署、封存、公證、DMG、GitHub 發行或 App Store 行為。

## 13. 已知限制與技術債

- 驗證必須繫結至受測的確切檢出內容與建置輸入；先前的建置結果不能證明後續檢出內容的行為。
- 沒有將舊 `UserDefaults` 學習資料遷移至結構版本 1 SQLite 的機制。
- macOS 與 iOS 各自重複解碼器、詞典、聯想、排序與標點概念，而非匯入共享核心。
- `HybridIME/InputMethodController.swift`，尤其是 `HybridIMEKeyboard/KeyboardViewController.swift`，集中許多狀態機與 UI 職責。
- 靜態詞彙快取淘汰是 FIFO 而非 LRU，也沒有記憶體壓力回應。
- 倉頡 TSV 仍會解析至記憶體；SQLite 遷移僅涵蓋雙語與聯想資料。
- macOS 資源預載入沒有就緒狀態、進度 UI 或重試。
- iOS 替換依賴宿主上下文與立即插入／刪除行為，而非標記文字組字。
- iOS 固定建立地球鍵，並將切換／長按選取交給 `handleInputModeList(from:with:)`；部分裝置也會在 extension 外顯示系統地球鍵，不同寬度、方向與已啟用鍵盤組合下的行為仍需持續驗證。
- iPad 在 700 點邊界的寬版版面切換、11 格幾何、堆疊符號標籤，以及 12 點替代符號輕掃預覽／提交互動，在模擬器與裝置上的視覺及行為仍未驗證。
- iOS 垂直游標備援會估算每行十個字元，無法得知視覺換行。
- 沒有可清除學習資料的設定 UI；記錄數量沒有全域上限或修剪政策。
- SQLite 執行錯誤大多靜默處理，除初始結構建立外沒有遷移。
- 沒有設定 XCTest、UI 測試、CI、靜態檢查、格式化工具、效能測試或延伸功能記憶體預算測試。
- 當解析後 macOS `HybridIME` scheme 的 Debug 或 Release 設定偏離版本 `1.2.0`、組建編號 `20260821`、部署目標 `26.0`、預期建置目標或套件識別碼時，`Scripts/release.sh` 會硬停止。
- 專案簽署包含特定擁有者的開發團隊；在其他開發者選取自己的團隊前，檢出內容的可攜性會降低。
- 儲存庫沒有全專案的原始碼授權。

## 14. 設計決策

- **離線優先：**隨附資料與本機學習避免網路依賴，讓 iOS 鍵盤不需完整存取權也能運作。
- **大型索引使用 SQLite：**雙語與聯想資料內容維持精簡、可查詢，並由小型快取限制大小，避免急切載入 TSV 至物件。
- **保留原始倉頡 TSV：**保留有順序的資料表維護與既有上游／本機修正工作流程，但代價是啟動時解析。
- **失敗即拒絕的文字替換：**範圍／尾綴防護寧可拒絕替換，也不在狀態過期後刪除宿主內容。
- **平台配接器分離：**InputMethodKit 與 `UITextDocumentProxy` 具有不同的生命週期與文字編輯契約；目前的重複實作讓差異保持明確，但增加維護成本。
- **以最近使用為基礎的學習：**可預測的最近選擇行為比不透明的統計模型簡單，但不使用周遭語言上下文。
- **啟動時不自動註冊 macOS：**安裝與文字輸入註冊保持外部處理，因此每次啟動都不會嘗試啟用輸入來源。
- **發行預檢在偏移時停止：**版本、識別碼、資源、簽章與公證檢查設計為在發佈不一致成品前先失敗。

## 15. 未來開發

以下是根據目前延伸功能端點推導出的 **計畫中／尚未實作** 建議，不是已承諾的路線圖：

- 將與平台無關的解碼、詞彙、聯想、排序與標點政策抽取至共享 Swift 模組，同時保留分離的 IMK 與鍵盤配接器。
- 在變更 `PRAGMA user_version` 前，加入從舊版 `UserDefaults` 與未來 SQLite 版本的明確結構遷移。
- 將 `KeyboardViewController` 拆分為組字、持久化、候選呈現與按鍵版面元件。
- 圍繞目前的獨立案例加入 XCTest 建置目標與測試資料包，另加入 iOS 延伸功能記憶體／啟動與宿主上下文測試。
- 加入清除學習資料的使用者控制項，以及有上限的保留／修剪政策。
- 在不記錄輸入文字的前提下，公開資源就緒狀態與診斷狀態。
- 實際發行前保留預檢、簽章、公證、資源與公開成品驗證邊界，並為每項外部狀態變更取得個別核准。

任何重構都必須保留離線運作、參數化 SQLite 值、平台容器分離、失敗即拒絕的宿主替換與第三方歸屬檔案。

## 授權與歸屬聲明

找不到全專案 `LICENSE`，因此本文件不對原始碼再散布權作任何聲明。

隨附資料集各自保留獨立條款：

- Rime Cangjie：請參閱 `HybridIME/CangjieData/LICENSE-Rime-Cangjie.txt` 與 `HybridIME/CangjieData/NOTICE.txt`。
- iOS Rime Cangjie 執行期資料表：請參閱 `HybridIMEKeyboard/CangjieData/LICENSE-Rime-Cangjie.txt` 與 `HybridIMEKeyboard/CangjieData/NOTICE-Rime-Cangjie.txt`。
- CC-CEDICT：請參閱 `HybridIME/DictionaryData/LICENSE-CC-CEDICT.txt` 與 `HybridIME/DictionaryData/NOTICE-CC-CEDICT.txt`。
- Rime Essay 與 Tatoeba：請參閱 `HybridIME/AssociationData/` 中的聲明與授權。
- iOS 隨附詞彙在 `HybridIMEKeyboard/LexiconData/` 下包含對應副本。
