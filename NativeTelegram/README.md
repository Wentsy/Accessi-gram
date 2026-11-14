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

使用者已回報前一版可以成功登入，但聊天室列表空白與 VoiceOver 朗讀異常，因此本分支加入**TDLib 64 位元字串解析、完整聊天分批同步，以及原生 UIKit 聊天列表／設定／聯絡人無障礙介面**。此修正尚未由 OC 重新編譯／實機驗證，不能當已確認穩定版。詳見 `docs/OC_HANDOFF.md`。通話、故事、貼圖商店、完整管理員工具、付款及加密通話不在本版範圍；背景推播已依使用者要求移除，不需要 APNs 或私人伺服器；訊息及媒體、聊天與翻頁為優先。

## 本輪無障礙與 iOS 系統整合更新（2026-11-14）

- iPhone 截圖上下黑邊：新增正式 LaunchScreen.storyboard 與 AppInfo.plist，讓 iPhone 以原生完整螢幕尺寸呈現，不再採舊式相容縮放。
- 鍵盤焦點：傳送文字後保留鍵盤；旁白切回聊天訊息時收起；開始錄音前亦先收起。
- 語音：收到 Telegram OGG/Opus 語音後使用 opusfile 解碼，原生 UIKit 播放器可自動播放、暫停、調整進度與速度。一般檔案改用 Quick Look 預覽或 iOS 系統分享。
- 互動選單：聊天訊息操作、機器人按鈕、表情回應及編輯改成 iOS 原生 UIKit 系統動作選單，避免 VoiceOver 打開後整頁空白。
- 背景推播：已依使用者指示整組取消，無需伺服器、APNs、額外推播簽署。**保留 App 開啟期間新訊息震動提醒**。
- 跨 App 分享：使用獨立 TDLib Share Extension，不需要 App Groups。首次在分享視窗另外登入 Telegram 一次，之後沿用分享端登入；直接選最近聊天、輸入說明、上傳媒體，收到 Telegram 成功回報才結束。大型附件仍受 iOS 分享程序執行時間限制。
- 小白簽：主 App 不需 App Groups 或 Push Notifications 權限，但 IPA 必須內含並正確簽署 Share Extension 的 .appex。主 App 原 Bundle ID、Keychain、TDLib 資料庫不變，直接覆蓋安裝。

**給 OC 的細節與簽署流程：** [docs/OC_HANDOFF.md](docs/OC_HANDOFF.md)。本輪更動已提交，但未在本環境使用 Xcode／iPhone 編譯實測，請由 OC 以相同 Bundle ID、Keychain 與 TDLib 路徑接手打包。

## 2026-11-15：iOS 18.7.8 的修正

- 分享收件人直接從分享端自身的 Telegram TDLib 讀取最近 100 個聊天，不再等待手機聯絡人匯出。分享端首次需要獨立登入，此後會保存授權；不使用 App Groups。
- 檔案傳送從 SwiftUI `fileImporter` 改為原生 `UIDocumentPickerViewController`，確保在「檔案」選擇完按「打開」會實際觸發傳送回呼；支援多選、iCloud 和文件提供者。
- 所有訊息操作、機器人按鈕、表情回應採 UIKit 原生系統動作選單；語音、圖片、影片、文件統一改用 UIKit 附件檢視畫面。
- 聊天訊息列表底部人工「聊天輸入列」焦點轉接已移除，讓最後一則訊息與真實輸入按鈕之間以自然 VoiceOver 閱讀順序銜接，不再停留在假的轉接項目。
- 不改已經能正常登入的 TDLib 帳號資料，也不要求重登；本輪尚未在 Xcode 與 iOS 18.7.8 真機驗證，直接提交給 OC 編譯。

## 2026-11-15：分享登入與快捷命令修正

- 分享登入：不再複製主 App 的授權或依賴 App Groups。分享視窗首次顯示獨立 Telegram 登入（手機驗證碼／兩步驟密碼／QR），分享端自己的 TDLib 資料庫保存登入狀態。主 App 設定不再有無效的「重新建立分享登入」功能。
- 訊息切換：移除聊天最尾端自動強制將旁白焦點送回照片按鈕的通知、移除每次聚焦訊息觸發的歷史分頁載入，減少左右滑動時焦點被拉回選單或編輯框。
- BotFather 快捷命令：在照片與檔案按鈕旁新增「機器人斜線命令」。選擇 BotFather 設定的 /指令後直接送出，不進編輯框、不用再按傳送；原有訊息內的 inline/reply keyboard 互動按鈕保留。
- MP3 等一般文件類型的音訊附件：點兩下直接打開原生音訊播放器，自動播放，支援常見 MP3、M4A、AAC、WAV、OGG/Opus 等格式，解碼能力依 iOS 和音訊套件而定。
- 本輪原始碼已提交給 OC，但尚未 Xcode 編譯或實機驗證；背景 APNs 維持取消，只保留 App 開啟時的新訊息震動。

## 最新：小白簽無 App Groups 版

- `project.yml` 已移除 App Groups entitlements，主 App 與分享端各用自己的沙盒，主 App 登入不受影響。
- `ShareExtension/ShareLoginController.swift` 讓首次使用者在分享介面完成 Telegram 登入。`scripts/build.sh` 會將 OC 提供的 Telegram API ID/Hash 同時加入主 App 和延伸功能 Info.plist；請勿把真實金鑰提交到公開 GitHub。
- `AccessibleMessageTimeline.swift` 刪除了人工 `MessageTailRedirect` 和「聊天輸入列」停靠點，讓 VoiceOver 由最後一則訊息自然滑到照片、檔案、機器人斜線命令及文字編輯框。快捷命令點選後直接傳送，不必經過編輯框。
- 這輪原始碼已提交，但尚未經 Xcode 編譯或 iOS 18.7.8 真機驗證。OC 以 `docs/OC_HANDOFF.md` 最新交接為準。
