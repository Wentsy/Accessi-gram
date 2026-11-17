# OC 接手打包 — Accessi Gram Native（最新整合版）

分支：`feat/stable-chat-links-read-delete`（新功能分支；起點是 OC 已修正分享附件原始檔名的穩定提交 `d97358311f4cb48de69c7d149d410098e73152ab`）

本文件是目前有效的打包參考，取代舊版曾經要求 App Groups、背景 APNs、分享資料庫快照與人工「聊天輸入列」的做法。**main 不動**。使用者 iPhone 為 iOS 18.7.8，採用「小白簽」簽名，無法取得 App Groups 共用容器。

## 必須保留

- 主 App Bundle ID `org.accessigram.native` 不變（請以使用者現有安裝包設定為準），保持同樣簽署識別與 Keychain 相容性，保留 `ApplicationSupport/tdlib`。
- **絕對不要刪除現有 App、清空 TDLib 或要求重登主 App**。此分支採覆蓋安裝。
- 已確認可用的主 App 登入、聊天、照片／檔案傳送、前景震動不改動。
- 主 App 與分享延伸功能的 Flutter／SwiftUI／UIKit 體驗仍以 VoiceOver 原生可逐項朗讀為準。

## 跨 App 分享：沒有 App Groups 也可直接送

### 原本失敗的真正原因

使用者收到「App Group 權限不存在」。先前 Share Extension 必須讀取主 App 的 App Group 容器與 TDLib 授權副本，但小白簽使用的描述檔沒有提供所需 entitlement。iOS 沙盒無法讓分享程序讀取主 App 資料，因此重新開啟主 App 再多次也無濟於事。這是簽名權限限制，**不能以程式碼繞過**。

### 新方案：獨立登入的 Share Extension

完全取消 App Groups 相依性。分享延伸功能在自己的沙盒維護 `ApplicationSupport/AccessiGramShare/tdlib`、`telegram-config.json` 和附件資料夾；不讀主 App 的 Keychain 或 SQLite，也不會影響主 App 已有的 Telegram 登入。

首次分享時，選「Accessi Gram 分享」→「接收對象」→ 分享端會顯示原生 UIKit Telegram 登入畫面，包含手機號碼、驗證碼、兩步驟密碼、電子郵件驗證與 QR Code 選項。**第一次需在分享端另外登入同一個 Telegram 帳號一次；往後保存分享端的登入資料，不必每次登入**。若 OC 沒有預置 API ID／Hash，分享登入畫面會要求這兩項；它們是 Telegram API 應用金鑰，不是使用者登入密碼。

登入後，`ExtensionTelegramSender.recentRecipients()` 由分享端 TDLib 取得最近 100 個私聊／群組／頻道，支援搜尋。選接收對象、輸入說明與附件後，**直接於分享視窗傳送**，等到 Telegram 回報 `updateMessageSendSucceeded` 才關閉分享視窗，失敗會顯示原因；不要求再次開啟主 App。較大的附件受 iOS Extension 記憶體／時限影響，傳送過程保持分享視窗開啟。

相關檔案：
- `ShareExtension/ExtensionTelegramSender.swift`：獨立的 TDLib 客戶端、Telegram 授權與媒體傳送。
- `ShareExtension/ShareLoginController.swift`：原生 UIKit 可用 VoiceOver 閱讀的首次登入。
- `ShareExtension/ShareViewController.swift`：系統分享入口、說明文字、最近聊天選擇與直接傳送。
- `Shared/ShareSessionBootstrap.swift`：分享專用授權設定與 TDLib 路徑（**僅屬於分享 target**）。
- `Shared/ShareMailbox.swift`：分享沙盒內的附件及最近聊天快取（**僅屬於分享 target**）。

### 小白簽必要的打包方式

- **不要啟用 App Groups，也不需要 Push Notifications、APNs、背景推播伺服器**。已移除兩份舊 `.entitlements` 檔；project.yml 不再設定 `CODE_SIGN_ENTITLEMENTS`。
- 必須保留主 App 內嵌的 `PlugIns/AccessiGramShareExtension.appex`，並分別簽署延伸功能與主程式，使 iOS 系統分享表單能顯示「Accessi Gram 分享」。
- 分享 target Bundle ID 為 `org.accessigram.native.share`，依小白簽憑證可簽署的識別碼實際調整，確保 extension 的 `NSExtension` 信息不被簽名工具刪除。
- 主 App 既有 Bundle ID、TDLib 資料不能因新增 extension 而改動。Extension 與 App 分開有各自的授權狀態，這是預期行為。
- `scripts/build.sh` 在提供 `TELEGRAM_API_ID`／`TELEGRAM_API_HASH` 時，會將同一組 API 應用金鑰同時放進**主 App 與 .appex 的 Info.plist**，減少首次分享手動輸入；**不要把真實 API Hash 提交到公開 GitHub**。

建置範例：

```sh
cd NativeTelegram
TELEGRAM_API_ID="$MY_TG_API_ID" \
TELEGRAM_API_HASH="$MY_TG_API_HASH" \
bash scripts/build.sh
```

輸出 `dist/AccessiGramNative-unsigned.ipa` 交由 OC／小白簽簽署。不會自行處理私人 Apple Developer、描述檔或手機安裝權限。

## 聊天 VoiceOver「聊天輸入列」卡住

先前為了跳過「垂直捲軸，100%」而加入 `MessageTailRedirect` 表格尾端人工項目，產生了新的「聊天輸入列」焦點陷阱，已整組刪除；同時保持 `UITableView` 隱藏卷軸指示器，恢復列表自然結束後接上獨立 `ComposerBarView` 按鈕的閱讀順序。**不要再新增人工焦點轉接項目或自動 `.layoutChanged` 搶焦點**。由真正的「傳送照片或影片」、「傳送檔案或附件」、「機器人斜線命令」、「訊息編輯框」供 VoiceOver 閱讀。

此前焦點回跳問題也已移除的機制：
- 訊息焦點不再立即觸發額外歷史分頁載入；仍以捲動位置／willDisplay 接近上緣時預載舊訊息。
- 收鍵盤只在編輯框確實還是第一響應者時觸發。
- 原生 UIKit 動作選單由系統管理 VoiceOver 焦點，不額外發出延後的 screenChanged。

## 機器人、附件與播放器

- **BotFather 斜線指令**：聊天輸入列「機器人斜線命令」按鈕使用 TDLib `getUserFullInfo.bot_info.commands`、群組 full info 讀出機器人 /commands；選擇後**立即送出** `/指令`，不進編輯框。原有的 inline/reply keyboard 互動選單保留。
- **文件選取**：iOS 18 的 `UIDocumentPickerViewController`，選完按「打開」取得 delegate 結果後複製到 App 私有檔案路徑再交給 TDLib。
- **媒體**：語音及 MP3/M4A/OGG 等音檔點兩下進入原生語音播放器，影音附件由原生 UIKit/AVKit/QuickLook 提供控制項。
- **前景震動**：App 開啟收到真實新訊息時震動，保留使用者已驗證可用的設定。背景推播整組取消。

## 交付狀態

本輪僅將**完整原始碼提交到分支**，沒有在此執行 Xcode 編譯、回歸／防禦型測試或 iOS 18.7.8 真機驗證。由 OC 拉取此分支最新提交接手編譯與簽署；若需修正編譯錯誤，維持以上行為與登錄資料不變。不得把「原始碼已提交」表述成「真機已確認功能正常」。

## 2026-11-15：分享登入輸入手機後發生 API_ID_INVALID（最新修正）

**根因與界線：** 這是 Telegram `auth.sendCode` 驗證分享 Extension 當前使用的 `api_id`／`api_hash` 失敗，不是手機號碼格式錯誤。分享端與主 App 分別有自己的資料庫和 API 設定；主 App 過去已登入不代表 Share Extension 一定獲得同一組 API 金鑰。若打包未注入兩個 target 的 Info.plist，分享端要求首次手動輸入 API ID／Hash，可能造成打錯或使用過時值。TDLib `setTdlibParameters` 接受輸入並進入手機號碼頁，不代表遠端已驗證該組 API；直到 `setAuthenticationPhoneNumber` 才可能收到 `API_ID_INVALID`。

**這次程式修復：**

- `ExtensionTelegramSender.query()` 對 `API_ID_INVALID`／`CONNECTION_API_ID_INVALID` 顯示具體的 API 憑證錯誤、切回 `.apiCredentials` 而不是把它描述成普通訊息傳送失敗；TDLib 參數設定階段也保留此提示。
- `ShareLoginController` 在手機／驗證碼／密碼／電子郵件／QR 登入頁新增「修改分享功能的 API ID／Hash」，VoiceOver 可直接找到；錯誤時會顯示 API 編輯框。
- `ExtensionTelegramSender.saveAPI` 更換已套用的 API 憑證前會先呼叫 `close` 等待分享 TDLib client 完全關閉，才清除**僅分享 Extension 沙盒內的資料庫、設定檔、加密金鑰**並重新以新憑證啟動。主 App `org.accessigram.native` 的 Keychain 和 TDLib 資料庫完全不動。若這個擴充功能先前已成功登入，手動更換 API 會需要重新登入分享端。
- API Hash 輸入欄位設為安全文字，輸入時檢查 API ID 大於零且 Hash 為 32 位十六進位；這只能篩除格式錯誤，真正的值仍必須由 Telegram 驗證。

**OC 建置交付重點：**

- 確認 GitHub Actions 真正有執行 `NativeTelegram/scripts/build.sh` 並傳入有效的 `TELEGRAM_API_ID` 和 `TELEGRAM_API_HASH` 環境變數。主 App 既存的 Keychain 無法自動複製給 Share Extension（因為小白簽不支援當前 App Groups 權限），因此不能假設分享端會知道主 App 的 API Hash。
- 打包後**只核對**主 App 與 `PlugIns/AccessiGramShareExtension.appex` 各自 Info.plist 是否都有相同的 `TelegramAPIID`，並確認 `TelegramAPIHash` 存在且為 32 位；不要在 CI 日誌印出真正的 API Hash，不要提交任何憑證到公開 GitHub。
- 只有使用者的 API ID／Hash 真正有效才能取得 Telegram 登入驗證碼。若 OC 不能向兩個 Info.plist 注入正確值，讓使用者在分享視窗透過 [Telegram API Development Tools](https://my.telegram.org/apps) 輸入自己的正確 API ID／Hash，**不需要提供手機密碼或 API Hash 給 ChatGPT**。
- 即使打包後改正 Info.plist，先前儲存在分享沙盒的舊 API 憑證仍會優先使用；使用者可利用本次新增的「修改分享功能的 API ID／Hash」覆蓋舊值，無須刪除 App 或重新登入主程式。

本輪只提交原始碼，不在此執行 Xcode 編譯／回歸測試；請由 OC 拉取最新提交接手。原有主 App Bundle ID、Keychain 和登入不能更動。

## 2026-11-15 — 穩定基準新增四組功能：連結、已讀、對話移除、鎖屏播放

**基準承諾**：本分支從 `d973583`（已修復分享附件檔名、且**沒有背景 APNs 推播試驗**）另開，未沿用後續 `c70be814` 起的推播程式、`registerDevice`、`remote-notification`、APNs entitlements 或推播診斷設定。不改 TDLib 資料庫、Keychain、主 App Bundle ID `org.accessigram.native`、Share Extension 獨立登入；維持可覆蓋更新，不須先刪 App。

### 1. 含連結訊息直接由 VoiceOver 動作轉輪開啟

- `TelegramModels.swift` 由 `formattedText.entities` 解析 `textEntityTypeUrl`（明文網址）和 `textEntityTypeTextUrl`（隱藏超連結），含文字與媒體 caption；普通 URL 再用 `NSDataDetector` 補抓，僅開放 HTTP/HTTPS。
- `AccessibleMessageTimeline.swift` 對每個訊息的 URL 加 `UIAccessibilityCustomAction`「開啟連結，{文字}」，與原有翻譯、回覆、複製等動作並列，不額外建立可卡住 VoiceOver 游標的虛擬元素。
- `ChatScreen.swift` 透過 `UIApplication.shared.open` 交給 iOS 系統 URL 開啟機制（正常網頁會依系統預設瀏覽器開啟）。**這是 VoiceOver「動作」轉輪，不是改寫 iOS 全局「連結」轉輪。**

### 2. 讀完仍標未讀

- `TelegramService.swift` 每次 `openChat`、`closeChat` 都對最新訊息送 `viewMessages(force_read: true)`；第一次載入歷史與聊天室正在開啟時收到新訊息，也依最新 ID 標已讀。
- 同時解除手動的 `toggleChatIsMarkedAsUnread(false)`，並處理 TDLib `updateChatReadInbox` 與 `updateChatIsMarkedAsUnread`；聊天列表顯示依 `unread_count` 和明確未讀標記產生。
- 不改現有增量載入、翻頁焦點策略或已修復的輸入框。

### 3. 聊天列表刪除對話、退出群組、離開頻道

- `AccessibleScreens.swift` 聊天列同時提供 VoiceOver「動作」轉輪與 UIKit 列表尾端滑動操作。
- 私聊依 Telegram `chat.can_be_deleted_only_for_self` / `chat.can_be_deleted_for_all_users` 顯示可用的選項；彈出系統選單後選「僅為我刪除」（`deleteChatHistory(revoke:false)`）或「為雙方刪除」（`revoke:true`），均設定 `remove_from_chat_list:true`。
- 基本群組、超級群組及頻道顯示相應的「退出群組」／「離開頻道」，確認後執行 `leaveChat`，再嘗試將對話從列表移除。
- 只有 TDLib 操作回報成功後才自聊天列表移除；伺服器拒絕時以既有 Telegram 提示回報。刪除和離開都由使用者確認才真正執行。

### 4. 語音與音檔在鎖定螢幕後仍繼續播放

- `Resources/AppInfo.plist` 加入 **`UIBackgroundModes = [audio]`**，與 `VoicePlayerController` 已有的 `AVAudioSession.Category.playback` 搭配，符合 iOS 原生背景音訊要求；這與 `remote-notification` **完全不同**，不代表恢復推播。
- 同一個 `VoicePlayerController` 同時處理語音訊息（包括轉碼後的 Ogg/Opus）與 MP3/M4A/音檔，並加入 `MPNowPlayingInfoCenter` 顯示鎖定畫面播放資訊、`MPRemoteCommandCenter` 播放／暫停／拖動進度。
- 不要求永遠保持 App 常駐；**僅針對已開始播放的音訊**，若使用者關閉附件播放器，仍依原有流程結束播放。

### OC 打包

由 GitHub Actions 雲端 macOS 拉此分支建置，不要求使用者自行操作 Mac；打包注入既有 Telegram API ID/Hash 到主 App 和分享 Extension，不要在公開提交中暴露 API Hash。請保留小白簽現有 Bundle ID 和簽署身份，直接覆蓋舊版。這次只提交程式碼及文件，**不執行本地回歸、防禦型測試，也不提供 IPA**，交由 OC 拉取編譯交付使用者。

## 2026-11-15：VoiceOver 雙指雙擊（Magic Tap）播放／暫停音訊

使用者已確認**未讀狀態問題已修好**，**背景音訊播放與訊息連結也已正常**。本次只新增語音／一般音訊的雙指雙擊播放暫停，不再更動任何已讀、對話、分享或訊息連結程式。

- `VoicePlayerScreen.swift`：在 `VoicePlayerController.accessibilityPerformMagicTap()` 接住 VoiceOver「雙指雙擊」，只在音訊已載入時切換 `AVAudioPlayer` 播放／暫停；其他功能與倍速不變。
- `AccessibleMediaSheet.swift`：播放器是原生附件視窗裡的子 controller；額外讓 `NativeMediaScreen` 和 `AccessibleMediaNavigationController` 把 Magic Tap 傳至子播放器，包含 VoiceOver 焦點在導覽列及關閉按鈕時。
- `VoicePlayerScreen.swift`：現有 `playCommand`、`pauseCommand` 之外，補齊 `MPRemoteCommandCenter.togglePlayPauseCommand`，供 iOS 鎖定畫面／系統媒體操作播放暫停；播放期間開啟 remote-control event reception，關閉播放器時解除。現有 Now Playing、背景音訊 `UIBackgroundModes=audio`、進度、倍速與 Ogg/Opus 支援都保留。
- `AccessibleHelp.swift` 使用指南更新魔術點按說明。**鎖定螢幕兩指雙擊須由 iOS VoiceOver／系統媒體控制派發；這次已完成 App 端命令接線，但尚未經使用者真機驗證，不能宣稱鎖屏手勢已經實測成功。**

由 OC 用 GitHub Actions 雲端 macOS 拉 `feat/stable-chat-links-read-delete` 繼續打包，不需個人 Mac，也不需任何 APNs／App Groups entitlement。本次未執行 Xcode 回歸／防禦性測試。請保留已成功的檔名、跨 App 分享與登入資料，不要轉回失敗的背景推播分支。

## 2026-11-15：使用者確認目前版本穩定（最新穩定基準）

- **使用者已完成真機測試**並明確回報「可以穩定使用、目前功能都正常」。此分支截至 `a540b40350ccf8dbc19024b25db5f802cd8f7d7e` 的功能組合列為新的穩定基準。
- 已確認項目：Telegram 聊天與訊息已讀狀態、訊息內連結 VoiceOver 動作、聊天列表刪除／離開群組與頻道、語音／音檔背景及鎖定畫面播放、VoiceOver 雙指雙擊播放／暫停；原有登入、跨 App 分享、附件原檔名與檔案傳送維持正常。
- **往後開發一律以 `feat/stable-chat-links-read-delete` 作為基準**；僅開新功能分支，未經使用者要求不要合併至 `main`，也不要把背景 APNs 推播實驗分支的程式重新帶入。
- 現階段無需額外回歸、防禦性測試，OC 按使用者指示負責拉取及編譯；使用者有需要再個別回報問題。

## 2026-11-17 — iOS 截圖預覽畫面直接分享失效（最新）

**基準釐清**：使用者已由 OC 將穩定分支合併至 `main`。2026-11-17 的 `main` HEAD 是 `f0f1727fa264da13aeb045ee904e0d2bd735fc15`；原功能分支已刪。**本修復分支 `fix/screenshot-share-extension` 直接由該穩定 main HEAD 建立**，沒有背景 APNs 實驗內容，不更改 `main`。

使用者回報：從相簿、檔案等正常分享都可以成功，但在**iOS 截圖預覽／編輯畫面**直接選 Accessi Gram 分享，按傳送後會直接回到選擇分享 App 的系統畫面，沒有顯示失敗。此處是使用者實測現象；未取得裝置崩潰日誌，不應斷言唯一根因。

### 實際修正：`ShareExtension/ShareViewController.swift`

- 舊版在 `NSItemProvider` 圖片路徑對 `image as! UIImage`、`image.jpegData(...)!`、檔案路徑 `item as! URL` 強制轉型／解包。截圖預覽可傳遞 in-memory PNG `Data`、UIImage、暫存檔 URL 或多種 representation，型態不符可能直接令 Share Extension 終止，導致無錯誤提示回到系統分享列表。
- 新增 `loadScreenshot()`：優先 `loadDataRepresentation` 取得 PNG/JPEG/HEIC 原始資料，必要時後退到 `loadObject(UIImage)` 和 `loadItem`。截圖 PNG 原樣保留，不額外 JPEG 有損壓縮；先寫入延伸功能私有的臨時路徑，再用既有 `ShareMailbox.stageFile` 搬到分享沙盒。
- 保留一般檔案的原始檔名與既有安全範圍檔案 URL 邏輯，不能因新增截圖支援讓正常的 Files／相簿分享退化。
- 讀取附件時移除強制轉型。處理完成後，若附件與說明文字均為空，不呼叫 TDLib send，顯示「沒有取得可傳送的截圖或文字」；任一 provider 無法讀取，顯示實際的「讀取分享內容失敗」而非無提示返回。
- 成功送達仍保留原流程：只有 `ExtensionTelegramSender.send` 確認完成後呼叫 `extensionContext.completeRequest`；失敗可在分享視窗查看原因、重試。

### 交付

OC 從 `fix/screenshot-share-extension` 拉取編譯並在 GitHub Actions 雲端 macOS 產出 unsigned IPA，再由既有小白簽覆蓋安裝。維持 `org.accessigram.native`、主 App 與 Share Extension 獨立 TDLib 登入及 API 配置，**不要刪掉 App／清除 Keychain 或資料庫**。本輪未執行本地 Xcode 回歸／防禦型測試，使用者負責測試截圖預覽分享；未實測成功前不合併 `main`。

## 2026-11-17 — 截圖預覽分享第二輪修正（以 OC 已能編譯版本為基準）

使用者在 OC 代為修正 Swift 語法並重編後，截圖直接分享顯示「讀取分享內容失敗：截圖圖片無法讀取，請從截圖預覽重新分享」。另外，一般分享的說明文字明明顯示「選填」，但無文字時按鈕無法點；即使先輸入文字，再選接收對象，返回分享畫面後仍須在編輯框任意輸入／刪字才能按傳送。

### 已直接改動 `ShareExtension/ShareViewController.swift`

- **保留 OC 的編譯修正**：從已有 OC 提交 `debbc49bf1e9e0895902ff75c641b45de86b3756` 的 `fix/screenshot-share-extension` 繼續修改；不從舊基準覆蓋。OC 曾修正 closure `self.loadScreenshot` 和 `.first(where: {...})` 兩處錯誤。
- **真正依來源提供型態讀截圖**：先取 `NSItemProvider.registeredTypeIdentifiers` 中實際存在的圖片型態，不再因 `hasItemConformingToTypeIdentifier(public.png)` 就假設 provider 真能提供 PNG。每種型態優先 `loadItem` 直接解出 `UIImage`，再依序嘗試 `Data`、檔案 representation；最後才用 `loadObject(UIImage)`。這是專門針對截圖預覽可能提供 `public.image`/`UIImage`（非 Data／檔案 URL）的情況。
- **準確保留圖片格式**：透過 ImageIO `CGImageSourceGetType` 從內容辨認 PNG、JPEG、HEIC、WebP，避免相信來源宣稱 UTI；不認得時才將有效 `UIImage` 轉成 PNG。寫入沙盒檔案之後，仍沿用正常分享已驗證可用的 `ShareMailbox.stageFile`。
- **檔案 URL 失效時走圖片備援**：截圖預覽可能提供短暫檔案 URL，若直接複製失敗、又可提供圖片，就改試圖片 representation，不立即放棄。
- **失敗訊息更有價值**：截圖提供的所有型態均無法載入時，顯示 `registeredTypeIdentifiers` 作為診斷依據；不再只有「請重新分享」而沒法排查。無附件又無內容仍禁止送出。
- **選填內容真正選填**：`isContentValid` 在已選接收對象且有來源附件時允許空說明；純文字分享需要實際內容。選擇接收對象後**同時**執行 `reloadConfigurationItems()` 和 `validateContent()`；返回分享畫面再驗證一次，讓 iOS 更新原生傳送按鈕，免再輸入／刪字。

### 交接與測試責任

- 最新程式提交：`88306844458313a723ae568187b5c9e6333ca5f8`（本文件提交不改 Swift）。分支 `fix/screenshot-share-extension`；**不合併 `main`**，維持先前穩定基準，使用者真機再判斷截圖來源是否可讀。
- OC 請從這個分支拉取，用 GitHub Actions 進行編譯，保留 Share Extension 的獨立 Telegram 登入、注入 API ID/Hash、原始分享檔名、主 App 登入／聊天／連結／鎖屏播放；採小白簽覆蓋安裝，不刪 App、不清除資料。
- 未進行回歸／防禦測試或模擬器測試；目前是實作完成，**不宣稱截圖直接分享已經真機驗證成功**。若還失敗，請回報新的錯誤訊息中「提供的圖片型態」部分，便能按實際 iOS 來源對應調整。

## 2026-11-17：最新穩定版確認與 main 合併授權

**本節取代上方歷史記錄中「等待實測／不合併 main」的舊指示。**
使用者已實機確認本次截圖預覽分享修復、可選填說明文字與選完接收對象直接傳送的版本，明確表示「這個版本可以變成最新穩定版」，並要求直接合併 main。

- 最新穩定基準為 `fix/screenshot-share-extension` 的程式，包含 OC 修正過的 Swift 語法及截圖分享圖片型態接收修正，搭配已驗證的 VoiceOver、已讀狀態、鎖屏音訊、連結與跨 App 分享功能。
- 本次更新是從 `main` 的穩定提交 `f0f1727f` 逐步向前整合，**沒有恢復背景 APNs 推播實驗**。
- 後續 OC 與更新工作**以 `main` 為唯一最新穩定基準**；後續新增功能另開分支。不要把已刪除的 `feat/stable-chat-links-read-delete` 當作活躍分支。
- 使用者會自行請 OC 清理舊測試分支；本次保留 `fix/screenshot-share-extension` 供對照，不代為刪除。
- 已由使用者完成真機驗證；本次不新增回歸測試或變更程式功能，只更新穩定基準文件並合併。
