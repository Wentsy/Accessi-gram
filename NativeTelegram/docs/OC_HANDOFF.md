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
4. **每次開啟「Unexpected setTdlibParameters」**：TDLib 初始狀態推送和手動 `getAuthorizationState` 回覆可能重覆。設置 `parametersRequested`，只有在 `authorizationStateWaitTdlibParameters` 且尚未傳過參數時才呼叫 `setTdlibParameters`。重複回覆的 race 不再彈出無害錯誤。只要維持相同 Bundle ID / Keychain 權限 / TDLib database 路徑，更新不應主動登出。
5. **API 可直接編入未簽名 IPA**：新的 `scripts/build.sh` 可使用 `TELEGRAM_API_ID` 與 `TELEGRAM_API_HASH` 環境變數。專案將值注入 `Info.plist`；App 首次讀取後存入 iOS Keychain，日後無需反覆輸入。若沒有環境變數，仍可在登入頁輸入一次。請不要把真實金鑰放回公開 Git 歷史。

**OC 建置方式（在本機私有環境設定變數，勿把數值貼到公開倉庫）：**

```bash
cd Accessi-gram/NativeTelegram
TELEGRAM_API_ID="$MY_TG_API_ID" TELEGRAM_API_HASH="$MY_TG_API_HASH" bash scripts/build.sh
```

注意：只要把 API 金鑰嵌進 IPA，就無法防止擁有 IPA 的人提取；這是免輸入換取的取捨。若實際金鑰先前已提交到公開 repo，請評估撤銷／更換並從此避免再次提交。
