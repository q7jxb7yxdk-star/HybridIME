# HybridIME

HybridIME 是一套以 Swift 開發的中英混合倉頡五代輸入工具，同一個 Xcode project 目前包含：

- macOS InputMethodKit 輸入法 `HybridIME`。
- iOS／iPadOS host app `HybridIMEiOS`。
- 嵌入 host app 的 Custom Keyboard extension `HybridIMEKeyboard`。

輸入英文字母時，兩個輸入法都會同時把內容視為英文與倉頡碼，並提供倉頡字、雙向翻譯、聯想與本機智能候選。所有 runtime 詞典均隨 app 離線提供；source 中沒有網路 API、帳戶、telemetry 或 cloud sync 路徑。

> 狀態說明：本文件以目前 working tree 為準。`Implemented` 表示 source 已接入正常路徑，不等同已在本次任務完成實機驗證；實際驗證結果見[開發與驗證](#開發與驗證)。

## 功能

### 共同功能（Implemented）

- 倉頡五代單字解碼，最多五碼；超過五碼仍可輸入英文。
- 以 Core Text 過濾目前系統字型無法正常顯示的候選字。
- CC-CEDICT 英文至繁體中文候選，以及倉頡中文至英文翻譯。
- 以游標前的連續中文做最長詞組翻譯查詢。
- 中英文聯想候選與連續中文學習。
- 依最近選擇提升智能候選；學習資料只寫入本機 SQLite。
- 依中文／英文前文選擇全形或半形標點，並提供替代標點候選。
- 以 bundled read-only SQLite lexicon 查詢雙語與聯想資料。

### macOS（Implemented）

- classic InputMethodKit `.app`，以背景程序建立 `IMKServer`。
- 在文字插入點附近顯示不搶焦點的候選視窗。
- `Space` 輸出英文及空格；若第一項是已學習的中文候選則提交中文。
- `Shift + Space` 輸出原始英文、不附加空格，並記錄該選擇。
- `Return` 或 `1`–`0` 選取候選；`Delete`、`Esc`、標點及 app 快捷鍵有獨立狀態處理。
- Command、Control、Option、滑鼠及系統輸入事件交回目前 app。

### iOS／iPadOS（Implemented，runtime 未驗證）

- UIKit 自訂鍵盤，包含字母、數字與符號頁面。
- iPad 在 regular horizontal size class 且鍵盤寬度至少 700 pt 時，使用 11-slot、353 pt 高的寬版配置；其他情況維持 compact 配置。
- 寬版數字符號鍵同時顯示主要與替代符號；向下滑動至少 12 pt 且垂直位移大於水平位移時，會顯示替代符號預覽並輸入替代符號。
- 候選列、倉頡字根提示、大小寫與 Caps Lock。
- 點按已學習候選、翻譯、標點或聯想候選時替換已插入文字。
- 長按 Space 後水平／垂直拖曳游標，並提供 selection feedback。
- extension 宣告 `RequestsOpenAccess=false`，離線詞典及學習不需要「允許完整取用」。
- 當 `needsInputModeSwitchKey` 為真時，顯示 Globe 鍵並使用 `handleInputModeList(from:with:)` 切換或長按選擇已啟用鍵盤。
- SwiftUI host app 提供加入與使用鍵盤、離線本機學習及第三方鍵盤系統限制的說明。
- `HybridIMEKeyboard/PrivacyInfo.xcprivacy` 宣告不追蹤、不收集資料，以及 Shift 雙擊計時所需的 `SystemBootTime` 原因 `35F9.1`。

## 系統需求

| 項目 | Repository 宣告 |
| --- | --- |
| macOS deployment target | `26.0` |
| iOS／iPadOS deployment target | `26.0` |
| Swift language version | `5.0` build setting |
| Xcode | 沒有 tool-version file 或 CI 明確宣告最低版本；project metadata 由 Xcode 26.5／26.6 建立或更新，需使用能讀取 object version 77 並提供 SDK 26 的 Xcode |
| Python | 只供建立及驗證靜態 SQLite lexicon；版本未在 repository 鎖定 |
| 第三方 package | 無 Swift Package、CocoaPods、Carthage、npm 或其他 package manifest／lockfile |

App runtime 使用 Apple 平台 framework：AppKit、InputMethodKit、UIKit、SwiftUI、Foundation、CoreText 與系統 SQLite3。

macOS 日常開發 build 可停用 code signing；要安裝並實際啟用輸入法，需有效的本機開發簽署。iOS 真機執行亦需使用自己的 Apple Development team。project 目前含有 owner-specific team 設定，其他開發者應在 Xcode 的 Signing & Capabilities 選擇自己的 team，不應沿用 repository 中的值作 credential。

## 取得與開啟專案

```sh
git clone <repository-url>
cd HybridIME
open HybridIME.xcodeproj
```

Repository 不需要另外安裝 package dependencies，也沒有 environment file 或 runtime API key。

Xcode 中可使用以下 schemes：

- `HybridIME`：macOS 輸入法。
- `HybridIMEiOS`：iOS／iPadOS host app，會同時 build 並嵌入 keyboard extension。
- `HybridIMEKeyboard`：獨立 build keyboard extension；通常由 host app scheme 驅動。

## 建置與執行

### macOS

在 Xcode 選擇 `HybridIME` scheme 與 `My Mac`。不簽署的命令列 build：

```sh
xcodebuild \
  -project HybridIME.xcodeproj \
  -scheme HybridIME \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/HybridIME-macOS \
  CODE_SIGNING_ALLOWED=NO \
  build
```

要使用輸入法，需把已適當簽署的 `HybridIME.app` 放入 `~/Library/Input Methods/`，再從「系統設定 > 鍵盤 > 文字輸入」加入「中英混合輸入法」。build 成功只證明產物可建立，不證明已安裝的 app、LaunchServices 註冊或 InputMethodKit endpoint 正常。

若已安裝版本出現「已選取但沒有輸入反應」，請參閱[技術文件的 InputMethodKit 診斷](TECHNICAL_DOCUMENTATION.md#macos-inputmethodkit-lifecycle)。

### iOS／iPadOS

在 Xcode 選擇 `HybridIMEiOS` scheme 與 Simulator 或已簽署的 device。命令列 Simulator build：

```sh
xcodebuild \
  -project HybridIME.xcodeproj \
  -scheme HybridIMEiOS \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/HybridIME-iOS \
  CODE_SIGNING_ALLOWED=NO \
  build
```

安裝 host app 後，前往「設定 > 一般 > 鍵盤 > 鍵盤 > 新增鍵盤」，選擇 `HybridIMEKeyboard`。當系統需要鍵盤切換控制時，HybridIME 底列會顯示 Globe 鍵；點按可切換鍵盤，長按可選擇已啟用的鍵盤。

## 基本輸入方式

macOS 輸入 `hsp` 後可用 `Return` 或候選數字鍵提交「怎」；按 `Space` 則輸出 `hsp `。iOS 會先透過 `UITextDocumentProxy` 把鍵入字母插入 host，點選候選後再刪除該字碼並插入候選。

兩平台一般候選次序為：

1. 倉頡中文候選。
2. 每個倉頡候選最多兩項英文翻譯。
3. 完整英文詞的繁體中文翻譯。

標準倉頡鍵位：

```text
a 日  b 月  c 金  d 木  e 水  f 火  g 土
h 竹  i 戈  j 十  k 大  l 中  m 一  n 弓
o 人  p 心  q 手  r 口  s 尸  t 廿  u 山
v 女  w 田  x 難  y 卜  z 重
```

## 專案結構

```text
HybridIME/                 macOS InputMethodKit target、倉頡資料及資料來源 TSV
HybridIMEKeyboard/         iOS Custom Keyboard、bundled SQLite lexicon 及鍵盤資源
HybridIMEiOS/              iOS／iPadOS host app 與設定說明 UI
HybridIME.xcodeproj/       targets、build settings 與 schemes
Scripts/                   資料生成、SQLite 驗證、standalone tests 及 release tooling
README.md                  開發者入口與執行方式
TECHNICAL_DOCUMENTATION.md 架構、資料流、設定、測試及維護細節
Info.plist                 macOS InputMethodKit bundle 設定
```

## 開發與驗證

Repository 沒有 XCTest／UI test target、formatter、linter 或 CI。`Scripts/` 下的 tests 是以 `swiftc` 編譯執行的離線 harness；其存在只代表 test-covered，不代表任何 checkout 都已通過。

靜態 lexicon 的 source equality 驗證：

```sh
python3 Scripts/verify_static_lexicon.py
```

重新建立 lexicon 會覆寫 checked-in SQLite 及複製 notices，只有更新資料時才應執行：

```sh
python3 Scripts/build_static_lexicon.py
```

本次文件任務的實際驗證結果記錄在[技術文件的 Testing](TECHNICAL_DOCUMENTATION.md#12-testing)。release、簽署、公證、安裝及外部 runtime 驗證不屬於一般開發 validation。

## 已知限制

- SQLite runtime 與 learning-store 的 release／安裝後行為必須以本次 build 結果及後續實機測試分開判斷。
- 舊版 `UserDefaults` learning keys 沒有遷移到 SQLite 的程式；現有學習可能不會延續。
- macOS target 未啟用 App Sandbox；learning database 沒有額外加密，也沒有清除學習資料的設定 UI。
- Apple 沒有公開 macOS 內建倉頡解碼 API，碼表與候選次序不能保證完全一致。
- macOS 候選視窗最多顯示十項，沒有翻頁；候選位置與中文詞組替換依賴 host 正確實作 text-input API。
- iOS 先插入英文字碼再刪除替換；若 host 不提供足夠 context、游標已移動或文字已改變，guard 會拒絕替換。
- iOS 會在 `needsInputModeSwitchKey` 為真時提供 Globe 鍵；其在各種 device、方向與多鍵盤組合下的行為仍需實機驗證。
- iPad 寬版配置、替代符號下滑門檻與 preview 在不同裝置、方向及 app 內的視覺與操作行為仍需 Simulator／實機驗證。
- 第三方鍵盤在安全文字欄位、電話／姓名電話鍵盤或 host 禁用 extension 時會由系統鍵盤取代；本次未做 device／多 app 相容性驗證。
- `Scripts/release.sh` 的 preflight 會讀取 `HybridIME` macOS scheme 的 Debug／Release resolved build settings，並硬性要求版本 `1.2.0`、build `20260821` 與 deployment target `26.0`。這只準備 release 流程，並不代表簽署、公證或發佈已完成。
- repository 沒有自動測試 target、CI、效能量測或 memory-budget regression test。

## 授權

Repository 沒有找到 project-wide `LICENSE`，因此不能推斷 HybridIME source code 的再利用授權。

第三方資料的授權與歸屬分別位於：

- `HybridIME/CangjieData/LICENSE-Rime-Cangjie.txt` 與 `HybridIME/CangjieData/NOTICE.txt`。
- `HybridIMEKeyboard/CangjieData/LICENSE-Rime-Cangjie.txt` 與 `HybridIMEKeyboard/CangjieData/NOTICE-Rime-Cangjie.txt`，隨 iOS runtime Cangjie table 提供。
- `HybridIME/DictionaryData/LICENSE-CC-CEDICT.txt` 與 `HybridIME/DictionaryData/NOTICE-CC-CEDICT.txt`。
- `HybridIME/AssociationData/LICENSE-Rime-Essay.txt`、`HybridIME/AssociationData/NOTICE-Rime-Essay.txt` 與 `HybridIME/AssociationData/NOTICE-Tatoeba-CC0.txt`。
- `HybridIMEKeyboard/LexiconData/` 內隨 bundled SQLite 一併提供的對應 license／notice。

詳細實作請參閱 [TECHNICAL_DOCUMENTATION.md](TECHNICAL_DOCUMENTATION.md)。
