# Accessi Gram Native — Telegram 原生無障礙客戶端

這是從零開發、**不依賴 Turrit IPA 或注入補丁**的獨立 iOS Telegram 客戶端。使用 Telegram 官方 TDLib 協定庫和 UIKit / SwiftUI。舊版補丁及 main 保持不變。

## 核心設計

- VoiceOver 訊息以一則為一個焦點，讀取順序：發送者、訊息內容、發送時間。
- 聊天輸入列採原生 UITextView＋UIKit 按鈕，文字編輯框、照片／檔案、語音錄製／停止傳送／取消都有明確的繁體中文旁白標籤。
- 設定頁只提供可執行操作，固定的朗讀順序、翻頁與翻譯說明移到獨立的「使用指南」。
- 已修正 TDLib 1.8.70 附件資料格式；照片、影片、錄音及一般文件均會先建立符合 API 的封裝後傳送，檔案提供者的連結會先複製到本機。
- App 前景接收到新訊息時提供震動提醒，可在設定中開關；同步舊訊息與自己發送不觸發。
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

使用者已回報前一版可以成功登入，但聊天室列表空白與 VoiceOver 朗讀異常，因此本分支加入**TDLib 64 位元字串解析、完整聊天分批同步，以及原生 UIKit 聊天列表／設定／聯絡人無障礙介面**。此修正尚未由 OC 重新編譯／實機驗證，不能當已確認穩定版。詳見 `docs/OC_HANDOFF.md`。通話、故事、貼圖商店、完整管理員工具、付款及加密通話不在本版範圍；推播註冊程式碼已加入，但仍依賴 OC 的 APNs 簽署和 Telegram 推播憑證；訊息及媒體、聊天與翻頁為優先。

## 本輪無障礙與 iOS 系統整合更新（2026-11-14）

- iPhone 截圖上下黑邊：新增正式 LaunchScreen.storyboard 與 AppInfo.plist，讓 iPhone 以原生完整螢幕尺寸呈現，不再採舊式相容縮放。
- 鍵盤焦點：傳送文字後保留鍵盤；旁白切回聊天訊息時收起；開始錄音前亦先收起。
- 語音：收到 Telegram OGG/Opus 語音後使用 opusfile 解碼，原生 UIKit 播放器可自動播放、暫停、調整進度與速度。一般檔案改用 Quick Look 預覽或 iOS 系統分享。
- 互動選單：聊天訊息操作、機器人按鈕及表情回應全部改為可單項朗讀的 UIKit 清單。
- App 關閉／背景通知：iOS 原生權限申請、APNs Token 及 Telegram TDLib registerDevice 已整合；**必須由 OC 簽署具有 Push Notifications 權限的 App ID，並替 Telegram API 應用配置 Apple APNs 服務端憑證，才能真正收到系統遠端通知**。未確認以上條件前不可宣稱背景推播可用。
- 跨 App 分享：新增直接使用 Telegram TDLib 的 Share Extension。分享時選收件人、輸入說明文字，再由延伸功能直接上傳；只有收到 Telegram 真正的傳送成功通知才結束分享。不需再手動開啟主 App。首次更新後只要開啟新版 App 一次，便會建立獨立、受保護的分享登入副本。大型附件傳送仍受 iOS 分享程序執行時間限制。
- 分享及通知所需能力：主 App、Share Extension 的 App Groups，以及主 App 的 aps-environment；**兩個套件需使用同一 Apple Team 簽名，並一起覆蓋安裝**。

**給 OC 的細節與簽署流程：** [docs/OC_HANDOFF.md](docs/OC_HANDOFF.md)。本輪更動已提交，但未在本環境使用 Xcode／iPhone 編譯實測，請由 OC 以相同 Bundle ID、Keychain 與 TDLib 路徑接手打包。
