# Accessi gram

以使用者提供的 Turrit 1.5.5（10387）IPA 為基礎的 VoiceOver 補丁。
目前為 **0.2.1**。

## 這版實作

- 全域返回與關閉：補上 Telegram 自訂導覽控制項、全螢幕媒體、瀏覽器、分享與彈窗的按鈕語意及雙指 Z 字處理。
- 底部焦點：依畫面座標排除底部標籤和聊天輸入列後方的列表項目。
- 聊天翻頁：依照旁白目前聚焦的訊息與閱讀方向，提前捲動原生歷史列表並預載相鄰訊息，保留目前焦點。做法參考 [Accessibilibili 評論區](https://github.com/Wentsy/Accessibilibili/blob/374eb10/lib/pages/common/a11y/reply_pagination.dart)。
- 訊息動作：沿用原本的回覆及訊息選單。複製、轉發和刪除使用原生選單提供的對應動作。
- 輸入列與面板：附件、表情、貼圖、鍵盤與錄製模式有各自的旁白標籤。面板開啟時隔離後方焦點。

## 編譯與打包

macOS + Xcode：

```sh
bash scripts/build.sh
python3 scripts/package.py Turrit_1.5.5_78c.ipa build/AccessiGram.dylib Accessi-gram-0.2.1-unsigned.ipa
```

也可至 Actions 的 **Build Accessi gram** 下載已編譯補丁。
打包器只接受此次提供的原始 IPA（SHA-256 見 `docs/BASELINE.md`），會同步注入主程式和分享 extension。
產物尚未簽名，需要原本使用的 iOS 簽名流程對主程式、frameworks、動態庫與 extensions 重新簽名。保留原 bundle identifiers/app groups 的對應；只更改桌面名稱，不能直接使用 ZIP 內已失效的舊簽章安裝。

原始 IPA 與其中的第三方套件不存入 Git 原始碼歷史。此 repo 包含本專案新增的補丁、打包器、編譯流程與交接資料。

## 給接手的 Open Code

先讀 `docs/BASELINE.md` 和 `docs/HANDOFF.md`。不要直接把 0.2.1 標成穩定版，也不要依 Swift 欄位的固定記憶體偏移修改資料。
