# HybridIME 技術文件

## 1. 架構概覽

HybridIME 是以 Swift、AppKit、SwiftUI 及 InputMethodKit 開發的 macOS 輸入法。

主要元件：

| 元件 | 職責 |
| --- | --- |
| `HybridIMEApp.swift` | 啟動背景 `NSApplication` 並建立 `IMKServer` |
| `InputMethodController.swift` | 接收按鍵事件、管理輸入緩衝區及提交文字 |
| `CangjieDecoder.swift` | 載入倉頡碼表、套用相容規則及查詢候選 |
| `BilingualDictionary.swift` | 載入 CC-CEDICT 中英雙向索引 |
| `AssociationDictionary.swift` | 載入中英文聯想索引及管理本機排序 |
| `SmartCandidateRanker.swift` | 記錄字碼候選選擇及提供智能預測 |
| `CandidateWindowController.swift` | 建立及定位自訂候選視窗 |
| `ContentView.swift` | 顯示 HybridIME 的說明視窗 |
| `Info.plist` | 定義輸入法識別碼、語言、圖示及控制器類別 |

## 2. InputMethodKit 啟動流程

`HybridIMEApp.main()` 不使用 SwiftUI `WindowGroup`。啟動流程直接取得
`NSApplication.shared`、設定 `AppDelegate`、把 activation policy 設為
`.accessory`，然後呼叫 `run()`。因此 macOS 在開機後首次選用輸入法時，
只會啟動背景輸入法服務，不會自動建立說明視窗或顯示 Dock 圖示。

`AppDelegate.applicationDidFinishLaunching` 會：

1. 從 `Info.plist` 讀取 `InputMethodConnectionName`。
2. 使用 bundle identifier 建立 `IMKServer`。
3. 由 `InputResources` 在 detached task 背景預載倉頡、CC-CEDICT 及聯想
   索引，完成後把不可變查詢快照發佈到 MainActor。

應用程式啟動時不會呼叫 `TISRegisterInputSource` 或 `TISEnableInputSource`。輸入來源的註冊及啟用只屬於安裝流程，避免 macOS 每次重新啟動輸入法程序時顯示「允許中英混合啟用中英混合」的提示。

`ContentView.swift` 目前保留作為說明內容，但不屬於輸入法的自動啟動
流程。若日後加入「關於 HybridIME」入口，應由明確的使用者操作建立視窗。

當 HybridIME 是目前選用的輸入法時，其程序由 macOS 管理。直接終止程序後，系統可能自動重新啟動；若要停止程序，應先切換至其他輸入法。

大型 TSV 合共超過 50 萬行。解碼器的檔案解析 initializer 及 loader 標記
為 `nonisolated`，避免在切換輸入法期間同步堵塞主執行緒及輸入法選單的
mouse tracking。載入完成前英文仍可提交，中文、翻譯及聯想候選暫時為空。

主要識別碼：

```text
Bundle ID: com.sunnyyu.inputmethod.HybridIME
Input source ID: com.sunnyyu.inputmethod.HybridIME.Hybrid
Language: zh-Hant
Keyboard layout: com.apple.keylayout.US
```

## 3. 按鍵處理

`InputMethodController.handle(_:client:)` 只處理 `keyDown` 事件。

### 英文字母

ASCII 英文字母會轉為小寫並加入 `buffer`。每次更新後：

1. 呼叫 `updateComposition()` 更新組字內容。
2. 當長度不超過五碼時，查詢最多十個倉頡候選。
3. 把每個鍵位轉換成對應的倉頡字母。
4. 在文字插入點附近顯示倉頡字母、英文碼及已有的候選。

輸入超過五個字母後仍可繼續輸入英文，但不再執行倉頡查詢。

候選由 `CandidateAction` 表示：

- `commit`：提交中文、英文至中文翻譯或標點候選。
- `translate`：提交英文翻譯，並可替換游標前已組成的中文前綴。

每個倉頡中文候選後最多加入兩個英文翻譯。`chineseTextBeforeComposition`
讀取 marked range 前最多 24 個 UTF-16 code units，保留末端連續中文；
`longestTranslationLookup` 由最長前綴開始查詢「前綴 + 當前中文候選」，
找不到詞組時才逐步縮短至單字。

### 提交及控制鍵

| 按鍵 | 行為 |
| --- | --- |
| `Space` | 英文語境提交英文並附加空格；其他語境若有智能預測則提交該候選，否則提交英文及空格 |
| `Shift + Space` | 提交緩衝區內的英文，不附加空格 |
| `Return` / 數字鍵盤 `Enter` | 英文語境提交英文；其他語境提交第一個候選，沒有候選時提交英文 |
| `1` 至 `9` | 提交第一至第九個候選 |
| `0` | 提交第十個候選 |
| `Delete` | 刪除緩衝區最後一個字母 |
| `Esc` | 清除組字內容及候選視窗 |
| `Command`、`Control` 或 `Option` 組合鍵 | 不處理事件，直接交回目標應用程式 |

修飾鍵檢查在其他按鍵處理之前執行。包含 Command、Control 或 Option 的
`keyDown` 會立即回傳 `false`，且不會同步提交、清除或修改 marked text，
避免 InputMethodKit 中斷 `⌘C`、`⌘V`、`⌘A`、`⌘Z` 等應用程式快捷鍵。
Shift 不在此透傳集合內，因此仍可保留英文大小寫。

### 英文語境與邊界提交

`englishTextBeforeComposition(in:)` 讀取 marked range 前最多 64 個 UTF-16
code units，並只檢查最近一個句號、問號、感嘆號或換行之後的片段。片段
含 ASCII 英文字母且不含中文字時，當前組字會標記為英文語境。

英文語境中的 Space 及 Return 直接提交原始英文，不套用中文智能預測。
輸入 ASCII 標點時，既有 `commitDefault` 流程會先提交緩衝區英文，再建立
標點候選狀態，因此 `I love you!` 的 `you` 不需要額外按 Space。句首第一個
英文詞仍使用一般混合輸入規則；`Shift + Space` 在任何語境均可強制提交
英文且不加入空格。

### 智能候選學習

`SmartCandidateRanker` 以正規化小寫字碼及候選文字為鍵，把每次實際提交
的中文、翻譯或英文候選記錄到 `UserDefaults`。資料使用
`smartCandidate.v2.<code>.*` key namespace，分別保存候選累計次數、最近
選擇時間及該字碼的候選清單。

同一字碼與同一候選累計達三次後即可成為預測，不使用百分比或前文情境。
查詢時只考慮目前仍存在於候選清單的項目，依累計次數、最近選擇時間及
文字次序決定最佳候選。`InputMethodController` 把原始英文碼及目前可見
候選一併交給排序器，但只有可見的非英文候選才會取得
`smartPredictionIndex`。

候選視窗會在預測候選後顯示 `◆`。非英文語境按 Space 時直接提交該候選；
英文語境維持提交英文，`Shift + Space` 則始終強制提交英文。標點及聯想
候選不會寫入這套智能候選記錄。

### 滑鼠事件透傳

`recognizedEvents(_:)` 明確宣告 `keyDown`、`leftMouseDown`、
`leftMouseUp`、`leftMouseDragged` 及 `mouseCancelled`。事件處理器只接受
`keyDown`，所有滑鼠事件立即回傳 `false`。

這會停用 InputMethodKit 在輸入法只接收 `keyDown` 時套用的預設 mouse
down 組字處理，確保 Google Sheets 等網頁文字客戶端收到完整左鍵序列。

`commitComposition(_:)` 若由系統要求結束組字，只提交現有內容並清除
狀態，不顯示聯想候選。`deactivateServer(_:)` 亦會隱藏候選視窗及清除
組字、標點和聯想狀態。

### 聯想候選狀態

聯想候選不建立 marked text。提交中文或英文後，
`showAssociations(context:language:client:)` 查詢同語言的後續候選，並以
`CandidateAction.associate` 保存候選文字、查詢鍵及語言。

| 按鍵 | 聯想狀態行為 |
| --- | --- |
| `Return`、`1` 至 `0` | 提交所選聯想並繼續查詢 |
| `Esc` | 關閉聯想並清除上下文 |
| 英文字母 | 收起聯想視窗，開始新的正常組字 |
| 標點、Delete、其他非文字鍵 | 關閉聯想並清除上下文 |
| Command、Control、Option 快捷鍵 | 清除聯想後透傳至應用程式 |

中文聯想直接附加候選；英文聯想附加候選及一個空格。選取後會呼叫
`AssociationDictionary.recordSelection`，把使用次數寫入目前使用者的
`UserDefaults`。資料只在本機使用。

### 標點符號

鍵盤可輸入的 ASCII 標點及符號會進入獨立的標點候選狀態。`punctuationPair(for:)` 定義半形與全形對照；逗號使用 `,`／`，`，句號使用 `.`／`。`，其他字符使用相應的全形字符。

特殊候選：

```text
$ → $  ¥  £  €  ₹  ₺  ＄
. → .  。  ⋯⋯
```

`$` 固定以半形美元符號為首選，全形 `＄` 固定最後。`.` 仍按游標前文字
在 `.` 與 `。` 之間切換第一候選，`⋯⋯` 固定排在其後。

`characterBeforeCursor(in:)` 會透過 `NSTextInputClient.selectedRange()` 及 `attributedSubstring(forProposedRange:actualRange:)` 讀取實際游標前一個字元。若目標應用程式不支援讀取，則使用本次輸入工作階段的 `lastCommittedCharacter` 作為備用值。

`isChinese(_:)` 檢查 CJK Unified Ideographs、Extension A 至 H、Compatibility Ideographs 及 `〇`：

- 游標前為中文字：第一候選為全形，第二候選為半形。
- 其他情況：第一候選為半形，第二候選為全形。

第一候選會立即成為 InputMethodKit marked text，因此使用者不需要按 `Space` 或 `Return`：

```text
英文後：1 ,   2 ，
中文後：1 ，   2 ,
```

標點候選狀態的按鍵行為：

| 按鍵 | 行為 |
| --- | --- |
| 繼續輸入文字或另一標點 | 自動提交第一候選，再處理新按鍵 |
| `1`、`Return` 或 `Space` | 提交第一候選 |
| `2` | 提交第二候選 |
| `Delete` 或 `Esc` | 取消尚未確認的標點 |

## 4. 候選視窗

`CandidateWindowController` 使用無邊框、不可成為主視窗的 `NSPanel`。

視窗特性：

- 層級為 `.statusBar`。
- 可顯示於所有 Spaces 及全螢幕應用程式。
- 不接收滑鼠事件。
- 使用 `NSVisualEffectView` 的 `.menu` 材質。
- 第一列在完整字碼命中時顯示最多十個帶數字的候選。
- 英文翻譯候選使用次要文字顏色，與中文候選區分。
- 智能預測候選在文字後顯示 `◆`。
- 第二列顯示每個鍵位對應的倉頡字母。
- 第三列顯示實際輸入的英文字母碼。
- 標點模式只顯示半形及全形候選列。
- 聯想模式只顯示帶數字的聯想候選列，不顯示倉頡字根及輸入碼。

當完整字碼尚未命中時，候選列會隱藏，但倉頡字母及英文碼會持續顯示。例如：

```text
m     → 一
mr    → 一口
mrs   → 一口尸
mrsq  → 一口尸手
mrsqf → 一口尸手火
```

`mrsqf` 命中「碼」後，視窗內容為：

```text
1 碼
一口尸手火
mrsqf
```

鍵位對照由 `CandidateWindowController.cangjieRoots(for:)` 定義：

```text
a 日  b 月  c 金  d 木  e 水  f 火  g 土
h 竹  i 戈  j 十  k 大  l 中  m 一  n 弓
o 人  p 心  q 手  r 口  s 尸  t 廿  u 山
v 女  w 田  x 難  y 卜  z 重
```

位置由目標應用程式的 `IMKTextInput.attributes` 提供。正常情況下，視窗位於插入點上方；空間不足時改為顯示於下方。若無法取得插入點位置，則顯示於主螢幕中央附近。

## 5. 倉頡碼表

### 5.1 上游來源

Rime 相關 repository 分工如下：

- [https://github.com/rime/home](https://github.com/rime/home)
  - Rime 專案首頁。
  - 提供專案介紹、文件及其他 repository 的入口。
  - 不直接存放 HybridIME 使用的倉頡字碼表。

- [https://github.com/rime/rime-cangjie](https://github.com/rime/rime-cangjie)
  - Rime 倉頡輸入方案 repository。
  - 存放 `cangjie5.base.dict.yaml`、`cangjie5.extended.dict.yaml` 等方案及碼表。
  - 查詢碼表內容、版本及 Git 修改歷史時，應以此 repository 為準。

GitHub repository 的最近更新日期不一定等於個別碼表的最後修改日期。查詢指定檔案的最後 commit 可使用：

```text
https://api.github.com/repos/rime/rime-cangjie/commits?path=cangjie5.base.dict.yaml&per_page=1
https://api.github.com/repos/rime/rime-cangjie/commits?path=cangjie5.extended.dict.yaml&per_page=1
```

### 5.2 基礎與擴展碼表

`CangjieDecoder.resourceNames` 定義載入次序：

```swift
[
    "cangjie5.base.dict",
    "cangjie5.extended.dict",
]
```

`cangjie5.base.dict.yaml`：

- 收錄一般及較常用的倉頡五代單字。
- 先於擴展碼表載入。
- 同碼候選通常具有較高優先次序。

`cangjie5.extended.dict.yaml`：

- 補充罕用字、異體字及 Unicode CJK 擴展區漢字。
- 可能包含本機字型沒有正常字形的字元。

解析器只接受：

- 單一 Swift `Character`
- 非空白倉頡碼
- 完全由 ASCII 小寫字母組成的倉頡碼

同一倉頡碼下的重複字會被移除，並保留第一次出現的位置。

## 6. macOS 相容覆寫

Apple 沒有公開 macOS 內建倉頡碼表或解碼 API。因此 HybridIME 以 Rime 倉頡五代為基礎，再透過：

```text
HybridIME/CangjieData/macOS-overrides.tsv
```

記錄已確認的 macOS 差異。

格式為以 Tab 分隔的欄位：

```text
operation	code	candidate...
```

### `add`

把一個或多個候選移至指定字碼的最前方，並依欄位次序排列：

```text
add	hsp	怎
```

若候選原本已存在，會先移除舊位置，避免重複。

### `remove`

從指定字碼移除一個或多個候選：

```text
remove	osp	怎
```

### `replace`

完全捨棄指定字碼的原有候選，改用所列的完整候選及次序：

```text
replace	abc	字	候	選
```

重複候選會自動移除，並保留第一次出現的位置。

覆寫檔獨立於上游碼表，可避免更新 Rime 碼表時覆蓋 macOS 相容修正。

## 7. 缺字過濾

擴展碼表可能包含本機 macOS 字型無法顯示的 Unicode 字元。這些字元通常由 Core Text 的 `LastResort` 字體顯示為中間帶問號的方框。

`CangjieDecoder` 在候選即將顯示時：

1. 使用 `CTFontCreateForString` 尋找可顯示該字元的替代字體。
2. 排除 PostScript 名稱為 `LastResort` 的字體。
3. 使用 `CTFontGetGlyphsForCharacters` 確認至少存在有效 glyph。
4. 使用 `NSCache` 快取每個字元的結果。
5. 略過沒有可用字形的候選，繼續尋找下一個候選，直至取得指定數量。

檢查採用延遲執行，並不在載入約 79,000 行碼表時逐字處理，因此不會大幅增加輸入法啟動時間。

## 8. 碼表更新流程

建議更新步驟：

1. 查看 `rime/rime-cangjie` 中兩個碼表的最新 commit。
2. 閱讀上游授權及變更內容。
3. 取代本地 `base` 及 `extended` 檔案。
4. 不要覆蓋 `macOS-overrides.tsv`。
5. 建置 HybridIME。
6. 驗證常用倉頡碼、超過五碼的英文輸入及數字候選選擇。
7. 驗證缺字候選不會顯示為方框問號。
8. 驗證英文後預設半形標點、中文後預設全形標點，以及第二候選切換。
9. 重新安裝、註冊及啟用輸入來源。

不建議直接修改上游 `.dict.yaml`：

- 上游更新會覆蓋本地修改。
- 難以識別哪些條目是 macOS 相容修正。
- 候選次序及重複項目較難維護。
- 第三方原始資料與本地行為規則會混在一起。

## 9. 中英雙向字典

`BilingualDictionary` 載入：

```text
HybridIME/DictionaryData/cedict-index.tsv
```

索引由 CC-CEDICT 生成，格式為：

```text
e	English key	繁體候選...
z	繁體詞語	English candidate...
```

`e` 是英文至繁體中文索引，`z` 是繁體中文至英文索引。產生器會：

1. 使用 CC-CEDICT 的繁體詞頭。
2. 把英文釋義轉為小寫並移除括號內補充說明。
3. 排除過長、含非英文符號或超過四個單詞的釋義。
4. 英文至中文索引同時保留原詞組及移除 `to`、`a`、`an`、`the`
   後的常用查詢鍵。
5. 中文至英文候選只保留移除上述前綴後的詞典形式，例如使用 `survey`
   而不是 `to survey`，並排除重複。
6. 每個查詢鍵最多保留十個不重複候選。

本地候選排序放在：

```text
HybridIME/DictionaryData/dictionary-overrides.tsv
```

支援 `add-e` 及 `add-z`，把候選依欄位次序移至指定英文或中文查詢鍵的
最前方。`replace-e` 及 `replace-z` 則完全取代指定方向的候選。此檔案
不由生成器改寫。

重新生成：

```sh
swift Scripts/build_cedict_index.swift \
  /path/to/cedict_ts.u8 \
  HybridIME/DictionaryData/cedict-index.tsv
```

完整英文鍵的中文翻譯候選排在倉頡候選之前，Space 維持輸出原英文。
中文至英文方向會在倉頡中文候選後顯示英文翻譯；若翻譯來自游標前中文
與當前候選組成的詞語，選取英文時會透過 `replacementRange` 一併替換
該中文前綴及目前 marked text。

當同一組字母同時命中倉頡碼與英文詞典時，完整排序是：

1. 倉頡中文候選。
2. 每個倉頡候選的英文翻譯。
3. 英文查中文候選。

例如 `oh` 先命中倉頡「入」，再顯示「入」的英文翻譯，最後顯示本地
`replace-e` 規則指定的「噢」。

## 10. 中英文聯想資料

### 10.1 中文聯想

中文資料來源為 [Rime Essay](https://github.com/rime/rime-essay)，即 Rime
的共享詞彙表及語言模型。生成器讀取詞語及權重，把每個純中文字詞拆成：

```text
context	completion	weight...
```

例如「測試」生成 `測 → 試`，「測試結果」可生成
`測試 → 結果`。每個上下文最多保留十個候選，按累計權重排序；詞語最長
八字，接續內容最長四字。

```sh
swift Scripts/build_chinese_associations.swift \
  /path/to/essay.txt \
  HybridIME/AssociationData/chinese-associations.tsv
```

### 10.2 英文聯想

英文資料只使用 Tatoeba 英文 CC0 句子匯出。生成器把句子正規化為小寫
英文單詞，統計相鄰單詞 bigram：

```text
context	completion	count...
```

每個英文詞最多保留十個下一詞候選，按出現次數排序。

```sh
swift Scripts/build_english_associations.swift \
  /path/to/eng_sentences_CC0.tsv \
  HybridIME/AssociationData/english-associations.tsv
```

### 10.3 查詢與學習

中文查詢由完整上下文開始逐字縮短，使用最長可命中的後綴。英文查詢使用
最後一個英文單詞。排序時先比較使用者在 `UserDefaults` 的選取次數，再
比較靜態權重或 bigram 次數。

App 只載入生成後的索引，不打包 Rime Essay 或 Tatoeba 原始語料。

## 11. 建置及安裝

命令列建置：

```sh
xcodebuild \
  -project HybridIME.xcodeproj \
  -scheme HybridIME \
  -configuration Debug \
  -derivedDataPath /tmp/HybridIMETraditionalDerivedData \
  -allowProvisioningUpdates \
  build
```

安裝位置：

```text
~/Library/Input Methods/HybridIME.app
```

安裝後可透過「系統設定 > 鍵盤 > 文字輸入」加入及啟用「中英混合」。開發時如需以 Carbon Text Input Source API 重新註冊，應由外部安裝命令執行一次，不應放在應用程式啟動流程。

建置需要可用的 Apple Development 憑證。這不代表必須加入付費 Apple Developer Program；免費 Apple ID 亦可由 Xcode 建立個人開發憑證，但憑證及簽署限制可能不同。

## 12. 已知限制

- 無法直接讀取或調用 Apple 的系統倉頡解碼器。
- 與 macOS 倉頡的一致性取決於 `macOS-overrides.tsv` 已收錄的差異。
- 候選視窗目前只顯示單頁最多十個候選，沒有翻頁功能。
- 字形可用性取決於目前 macOS 版本及已安裝字體。
- 目標應用程式若未提供正確插入點位置，候選視窗只能使用備用位置。
- 英文翻譯使用精確完整詞匹配，暫不支援模糊搜尋、詞形還原或句子翻譯。
- 中文至英文翻譯依賴目標應用程式正確提供 marked range、selection 及
  `attributedSubstring`；不完整支援 `NSTextInputClient` 的應用程式可能
  只能使用當前單字翻譯。
- 英文聯想資料來自較小的 CC0 子集，罕見詞的候選可能不足。
- 聯想目前沒有設定介面或清除個人學習資料的按鈕。

## 13. 授權與歸屬

Rime 倉頡資料的來源及授權聲明位於：

```text
HybridIME/CangjieData/LICENSE-Rime-Cangjie.txt
HybridIME/CangjieData/NOTICE.txt
```

更新或重新發佈碼表時，必須保留適用的第三方授權及歸屬聲明。

CC-CEDICT 衍生索引的來源及 CC BY-SA 4.0 授權聲明位於：

```text
HybridIME/DictionaryData/LICENSE-CC-CEDICT.txt
HybridIME/DictionaryData/NOTICE-CC-CEDICT.txt
```

聯想資料的來源及授權聲明位於：

```text
HybridIME/AssociationData/LICENSE-Rime-Essay.txt
HybridIME/AssociationData/NOTICE-Rime-Essay.txt
HybridIME/AssociationData/NOTICE-Tatoeba-CC0.txt
```
