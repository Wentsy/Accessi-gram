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

## 0.2.6 聊天閱讀及彈窗（2026-11-14）

- 取消虛擬 HistoryBoundary，避免從訊息末端滑到虛構的按鈕。
- 接近可視訊息區的前後兩項時，提前透過 ListView 原生 scroller 露出鄰近訊息，不重設目前單指閱讀焦點。
- 保留 iOS 18 的相鄰文字導覽與 Read All 列表翻頁處理，但不保證網路未載入歷史時能無限連讀。
- TextAlertContentNode 的 actionNodes、ActionSheetButtonNode 等採用固定 AX 元素，直接執行原生 performAction。
- 沒有 iPhone 實機，不能聲稱 VoiceOver 行為已實測；需由 OC 編譯與使用者檢查。

## 0.2.7 全域清單接續閱讀

- 從已測試改善的 0.2.6 延伸；保留聊天專屬 HistoryViewport，新增非聊天用的 GlobalPaginationState 及 prepareGlobalPagination。
- 原生 ListViewBackingView 使用可見 itemNodes 判定接近頂／底邊界，依前一焦點判斷方向並預先滾動；監聽佈局變更可在載入新資料時繼續露出內容。
- 一般垂直 UIScrollView、UITableViewCell、UICollectionViewCell、UILabel、UIButton 上的可讀內容會進行保留焦點的短距離預讀。輸入框不參與。
- 原生翻頁（含三指手勢）仍保留；不強迫移動目前的 VoiceOver 焦點。
- 警告：後端若未取得下一批資料，單靠客戶端不能保證自動載入；請以實機操作評估。
- 原生自訂 AlertController action 使用 `pressed`、ActionSheet item 使用 `buttonPressed`，避免呼叫 Swift-only `performAction` 導致不可點擊。
