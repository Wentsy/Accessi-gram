# Accessi Gram Native — Telegram 原生無障礙客戶端

這是從零開發、**不依賴 Turrit IPA 或注入補丁**的獨立 iOS Telegram 客戶端。使用 Telegram 官方 TDLib 協定庫和 UIKit / SwiftUI。舊版補丁及 main 保持不變。

## 核心設計

- VoiceOver 訊息以一則為一個焦點，讀取順序：發送者、訊息內容、發送時間。
- 全聊天室、群組、頻道共用同一個 UITableView 歷史訊息元件。接近上緣即預載歷史，增量插入資料並補償捲動偏移，**不重新載入整張列表、不強制將 VoiceOver 焦點送到輸入框**。
- 每則訊息具有 VoiceOver 自訂動作：翻譯成繁體中文、回覆、複製、轉寄、刪除、機器人按鈕等。翻譯結果透過 VoiceOver announcement 直接朗讀。
- 基礎功能：手機號碼 / 驗證碼 / 二階段密碼 / QR 登入、聊天室和搜尋、訊息送收、錄製與播放語音、照片與影片上傳與預覽、附件、機器人 inline/reply keyboard、封存、置頂、標記未讀、刪除對話、基本設定。
- 翻譯使用 Google Translate 免費網頁端點 `translate.googleapis.com`（**非正式、無 SLA、未保證長期可用**）；僅在使用者主動選擇翻譯時送出文字。機密或秘密聊天翻譯會將該則文字傳至第三方。
- 本專案依賴 TDLibFramework 預編譯 XCFramework；API ID / Hash 由使用者在首次啟動輸入，以鑰匙圈儲存，不放進原始碼。

## OC / Xcode 打包

在 macOS 安裝 Xcode 及 XcodeGen。進入 `NativeTelegram` 目錄執行：

```bash
bash scripts/build.sh
```

產出 `dist/AccessiGramNative-unsigned.ipa`。OC 以自己的簽名流程簽署整個 app（含 Framework）。也可以先用 `xcodegen generate` 建立 Xcode 專案，指定自己的開發團隊進行編譯。專案目標 iOS 16+。

需要先從 [Telegram API Development Tools](https://my.telegram.org) 取得自己的 `api_id` 與 `api_hash`；不能直接使用 TDLib 示例中的共用金鑰作為發佈版。使用者只在裝置上輸入一次。

## 目前限制

此分支為第一個完整架構實作提交，**尚未由 macOS / Xcode 真機編譯或 Telegram 帳號驗證，不能當已確認可安裝穩定版**。OC 應從此分支接續處理編譯、API 差異和裝置端回報。通話、推播註冊、故事、貼圖商店、完整管理員工具、付款及加密通話不在本版範圍；訊息及媒體、聊天與翻頁為優先。
