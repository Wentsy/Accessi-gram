import UIKit

/// Read-only documentation is deliberately outside Settings. Each topic is one
/// accessible text element, and no text row pretends to be an adjustable option.
@MainActor
final class AccessibleHelpController: UITableViewController {
    private struct Topic {
        let title: String
        let explanation: String
    }

    private let sections: [(title: String, topics: [Topic])] = [
        ("聊天與朗讀", [
            Topic(title: "訊息朗讀順序",
                  explanation: "每則訊息是獨立的旁白焦點，依序朗讀發送者姓名、訊息內容、發送時間。文字、語音、照片、影片、群組與頻道訊息都使用同一套順序。"),
            Topic(title: "左右滑動與歷史訊息",
                  explanation: "在聊天訊息區用單指左右滑，每次移動到一則訊息。接近歷史前端時，程式會預先載入更早的內容，並保留當前閱讀位置。若網路不穩，訊息載入可能需要一些時間。"),
            Topic(title: "群組與頻道",
                  explanation: "群組和頻道也使用相同的訊息閱讀方式。長篇貼文的文字與附件描述合在同一則訊息中，避免左右滑動時被拆成多個焦點。")
        ]),
        ("傳送訊息與附件", [
            Topic(title: "輸入文字與收起鍵盤",
                  explanation: "打開聊天後，找到訊息編輯框，點兩下輸入文字。按傳送後鍵盤會保持展開，方便連續傳送；用旁白左右滑回聊天訊息時，鍵盤會自動收起而不改變正在朗讀的訊息焦點。"),
            Topic(title: "錄製語音訊息",
                  explanation: "訊息編輯框沒有文字時，右邊是開始錄製語音訊息按鈕。開始後，同一位置變成停止錄音並傳送，旁邊還有取消錄音。停止並傳送會將剛錄好的語音交給 Telegram 傳送。"),
            Topic(title: "照片、影片與檔案",
                  explanation: "訊息編輯框左邊依序是傳送照片或影片，以及傳送檔案或附件。iOS 18 會開啟原生檔案選取器，選好按「打開」會直接準備傳送。收到的一般檔案會使用 iOS 的 Quick Look 或分享功能開啟。"),
            Topic(title: "播放語音訊息",
                  explanation: "對語音訊息點兩下就能開啟播放器並自動開始播放，支援 Telegram 的 OGG Opus 語音。可使用播放暫停、播放進度和速度按鈕，返回聊天室即停止播放。")
        ]),
        ("訊息操作", [
            Topic(title: "訊息上下滑動",
                  explanation: "在一則訊息上以單指上下滑，選擇回覆、複製、翻譯成繁體中文、更多操作或開啟附件，再點兩下執行。更多操作會使用 iOS 原生動作選單，裡面的按鈕可直接以旁白左右滑。讀完最新訊息可以繼續滑到照片、檔案和編輯框。"),
            Topic(title: "快速翻譯",
                  explanation: "選擇翻譯成繁體中文後，會直接朗讀翻譯結果，不必切換頁面。翻譯功能使用 Google 免費網頁端點；只有你主動選擇翻譯的文字才會送往 Google，秘密聊天的文字也不例外。"),
            Topic(title: "機器人按鈕",
                  explanation: "遇到有互動按鈕的機器人訊息，可用上下滑選擇展開機器人選單，再從清楚標示的按鈕中選擇操作。")
        ]),
        ("通知與分享", [
            Topic(title: "背景推播已取消",
                  explanation: "這個版本不需要背景推播伺服器或 APNs 權限；關閉 App 時不提供遠端系統通知，App 開啟期間仍能透過設定中的新訊息震動提醒。"),
            Topic(title: "前景震動",
                  explanation: "App 開啟期間收到新訊息會震動，設定可選擇開啟或關閉；載入舊訊息與自己送出的訊息不會觸發。"),
            Topic(title: "從其他 App 分享",
                  explanation: "在其他 App 的分享介面選擇 Accessi Gram，先選擇聯絡人或群組，再輸入說明文字。分享選單會直接從 Telegram 取得最近的聊天清單，讓你選擇聯絡人、群組或頻道。Share Extension 會自行連線 Telegram 並傳送，收到伺服器確認成功才結束分享視窗，不需要再開啟主 App。首次更新後要開啟新版 Accessi Gram 一次，建立分享專用的登入資料。分享大型影片時請保持分享視窗開啟。")
        ]),
        ("其他", [
            Topic(title: "登入與同步",
                  explanation: "更新 App 時保留相同的 Bundle ID、Keychain 權限與 TDLib 資料庫，通常不需要重新登入。聊天列表會持續從 Telegram 載入對話，設定中的重新同步對話可主動要求更新。"),
            Topic(title: "無障礙說明",
                  explanation: "這個頁面是使用指南，不是設定清單。只有按下後會執行動作或能調整數值的項目才會放在設定頁面。")
        ])
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "使用指南"
        tableView.register(AccessibleSettingCell.self, forCellReuseIdentifier: "guide")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 110
        tableView.allowsSelection = false
        tableView.accessibilityLanguage = "zh-TW"
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].topics.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    override func tableView(_ tableView: UITableView, cellForRowAt path: IndexPath) -> UITableViewCell {
        let item = sections[path.section].topics[path.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "guide", for: path) as! AccessibleSettingCell
        cell.display(title: item.title, detail: item.explanation)
        cell.accessibilityLanguage = "zh-TW"
        return cell
    }
}
