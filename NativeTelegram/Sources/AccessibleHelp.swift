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
                  explanation: "在聊天訊息區用單指左右滑，每次移動到一則訊息。到最新訊息之後，繼續右滑會直接進入照片、附件、斜線命令與訊息編輯框，不經過人工轉接項目。接近歷史前端時會預先載入更早內容；若網路不穩，可能需要一些時間。"),
            Topic(title: "群組與頻道",
                  explanation: "群組和頻道也使用相同的訊息閱讀方式。長篇貼文的文字與附件描述合在同一則訊息中，避免左右滑動時被拆成多個焦點。"),
            Topic(title: "聊天已讀狀態",
                  explanation: "進入對話閱讀訊息後會自動標記已讀，返回聊天列表時同步未讀數量與手動標記的未讀狀態。")
        ]),
        ("傳送訊息與附件", [
            Topic(title: "輸入文字與收起鍵盤",
                  explanation: "打開聊天後，找到訊息編輯框，點兩下輸入文字。按傳送後鍵盤會保持展開，方便連續傳送；用旁白左右滑回聊天訊息時，鍵盤會自動收起而不改變正在朗讀的訊息焦點。"),
            Topic(title: "錄製語音訊息",
                  explanation: "訊息編輯框沒有文字時，右邊是開始錄製語音訊息按鈕。開始後，同一位置變成停止錄音並傳送，旁邊還有取消錄音。停止並傳送會將剛錄好的語音交給 Telegram 傳送。"),
            Topic(title: "照片、影片與檔案",
                  explanation: "訊息編輯框左邊依序是傳送照片或影片，以及傳送檔案或附件。iOS 18 會開啟原生檔案選取器，選好按「打開」會直接準備傳送。收到的一般檔案會使用 iOS 的 Quick Look 或分享功能開啟。"),
            Topic(title: "播放語音訊息",
                  explanation: "對語音訊息點兩下就能開啟播放器並自動開始播放，支援 Telegram 的 OGG Opus 語音。一般 MP3、M4A 等音訊檔也使用同一播放器。VoiceOver 雙指雙擊可切換播放與暫停，並支援鎖定畫面的系統播放／暫停媒體指令。播放期間可鎖定 iPhone 螢幕持續收聽，並可從鎖定畫面播放、暫停或調整進度。關閉附件播放器才會結束播放。")
        ]),
        ("訊息操作", [
            Topic(title: "訊息上下滑動",
                  explanation: "在一則訊息上以單指上下滑，選擇回覆、複製、翻譯成繁體中文、更多操作或開啟附件，再點兩下執行。更多操作會使用 iOS 原生動作選單，裡面的按鈕可直接以旁白左右滑。讀完最新訊息可以繼續滑到照片、檔案和編輯框。"),
            Topic(title: "開啟訊息連結",
                  explanation: "遇到含網址或文字超連結的訊息、媒體說明，在這則訊息上切換到旁白的動作轉輪，選擇「開啟連結」，點兩下就會透過 iOS 系統交由預設瀏覽器開啟。每個連結各有一個獨立動作。"),
            Topic(title: "刪除整則對話",
                  explanation: "在聊天列表找到私聊，使用旁白動作轉輪選「刪除對話」，依 Telegram 權限選擇僅為我刪除或為雙方刪除。群組和頻道會顯示「退出群組」或「離開頻道」，確認後才執行。也支援一般列表滑動操作。"),
            Topic(title: "表情回應",
                  explanation: "訊息選單的表情回應會先向 Telegram 查詢這則訊息允許使用的表情，不能回應的訊息會提示原因。已回應的表情可再次選擇來取消；訊息旁白會朗讀現有回應的表情、數量及自己是否已回應。"),
            Topic(title: "轉寄訊息",
                  explanation: "從訊息選單選「轉寄訊息」，在最近聊天清單中搜尋或選擇收件者。轉寄使用 Telegram 原生功能，原始照片、影片、檔案、文字連結及媒體說明會一起傳送；若原訊息禁止轉寄，Telegram 會回報失敗原因。"),
            Topic(title: "搜尋聊天內容",
                  explanation: "進入聊天室後，在右上角點「搜尋聊天內容」，輸入關鍵字按搜尋。搜尋 Telegram 的聊天歷史，會同時試繁體和簡體的字形，點兩下結果可回到聊天室並直接跳至該則訊息。"),
            Topic(title: "快速翻譯",
                  explanation: "選擇翻譯成繁體中文後，會直接朗讀翻譯結果，不必切換頁面。翻譯功能使用 Google 免費網頁端點；只有你主動選擇翻譯的文字才會送往 Google，秘密聊天的文字也不例外。"),
            Topic(title: "BotFather 斜線命令",
                  explanation: "聊天室輸入列的照片、檔案按鈕旁有「機器人斜線命令」。點開後顯示機器人設定好的 / 指令，選擇任一指令會立即傳送，不會進入編輯框，也不需要再按傳送。這與機器人訊息下方的互動按鈕不同，兩種功能都保留。"),
            Topic(title: "機器人按鈕",
                  explanation: "遇到有互動按鈕的機器人訊息，可用上下滑選擇展開機器人選單，再從清楚標示的按鈕中選擇操作。")
        ]),
        ("通知與分享", [
            Topic(title: "背景推播已取消",
                  explanation: "這個版本不需要背景推播伺服器或 APNs 權限；關閉 App 時不提供遠端系統通知，App 開啟期間仍能透過設定中的新訊息震動提醒。"),
            Topic(title: "前景震動",
                  explanation: "App 開啟期間收到新訊息會震動，設定可選擇開啟或關閉；載入舊訊息與自己送出的訊息不會觸發。"),
            Topic(title: "從其他 App 分享",
                  explanation: "在其他 App 的分享介面選擇 Accessi Gram，先選擇聯絡人或群組，再輸入說明文字。分享選單會直接從 Telegram 取得最近的聊天清單，讓你選擇聯絡人、群組或頻道。分享延伸功能擁有獨立的 Telegram 登入。第一次分享時在分享視窗完成一次登入，往後會保留登入狀態，不需要再開啟主 App，也不需要 App Groups 簽署權限。選好最近對話、輸入說明後直接傳送，收到 Telegram 成功回報才結束分享。大型影片仍需保持分享視窗開啟。")
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
