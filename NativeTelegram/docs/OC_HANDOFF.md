# OC 打包交接：Accessi Gram Native

## 分支

- GitHub: https://github.com/Wentsy/Accessi-gram/tree/rewrite/native-tdlib-voiceover/NativeTelegram
- Branch: `rewrite/native-tdlib-voiceover`
- 舊 Turrit IPA 補丁仍在原倉庫 main，**不要將兩個專案混編或直接把舊 dylib 注入這個 App**。
- 這是全新 SwiftUI + UIKit + TDLib iOS 原生專案；無需 Turrit IPA。

## 一次打包

```bash
git clone -b rewrite/native-tdlib-voiceover https://github.com/Wentsy/Accessi-gram.git
cd Accessi-gram/NativeTelegram
brew install xcodegen
bash scripts/build.sh
```

輸出 `dist/AccessiGramNative-unsigned.ipa`；iPhone 安裝前仍需要用既有簽名工具重新簽名（TDLib Framework 和主 App 都需正確處理），或由 Xcode 設定開發團隊進行簽署。可在 `xcodegen generate` 之後開啟 `AccessiGramNative.xcodeproj`。

- iOS 最低版本 16。
- SPM 自動從 `Swiftgram/TDLibFramework` 下載官方 TDLib 的預編譯 XCFramework，初次需要較多網路流量。
- 若希望不用每次輸入，OC 可從私有環境變數 `TELEGRAM_API_ID` / `TELEGRAM_API_HASH` 注入未簽名 IPA 的 Info.plist。App 會將第一次讀取到的 API 金鑰存到 Keychain。不要將真實 API Hash 提交到公開 GitHub。
- API 金鑰及本機資料庫的隨機加密金鑰均存放 iOS Keychain，沒有上傳到 GitHub。
- Google 翻譯是 Google 網頁公開端點，不是官方有 SLA 的 Cloud Translation API，可能有額度或封鎖限制。文字僅在手動選擇翻譯時才送給 Google。

## 實作範圍

- 登入：手機號碼、驗證碼、二步驟密碼、QR Code、電子郵件驗證狀態。
- 聊天列表：未讀數、預覽、搜尋、封存、置頂、標記未讀、刪除對話、動態載入更多、新增聊天、聯絡人以及 username 尋找。
- 訊息：一則一個 VoiceOver 焦點；口述順序固定為「發送者、訊息內容、發送時間」。
- 連續閱讀：所有私聊、群組、頻道共用 `AccessibleMessageTimeline.swift` 內的 `UITableView`。當行數進入距離歷史最前端約 30 列時就提前載入更早一批最多 75 則訊息。以 diff 插入列，保留可見訊息錨點及其畫面位置，避免整表刷新和主動移動 VoiceOver 焦點。
- 訊息操作：上下滑動可選翻譯（中文結果直接 VoiceOver announcement）、回覆、複製、更多操作；更多操作含轉寄、編輯、刪除、表情回應及附件。
- 訊息內容：文字、照片、影片、語音、音訊、檔案、貼圖描述、投票選項與常見系統訊息。
- 媒體：PhotosPicker、檔案挑選、麥克風錄音、照片檢視、影片播放、音檔播放及分享。
- 機器人：inline keyboard / reply keyboard 會以 VoiceOver 自訂動作與可展開選單提供，支援基本 callback、URL 與文字命令。
- 翻譯：`GoogleTranslate.swift` 按需連到免金鑰網頁端點，長篇貼文分段翻譯。

## 請保留的 UX 不變條件

1. 聊天訊息列表要做到**一滑一則**，不能把輸入框、圖片元件、下方工具列混進訊息列的焦點序列。
2. 讀到歷史第一則前必須已啟動下一批的預載；插入後保留目前朗讀的訊息物件與其座標，**禁止在分頁完成時發 `screenChanged` / `layoutChanged` 強制跳焦**。
3. 翻譯是訊息自己的 `UIAccessibilityCustomAction`，從 VoiceOver 上下滑選「翻譯成繁體中文」，點兩下後直接宣告繁體中文結果；不必強迫跳到新頁。
4. 群組和頻道不可另外換用不同的滾動實作，統一沿用訊息時間軸；大段貼文的附件和文字仍只有一個訊息焦點。
5. 初次進入聊天室時，停在最新訊息區；再透過 VoiceOver 左右滑及歷史預載往回、往後閱讀，不要用每次 `reloadData` 的方式進行翻頁。

## 已知未完成／需要 OC 確認

使用者已回報前一版**成功登入 Telegram**；本次無障礙與同步修正尚未由 OC 編譯／真機驗證，不能直接稱作穩定 IPA。若 Xcode 報 SDK 或 TDLib API 版本不相容，先以此分支修正，勿改動舊版 `main`。我們沒有在這裡進行使用者不希望的回歸測試。

- 不含背景推播註冊、即時通話、影片通話、Stories、完整群組管理員工具、討論串／論壇主題、付款、完整貼圖鍵盤。
- 語音採 iOS M4A AAC；TDLib 支援傳送但部分 Telegram 客戶端可能當成一般音檔顯示，若需完全一致的 Telegram Opus/OGG 語音泡泡需加轉碼。
- 機器人部分進階 inline 模式（例如付款、Web App）尚未實作；一般按鈕可操作。
- 原版 Telegram 的聊天室傳送權限、管理員細節及群組論壇子主題需要後續擴充。
- Google 免費端點不保證穩定、無隱私 SLA。祕密聊天訊息若使用翻譯，文字也會送到第三方，UI 已提醒。


## 2026-11-14：登入後空白、中文不朗讀與 TDLib 初始化修正

此更新修正三個可追溯的問題，OC **直接拉取同一分支最新提交**：

1. **聊天室被錯誤隱藏**：TDLib JSON 的 64 位元欄位（特別是 `chatPosition.order`）可能是十進位字串；舊的 `JSONObject.number` 僅接受 NSNumber，令排序為 0 而隱藏全部聊天。現統一接受 NSNumber / decimal String，包含 chat ID、message ID、排序等值。
2. **歷史清單同步不完整**：原先 `loadChats` 只叫一次，又在 `getChats` 只讀當前少數聊天室。現會依 TDLib 官方機制逐批 `loadChats`，直到回傳 404（代表已載完），並用 `getChats` 補充快取與 `updateNewChat` 等事件。原帳號聊天不需重新匯入，也不主動刪除已儲存資料。
3. **VoiceOver 只有工具列能朗讀**：不再用 SwiftUI 的 List/Form 呈現登入後主要頁。新增 `AccessibleScreens.swift`：原生 UIKit 聊天、封存、設定、聯絡人清單，所有表格列有真正的 `accessibilityLabel`、`accessibilityLanguage = "zh-TW"`、適當 traits。聊天訊息 `MessageRow` 仍維持一則一個焦點，內部 UILabel 不再多一個焦點。
4. **每次開啟「Unexpected setTdlibParameters」**：TDLib 初始狀態推送和手動 `getAuthorizationState` 回覆可能重覆。設置 `parametersRequested`，只有在 `authorizationStateWaitTdlibParameters` 且尚未傳過參數時才呼叫 `setTdlibParameters`。**若 OC 之前另外寫入一段直接呼叫 `setTdlibParameters` 的程式，請刪除第二個呼叫，預填 API 不代表要再次初始化。**重複回覆的 race 不再彈出無害錯誤。只要維持相同 Bundle ID / Keychain 權限 / TDLib database 路徑，更新不應主動登出。
5. **API 可直接編入未簽名 IPA**：新的 `scripts/build.sh` 可使用 `TELEGRAM_API_ID` 與 `TELEGRAM_API_HASH` 環境變數。專案將值注入 `Info.plist`；App 首次讀取後存入 iOS Keychain，日後無需反覆輸入。若沒有環境變數，仍可在登入頁輸入一次。請不要把真實金鑰放回公開 Git 歷史。

**OC 建置方式（在本機私有環境設定變數，勿把數值貼到公開倉庫）：**

```bash
cd Accessi-gram/NativeTelegram
TELEGRAM_API_ID="$MY_TG_API_ID" TELEGRAM_API_HASH="$MY_TG_API_HASH" bash scripts/build.sh
```

注意：只要把 API 金鑰嵌進 IPA，就無法防止擁有 IPA 的人提取；這是免輸入換取的取捨。若實際金鑰先前已提交到公開 repo，請評估撤銷／更換並從此避免再次提交。

## 2026-11-14：訊息輸入列與錄音的 VoiceOver 修正

使用者回報聊天列表已可朗讀，但聊天室內編輯框、錄音按鈕仍無法直接左右滑朗讀。本次改以原生 UIKit 元件處理：

- AccessibleComposer.swift：用 UITextView 讓 VoiceOver 正常進入文字編輯、讀取中文輸入；相簿、檔案、發送、錄音、停止並傳送、取消錄音皆有 zh-TW 標籤及提示，外層容器不再產生空白焦點。
- 錄音按鈕固定位置，狀態在「開始錄製語音訊息」和「停止錄音並傳送語音訊息」之間切換；錄音中另有「取消錄音」。不更動 TDLib 資料庫。
- 聊天回覆提示改為 AccessibleReplyBanner，內容和取消回覆各一個焦點。
- 轉寄列表改為 AccessibleForwardSheet 原生 UITableView，選擇的聊天名稱可直接被旁白讀到。
- 接收照片、音訊播放改成明確標籤的 UIKit 控制項，影片播放使用原生 AVKit。
- 設定頁移除不可調整的朗讀順序、翻頁與翻譯描述，改成 AccessibleHelp.swift 提供「使用指南」。設定只保留「使用指南」、「重新同步對話」、「登出 Telegram」這三個真的有動作的選項。
- 已移除沒有使用的舊 SwiftUI 聊天、設定介面，也清掉先前硬編入公開原始碼的 API 預設值。免輸入 API 請沿用 build.sh 使用私有環境變數注入 Info.plist。**不應再把真實 API Hash 提交到公開倉庫。**

給 OC：拉取 rewrite/native-tdlib-voiceover 最新提交後編譯，使用與原版相同的 Bundle ID、Keychain 權限和 TDLib 資料庫路徑覆蓋安裝。這次未在此環境執行 Xcode／真機測試。更新後聊天輸入列從左至右應能讀到：「傳送照片或影片」、「傳送檔案或附件」、「訊息編輯框」、「開始錄製語音訊息」或「傳送文字訊息」。錄音時應有「停止錄音並傳送語音訊息」及「取消錄音」。


## 2026-11-14：附件無法傳送／新訊息震動修正

使用者回報語音錄製完成後彈出 `InputFile is not specified`，照片及影片無法傳送，「檔案」App 選完按「打開」後沒有任何反應。本次同步修正並加入前景震動：

- TDLibFramework 現行依賴為 TDLib 1.8.70；TDLib 1.8.65 之後的媒體內容參數已改成 `inputPhoto` / `inputVideo` / `inputVoiceNote` / `inputDocument` 中再放 `inputFileLocal`。原本直接放 `inputFileLocal` 會讓資料解析後找不到實際檔案。修正 `TelegramService.sendMedia` 全類別封裝，訊息仍透過官方 `sendMessage` 傳送。
- `AttachmentPreparation.swift`：PhotosPicker 圖片轉換成真實 JPEG 路徑，避免 HEIC 檔案內容配上錯誤 .jpg 副檔名；影片透過 AVFoundation 匯出 MP4；iOS Files / iCloud / 檔案提供者 URL 先用 NSFileCoordinator 與 security scope 複製到 App 私有暫存位置，並保留原始文件名稱後傳送為一般檔案。
- `VoiceRecorder` 新增實際錄音秒數 `lastDuration`，傳給 `inputVoiceNote.duration`。原生 M4A AAC 語音若無法當作 Telegram 語音泡泡，送出要求回傳可辨識的語音格式錯誤時改為一般音訊附件；**完整一致的 OGG Opus 語音泡泡仍需額外 Opus 編碼器**。
- 檔案準備錯誤和 TDLib 的 `sendMessage`／`updateMessageSendFailed` 錯誤現在會顯示原因，不再「點打開沒反應」。VoiceOver 在 TDLib 接受要求後才播報「已提交附件，正在傳送」，不會把錄音停止誤報成傳送成功。
- `TelegramService` 在 `updateNewMessage` 判斷 **App 前景、非自己發送、真實新進訊息** 時使用 iPhone 系統震動；用訊息 ID 排除重複更新、限制短時間連續震動；歷史分頁和開機同步不會觸發。
- `AccessibleSettingsController` 新增 **App 開啟時新訊息震動** 可調整選項，預設開啟，值以 UserDefaults 儲存，可在 VoiceOver 直接點擊開關。

OC 請拉取同一分支 `rewrite/native-tdlib-voiceover` 的最新提交重新打包，直接覆蓋安裝，沿用 Bundle ID、Keychain 與 TDLib 資料庫。修正沒有改登入流程。依使用者要求，此處只提交原始碼，不進行回歸測試；OC 可依實際 iOS 編譯結果接手。注意所有 iPhone / iOS 設備震動行為仍受系統觸覺設定限制。

## 2026-11-14：系統通知、語音播放器、跨 App 分享、鍵盤與全螢幕

本次更新保留前一版已驗證可以使用的登入、前景震動及附件上傳流程。OC 拉取分支最新版即可，**不可刪除 App 或清空 TDLib 本機資料庫**。

### 1. 背景推播已依使用者要求完全取消

本分支**不要求也不啟用背景 APNs 推播**。已刪除 SystemNotificationManager.swift、TDLib registerDevice／processPushNotification、授權按鈕、UIBackgroundModes remote-notification、App.entitlements 的 aps-environment、Build Script 的 TELEGRAM_APNS_SANDBOX。OC **不需要伺服器、APNs 憑證或 Push Notifications capability**。

保留已確認運作的**App 開啟時新訊息震動**（設定內可關閉），它由 TDLib updateNewMessage 與 AudioToolbox 系統震動處理，無需遠端推播。

Share Extension 仍然需要 App Groups 權限，這和 APNs 完全是不同的能力。主 App / Share Extension 的 Bundle ID 與 App Group 需由相同 Apple Team 簽名。

### 2. 語音訊息：OGG／Opus 原生播放

新增 Swift Package 依賴 `sbooth/opus-binary-xcframework` 0.3.0 與 `sbooth/ogg-binary-xcframework` 0.1.3，使用 opusfile 解碼 Telegram 常見 OGG/Opus 至暫存 PCM WAV，交給 iOS AVAudioPlayer 播放。新增 OggOpusTranscoder.swift、VoicePlayerScreen.swift。雙擊語音訊息會直接開啟播放器，下載完成後自動開始播放；原生 UIKit 介面提供 VoiceOver 可讀的播放、暫停、快轉進度、播放速度 1／1.5／2 倍和秒數。M4A、MP3 等 iOS 已支援格式則直接使用原生解碼。

一般文件改用 AccessibleDocumentViewer.swift，具有原生 UIKit「預覽檔案」（Quick Look）、「使用其他 App 開啟或分享檔案」，避免下載後陷入沒有可朗讀內容的 SwiftUI 檔案頁。

### 3. iOS Share Extension 直接傳送（更新：不必再開啟主 App）

已改掉前一版「暫存後等待使用者手動開主 App」的流程。使用者從任何 App 選擇分享 → Accessi Gram → 選收件人／群組 → 輸入說明 → 傳送，**由 Share Extension 本身直接使用 TDLib 上傳**。程式會等到 Telegram 的 updateMessageSendSucceeded 才完成分享視窗；失敗會顯示原因及「重新傳送」按鈕，部分已傳送的附件重試時不會重複傳送。絕不把「已加入本地佇列」當作傳送成功。

實作：
- Shared/ShareSessionBootstrap.swift：主 App 在首次啟動 TDLib 以前，將既有已登入的 TDLib 資料庫複製到 App Group 下獨立的 share-tdlib。API ID／Hash 及 TDLib 資料庫解密金鑰存放在受 iOS 檔案保護、僅 App Group 成員可存取的 share-session.json。
- ShareExtension/ExtensionTelegramSender.swift：分享端用另一個 TDLib client 及獨立的 share-tdlib 資料庫連線，依據收件人 ID 用 sendMessage 發送文字、圖片、影片與文件，等待後續傳送成功／失敗更新；不與主 App 同時打開相同 SQLite 目錄，也無須再次輸入帳密。已加入失敗重試時不重覆傳送已完成附件的處理。
- ShareExtension/ShareViewController.swift：選擇收件人、輸入說明、準備媒體後，直接 await ExtensionTelegramSender.send；只有 Telegram 回報送出才關閉分享視窗。僅附件在傳送過程會暫存至 App Group，確認成功後清掉。
- NativeTelegram/project.yml：Share Extension 已直接依賴 TDLibFramework 與共用的 ShareSessionBootstrap；打包時要確保 .appex 可連結 TDLib 的 XCFramework、保留 App Groups entitlements。
- TelegramService.logOut() 現在會清除分享專用登入副本，避免原帳號登出後 Extension 還能沿用舊授權。

**重要：OC 安裝／首次啟動順序**：保留原有 Bundle ID、Keychain、ApplicationSupport/tdlib；用具備 App Groups 的新版簽署設定覆蓋安裝。**更新後開啟 Accessi Gram 一次**，讓 App 在打開已登入 TDLib 前備妥分享專用授權副本。此後從其他 App 分享**無須再打開 Accessi Gram**。若是全新安裝，必須登入、完整關閉並再打開一次，供主 App 建立分享用資料庫快照。若副本未就緒或授權失效，分享端會明確顯示錯誤，不會默默留在佇列。

Apple 的 Share Extension 可以直接進行網路傳輸，但無法保證主 App 會由分享視窗強制啟動。本版不依靠強制啟動；傳送時需維持分享視窗開啟，**大檔上傳受 iOS Extension 生命周期／資源上限影響，不保證 App 關閉後長時間持續上傳**。App Group 中的授權副本需視同 Telegram 登入敏感資料保護，不可備份或提交公開 GitHub。

### 4. VoiceOver 選單與鍵盤收合

訊息操作、機器人互動、表情回應現在改用 AccessibleSystemMenu.swift 的真正 UIKit UIAlertController action sheet，由 iOS 系統處理 VoiceOver 焦點與操作；已刪除無法觸摸／朗讀的 AccessibleChoiceSheet。圖片、影片、語音與一般檔案統一使用 AccessibleMediaSheet.swift 原生 UIKit 頁面，避免舊 SwiftUI MediaViewer 空白。

輸入文字後點傳送**不收鍵盤**，方便連續輸入；用 VoiceOver 左右滑從輸入列回到任一訊息時，該訊息取得焦點後自動收鍵盤，不強制跳開訊息焦點；在編輯框空白時點錄音，也會先收起鍵盤。

### 5. 截圖裡上下黑邊與底部空白

已補上正式 iOS LaunchScreen.storyboard 並於 AppInfo.plist 設定 UILaunchStoryboardName，避免舊型 iPhone 相容縮放造成整個 App 上下留下大片黑色區域。這是全畫面尺寸問題，不應用手動偏移或額外 padding 來掩蓋。

### OC 編譯與簽署

```bash
cd Accessi-gram/NativeTelegram
TELEGRAM_API_ID="$MY_TG_API_ID" \
TELEGRAM_API_HASH="$MY_TG_API_HASH" \
bash scripts/build.sh
```

此腳本提供**未簽名 IPA**。背景 APNs 整組已移除，不需要 Push Notifications capability、推播伺服器或憑證。**Share Extension 仍須有效 App Groups 權限**，OC 需正確簽署。IPA 內需有 PlugIns/AccessiGramShareExtension.appex。維持 main Bundle ID、Keychain、TDLib 路徑不變；請勿讓簽名或 app group 設定改變既有帳號容器。App 與 extension 的 CFBundleVersion 已由 CURRENT_PROJECT_VERSION 控制，OC 可照原有流程自動遞增，不需把尾碼寫死。

**狀態：** 原始碼已提交，但此環境未執行 Xcode 編譯及真機檢查，因此語音播放、Share Extension 與全螢幕修正不能宣稱已實測成功。由 OC 拉取最新提交後依 Apple 簽署能力和 Telegram 憑證進行打包。


### 2026-11-14 最新覆蓋說明：直接分享已取代舊版暫存流程

舊版文件與說明中「分享後要再手動打開 App」「分享成功僅代表暫存」已作廢。OC 應以此段及上方最新版第 3 節為準。此修改與上個尚未測試版本的 OGG/Opus 語音播放器、UIKit 選單、鍵盤收合、LaunchScreen 全螢幕修復一起留在 **rewrite/native-tdlib-voiceover**。請一次拉取分支最新提交打包，不需要中間版本。此環境沒有 Xcode／實機環境，不能把程式碼提交等同確認真機送出成功。

## 2026-11-15：iOS 18.7.8 實機回報統整修正（此節優先於舊交接）

1. **分享找不到聯絡人**：不再要求主 App 預先匯出手機聯絡人。ShareRecipientPicker 直接呼叫 ExtensionTelegramSender.recentRecipients()；該方法先讓 TDLib 載入 Main Chat List，再 getChats(limit=100)，逐一 getChat 取標題，顯示最近私聊／群組／頻道，並保留本機快取供下次即刻顯示。只有分享專用 TDLib 登入不存在或失效時才顯示明確錯誤，而非永遠提示「請同步聯絡人」。
2. **傳送檔案按「打開」完全沒反應**：SwiftUI fileImporter 已移除，換成 AccessibleDocumentPicker.swift 包裝 UIKit UIDocumentPickerViewController (asCopy: true)，由 UIDocumentPickerDelegate.documentPicker(didPickDocumentsAt:) 取得 iOS 18 的文件 URL。App 自有的暫存檔直接複製，外部檔案提供者才使用 NSFileCoordinator＋Security Scope。選取後立即以旁白宣告準備階段，TDLib 接受後才說明傳送中，錯誤明確顯示。
3. **機器人和所有更多選單空白**：移除 AccessibleChoiceSheet.swift（舊的 UIViewControllerRepresentable／巢狀 sheet）；現在訊息操作、機器人互動、表情回應、編輯文字皆透過 AccessibleSystemMenu.swift 的 iOS 原生 UIAlertController 呈現。附件／語音／影片／照片改成 AccessibleMediaSheet.swift 原生 UIKit 容器，移除過時 SwiftUI MediaViewer。分享收件人與轉寄仍使用 UIKit UITableView，每個聊天是有名稱的單一可點擊元素。
4. **訊息最後出現「垂直捲軸，14頁，100%」且無法滑到輸入列**：AccessibleMessageTimeline.swift 取消可聚焦的捲軸可視指示器，新增 MessageTailRedirect 作為表格最尾端的焦點轉接；VoiceOver 到最新訊息後，接著移到 ComposerBarView 的真實「傳送照片或影片」，下一步才是「傳送檔案或附件」「訊息編輯框」。不改既有歷史翻頁／錨點保留方式。
5. **背景推播取消**：刪除所有 APNs 請求、系統通知設定入口、裝置 token 註冊及推播 entitlement；只保留有用的 App 前景新訊息震動。
6. **不改登入**：保留原本的主 App Bundle ID、Keychain、TDLib database 路徑與已登入帳號；OC 直接更新同一分支最新 commit 覆蓋安裝。Share Extension 仍需要和主 App 同一 Team 的 App Groups entitlement，但不需要任何私人推播伺服器。

依使用者指示，此處只提交原始碼給 OC，沒有做 Xcode 編譯或回歸／防禦性測試，不得以本次提交宣稱 iOS 18.7.8 實機已驗證。主分支 main 未動。
