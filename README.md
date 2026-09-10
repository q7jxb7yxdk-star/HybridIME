# HybridIME

HybridIME 是一套以 Swift 開發的中英混合倉頡五代輸入工具，同一個 Xcode 專案目前包含：

- macOS InputMethodKit 輸入法 `HybridIME`。
- iOS／iPadOS 主程式 `HybridIMEiOS`。
- 嵌入主程式的自訂鍵盤延伸功能 `HybridIMEKeyboard`。

輸入英文字母時，兩個輸入法都會同時把內容視為英文與倉頡碼，並提供倉頡字、雙向翻譯、聯想與本機智能候選。所有執行期詞典均隨應用程式離線提供；原始碼中沒有網路 API、帳戶、遙測或雲端同步路徑。

> 狀態說明：本文件以目前 Git 工作樹為準。「已實作」表示原始碼已接入正常路徑，不等同已在本次任務完成實機驗證；實際驗證結果見[開發與驗證](#開發與驗證)。

## 功能

### 共同功能（已實作）

- 倉頡五代單字解碼，最多五碼；超過五碼仍可輸入英文。
- 以 Core Text 過濾目前系統字型無法正常顯示的候選字。
- CC-CEDICT 英文至繁體中文候選，以及倉頡中文至英文翻譯。
- 以游標前的連續中文做最長詞組翻譯查詢。
- 中英文聯想候選與連續中文學習。
- 依最近選擇提升智能候選；學習資料只寫入本機 SQLite。
- 依中文／英文前文選擇全形或半形標點，並提供替代標點候選。
- 以隨附的唯讀 SQLite 詞庫查詢倉頡、雙語與聯想資料。

### macOS（已實作）

- 傳統 InputMethodKit `.app`，以背景程序建立 `IMKServer`。
- 在文字插入點附近顯示不搶焦點的候選視窗。
- ASCII 字母會立即插入宿主應用程式；輸入法追蹤該文字範圍，以便候選選取時安全替換。
- `Space` 輸出英文及空格；若第一項是已學習的中文候選則提交中文。
- `Shift + Space` 輸出原始英文、不附加空格，並記錄該選擇。
- `1`–`0` 選取候選區的對應項目；沒有對應候選時，數字會交回宿主應用程式。
- `Return` 不選取候選，而是結束目前英文組字並交回宿主應用程式處理。
- Safari URL 欄的自動完成尾段不會截斷輸入碼；選取候選時會連同該尾段一起安全替換。
- 未選取候選的直接英文使用半形標點；只有實際提交中文字後，後續標點才依中文上下文選用全形。
- Command、Control、Option、滑鼠及系統輸入事件交回目前應用程式。

### iOS／iPadOS（已實作，已進行有限執行期驗證）

- UIKit 自訂鍵盤，包含字母、數字與符號頁面。
- 按住倉頡字根、數字或符號鍵時顯示原生式放大鍵帽；字根鍵帽同時呈現倉頡碼與英文字母，iPhone 橫向改為左右排列。
- iPad 在水平尺寸類別為 `regular` 且鍵盤寬度至少 700 點時使用 11 格寬版配置；扣除 iPadOS 額外提供的約 75 點系統輸入輔助列後，自訂內容在縱向使用 265 點、橫向使用 353 點，使整體可見高度分別貼近原生倉頡鍵盤的 340 點與 428 點。寬版的字母、數字與符號列以 50 點按鍵高度基準及同一字母鍵格位排版；Delete、Return、右 Shift 為 1.25 格，左 Shift、逗號與句號為一格，第二列採半格縮排及尾端補償。非寬版或浮動 iPad 的緊湊配置維持 260 點。
- iPhone 縱向使用按同裝置最新截圖差值校準的 242 點自訂內容高度。橫向時沿用緊湊版的 QWERTY、Shift、Delete 與底列位置，按鍵隨可用寬度成為橫向比例；字母鍵以左側倉頡字根、右側英文字母顯示，並使用 187 點自訂內容高度。這兩個方向連同系統管理區後，整體可見高度分別貼近原生倉頡鍵盤的 335 點與 207 點。Shift／Delete、頁面鍵及 Return 依方向使用從原生倉頡截圖量度的寬度。
- 寬版數字符號鍵同時顯示主要與替代符號；向下滑動至少 12 點且垂直位移大於水平位移時，會顯示替代符號預覽並輸入替代符號。
- 候選列、倉頡字根提示、大小寫與 Caps Lock。
- 候選列固定保留在鍵盤總高度之內；iPhone 縱向、iPhone 橫向及 iPad 寬版均由四列按鍵在剩餘高度內平均分配，空間不足時由按鍵列垂直壓縮，不因候選內容把鍵盤根視圖向上撐高。
- 點按已學習候選、翻譯、標點或聯想候選時替換已插入文字。
- 點按 Delete 刪除一個字元；長按 0.35 秒後會連續刪除，放開時停止。
- 在沒有組字時連按兩次 Space，第二擊會將第一個由鍵盤插入且仍位於游標前的空格換成句點；最近實際提交的非空白字元為中文時輸出 `。`，英文或無法判定時輸出 `.`，不保留空格。
- 長按 Space 後水平／垂直拖曳游標，並提供選取回饋。
- 延伸功能宣告 `RequestsOpenAccess=false`，離線詞典及學習不需要「允許完整取用」。
- 為降低 Xcode 覆蓋安裝或系統重載已啟用鍵盤時的啟動工作，倉頡 decoder 與唯讀詞典會延後至首次輸入英文字母才建立；extension 消失時會清除暫存組字狀態。
- 緊湊版面只在 `needsInputModeSwitchKey` 要求時顯示自訂地球鍵，並使用 `handleInputModeList(from:with:)` 切換或長按選擇已啟用鍵盤；Face ID iPhone 已由系統在鍵盤下方提供地球鍵時不會重複顯示。
- iPhone 沒有自訂地球鍵時，底列為 `123／ABC`、`,`、填滿可用寬度的 Space、`.`、Return；左右控制鍵等寬，Space 位於中間。Return 一律顯示向左折返箭頭圖示；有自訂地球鍵時保留既有 fallback 底列。
- 控制器明確設定 `hasDictationKey=false`，不宣告自訂聽寫鍵，讓 iOS／iPadOS 在允許時管理及顯示系統咪高峰；實際顯示仍取決於系統聽寫設定、裝置、版面及目前 App。
- 鍵盤根視圖保持透明，沿用 iOS 管理的鍵盤背景材質，讓內容區與系統地球／咪高峰區視覺一致。
- 鍵盤按鍵不強制採用個別宿主文字欄的 `keyboardAppearance`，而是繼承 iOS 提供給鍵盤 extension 的 Light／Dark trait，並在系統外觀切換時更新按鍵 configuration，避免同一系統外觀下因 App 而出現與原生鍵盤不同的鍵色。Dark 使用近黑面板與深灰鍵面，Light 使用淺灰面板、白色字元鍵與較深控制鍵；這些是以公開 UIKit 動態色彩貼近原生鍵盤的實作，並非私有系統材質。
- SwiftUI 主程式提供加入與使用鍵盤、離線本機學習及第三方鍵盤系統限制的說明。
- `HybridIMEKeyboard/PrivacyInfo.xcprivacy` 宣告不追蹤、不收集資料，以及 Shift 雙擊計時所需的 `SystemBootTime` 原因 `35F9.1`。

## 系統需求

| 項目 | 儲存庫宣告 |
| --- | --- |
| macOS 部署目標 | `26.0` |
| iOS／iPadOS 部署目標 | `26.0` |
| Swift 語言版本 | 建置設定為 `5.0` |
| Xcode | 沒有工具版本檔或 CI 明確宣告最低版本；專案中繼資料由 Xcode 26.5／26.6 建立或更新，需使用能讀取 `object version 77` 並提供 SDK 26 的 Xcode |
| 第三方套件 | 無 Swift Package、CocoaPods、Carthage、npm 或其他套件資訊清單／鎖定檔 |

應用程式執行期使用 Apple 平台框架：AppKit、InputMethodKit、UIKit、SwiftUI、Foundation、CoreText 與系統 SQLite3。

macOS 日常開發建置可停用程式碼簽署；要安裝並實際啟用輸入法，需有效的本機開發簽署。iOS 真機執行亦需使用自己的 Apple Development 團隊。專案目前含有擁有者專用的團隊設定，其他開發者應在 Xcode 的 Signing & Capabilities 選擇自己的團隊，不應沿用儲存庫中的值作為憑證。

## 取得與開啟專案

```sh
git clone <repository-url>
cd HybridIME
open HybridIME.xcodeproj
```

儲存庫不需要另外安裝套件相依項目，也沒有環境設定檔或執行期 API 金鑰。

Xcode 中可使用以下 scheme：

- `HybridIME`：macOS 輸入法。
- `HybridIMEiOS`：iOS／iPadOS 主程式，會同時建置並嵌入鍵盤延伸功能。
- `HybridIMEKeyboard`：獨立建置鍵盤延伸功能；通常由主程式的 scheme 驅動。

## 建置與執行

### macOS

在 Xcode 選擇 `HybridIME` scheme 與 `My Mac`。不簽署的命令列建置：

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

要使用輸入法，需把已適當簽署的 `HybridIME.app` 放入 `~/Library/Input Methods/`，再從「系統設定 > 鍵盤 > 文字輸入」加入「中英混合輸入法」。建置成功只證明產物可建立，不證明已安裝的應用程式、LaunchServices 註冊或 InputMethodKit 端點正常。

若已安裝版本出現「已選取但沒有輸入反應」，請先檢查 `~/Library/Logs/DiagnosticReports/` 是否有新的 `HybridIME-*.ips`，再參閱[技術文件的 InputMethodKit 診斷](TECHNICAL_DOCUMENTATION.md#macos-inputmethodkit-生命週期)，檢查註冊與 XPC endpoint。

macOS 控制器會以 `IMKTextInput.insertText` 直接插入並自行追蹤可替換範圍，不以 InputMethodKit marked text 保存字母組字。狀態清理不會呼叫 `updateComposition()`；`composedString(_:)` 只保留作為 InputMethodKit 協定介面，並明確回傳 `NSString`。

### iOS／iPadOS

在 Xcode 選擇 `HybridIMEiOS` scheme 與模擬器或已簽署的裝置。模擬器命令列建置：

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

安裝主程式後，前往「設定 > 一般 > 鍵盤 > 鍵盤 > 新增鍵盤」，選擇 `HybridIMEKeyboard`。若 HybridIME 底列顯示地球鍵，點按可切換鍵盤，長按可選擇已啟用的鍵盤；Face ID iPhone 則可使用鍵盤下方由系統提供的地球鍵。

## 基本輸入方式

macOS 輸入 `vnd` 時會立即在宿主應用程式顯示該字母，候選區顯示 `1 好`；按 `1` 會把已輸入字母替換成「好」。`Return` 不會選取候選，而會交回宿主執行換行、送出或前往網址等原有動作。未選候選的 `www.` 保持英文及半形句點；候選區即使存在中文字，也不會自行改變英文或標點。iOS 同樣會先透過 `UITextDocumentProxy` 把鍵入字母插入宿主應用程式，點選候選後再刪除該字碼並插入候選。

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
HybridIME/                 macOS InputMethodKit 建置目標與可更新的字典／聯想來源 TSV
HybridIMEKeyboard/         iOS 自訂鍵盤、兩平台共用的隨附 SQLite 詞庫及鍵盤資源
HybridIMEiOS/              iOS／iPadOS 主程式與設定說明介面
HybridIME.xcodeproj/       建置目標、建置設定與 schemes
Scripts/                   資料生成、SQLite 驗證、獨立測試及發佈工具
README.md                  開發者入口與執行方式
TECHNICAL_DOCUMENTATION.md 架構、資料流、設定、測試及維護細節
Info.plist                 macOS InputMethodKit 套件設定
```

## 開發與驗證

儲存庫沒有 XCTest／UI 測試建置目標、格式化工具、程式碼檢查工具或 CI。`Scripts/` 下的測試是以 `swiftc` 編譯執行的離線測試工具；其存在只代表相關範圍已有測試，不代表任何版本的工作樹都已通過。

靜態詞庫的一致性驗證會以唯讀方式開啟 SQLite，將雙語與聯想資料逐列比對其來源；`cangjie` 是固定的 SQLite canonical source，不會由工具重建：

```sh
swiftc -parse-as-library -module-cache-path /tmp/hybridime-module-cache-verify \
  Scripts/verify_static_lexicon.swift -lsqlite3 -o /tmp/hybridime-verify-static
/tmp/hybridime-verify-static
```

更新器只會在單一 SQLite transaction 中重新寫入 `association` 與 `bilingual`，並更新 `LexiconData` 的授權／聲明；它會在開始前驗證固定的 `cangjie` 表，絕不 drop、重建或修改它：

```sh
swiftc -parse-as-library -module-cache-path /tmp/hybridime-module-cache-update \
  Scripts/update_static_lexicon.swift -lsqlite3 -o /tmp/hybridime-update-static
/tmp/hybridime-update-static
```

實際驗證結果記錄在[技術文件的測試章節](TECHNICAL_DOCUMENTATION.md#12-測試)。本機 Developer ID 簽署與 macOS 安裝驗證會和一般建置、真實文字輸入、公證及發佈結果分開記錄。

## 已知限制

- SQLite 執行期與學習資料庫的發佈／安裝後行為必須以本次建置結果及後續實機測試分開判斷。
- 舊版 `UserDefaults` 學習鍵值沒有遷移到 SQLite 的程式；現有學習可能不會延續。
- macOS 建置目標未啟用 App Sandbox；學習資料庫沒有額外加密，也沒有清除學習資料的設定介面。
- Apple 沒有公開 macOS 內建倉頡解碼 API，碼表與候選次序不能保證完全一致。
- macOS 候選視窗最多顯示十項，沒有翻頁；候選位置與中文詞組替換依賴宿主應用程式正確實作文字輸入 API。
- iOS 先插入英文字碼再刪除替換；若宿主應用程式不提供足夠前後文、游標已移動或文字已改變，防護條件會拒絕替換。
- iOS 緊湊版面依 `needsInputModeSwitchKey` 決定是否提供自訂地球鍵；系統地球鍵與自訂地球鍵在各種裝置、方向及多鍵盤組合下的實際顯示仍需持續實機驗證。
- 已啟用 HybridIME 時以 Xcode 覆蓋安裝後的 keyboard extension 終止／重載行為尚未完成實機驗證；應以 `HybridIMEKeyboard`、`keyboardd` 與 `extensionkitd` 的 crash／Console 診斷，分辨系統重載與延伸功能問題。
- iPhone 在本次量度裝置上使用縱向 242 點、橫向 187 點自訂內容高度；這些值來自同一裝置與宿主 App 的 HybridIME／Apple 內建倉頡截圖差值，無公開 API 可讀取或保證在其他裝置及宿主 App 同步原生高度，其按鍵比例、字根／英文標籤與地球鍵仍需實機驗證。
- iPad 寬版配置、原生式按鍵格線、Light／Dark 外觀、替代符號下滑門檻與預覽在不同裝置、方向及應用程式內的視覺與操作行為仍需模擬器／實機驗證。
- 第三方鍵盤在安全文字欄位、電話／姓名電話鍵盤或宿主應用程式禁用延伸功能時會由系統鍵盤取代；本次未做裝置／多應用程式相容性驗證。
- `Scripts/release.sh` 的前置檢查會讀取 `HybridIME` macOS scheme 的 Debug／Release 已解析建置設定，並硬性要求版本 `1.3.0`、組建編號 `20260908` 與部署目標 `26.0`。這只準備發佈流程，並不代表簽署、公證或發佈已完成。
- 儲存庫沒有自動測試建置目標、CI、效能量測或記憶體預算迴歸測試。

## 授權

儲存庫沒有找到涵蓋整個專案的 `LICENSE`，因此不能推斷 HybridIME 原始碼的再利用授權。

第三方資料的授權與歸屬分別位於：

- `HybridIME/CangjieData/LICENSE-Rime-Cangjie.txt` 與 `HybridIME/CangjieData/NOTICE.txt`。
- `HybridIME/DictionaryData/LICENSE-CC-CEDICT.txt` 與 `HybridIME/DictionaryData/NOTICE-CC-CEDICT.txt`。
- `HybridIME/AssociationData/LICENSE-Rime-Essay.txt`、`HybridIME/AssociationData/NOTICE-Rime-Essay.txt` 與 `HybridIME/AssociationData/NOTICE-Tatoeba-CC0.txt`。
- `HybridIMEKeyboard/LexiconData/` 內隨附 SQLite 一併提供 Rime Cangjie、CC-CEDICT、Rime Essay 與 Tatoeba 的對應授權／聲明文件。

詳細實作請參閱 [TECHNICAL_DOCUMENTATION.md](TECHNICAL_DOCUMENTATION.md)。
