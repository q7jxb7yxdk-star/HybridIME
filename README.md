# HybridIME

HybridIME 是一個 macOS 中英文混合倉頡五代輸入法。

輸入英文字母時，HybridIME 會同時把輸入內容視為英文及倉頡碼：

- 按 `Space`：輸出英文及一個空格。
- 按 `Return`：輸出第一個中文候選字。
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
