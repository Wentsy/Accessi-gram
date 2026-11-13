# 原始基準

- 專案名稱：Accessi gram
- 原始檔：Turrit_1.5.5_78c.ipa
- CFBundleIdentifier：com.seastar.turrit
- CFBundleShortVersionString：1.5.5
- CFBundleVersion：10387
- SHA-256：d4424474abf9c7933b146a4a5ef6deda48d30ccf69675dd08eede0bb67ec6df8
- 主程式、TurritUIFramework、TurritCoreFramework、Share extension 的 LC_ENCRYPTION_INFO_64 cryptid 都是 0。
- 本機分析日期：2026-11-14（台灣時間）。

原包已含 TGExtra、zxPluginsInject、TelegramScreenshotBypass、sideloadFixerLol、TelegramChatFixer 及 CydiaSubstrate。打包器保留它們，尚未驗證其全部行為。

從 IPA Objective-C metadata 確認的目標與方法/欄位摘要見 `binary-targets.json`。欄位名稱只用於 Swift Mirror，不依賴反組譯出的固定 offset。

實作參考 TelegramMessenger/Telegram-iOS 的 TabBarComponent、SelectablePeerNode、ListView 與 ChatControllerLoadDisplayNode。上游最新版不是此 IPA 的原始碼；型別與欄位仍以 IPA metadata 為準。

Apple 無障礙介面參考：
- https://developer.apple.com/documentation/objectivec/nsobject-swift.class/accessibilityperformescape()
- https://developer.apple.com/documentation/objectivec/nsobject-swift.class/accessibilityscroll(_:)
- https://developer.apple.com/documentation/uikit/uiaccessibility/notification/pagescrolled

尚無 iPhone/VoiceOver 實測紀錄。不能由 Mach-O 檢查推論手勢、流暢度或所有操作均符合 Apple 無障礙要求。
