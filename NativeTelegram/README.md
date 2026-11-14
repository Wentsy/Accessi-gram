# Accessi Gram Native — Telegram 原生無障礙客戶端

這是從零開發、**不依賴 Turrit IPA 或注入補丁**的獨立 iOS Telegram 客戶端。使用 Telegram 官方 TDLib 協定庫和 UIKit / SwiftUI。舊版補丁及 main 保持不變。

## 核心設計

- VoiceOver 訊息以一則為一個焦點，讀取順序：發送者、訊息內容、發送時間。
- 全聊天室、群組、頻道共用同一個 UITableView 歷史訊息元件。接近上緣即預載歷史，增量插入資料並補償捲動偏移，**不重新載入整張列表、不強制將 VoiceOver 焦點送到輸入框**。
- 每則訊息具有 VoiceOver 自訂動作：翻譯成繁體中文、回覆、複製、轉寄、刪除、機器人按鈕等。翻譯結果透過 VoiceOver announcement 直接朗讀。
- 基礎功能：手機號碼 / 驗證碼 / 二階段密碼 / QR 登入、聊天室和搜尋、訊息送收、錄製與播放語音、照片與影片上傳與預覽、附件、機器人 inline/reply keyboard、封存、置頂、標記未讀、刪除對話、基本設定。
- 翻譯使用 Google Translate 免費網頁端點 `translate.googleapis.com`（**非正式、無 SLA、未保證長期可用**）；僅在使用者主動選擇翻譯時送出文字。機密或秘密聊天翻譯會將該則文字傳至第三方。
- 本專案依賴 TDLibFramework 預編譯 XCFramework；API ID / Hash 可由使用者首次啟動輸入，或 OC 在打包時透過私有環境變數注入，首次讀取後存入 Keychain，避免將金鑰放到公開原始碼。

## OC / Xcode 打包

在 macOS 安裝 Xcode 及 XcodeGen。進入 `NativeTelegram` 目錄執行：

```bash
bash scripts/build.sh
# 若 OC 希望預置 API：
# TELEGRAM_API_ID="$MY_TG_API_ID" TELEGRAM_API_HASH="$MY_TG_API_HASH" bash scripts/build.sh
```

產出 `dist/AccessiGramNative-unsigned.ipa`。OC 以自己的簽名流程簽署整個 app（含 Framework）。也可以先用 `xcodegen generate` 建立 Xcode 專案，指定自己的開發團隊進行編譯。專案目標 iOS 16+。

需要先從 [Telegram API Development Tools](https://my.telegram.org) 取得自己的 `api_id` 與 `api_hash`；不能直接使用 TDLib 示例中的共用金鑰作為發佈版。若 OC 曾把自己的金鑰直接寫在原始碼，建議改用建置時私有環境變數注入。

## 目前限制

使用者已回報前一版可以成功登入，但聊天室列表空白與 VoiceOver 朗讀異常，因此本分支加入**TDLib 64 位元字串解析、完整聊天分批同步，以及原生 UIKit 聊天列表／設定／聯絡人無障礙介面**。此修正尚未由 OC 重新編譯／實機驗證，不能當已確認穩定版。詳見 `docs/OC_HANDOFF.md`。通話、推播註冊、故事、貼圖商店、完整管理員工具、付款及加密通話不在本版範圍；訊息及媒體、聊天與翻頁為優先。
