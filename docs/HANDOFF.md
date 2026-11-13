# 接手事項

使用者優先順序：底部分頁 → 返回按鈕/雙指 Z 字 → 分享檔案與選取對象 → 開啟聊天到最新訊息 → 三指捲動與連續朗讀。

0.1.0 採用可獨立編譯的 Swift/Objective-C dylib，無需原 Turrit 原始碼。原 IPA 已解密。變更只限於新增補丁及 IPA 注入打包流程。

需實機確認的實質限制：

1. Turrit Swift 私有型別能否完整提供 Mirror 資料；若套件沒有反射資料，對應功能會沿用原本行為，不會宣稱成功。
2. TabBarComponent 的 itemViews、component、items 在不同版型下是否吻合，及是否正確保留搜尋入口。
3. NavigationButtonItemNode 的 pressed callback 是否符合 () -> Void；其他 Swift callback 不使用不安全的強制轉型。
4. 載入聊天後 downPressed 會沿用 Telegram 的導覽堆疊/搜尋語意；目前一般新開聊天會走原本到底部的路徑，從搜尋或引用訊息進入的語意需另確認。
5. 訊息可見範圍排序會保留原容器，不新增定時 screenChanged/layoutChanged 廣播；尚不能保證雙指連續朗讀自動讀完未載入的歷史。
6. 分享 extension 的 app groups/簽名需由實際使用的簽名工具保留/重配；僅注入 dylib 無法解決錯誤的 entitlement。
7. 無內容的圖示按鈕、送出按鈕、附件各種彈窗尚需實機結果定位；不要對所有 UIView 全域開啟 isAccessibilityElement。

只在使用者回報可用後更新穩定基準。不要將未驗證的完整支援寫入版本說明。
