# Accessi gram

以使用者提供的 Turrit 1.5.5（10387）IPA 為基礎的 VoiceOver 補丁。
目前為 **0.2.6**。

## 0.2.6 本次調整

- 對話列表不再提供虛擬「載入較早／較新的訊息」焦點，改為靠近頂／底部前預先呈現前後聊天訊息。
- 不再把捲動容器的無障礙子樹整個隱藏，並排除無內容的訊息佔位焦點。
- 為 Telegram 自訂確認視窗和動作選單提供標籤、按鈕語意、點擊功能，讓刪除確認／取消不依賴螢幕識別。
- 保留原生聊天分頁載入，VoiceOver 捲動通知只在實際完成後發送。

## 這版實作

- 全域返回與關閉：補上 Telegram 自訂導覽控制項、全螢幕媒體、瀏覽器、分享與彈窗的按鈕語意及雙指 Z 字處理。
- 底部焦點：依畫面座標排除底部標籤和聊天輸入列後方的列表項目。
- 聊天翻頁：依照 [Accessibilibili 評論區](https://github.com/Wentsy/Accessibilibili/blob/374eb10/ios/Runner/SceneDelegate.swift) 的模式串接相鄰訊息，透過原生聊天列表顯示下一則與載入歷史。只有完成旁白翻頁時發出捲動完成通知。
- 群組與頻道：長貼文將圖片描述和文字放在同一個旁白焦點，翻頁完成後銜接相鄰訊息。頂端置頂欄與底端頻道操作列會從訊息可讀範圍扣除。
- 訊息動作：沿用原本的回覆及訊息選單。複製、轉發和刪除使用原生選單提供的對應動作。
- 輸入列與面板：附件、表情、貼圖、鍵盤與錄製模式有各自的旁白標籤。面板開啟時隔離後方焦點。

## 編譯與打包

macOS + Xcode：

```sh
bash scripts/build.sh
python3 scripts/package.py Turrit_1.5.5_78c.ipa build/AccessiGram.dylib Accessi-gram-0.2.6-unsigned.ipa
```

也可至 Actions 的 **Build Accessi gram** 下載已編譯補丁。
打包器只接受此次提供的原始 IPA（SHA-256 見 `docs/BASELINE.md`），會同步注入主程式和分享 extension。
產物尚未簽名，需要原本使用的 iOS 簽名流程對主程式、frameworks、動態庫與 extensions 重新簽名。保留原 bundle identifiers/app groups 的對應；只更改桌面名稱，不能直接使用 ZIP 內已失效的舊簽章安裝。

原始 IPA 與其中的第三方套件不存入 Git 原始碼歷史。此 repo 包含本專案新增的補丁、打包器、編譯流程與交接資料。

## 給接手的 Open Code

先讀 `docs/BASELINE.md` 和 `docs/HANDOFF.md`。不要直接把 0.2.6 標成穩定版，也不要依 Swift 欄位的固定記憶體偏移修改資料。
