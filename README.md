# HybridIME

HybridIME 是一個 macOS 中英文混合倉頡五代輸入法。

輸入英文字母時，HybridIME 會同時把輸入內容視為英文及倉頡碼：

- 按 `Space`：一般輸出英文及一個空格；已學習的中文候選可自動選取。
- 按 `Shift + Space`：輸出英文，不附加空格。
- 按 `Return`：有候選時輸出第一候選；沒有候選時輸出英文。
- 按 `1` 至 `9`：選擇對應的中文候選字。
- 按 `0`：選擇第十個中文候選字。
- 按 `Delete`：刪除最後一個輸入字母。
- 按 `Esc`：取消目前輸入。

例如輸入 `hsp` 時，可以按 `Return` 或候選數字鍵輸出「怎」；若要輸出英文 `hsp`，則按 `Space`。

## 主要功能

- 同一組按鍵同時支援英文及倉頡五代解碼。
- 候選視窗顯示在文字插入點附近。
- 輸入期間即時顯示每個鍵位對應的倉頡字母。
- 最多顯示十個中文候選字。
- 英文輸入不受五碼限制；超過五碼後不再查詢倉頡候選。
- 根據游標前的文字自動選擇半形或全形標點。
- 標點會立即顯示，同時保留半形及全形候選。
- 支援 Unicode 擴展區漢字。
- 自動略過 macOS 無法正常顯示、只能使用 `LastResort` 字體呈現的候選字。
- 支援 macOS 相容字碼及候選次序覆寫。
- 輸入完整英文詞時顯示繁體中文翻譯候選。
- 輸入倉頡時，在中文候選後顯示對應的英文翻譯。
- Command、Control 及 Option 快捷鍵會交回目前應用程式。
- 提交中文或英文後顯示同語言的聯想候選。
- 聯想候選會按本機使用次數逐步調整排序。
- 同一字碼選擇同一候選三次後，會啟用本機智能預測。
- 英文句段中的單詞可由 Space 或標點直接提交；Return 優先選取候選。
- 大型字典及聯想索引會在背景預載，避免切換輸入法時阻塞介面。
- 左鍵按下、拖曳、放開及取消事件會完整交回目前應用程式。
- 輸入法以背景程序啟動，不會在開機後首次選用時顯示 App 視窗。

## 候選顯示

候選視窗由上至下顯示：

1. 完整字碼命中時的中文候選。
2. 目前鍵位對應的倉頡字母。
3. 實際輸入的英文字母碼。

例如輸入「碼」的完整字碼 `mrsqf`：

```text
1 碼
一口尸手火
mrsqf
```

輸入中途即使尚未有完整字碼候選，倉頡字母仍會持續更新：

```text
m     → 一
mr    → 一口
mrs   → 一口尸
mrsq  → 一口尸手
mrsqf → 一口尸手火
```

若中途字碼本身已有候選，例如 `mr`，候選列也會立即顯示。

倉頡候選會同時查詢 CC-CEDICT。每個中文候選後可顯示最多兩個較淡色的
英文翻譯，例如「測」可顯示 `survey`、`measure`。英文動詞候選會使用
詞典形式，不顯示開頭的 `to`。

若游標前已有中文，HybridIME 會優先用最長中文詞組查詢。例如先輸入
「測」，再輸入「試」的倉頡碼時，會以「測試」查詢並顯示 `test`、
`beta`。選擇英文候選會把游標前已組成的中文詞連同目前組字替換成英文。

候選排序為：

1. 精確倉頡中文候選。
2. 該中文候選的英文翻譯。
3. 已輸入英文的中文翻譯。

例如輸入 `oh`：

```text
1 入   2 conform to   3 containing   4 噢
```

其中「入」來自倉頡碼，「conform to」及「containing」是「入」的英文
翻譯，「噢」則是英文 `oh` 的中文翻譯。

標準鍵位對照：

```text
a 日  b 月  c 金  d 木  e 水  f 火  g 土
h 竹  i 戈  j 十  k 大  l 中  m 一  n 弓
o 人  p 心  q 手  r 口  s 尸  t 廿  u 山
v 女  w 田  x 難  y 卜  z 重
```

## 標點符號

HybridIME 會根據游標前的字元自動選擇標點形式：

- 英文、數字或空白後：預設半形。
- 中文字後：預設全形。

例如輸入逗號：

```text
hello,
候選：1 ,   2 ，
```

```text
你好，
候選：1 ，   2 ,
```

預設標點會立即顯示，不需要按 `Space` 或 `Return`。繼續輸入時會自動確認第一候選；按 `2` 可改用另一種形式，按 `Delete` 或 `Esc` 可取消尚未確認的標點。

此規則適用於鍵盤可輸入的 ASCII 標點及符號。逗號對應 `，`，句號對應 `。`，其他字符使用相應的全形形式。

部分符號提供額外候選：

```text
$ → $  ¥  £  €  ₹  ₺  ＄
英文後 . → .  。  ⋯⋯
中文後 . → 。  .  ⋯⋯
< → <  ＜  ⟵
> → >  ＞  ⟶
```

美元符號的次序不按語境調整；較少使用的全形 `＄` 固定排在最後。
小於、大於符號亦使用固定次序，並提供左右長箭頭候選。

在英文句段中，Space 會直接提交目前英文並加入空格，輸入標點亦會先提交
英文再處理標點。因此可直接連續輸入 `I love you!`，不需要在 `you` 與
`!` 之間額外按 Space。Return 仍優先提交第一候選，只有沒有候選時才輸出
原始英文。

若英文位於句尾或不需要尾隨空格，可使用 `Shift + Space`：

```text
hello + Space         → "hello "
hello + Shift + Space → "hello"
```

## 智能候選

HybridIME 會在本機記錄每組輸入碼實際選擇的候選。同一字碼選擇同一候選
累計三次後，該候選會成為智能預測，並在候選視窗中以 `◆` 標示。

非英文語境下按 Space 會直接提交已標示的預測候選。這項規則不計算百分比，
也不依賴前文；只根據「同一字碼 + 同一候選」的累計次數。若同一字碼有
多個候選達到門檻，會優先使用選擇次數較多、最近選過的候選。

智能學習資料只儲存在本機 `UserDefaults`，不會上傳。需要強制輸出原始
英文時，可按 `Shift + Space`。

## 系統需求

- macOS 26.5 或以上
- Xcode 26.3 或以上
- Apple Development 開發憑證

目前專案以 Apple Silicon Mac 為主要開發及測試環境。

## 建置

使用 Xcode 開啟：

```text
HybridIME.xcodeproj
```

選擇 `HybridIME` scheme 及 `My Mac` destination，然後執行 Build。

也可以使用命令列：

```sh
xcodebuild \
  -project HybridIME.xcodeproj \
  -scheme HybridIME \
  -configuration Debug \
  -derivedDataPath /tmp/HybridIMETraditionalDerivedData \
  -allowProvisioningUpdates \
  build
```

建置成品位於：

```text
/tmp/HybridIMETraditionalDerivedData/Build/Products/Debug/HybridIME.app
```

## 安裝

1. 將 `HybridIME.app` 放入：

   ```text
   ~/Library/Input Methods/
   ```

2. 登出並重新登入 macOS。開發期間重新註冊輸入來源後，通常不需要再次登出。
3. 前往「系統設定 > 鍵盤 > 文字輸入 > 編輯」。
4. 按 `+`，在「繁體中文」分類加入「中英混合」。
5. 從選單列的輸入法選單切換至「中英混合」。

HybridIME 啟動時不會自行註冊或啟用輸入來源。安裝或更新後只需由 macOS 加入一次；日常由系統啟動輸入法時，不會再次要求允許「中英混合」啟用自己。

HybridIME 直接建立 `NSApplication` 及 `IMKServer`，不建立一般 App 視窗。
重新開機後首次選擇「中英混合」時，輸入法只會在背景啟動。

開發期間若要停止 HybridIME，應先切換至其他輸入法，再執行：

```sh
pkill -x HybridIME
```

若「中英混合」仍是目前使用中的輸入法，macOS 可能會自動重新啟動其程序。

## 倉頡碼表

HybridIME 依次載入：

1. `cangjie5.base.dict.yaml`：一般及較常用的倉頡五代單字。
2. `cangjie5.extended.dict.yaml`：罕用字、異體字、相容漢字及 Unicode CJK 擴展區漢字。

基礎碼表先載入，因此同一倉頡碼下的基礎候選通常優先顯示。重複候選會被移除。

## Rime 來源

- [Rime 專案首頁](https://github.com/rime/home)：Rime 的介紹、文件及各子專案入口。
- [Rime 倉頡方案](https://github.com/rime/rime-cangjie)：HybridIME 所使用的倉頡五代方案及 `.dict.yaml` 原始碼表。

`rime/home` 並不直接存放上述倉頡碼表。查詢碼表內容、修改紀錄及最新版本時，應以 `rime/rime-cangjie` repository 為準。

## macOS 相容規則

Rime 倉頡五代與 macOS 內建倉頡在部分字碼及候選次序上可能不同。HybridIME 使用：

```text
HybridIME/CangjieData/macOS-overrides.tsv
```

集中記錄已確認的相容修正，而不直接修改上游 Rime 碼表。

目前相容層亦把「面」由 Rime 的 `mwsl` 調整為 macOS 倉頡碼 `mwyl`。

## 中英雙向字典

HybridIME 使用 [CC-CEDICT](https://cc-cedict.org/wiki/) 建立獨立的中英
雙向索引。輸入完整英文詞時，中文翻譯會排在倉頡候選之前，例如輸入
`test` 可選擇「測試」。按 Space 仍然輸出原本英文，不會自動翻譯。

輸入倉頡碼時，每個中文候選後會加入其英文翻譯候選。系統亦會結合游標前
的連續中文，優先查詢最長詞組；選擇英文候選時會以英文替換該中文詞組。

`HybridIME/DictionaryData/dictionary-overrides.tsv` 可把已確認的翻譯候選
移至最前，這些本地排序不會在重新生成 CC-CEDICT 索引時被覆蓋。
覆寫亦可使用 `replace-e` 或 `replace-z` 完全取代指定方向的候選。

## 應用程式快捷鍵

包含 Command、Control 或 Option 的按鍵組合不由 HybridIME 處理，會直接
交回目前應用程式。因此 `⌘C`、`⌘V`、`⌘X`、`⌘A`、`⌘Z`、`⌘S`、
`⌘W` 等快捷鍵可正常使用。Shift 仍用於輸入英文大寫。

HybridIME 亦會明確接收並透傳完整的左鍵按下、拖曳、放開及取消事件，
避免 InputMethodKit 的預設 mouse down 組字處理干擾 Google Sheets 等
網頁文字客戶端的 cell 點擊與拖曳選取。

## 中英文聯想

提交中文後，HybridIME 會根據最後的中文詞語顯示中文聯想。例如提交
「測」後可顯示：

```text
1 試   2 量   3 評   4 定
```

選擇「試」後，會以「測試」繼續顯示：

```text
1 用例   2 人員   3 工程師   4 開發   5 結果
```

英文聯想在按 Space 提交英文後出現。例如輸入 `thank` 並按 Space，可顯示
`you`、`god`、`for` 等候選。選擇英文聯想後會自動加入空格並繼續聯想。

- 按 `Return` 或數字鍵選擇聯想。
- 按 `Esc` 關閉聯想。
- 開始輸入新字時，聯想視窗會收起並進入正常組字。
- 標點、Delete、移動游標或應用程式快捷鍵會清除聯想上下文。
- 使用者選過的聯想會只在本機透過 `UserDefaults` 累計，提高日後排序。
- 輸入內容及學習資料不會上傳。

中文聯想資料由
[Rime Essay](https://github.com/rime/rime-essay) 的詞彙及權重生成。英文
聯想只使用 [Tatoeba](https://tatoeba.org/en/downloads) 的英文 CC0
句子子集生成相鄰詞統計。

重新生成：

```sh
swift Scripts/build_chinese_associations.swift \
  /path/to/essay.txt \
  HybridIME/AssociationData/chinese-associations.tsv

swift Scripts/build_english_associations.swift \
  /path/to/eng_sentences_CC0.tsv \
  HybridIME/AssociationData/english-associations.tsv
```

更新字典時，從
[MDBG CC-CEDICT 下載頁](https://www.mdbg.net/chinese/dictionary?page=cc-cedict)
取得最新資料，再執行：

```sh
swift Scripts/build_cedict_index.swift \
  /path/to/cedict_ts.u8 \
  HybridIME/DictionaryData/cedict-index.tsv
```

## 已知限制

- Apple 沒有提供公開 API 讀取或調用 macOS 內建倉頡碼表。
- HybridIME 不能保證所有字碼及候選次序均與 macOS 內建倉頡完全相同。
- 候選相容性需要按已確認的差異逐步補充。

詳細架構、資料格式及維護方法請參閱
[TECHNICAL_DOCUMENTATION.md](TECHNICAL_DOCUMENTATION.md)。

## 授權

應用程式程式碼及第三方碼表可能使用不同授權。Rime 倉頡碼表的授權及來源聲明請參閱：

- `HybridIME/CangjieData/LICENSE-Rime-Cangjie.txt`
- `HybridIME/CangjieData/NOTICE.txt`
- `HybridIME/DictionaryData/LICENSE-CC-CEDICT.txt`
- `HybridIME/DictionaryData/NOTICE-CC-CEDICT.txt`
- `HybridIME/AssociationData/LICENSE-Rime-Essay.txt`
- `HybridIME/AssociationData/NOTICE-Rime-Essay.txt`
- `HybridIME/AssociationData/NOTICE-Tatoeba-CC0.txt`
