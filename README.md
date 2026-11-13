# Accessi gram

以使用者提供的 Turrit 1.5.5（10387）IPA 為基礎的 VoiceOver 補丁。
目前為 **0.1.0 實驗版，尚未完成 iPhone 旁白實測**，不是穩定基準。

## 這版實作

- 新式底部分頁：提供有名稱、未讀數及選取狀態的旁白元素，雙擊呼叫原本的分頁切換動作；不模擬座標點擊。
- 舊式底部分頁：修正無障礙框的螢幕座標。
- 自訂導覽按鈕：補上按鈕語意及雙擊啟動；雙指 Z 字返回使用既有返回處理，沒有處理時才交給 navigation controller。
- 分享對象：讀出對象文字與選取狀態，雙擊執行原本選取操作；主程式與分享 extension 都載入補丁。
- 聊天：第一次開啟、訊息實際載入後，呼叫原本向下導覽動作；增加「跳到最新訊息」旁白自訂動作。手動三指捲動會取消尚未執行的自動跳轉。
- 對話閱讀順序：使用可見訊息的螢幕位置排序，保留原訊息的無障礙容器、內容與動作，避免每次重建訊息元素。

三指翻頁沿用 Telegram ListView 本身對倒置清單、載入歷史與 pageScrolled 通知的處理；這版沒有重寫它的網路分頁機制。網路慢時的連續朗讀、送出按鈕與附件選單所有分支，目前不能宣稱已全面修復。

## 編譯與打包

macOS + Xcode：

```sh
bash scripts/build.sh
python3 scripts/package.py Turrit_1.5.5_78c.ipa build/AccessiGram.dylib Accessi-gram-0.1.0-unsigned.ipa
```

也可至 Actions 的 **Build Accessi gram** 下載已編譯補丁。
打包器只接受此次提供的原始 IPA（SHA-256 見 `docs/BASELINE.md`），會同步注入主程式和分享 extension。
產物尚未簽名，需要原本使用的 iOS 簽名流程對主程式、frameworks、動態庫與 extensions 重新簽名。保留原 bundle identifiers/app groups 的對應；只更改桌面名稱，不能直接使用 ZIP 內已失效的舊簽章安裝。

原始 IPA 與其中的第三方套件不存入 Git 原始碼歷史。此 repo 包含本專案新增的補丁、打包器、編譯流程與交接資料。

## 給接手的 Open Code

先讀 `docs/BASELINE.md` 和 `docs/HANDOFF.md`。不要直接把 0.1.0 標成穩定版，也不要依 Swift 欄位的固定記憶體偏移修改資料。
