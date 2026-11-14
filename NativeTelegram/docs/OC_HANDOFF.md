# OC 打包交接：Accessi Gram Native

## 分支

- GitHub: https://github.com/Wentsy/Accessi-gram/tree/rewrite/native-tdlib-voiceover/NativeTelegram
- Branch: \`rewrite/native-tdlib-voiceover\`
- 舊 Turrit IPA 補丁仍在原倉庫 main，**不要將兩個專案混編或直接把舊 dylib 注入這個 App**。
- 這是全新 SwiftUI + UIKit + TDLib iOS 原生專案；無需 Turrit IPA。

## 一次打包

\`\`\`bash
git clone -b rewrite/native-tdlib-voiceover https://github.com/Wentsy/Accessi-gram.git
cd Accessi-gram/NativeTelegram
brew install xcodegen
bash scripts/build.sh
\`\`\`

輸出 \`dist/AccessiGramNative-unsigned.ipa\`；iPhone 安裝前仍需要用既有簽名工具重新簽名（TDLib Framework 和主 App 都需正確處理），或由 Xcode 設定開發團隊進行簽署。可在 \`xcodegen generate\` 之後開啟 \`AccessiGramNative.xcodeproj\`。

- iOS 最低版本 16。
- SPM 自動從 \`Swiftgram/TDLibFramework\` 下載官方 TDLib 的預編譯 XCFramework，初次需要較多網路流量。
- 首次啟動必須在本機輸入自己向 \`my.telegram.org\` 申請的 API ID / API Hash；不內建、也不能共用第三方公開的金鑰。
- API 金鑰及本機資料庫的隨機加密金鑰均存放 iOS Keychain，沒有上傳到 GitHub。
- Google 翻譯是 Google 網頁公開端點，不是官方有 SLA 的 Cloud Translation API，可能有額度或封鎖限制。文字僅在手動選擇翻譯時才送給 Google。

## 實作範圍

- 登入：手機號碼、驗證碼、二步驟密碼、QR Code、電子郵件驗證狀態。
- 聊天列表：未讀數、預覽、搜尋、封存、置頂、標記未讀、刪除對話、動態載入更多、新增聊天、聯絡人以及 username 尋找。
- 訊息：一則一個 VoiceOver 焦點；口述順序固定為「發送者、訊息內容、發送時間」。
- 連續閱讀：所有私聊、群組、頻道共用 \`AccessibleMessageTimeline.swift\` 內的 \`UITableView\`。當行數進入距離歷史最前端約 30 列時就提前載入更早一批最多 75 則訊息。以 diff 插入列，保留可見訊息錨點及其畫面位置，避免整表刷新和主動移動 VoiceOver 焦點。
- 訊息操作：上下滑動可選翻譯（中文結果直接 VoiceOver announcement）、回覆、複製、更多操作；更多操作含轉寄、編輯、刪除、表情回應及附件。
- 訊息內容：文字、照片、影片、語音、音訊、檔案、貼圖描述、投票選項與常見系統訊息。
- 媒體：PhotosPicker、檔案挑選、麥克風錄音、照片檢視、影片播放、音檔播放及分享。
- 機器人：inline keyboard / reply keyboard 會以 VoiceOver 自訂動作與可展開選單提供，支援基本 callback、URL 與文字命令。
- 翻譯：\`GoogleTranslate.swift\` 按需連到免金鑰網頁端點，長篇貼文分段翻譯。

## 請保留的 UX 不變條件

1. 聊天訊息列表要做到**一滑一則**，不能把輸入框、圖片元件、下方工具列混進訊息列的焦點序列。
2. 讀到歷史第一則前必須已啟動下一批的預載；插入後保留目前朗讀的訊息物件與其座標，**禁止在分頁完成時發 \`screenChanged\` / \`layoutChanged\` 強制跳焦**。
3. 翻譯是訊息自己的 \`UIAccessibilityCustomAction\`，從 VoiceOver 上下滑選「翻譯成繁體中文」，點兩下後直接宣告繁體中文結果；不必強迫跳到新頁。
4. 群組和頻道不可另外換用不同的滾動實作，統一沿用訊息時間軸；大段貼文的附件和文字仍只有一個訊息焦點。
5. 初次進入聊天室時，停在最新訊息區；再透過 VoiceOver 左右滑及歷史預載往回、往後閱讀，不要用每次 \`reloadData\` 的方式進行翻頁。

## 已知未完成／需要 OC 確認

此交接版本**沒有在 macOS / Xcode 編譯，也沒有真實 Telegram 帳號的功能驗證**；不能稱作穩定 IPA。若 Xcode 報 SDK 或 TDLib API 版本不相容，先以此分支修正，勿改動舊版 \`main\`。我們沒有在這裡進行使用者不希望的回歸測試。

- 不含背景推播註冊、即時通話、影片通話、Stories、完整群組管理員工具、討論串／論壇主題、付款、完整貼圖鍵盤。
- 語音採 iOS M4A AAC；TDLib 支援傳送但部分 Telegram 客戶端可能當成一般音檔顯示，若需完全一致的 Telegram Opus/OGG 語音泡泡需加轉碼。
- 機器人部分進階 inline 模式（例如付款、Web App）尚未實作；一般按鈕可操作。
- 原版 Telegram 的聊天室傳送權限、管理員細節及群組論壇子主題需要後續擴充。
- Google 免費端點不保證穩定、無隱私 SLA。祕密聊天訊息若使用翻譯，文字也會送到第三方，UI 已提醒。
