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

### 1. APNs 遠端推播與 iOS 原生通知

新增 SystemNotificationManager.swift，整合 UIApplicationDelegate、UNUserNotificationCenter 授權、registerForRemoteNotifications、APNs device token、TDLib registerDevice(deviceTokenApplePush)、processPushNotification。使用者在「設定 → iOS 系統通知」點兩下請求權限；允許後自動向 Telegram 註冊裝置。App 前景仍使用原有震動，不重覆發系統橫幅；背景或關閉 App 時依賴 iOS 原生 APNs 通知中心、鎖定畫面與系統音效，點擊通知後可開啟對應對話。

**這需要 OC 同時完成下列外部設定，僅編譯程式碼不足以保證背景推播：**

- Apple Developer 對主 App 的 App ID org.accessigram.native 開啟 Push Notifications 與 App Groups，並對 Share Extension 的 App ID org.accessigram.native.share 開啟同一個 App Group：group.org.accessigram.native。建立含這些權限的 iOS provisioning profiles，且都要由相同 Apple Team 簽名。先簽署 PlugIns 內的 .appex，再簽署主 .app。
- 主 App 的 Resources/App.entitlements 已提供 aps-environment=development。若使用正式發行描述檔，必須改成 production 並使用生產環境 APNs token；不可以用開發環境 token 註冊生產環境，反之亦然。
- Bundle 的 TelegramAPNsIsSandbox 必須與 provision profile 匹配。build.sh 支援 `TELEGRAM_APNS_SANDBOX=YES` (開發) 或 `TELEGRAM_APNS_SANDBOX=NO` (正式) 注入 Info.plist，預設 false。
- **Telegram API 應用在 my.telegram.org 必須配置相容的 Apple 推播憑證／伺服器驗證資料**。這是 Telegram 向 Apple 發送 APNs 所需的服務端憑證，不能單靠 App 端自行產生，也不能借用官方 Telegram 的推播資格。
- 正式的遠端通知聲音由 Telegram APNs payload 及 iOS 通知設定決定；本版使用 iOS 系統原生音效，不虛設無法生效的「任選 iOS 原生通知音」選單。使用者可透過 iOS 設定調整允許通知、聲音及顯示方式。
- 如果使用的個人簽署方案不支援 Push Notifications / App Groups，就無法保證 App 關閉後收到系統推播。前景震動不受此影響。App 被使用者強制結束後，iOS 不保證會喚醒它處理背景 silent push；若遠端 alert push 配置正確，系統仍可顯示通知。

### 2. 語音訊息：OGG／Opus 原生播放

新增 Swift Package 依賴 `sbooth/opus-binary-xcframework` 0.3.0 與 `sbooth/ogg-binary-xcframework` 0.1.3，使用 opusfile 解碼 Telegram 常見 OGG/Opus 至暫存 PCM WAV，交給 iOS AVAudioPlayer 播放。新增 OggOpusTranscoder.swift、VoicePlayerScreen.swift。雙擊語音訊息會直接開啟播放器，下載完成後自動開始播放；原生 UIKit 介面提供 VoiceOver 可讀的播放、暫停、快轉進度、播放速度 1／1.5／2 倍和秒數。M4A、MP3 等 iOS 已支援格式則直接使用原生解碼。

一般文件改用 AccessibleDocumentViewer.swift，具有原生 UIKit「預覽檔案」（Quick Look）、「使用其他 App 開啟或分享檔案」，避免下載後陷入沒有可朗讀內容的 SwiftUI 檔案頁。

### 3. 真正的 iOS Share Extension

新增 AccessiGramShareExtension target（.appex），ShareExtension/ShareViewController.swift、Shared/ShareMailbox.swift。從其他 App 叫出系統分享選單可開啟 Accessi Gram 分享視窗，在視窗內搜尋私聊／群組／聯絡人，輸入說明文字並確認分享。App 將最近聊天和聯絡人清單同步到 App Group 容器；Share Extension 把檔案和說明文字安全寫入共用容器佇列；**再次開啟 Accessi Gram 時會自動送出**，不再只有進入主程式卻不選收件人。

**iOS 限制：** Apple 不允許一般 Share Extension 使用未公開 API 強制啟動主 App，因此這個版本採用官方支援的「選收件人 → 暫存 → 開啟 App 自動送出」流程，而不是保證 Share Extension 在背景就直接以使用者帳號送出。分享對話框必須清楚告知「請開啟 Accessi Gram 後完成傳送」，不可顯示「已成功傳送」假訊息。Share Extension 不重複登入 TDLib，不共用 TDLib 資料庫句柄，避免破壞主 App 的登入。

### 4. VoiceOver 選單與鍵盤收合

訊息操作、機器人互動、表情回應的 SwiftUI confirmationDialog 由 AccessibleChoiceSheet.swift 的原生 UIKit UITableView 取代，每個選項具有獨立繁體中文 VoiceOver 焦點、標籤及操作提示。音訊播放器和一般文件亦改為 UIKit。

輸入文字後點傳送**不收鍵盤**，方便連續輸入；用 VoiceOver 左右滑從輸入列回到任一訊息時，該訊息取得焦點後自動收鍵盤，不強制跳開訊息焦點；在編輯框空白時點錄音，也會先收起鍵盤。

### 5. 截圖裡上下黑邊與底部空白

已補上正式 iOS LaunchScreen.storyboard 並於 AppInfo.plist 設定 UILaunchStoryboardName，避免舊型 iPhone 相容縮放造成整個 App 上下留下大片黑色區域。這是全畫面尺寸問題，不應用手動偏移或額外 padding 來掩蓋。

### OC 編譯與簽署

```bash
cd Accessi-gram/NativeTelegram
TELEGRAM_API_ID="$MY_TG_API_ID" \
TELEGRAM_API_HASH="$MY_TG_API_HASH" \
TELEGRAM_APNS_SANDBOX=YES \
bash scripts/build.sh
```

上述 YES 僅適用開發型 APNs 描述檔，生產簽名須改用 NO，並讓 App.entitlements 的 aps-environment 與描述檔一致。此腳本提供**未簽名 IPA**，**不會自動申請 APNs 金鑰、不會向 Telegram 註冊服務端憑證、也不會替 OC 建立 Apple App Groups 能力**。IPA 內需有 PlugIns/AccessiGramShareExtension.appex。維持 main Bundle ID、Keychain、TDLib 路徑不變；請勿讓簽名或 app group 設定改變既有帳號容器。App 與 extension 的 CFBundleVersion 已由 CURRENT_PROJECT_VERSION 控制，OC 可照原有流程自動遞增，不需把尾碼寫死。

**狀態：** 原始碼已提交，但此環境未執行 Xcode 編譯及真機檢查，因此語音播放、背景 APNs、Share Extension 與全螢幕修正不能宣稱已實測成功。由 OC 拉取最新提交後依 Apple 簽署能力和 Telegram 憑證進行打包。
