# HybridIME 技術文件

## 1. 架構概覽

HybridIME 是以 Swift、AppKit、SwiftUI 及 InputMethodKit 開發的 macOS 輸入法。

主要元件：

| 元件 | 職責 |
| --- | --- |
| `HybridIMEApp.swift` | 建立 `IMKServer`，向 macOS 註冊並啟用輸入來源 |
| `InputMethodController.swift` | 接收按鍵事件、管理輸入緩衝區及提交文字 |
| `CangjieDecoder.swift` | 載入倉頡碼表、套用相容規則及查詢候選 |
| `CandidateWindowController.swift` | 建立及定位自訂候選視窗 |
| `ContentView.swift` | 顯示 HybridIME 的說明視窗 |
| `Info.plist` | 定義輸入法識別碼、語言、圖示及控制器類別 |

## 2. InputMethodKit 啟動流程

`AppDelegate.applicationDidFinishLaunching` 會：

1. 從 `Info.plist` 讀取 `InputMethodConnectionName`。
2. 使用 bundle identifier 建立 `IMKServer`。

應用程式啟動時不會呼叫 `TISRegisterInputSource` 或 `TISEnableInputSource`。輸入來源的註冊及啟用只屬於安裝流程，避免 macOS 每次重新啟動輸入法程序時顯示「允許中英混合啟用中英混合」的提示。

當 HybridIME 是目前選用的輸入法時，其程序由 macOS 管理。直接終止程序後，系統可能自動重新啟動；若要停止程序，應先切換至其他輸入法。

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

### 提交及控制鍵

| 按鍵 | 行為 |
| --- | --- |
| `Space` | 提交緩衝區內的英文，並附加一個空格 |
| `Return` / 數字鍵盤 `Enter` | 提交第一個中文候選；沒有候選時提交英文 |
| `1` 至 `9` | 提交第一至第九個候選 |
| `0` | 提交第十個候選 |
| `Delete` | 刪除緩衝區最後一個字母 |
| `Esc` | 清除組字內容及候選視窗 |
| `Command`、`Control` 或 `Option` 組合鍵 | 先提交英文，再把事件交回目標應用程式 |

### 標點符號

鍵盤可輸入的 ASCII 標點及符號會進入獨立的標點候選狀態。`punctuationPair(for:)` 定義半形與全形對照；逗號使用 `,`／`，`，句號使用 `.`／`。`，其他字符使用相應的全形字符。

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
- 第二列顯示每個鍵位對應的倉頡字母。
- 第三列顯示實際輸入的英文字母碼。
- 標點模式只顯示半形及全形候選列。

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

## 9. 建置及安裝

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

## 10. 已知限制

- 無法直接讀取或調用 Apple 的系統倉頡解碼器。
- 與 macOS 倉頡的一致性取決於 `macOS-overrides.tsv` 已收錄的差異。
- 候選視窗目前只顯示單頁最多十個候選，沒有翻頁功能。
- 字形可用性取決於目前 macOS 版本及已安裝字體。
- 目標應用程式若未提供正確插入點位置，候選視窗只能使用備用位置。

## 11. 授權與歸屬

Rime 倉頡資料的來源及授權聲明位於：

```text
HybridIME/CangjieData/LICENSE-Rime-Cangjie.txt
HybridIME/CangjieData/NOTICE.txt
```

更新或重新發佈碼表時，必須保留適用的第三方授權及歸屬聲明。
