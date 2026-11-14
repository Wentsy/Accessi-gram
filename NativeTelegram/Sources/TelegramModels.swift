import Foundation
import Combine

struct TelegramContact: Identifiable {
    let id: Int64
    let name: String
}

typealias JSONObject = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func object(_ key: String) -> JSONObject { self[key] as? JSONObject ?? [:] }
    func objects(_ key: String) -> [JSONObject] { self[key] as? [JSONObject] ?? [] }
    func text(_ key: String) -> String { self[key] as? String ?? "" }
    // The TDLib JSON API sends int64 values as decimal strings.
    func number(_ key: String) -> Int64 {
        if let value = self[key] as? NSNumber { return value.int64Value }
        if let value = self[key] as? String { return Int64(value) ?? 0 }
        return 0
    }
    func intIDs(_ key: String) -> [Int64] {
        (self[key] as? [Any] ?? []).compactMap {
            if let value = $0 as? NSNumber { return value.int64Value }
            if let value = $0 as? String { return Int64(value) }
            return nil
        }
    }
    func flag(_ key: String) -> Bool { self[key] as? Bool ?? false }
}

struct BotButton: Identifiable {
    let id: String
    let title: String
    let kind: String
    let value: String

    init(_ json: JSONObject, index: Int) {
        title = json.text("text")
        let type = json.object("type")
        kind = type.text("@type")
        value = type.text("url").isEmpty ? type.text("data") : type.text("url")
        id = "\(index):\(title):\(kind)"
    }
}

struct TelegramChat: Identifiable, Equatable {
    let id: Int64
    var title: String
    var order: Int64
    var unreadCount: Int
    var lastPreview: String
    var type: String
    var isPinned: Bool
    var isArchived: Bool

    init(_ raw: JSONObject) {
        id = raw.number("id")
        title = raw.text("title")
        unreadCount = Int(raw.number("unread_count"))
        let positions = raw.objects("positions")
        let main = positions.first {
            $0.object("list").text("@type") == "chatListMain" && $0.number("order") > 0
        }
        let archive = positions.first {
            $0.object("list").text("@type") == "chatListArchive" && $0.number("order") > 0
        }
        order = (main ?? archive ?? [:]).number("order")
        isPinned = (main ?? archive ?? [:]).flag("is_pinned")
        isArchived = main == nil && archive != nil
        type = raw.object("type").text("@type")
        let content = raw.object("last_message").object("content")
        lastPreview = content.object("text").text("text")
        if lastPreview.isEmpty {
            lastPreview = content.text("@type").replacingOccurrences(of: "message", with: "")
        }
    }

    var spoken: String {
        let count = unreadCount > 0 ? "，\(unreadCount) 則未讀" : ""
        return "\(title)\(count)，\(lastPreview)"
    }
}

struct TelegramMessage: Identifiable, Equatable {
    let id: Int64
    let chatID: Int64
    var sender: String
    var body: String
    let date: Date
    var fileID: Int
    var fileKind: String
    var outgoing: Bool
    var buttons: [BotButton]
    var keyboardButtons: [BotButton]
    var translated: String?
    var replyID: Int64

    var spoken: String {
        let result = translated.map { "，翻譯：\($0)" } ?? ""
        let timestamp = Self.timestamp.string(from: date)
        return "\(sender)，\(body)\(result)，\(timestamp)"
    }

    static let timestamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.sender == rhs.sender && lhs.body == rhs.body &&
        lhs.fileID == rhs.fileID && lhs.translated == rhs.translated &&
        lhs.buttons.map(\.id) == rhs.buttons.map(\.id)
    }

    init(_ raw: JSONObject, users: [Int64: String], chats: [Int64: TelegramChat]) {
        id = raw.number("id")
        chatID = raw.number("chat_id")
        outgoing = raw.flag("is_outgoing")
        date = Date(timeIntervalSince1970: TimeInterval(raw.number("date")))
        replyID = raw.object("reply_to").number("message_id")
        let from = raw.object("sender_id")
        if outgoing {
            sender = "我"
        } else if from.text("@type") == "messageSenderUser" {
            let userID = from.number("user_id")
            sender = users[userID] ?? "使用者 \(userID)"
        } else if from.text("@type") == "messageSenderChat" {
            let senderChat = from.number("chat_id")
            sender = chats[senderChat]?.title ?? "頻道"
        } else {
            sender = "系統"
        }

        let content = raw.object("content")
        let type = content.text("@type")
        fileID = 0
        fileKind = ""
        var prefix = ""
        var caption = ""
        switch type {
        case "messageText":
            caption = content.object("text").text("text")
        case "messagePhoto":
            prefix = "照片"
            caption = content.object("caption").text("text")
            fileID = Int(content.object("photo").objects("sizes").last?.object("photo").number("id") ?? 0)
            fileKind = "photo"
        case "messageVideo":
            prefix = "影片"
            caption = content.object("caption").text("text")
            fileID = Int(content.object("video").object("video").number("id"))
            fileKind = "video"
        case "messageVoiceNote":
            let length = content.object("voice_note").number("duration")
            prefix = "語音訊息，\(length) 秒"
            fileID = Int(content.object("voice_note").object("voice").number("id"))
            fileKind = "voice"
        case "messageAudio":
            prefix = "音訊 \(content.object("audio").text("title"))"
            caption = content.object("caption").text("text")
            fileID = Int(content.object("audio").object("audio").number("id"))
            fileKind = "audio"
        case "messageAnimation":
            prefix = "動態圖片"
            caption = content.object("caption").text("text")
            fileID = Int(content.object("animation").object("animation").number("id"))
            fileKind = "video"
        case "messageDocument":
            prefix = "檔案 \(content.object("document").text("file_name"))"
            caption = content.object("caption").text("text")
            fileID = Int(content.object("document").object("document").number("id"))
            fileKind = "document"
        case "messageSticker":
            prefix = "貼圖 \(content.object("sticker").text("emoji"))"
        case "messageVideoNote":
            prefix = "圓形影片"
            fileID = Int(content.object("video_note").object("video").number("id"))
            fileKind = "video"
        case "messagePoll":
            prefix = "投票"
            caption = content.object("poll").object("question").text("text")
            let options = content.object("poll").objects("options")
            if !options.isEmpty {
                caption += "，選項：" + options.map { $0.object("text").text("text") }.joined(separator: "，")
            }
        case "messageContact":
            prefix = "聯絡人"
            caption = content.object("contact").text("first_name") + " " + content.object("contact").text("last_name")
        case "messageLocation":
            prefix = "位置資訊"
        case "messagePinMessage":
            prefix = "置頂訊息"
        case "messageChatAddMembers":
            prefix = "成員加入群組"
        case "messageChatDeleteMember":
            prefix = "成員離開群組"
        default:
            prefix = type.replacingOccurrences(of: "message", with: "")
        }
        body = [prefix, caption].filter { !$0.isEmpty }.joined(separator: "，")
        if body.isEmpty { body = "空白訊息" }

        let markup = raw.object("reply_markup")
        let rows = markup["rows"] as? [[JSONObject]] ?? []
        let buttons = rows.flatMap { $0 }
        if markup.text("@type") == "replyMarkupInlineKeyboard" {
            self.buttons = buttons.enumerated().map { BotButton($0.element, index: $0.offset) }
            keyboardButtons = []
        } else if markup.text("@type") == "replyMarkupShowKeyboard" {
            self.buttons = []
            keyboardButtons = buttons.enumerated().map { BotButton($0.element, index: $0.offset) }
        } else {
            self.buttons = []
            keyboardButtons = []
        }
    }
}

@MainActor
final class MessageThread: ObservableObject {
    let chatID: Int64
    @Published var messages: [TelegramMessage] = []
    @Published var loading = false
    @Published var hasMore = true
    @Published var replyTo: TelegramMessage?
    @Published var translationCache: [Int64: String] = [:]
    var hasOpened = false
    var isInitialized = false
    var paginationStallCount = 0

    init(chatID: Int64) { self.chatID = chatID }

    func merge(_ incoming: [TelegramMessage]) {
        guard !incoming.isEmpty else { return }
        var byID = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        for var message in incoming {
            message.translated = translationCache[message.id]
            byID[message.id] = message
        }
        messages = byID.values.sorted { $0.id < $1.id }
    }

    func remove(_ ids: Set<Int64>) {
        messages.removeAll { ids.contains($0.id) }
    }

    func setTranslation(_ id: Int64, translated: String) {
        translationCache[id] = translated
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].translated = translated
        }
    }
}
