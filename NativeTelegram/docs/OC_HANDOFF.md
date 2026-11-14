# OC 接手打包 — Accessi Gram Native（最新整合版）

分支：\`rewrite/native-tdlib-voiceover\`

本文件是目前有效的打包參考，取代舊版曾經要求 App Groups、背景 APNs、分享資料庫快照與人工「聊天輸入列」的做法。**main 不動**。使用者 iPhone 為 iOS 18.7.8，採用「小白簽」簽名，無法取得 App Groups 共用容器。

## 必須保留

- 主 App Bundle ID \`org.accessigram.native\` 不變（請以使用者現有安裝包設定為準），保持同樣簽署識別與 Keychain 相容性，保留 \`ApplicationSupport/tdlib\`。
- **絕對不要刪除現有 App、清空 TDLib 或要求重登主 App**。此分支採覆蓋安裝。
- 已確認可用的主 App 登入、聊天、照片／檔案傳送、前景震動不改動。
- 主 App 與分享延伸功能的 Flutter／SwiftUI／UIKit 體驗仍以 VoiceOver 原生可逐項朗讀為準。

## 跨 App 分享：沒有 App Groups 也可直接送

### 原本失敗的真正原因

使用者收到「App Group 權限不存在」。先前 Share Extension 必須讀取主 App 的 App Group 容器與 TDLib 授權副本，但小白簽使用的描述檔沒有提供所需 entitlement。iOS 沙盒無法讓分享程序讀取主 App 資料，因此重新開啟主 App 再多次也無濟於事。這是簽名權限限制，**不能以程式碼繞過**。

### 新方案：獨立登入的 Share Extension

完全取消 App Groups 相依性。分享延伸功能在自己的沙盒維護 \`ApplicationSupport/AccessiGramShare/tdlib\`、\`telegram-config.json\` 和附件資料夾；不讀主 App 的 Keychain 或 SQLite，也不會影響主 App 已有的 Telegram 登入。

首次分享時，選「Accessi Gram 分享」→「接收對象」→ 分享端會顯示原生 UIKit Telegram 登入畫面，包含手機號碼、驗證碼、兩步驟密碼、電子郵件驗證與 QR Code 選項。**第一次需在分享端另外登入同一個 Telegram 帳號一次；往後保存分享端的登入資料，不必每次登入**。若 OC 沒有預置 API ID／Hash，分享登入畫面會要求這兩項；它們是 Telegram API 應用金鑰，不是使用者登入密碼。

登入後，\`ExtensionTelegramSender.recentRecipients()\` 由分享端 TDLib 取得最近 100 個私聊／群組／頻道，支援搜尋。選接收對象、輸入說明與附件後，**直接於分享視窗傳送**，等到 Telegram 回報 \`updateMessageSendSucceeded\` 才關閉分享視窗，失敗會顯示原因；不要求再次開啟主 App。較大的附件受 iOS Extension 記憶體／時限影響，傳送過程保持分享視窗開啟。

相關檔案：
- \`ShareExtension/ExtensionTelegramSender.swift\`：獨立的 TDLib 客戶端、Telegram 授權與媒體傳送。
- \`ShareExtension/ShareLoginController.swift\`：原生 UIKit 可用 VoiceOver 閱讀的首次登入。
- \`ShareExtension/ShareViewController.swift\`：系統分享入口、說明文字、最近聊天選擇與直接傳送。
- \`Shared/ShareSessionBootstrap.swift\`：分享專用授權設定與 TDLib 路徑（**僅屬於分享 target**）。
- \`Shared/ShareMailbox.swift\`：分享沙盒內的附件及最近聊天快取（**僅屬於分享 target**）。

### 小白簽必要的打包方式

- **不要啟用 App Groups，也不需要 Push Notifications、APNs、背景推播伺服器**。已移除兩份舊 \`.entitlements\` 檔；project.yml 不再設定 \`CODE_SIGN_ENTITLEMENTS\`。
- 必須保留主 App 內嵌的 \`PlugIns/AccessiGramShareExtension.appex\`，並分別簽署延伸功能與主程式，使 iOS 系統分享表單能顯示「Accessi Gram 分享」。
- 分享 target Bundle ID 為 \`org.accessigram.native.share\`，依小白簽憑證可簽署的識別碼實際調整，確保 extension 的 \`NSExtension\` 信息不被簽名工具刪除。
- 主 App 既有 Bundle ID、TDLib 資料不能因新增 extension 而改動。Extension 與 App 分開有各自的授權狀態，這是預期行為。
- \`scripts/build.sh\` 在提供 \`TELEGRAM_API_ID\`／\`TELEGRAM_API_HASH\` 時，會將同一組 API 應用金鑰同時放進**主 App 與 .appex 的 Info.plist**，減少首次分享手動輸入；**不要把真實 API Hash 提交到公開 GitHub**。

建置範例：

\`\`\`sh
cd NativeTelegram
TELEGRAM_API_ID="$MY_TG_API_ID" \
TELEGRAM_API_HASH="$MY_TG_API_HASH" \
bash scripts/build.sh
\`\`\`

輸出 \`dist/AccessiGramNative-unsigned.ipa\` 交由 OC／小白簽簽署。不會自行處理私人 Apple Developer、描述檔或手機安裝權限。

## 聊天 VoiceOver「聊天輸入列」卡住

先前為了跳過「垂直捲軸，100%」而加入 \`MessageTailRedirect\` 表格尾端人工項目，產生了新的「聊天輸入列」焦點陷阱，已整組刪除；同時保持 \`UITableView\` 隱藏卷軸指示器，恢復列表自然結束後接上獨立 \`ComposerBarView\` 按鈕的閱讀順序。**不要再新增人工焦點轉接項目或自動 \`.layoutChanged\` 搶焦點**。由真正的「傳送照片或影片」、「傳送檔案或附件」、「機器人斜線命令」、「訊息編輯框」供 VoiceOver 閱讀。

此前焦點回跳問題也已移除的機制：
- 訊息焦點不再立即觸發額外歷史分頁載入；仍以捲動位置／willDisplay 接近上緣時預載舊訊息。
- 收鍵盤只在編輯框確實還是第一響應者時觸發。
- 原生 UIKit 動作選單由系統管理 VoiceOver 焦點，不額外發出延後的 screenChanged。

## 機器人、附件與播放器

- **BotFather 斜線指令**：聊天輸入列「機器人斜線命令」按鈕使用 TDLib \`getUserFullInfo.bot_info.commands\`、群組 full info 讀出機器人 /commands；選擇後**立即送出** \`/指令\`，不進編輯框。原有的 inline/reply keyboard 互動選單保留。
- **文件選取**：iOS 18 的 \`UIDocumentPickerViewController\`，選完按「打開」取得 delegate 結果後複製到 App 私有檔案路徑再交給 TDLib。
- **媒體**：語音及 MP3/M4A/OGG 等音檔點兩下進入原生語音播放器，影音附件由原生 UIKit/AVKit/QuickLook 提供控制項。
- **前景震動**：App 開啟收到真實新訊息時震動，保留使用者已驗證可用的設定。背景推播整組取消。

## 交付狀態

本輪僅將**完整原始碼提交到分支**，沒有在此執行 Xcode 編譯、回歸／防禦型測試或 iOS 18.7.8 真機驗證。由 OC 拉取此分支最新提交接手編譯與簽署；若需修正編譯錯誤，維持以上行為與登錄資料不變。不得把「原始碼已提交」表述成「真機已確認功能正常」。
