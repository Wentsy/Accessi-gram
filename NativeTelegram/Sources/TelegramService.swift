import Foundation
import Combine
import Security
import UIKit
import AudioToolbox
import TDLibFramework

typealias TDCallback = (JSONObject) -> Void

enum AuthStage: String {
    case credentials, phone, code, password, email, emailCode, qr, ready, unknown
}

enum KeychainAPI {
    static let account = "org.accessigram.native.telegram"
    static let databaseAccount = "org.accessigram.native.database"

    static func save(id: Int, hash: String) {
        let data = try! JSONSerialization.data(withJSONObject: ["id": id, "hash": hash])
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func databaseKey() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: databaseAccount,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var found: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess {
            return (found as! Data).base64EncodedString()
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let data = Data(bytes)
        var attributes = query
        attributes.removeValue(forKey: kSecMatchLimit as String)
        attributes.removeValue(forKey: kSecReturnData as String)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
        return data.base64EncodedString()
    }

    static func load() -> (Int, String)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var found: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess {
            let json = try! JSONSerialization.jsonObject(with: found as! Data) as! JSONObject
            return (Int(json.number("id")), json.text("hash"))
        }
        // OC can embed credentials in the compiled app's Info.plist without
        // committing personal API secrets to this public repository.
        let info = Bundle.main.infoDictionary ?? [:]
        let bundledID = (info["TelegramAPIID"] as? String) ?? "\(info["TelegramAPIID"] as? Int ?? 0)"
        let bundledHash = info["TelegramAPIHash"] as? String ?? ""
        guard let id = Int(bundledID), id > 0, !bundledHash.isEmpty else { return nil }
        save(id: id, hash: bundledHash)
        return (id, bundledHash)
    }
}

@MainActor
final class TelegramService: ObservableObject {
    static let shared = TelegramService()

    @Published var authStage: AuthStage = .credentials
    @Published var qrLink = ""
    @Published var errorMessage = ""
    @Published var chats: [TelegramChat] = []
    @Published var searchResults: [TelegramChat] = []
    @Published var archived = false
    @Published var loadingChats = false
    @Published var chatSyncStatus = "等待同步聊天"
    @Published var hasLoadedChatList = false
    @Published var moreChatsAvailable = true
    @Published var passwordHint = ""
    @Published var contacts: [TelegramContact] = []
    @Published var systemNotificationStatus = "尚未取得通知權限"
    @Published var notificationChatID: Int64?
    @Published var foregroundVibrationEnabled =
        UserDefaults.standard.object(forKey: "foregroundMessageVibration") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(foregroundVibrationEnabled,
                                      forKey: "foregroundMessageVibration")
        }
    }

    private var clientID: Int32 = 0
    private var apiID = 0
    private var apiHash = ""
    private var callbacks: [String: TDCallback] = [:]
    private var chatsByID: [Int64: TelegramChat] = [:]
    private var users: [Int64: String] = [:]
    private var threads: [Int64: MessageThread] = [:]
    private var requestedUsers = Set<Int64>()
    private var receiverStarted = false
    private var chatListLimit = 100
    private var parametersRequested = false
    private var authorizedSince = Date.distantFuture
    private var alreadyVibrated = Set<String>()
    private var recentVibrationIDs: [String] = []
    private var lastVibration = Date.distantPast
    private var currentPushToken = ""
    private var registeredPushToken = ""
    private var shareUploadInProgress = false

    private init() {}

    func start() {
        guard clientID == 0 else { return }
        if let (id, hash) = KeychainAPI.load() { connect(apiID: id, apiHash: hash) }
    }

    func configure(id: Int, hash: String) {
        KeychainAPI.save(id: id, hash: hash)
        connect(apiID: id, apiHash: hash)
    }

    private func connect(apiID: Int, apiHash: String) {
        self.apiID = apiID
        self.apiHash = apiHash
        clientID = td_create_client_id()
        if !receiverStarted {
            receiverStarted = true
            DispatchQueue.global(qos: .userInitiated).async {
                while true {
                    if let output = td_receive(0.5) {
                        let message = String(cString: output)
                        let json = try! JSONSerialization.jsonObject(with: Data(message.utf8)) as! JSONObject
                        Task { @MainActor in self.handle(json) }
                    }
                }
            }
        }
        // State notifications and getAuthorizationState can arrive out of order.
        // handleAuth is idempotent and sends parameters only once.
        request("getAuthorizationState") { [weak self] response in
            if response.text("@type").hasPrefix("authorizationState") {
                self?.handleAuth(response)
            }
        }
    }

    func request(_ method: String, _ arguments: JSONObject = [:], completion: TDCallback? = nil) {
        var payload = arguments
        payload["@type"] = method
        if let completion {
            let extra = UUID().uuidString
            payload["@extra"] = extra
            callbacks[extra] = completion
        }
        let data = try! JSONSerialization.data(withJSONObject: payload)
        td_send(clientID, String(decoding: data, as: UTF8.self))
    }

    func command(_ method: String, _ arguments: JSONObject = [:]) {
        request(method, arguments) { [weak self] response in
            if response.text("@type") == "error" {
                self?.errorMessage = response.text("message")
            }
        }
    }

    private func handle(_ json: JSONObject) {
        if let extra = json["@extra"] as? String {
            callbacks.removeValue(forKey: extra)?(json)
            return
        }
        switch json.text("@type") {
        case "updateAuthorizationState":
            handleAuth(json.object("authorization_state"))
        case "updateNewChat":
            addChat(json.object("chat"))
        case "updateChatTitle":
            let id = json.number("chat_id")
            chatsByID[id]?.title = json.text("title")
            publishChats()
        case "updateChatPosition":
            let id = json.number("chat_id")
            request("getChat", ["chat_id": id]) { [weak self] raw in
                if raw.text("@type") == "chat" { self?.addChat(raw) }
            }
        case "updateChatLastMessage":
            let id = json.number("chat_id")
            if var chat = chatsByID[id] {
                let content = json.object("last_message").object("content")
                chat.lastPreview = content.object("text").text("text")
                if chat.lastPreview.isEmpty {
                    chat.lastPreview = content.text("@type").replacingOccurrences(of: "message", with: "")
                }
                if let position = json.objects("positions").first(where: {
                    $0.object("list").text("@type") == "chatListMain" || $0.object("list").text("@type") == "chatListArchive"
                }) {
                    chat.order = position.number("order")
                    chat.isArchived = position.object("list").text("@type") == "chatListArchive"
                }
                chatsByID[id] = chat
                publishChats()
            }
        case "updateChatReadInbox":
            chatsByID[json.number("chat_id")]?.unreadCount = Int(json.number("unread_count"))
            publishChats()
        case "updateUser":
            storeUser(json.object("user"))
        case "updateNewMessage":
            let message = json.object("message")
            receive(message)
            vibrateIfIncoming(message)
        case "updateMessageSendSucceeded":
            let message = json.object("message")
            threads[message.number("chat_id")]?.remove([json.number("old_message_id")])
            receive(message)
        case "updateMessageSendFailed":
            let failure = json.object("error")
            let reason = failure.text("message")
            errorMessage = "Telegram 傳送訊息失敗：\(reason.isEmpty ? "未知原因" : reason)"
        case "updateMessageContent", "updateMessageEdited":
            let chatID = json.number("chat_id")
            let id = json.number("message_id")
            request("getMessage", ["chat_id": chatID, "message_id": id]) { [weak self] object in
                self?.receive(object)
            }
        case "updateDeleteMessages":
            let ids = Set(json.intIDs("message_ids"))
            threads[json.number("chat_id")]?.remove(ids)
        default: break
        }
    }

    private func handleAuth(_ state: JSONObject) {
        switch state.text("@type") {
        case "authorizationStateWaitTdlibParameters":
            guard !parametersRequested else { return }
            parametersRequested = true
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            request("setTdlibParameters", [
                "api_id": apiID, "api_hash": apiHash,
                "database_directory": root.appendingPathComponent("tdlib").path,
                "files_directory": root.appendingPathComponent("files").path,
                "database_encryption_key": KeychainAPI.databaseKey(),
                "use_message_database": true, "use_file_database": true,
                "use_chat_info_database": true, "use_secret_chats": true,
                "enable_storage_optimizer": true,
                "system_language_code": "zh-TW",
                "system_version": UIDevice.current.systemVersion,
                "device_model": UIDevice.current.model,
                "application_version": "1.0", "use_test_dc": false
            ]) { [weak self] response in
                guard let self else { return }
                if response.text("@type") == "error" {
                    let detail = response.text("message")
                    // Race with an already accepted initialization is harmless.
                    if !detail.localizedCaseInsensitiveContains("unexpected setTdlibParameters") {
                        self.parametersRequested = false
                        self.errorMessage = detail
                    }
                }
            }
        case "authorizationStateWaitPhoneNumber": authStage = .phone
        case "authorizationStateWaitCode": authStage = .code
        case "authorizationStateWaitPassword":
            authStage = .password
            passwordHint = state.text("password_hint")
        case "authorizationStateWaitEmailAddress": authStage = .email
        case "authorizationStateWaitEmailCode": authStage = .emailCode
        case "authorizationStateWaitOtherDeviceConfirmation":
            authStage = .qr
            qrLink = state.text("link")
        case "authorizationStateReady":
            let firstReady = authStage != .ready
            authStage = .ready
            if firstReady {
                authorizedSince = Date()
                alreadyVibrated.removeAll()
                recentVibrationIDs.removeAll()
                chatSyncStatus = "正在同步 Telegram 對話與群組"
                SystemNotificationManager.shared.refreshAuthorizationStatus()
                registerPendingPushToken()
                loadContacts()
                processSharedUploads()
                loadChats()
            }
        case "authorizationStateLoggingOut", "authorizationStateClosed": authStage = .phone
        default: authStage = .unknown
        }
    }

    func registerPushToken(_ token: String) {
        currentPushToken = token
        registerPendingPushToken()
    }

    private func registerPendingPushToken() {
        guard authStage == .ready, !currentPushToken.isEmpty,
              registeredPushToken != currentPushToken else { return }

        // OC must match this to the APS environment of the provisioning
        // profile. Debug/dev tokens must use sandbox; TestFlight/production do not.
        let sandbox = Bundle.main.object(forInfoDictionaryKey: "TelegramAPNsIsSandbox") as? Bool ?? false
        request("registerDevice", [
            "device_token": [
                "@type": "deviceTokenApplePush",
                "device_token": currentPushToken,
                "is_app_sandbox": sandbox
            ] as JSONObject,
            "other_user_ids": [] as [Int64]
        ]) { [weak self] result in
            guard let self else { return }
            if result.text("@type") == "pushReceiverId" {
                self.registeredPushToken = self.currentPushToken
                self.systemNotificationStatus = "iOS 通知已授權，Telegram 推播裝置已註冊"
            } else if result.text("@type") == "error" {
                self.systemNotificationStatus =
                    "Telegram 推播註冊失敗：\(result.text("message"))"
            }
        }
    }

    func processPush(_ userInfo: JSONObject, completion: @escaping (Bool) -> Void) {
        if clientID == 0 { start() }
        let data = try! JSONSerialization.data(withJSONObject: userInfo)
        request("processPushNotification", [
            "payload": String(decoding: data, as: UTF8.self)
        ]) { response in
            completion(response.text("@type") != "error")
        }
    }

    func phone(_ phone: String) {
        command("setAuthenticationPhoneNumber", ["phone_number": phone, "settings": [
            "@type": "phoneNumberAuthenticationSettings", "allow_flash_call": false,
            "allow_missed_call": false, "is_current_phone_number": false,
            "allow_sms_retriever_api": false
        ]])
    }

    func code(_ code: String) { command("checkAuthenticationCode", ["code": code]) }
    func password(_ password: String) { command("checkAuthenticationPassword", ["password": password]) }
    func email(_ email: String) { command("setAuthenticationEmailAddress", ["email_address": email]) }
    func emailCode(_ code: String) {
        command("checkAuthenticationEmailCode", ["code": ["@type": "emailAddressAuthenticationCode", "code": code]])
    }
    func startQR() { command("requestQrCodeAuthentication", ["other_user_ids": []]) }
    func logOut() { command("logOut") }

    func loadChats() {
        guard authStage == .ready, !loadingChats else { return }
        loadingChats = true
        moreChatsAvailable = true
        chatSyncStatus = "正在同步 Telegram 對話與群組"
        chatListLimit = max(100, chatsByID.count)
        let list: JSONObject = ["@type": archived ? "chatListArchive" : "chatListMain"]
        syncNextChatPage(in: list)
    }

    // TDLib loads an amount selected by the library. One loadChats call does
    // not mean the full chat history is available; keep fetching until 404.
    private func syncNextChatPage(in list: JSONObject) {
        request("loadChats", ["chat_list": list, "limit": 100]) { [weak self] outcome in
            guard let self else { return }
            self.request("getChats", ["chat_list": list, "limit": self.chatListLimit]) { [weak self] snapshot in
                guard let self else { return }
                self.hasLoadedChatList = true
                for id in snapshot.intIDs("chat_ids") where self.chatsByID[id] == nil {
                    self.request("getChat", ["chat_id": id]) { [weak self] chat in
                        if chat.text("@type") == "chat" { self?.addChat(chat) }
                    }
                }

                if outcome.text("@type") == "ok" {
                    self.chatListLimit += 100
                    self.syncNextChatPage(in: list)
                } else {
                    self.loadingChats = false
                    let finished = outcome.number("code") == 404
                    self.moreChatsAvailable = !finished
                    self.chatSyncStatus = finished
                        ? "聊天同步完成，已載入 \(self.chatsByID.count) 個對話"
                        : "同步暫時中斷，可按重新同步"
                    if !finished && outcome.text("@type") == "error" {
                        self.errorMessage = outcome.text("message")
                    }
                }
            }
        }
    }

    func loadMoreChats() {
        // Initial sync already walks every chat page. While it runs, UIKit
        // can browse the rows received so far without firing duplicate loads.
        guard !loadingChats && moreChatsAvailable else { return }
        loadChats()
    }

    func toggleArchive() {
        chatListLimit = 100
        moreChatsAvailable = true
        archived.toggle()
        publishChats()
        loadChats()
    }

    private func addChat(_ raw: JSONObject) {
        if raw.number("id") == 0 { return }
        let chat = TelegramChat(raw)
        chatsByID[chat.id] = chat
        publishChats()
    }

    private func publishChats() {
        chats = chatsByID.values
            .filter { $0.isArchived == archived && $0.order > 0 }
            .sorted { $0.order == $1.order ? $0.id > $1.id : $0.order > $1.order }
        if !chats.isEmpty {
            chatSyncStatus = "已同步 \(chats.count) 個對話"
        }
        publishShareRecipients()
    }


    func loadContacts() {
        request("getContacts") { [weak self] response in
            let ids = response.intIDs("user_ids")
            for userID in ids {
                self?.request("getUser", ["user_id": userID]) { [weak self] user in
                    guard let self, user.text("@type") == "user" else { return }
                    self.storeUser(user)
                    let name = self.users[userID] ?? "使用者 \(userID)"
                    if !self.contacts.contains(where: { $0.id == userID }) {
                        self.contacts.append(TelegramContact(id: userID, name: name))
                        self.contacts.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                        self.publishShareRecipients()
                    }
                }
            }
        }
    }

    private func publishShareRecipients() {
        var entries = chatsByID.values
            .filter { $0.order > 0 && !$0.isArchived }
            .sorted { $0.order > $1.order }
            .map {
                ShareRecipient(id: "chat:\($0.id)", title: $0.title,
                               chatID: "\($0.id)", userID: nil)
            }

        // Contacts without an existing conversation can also be selected.
        for contact in contacts where !entries.contains(where: {
            $0.title == contact.name
        }) {
            entries.append(ShareRecipient(
                id: "contact:\(contact.id)", title: contact.name,
                chatID: nil, userID: "\(contact.id)"
            ))
        }
        ShareMailbox.saveRecipients(entries)
    }

    func processSharedUploads() {
        guard authStage == .ready, !shareUploadInProgress else { return }
        guard let first = ShareMailbox.pending().first else { return }
        shareUploadInProgress = true

        if let chat = first.target.chatID.flatMap(Int64.init) {
            sendSharedDraft(first, to: chat)
        } else if let user = first.target.userID.flatMap(Int64.init) {
            createPrivateChat(userID: user) { [weak self] id in
                guard let self else { return }
                if let id {
                    self.sendSharedDraft(first, to: id)
                } else {
                    self.shareUploadInProgress = false
                }
            }
        } else {
            errorMessage = "分享找不到收件人，請重新選擇"
            shareUploadInProgress = false
        }
    }

    private func sendSharedDraft(_ draft: PendingShare, to chatID: Int64) {
        if draft.attachments.isEmpty {
            sendText(chatID: chatID, text: draft.caption)
        } else {
            for (index, attachment) in draft.attachments.enumerated() {
                guard let url = ShareMailbox.url(for: attachment) else { continue }
                sendMedia(chatID: chatID, fileURL: url,
                          kind: attachment.kind,
                          caption: index == 0 ? draft.caption : "")
            }
        }
        ShareMailbox.complete(draft)
        shareUploadInProgress = false
        UIAccessibility.post(notification: .announcement,
                             argument: "已提交分享給 \(draft.target.title)，正在傳送")
        processSharedUploads()
    }

    func createPrivateChat(userID: Int64, completion: @escaping (Int64?) -> Void) {
        request("createPrivateChat", ["user_id": userID, "force": false]) { [weak self] response in
            guard response.text("@type") == "chat" else {
                self?.errorMessage = response.text("message")
                completion(nil)
                return
            }
            self?.addChat(response)
            completion(response.number("id"))
        }
    }

    func findUsername(_ input: String, completion: @escaping (Int64?) -> Void) {
        let username = input.trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
        request("searchPublicChat", ["username": username]) { [weak self] response in
            guard response.text("@type") == "chat" else {
                self?.errorMessage = response.text("message")
                completion(nil)
                return
            }
            self?.addChat(response)
            completion(response.number("id"))
        }
    }

    func chatTitle(_ id: Int64) -> String { chatsByID[id]?.title ?? "聊天室" }
    func chatType(_ id: Int64) -> String { chatsByID[id]?.type ?? "" }

    private func storeUser(_ raw: JSONObject) {
        let id = raw.number("id")
        if id == 0 { return }
        let name = [raw.text("first_name"), raw.text("last_name")].filter { !$0.isEmpty }.joined(separator: " ")
        users[id] = name.isEmpty ? "使用者 \(id)" : name
        for thread in threads.values {
            var copy = thread.messages
            for index in copy.indices where copy[index].sender == "使用者 \(id)" {
                copy[index].sender = users[id]!
            }
            if thread.messages != copy { thread.messages = copy }
        }
    }

    private func loadSender(_ raw: JSONObject) {
        let sender = raw.object("sender_id")
        guard sender.text("@type") == "messageSenderUser" else { return }
        let userID = sender.number("user_id")
        if users[userID] != nil || requestedUsers.contains(userID) { return }
        requestedUsers.insert(userID)
        request("getUser", ["user_id": userID]) { [weak self] user in
            if user.text("@type") == "user" { self?.storeUser(user) }
        }
    }

    func thread(_ id: Int64) -> MessageThread {
        if let existing = threads[id] { return existing }
        let fresh = MessageThread(chatID: id)
        threads[id] = fresh
        return fresh
    }

    func open(_ id: Int64) {
        let model = thread(id)
        if !model.hasOpened {
            model.hasOpened = true
            command("openChat", ["chat_id": id])
        }
        if !model.isInitialized {
            model.isInitialized = true
            history(id, before: 0)
        }
    }

    func close(_ id: Int64) {
        let model = thread(id)
        if model.hasOpened {
            model.hasOpened = false
            command("closeChat", ["chat_id": id])
        }
    }

    func older(_ id: Int64) {
        let model = thread(id)
        guard !model.loading && model.hasMore else { return }
        history(id, before: model.messages.first?.id ?? 0)
    }

    private func history(_ id: Int64, before: Int64) {
        let model = thread(id)
        if model.loading { return }
        model.loading = true
        request("getChatHistory", [
            "chat_id": id, "from_message_id": before,
            "offset": 0, "limit": 75, "only_local": false
        ]) { [weak self] result in
            guard let self else { return }
            let raw = result.objects("messages")
            raw.forEach { self.loadSender($0) }
            let page = raw.map { TelegramMessage($0, users: self.users, chats: self.chatsByID) }
            let priorOldest = model.messages.first?.id
            model.merge(page)
            model.loading = false
            if raw.isEmpty && result.text("@type") != "error" {
                model.hasMore = false
            }
            model.paginationStallCount = (before > 0 && priorOldest == model.messages.first?.id)
                ? model.paginationStallCount + 1 : 0
            if before == 0, let last = model.messages.last {
                self.command("viewMessages", ["chat_id": id,
                                              "message_ids": [last.id], "force_read": true])
            }
        }
    }

    // Only real-time incoming updates can trigger this. getChatHistory / cached
    // messages and outgoing sends intentionally never call this method.
    private func vibrateIfIncoming(_ message: JSONObject) {
        guard foregroundVibrationEnabled,
              UIApplication.shared.applicationState == .active,
              !message.flag("is_outgoing"),
              message.number("date") >= Int64(authorizedSince.timeIntervalSince1970) - 2
        else { return }

        let key = "\(message.number("chat_id")):\(message.number("id"))"
        guard !alreadyVibrated.contains(key) else { return }
        alreadyVibrated.insert(key)
        recentVibrationIDs.append(key)
        if recentVibrationIDs.count > 240 {
            alreadyVibrated.remove(recentVibrationIDs.removeFirst())
        }

        let now = Date()
        guard now.timeIntervalSince(lastVibration) >= 0.7 else { return }
        lastVibration = now
        // iPhone system vibration. Respect device/system haptic settings.
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    func toggleForegroundVibration() {
        foregroundVibrationEnabled.toggle()
    }

    private func receive(_ raw: JSONObject) {
        if raw.number("id") == 0 { return }
        loadSender(raw)
        let message = TelegramMessage(raw, users: users, chats: chatsByID)
        thread(message.chatID).merge([message])
    }

    func sendText(chatID: Int64, text: String, replyID: Int64 = 0) {
        var args: JSONObject = [
            "chat_id": chatID,
            "input_message_content": [
                "@type": "inputMessageText",
                "text": ["@type": "formattedText", "text": text, "entities": []],
                "clear_draft": true, "disable_web_page_preview": false
            ] as JSONObject
        ]
        if replyID > 0 {
            args["reply_to"] = ["@type": "inputMessageReplyToMessage", "message_id": replyID]
        }
        command("sendMessage", args)
    }

    // TDLib >= 1.8.65 expects inputPhoto/inputVideo/inputVoiceNote/
    // inputDocument containing inputFileLocal, not a raw inputFileLocal
    // directly at the inputMessageContent level.
    func sendMedia(chatID: Int64, fileURL: URL, kind: String,
                   caption: String = "", duration: Int = 0) {
        let path = fileURL.path
        guard FileManager.default.isReadableFile(atPath: path) else {
            errorMessage = "找不到可傳送的檔案：\(fileURL.lastPathComponent)"
            return
        }

        let file: JSONObject = ["@type": "inputFileLocal", "path": path]
        let text: JSONObject = ["@type": "formattedText", "text": caption, "entities": []]
        let payload: JSONObject

        switch kind {
        case "photo":
            payload = [
                "@type": "inputMessagePhoto",
                "photo": [
                    "@type": "inputPhoto",
                    "photo": file,
                    "added_sticker_file_ids": [],
                    "width": 0, "height": 0
                ] as JSONObject,
                "caption": text,
                "show_caption_above_media": false,
                "has_spoiler": false
            ]
        case "video":
            payload = [
                "@type": "inputMessageVideo",
                "video": [
                    "@type": "inputVideo",
                    "video": file,
                    "start_timestamp": 0,
                    "added_sticker_file_ids": [],
                    "duration": duration, "width": 0, "height": 0,
                    "supports_streaming": true
                ] as JSONObject,
                "caption": text,
                "show_caption_above_media": false,
                "has_spoiler": false
            ]
        case "voice":
            payload = [
                "@type": "inputMessageVoiceNote",
                "voice_note": [
                    "@type": "inputVoiceNote",
                    "voice_note": file, "duration": duration, "waveform": ""
                ] as JSONObject,
                "caption": text
            ]
        case "audio":
            payload = [
                "@type": "inputMessageAudio",
                "audio": [
                    "@type": "inputAudio",
                    "audio": file, "duration": duration, "title": "", "performer": ""
                ] as JSONObject,
                "caption": text
            ]
        default:
            payload = [
                "@type": "inputMessageDocument",
                "document": [
                    "@type": "inputDocument",
                    "document": file, "disable_content_type_detection": true
                ] as JSONObject,
                "caption": text
            ]
        }

        request("sendMessage", [
            "chat_id": chatID, "input_message_content": payload
        ]) { [weak self] response in
            guard let self else { return }
            if response.text("@type") == "error" {
                let reason = response.text("message")
                if kind == "voice", fileURL.pathExtension.lowercased() == "m4a",
                   reason.localizedCaseInsensitiveContains("voice") ||
                   reason.localizedCaseInsensitiveContains("audio") {
                    // AAC/M4A can be sent as ordinary audio when TDLib rejects it
                    // as a voice-note bubble. The file itself is still delivered.
                    self.sendMedia(chatID: chatID, fileURL: fileURL,
                                   kind: "audio", caption: caption, duration: duration)
                } else {
                    self.errorMessage = "附件傳送失敗：\(reason)"
                }
            } else if response.text("@type") == "message" {
                UIAccessibility.post(notification: .announcement,
                                     argument: "已提交附件，正在傳送")
            }
        }
    }

    func download(_ fileID: Int, completion: @escaping (URL?) -> Void) {
        request("downloadFile", ["file_id": fileID, "priority": 16,
                                 "offset": 0, "limit": 0, "synchronous": true]) { response in
            let path = response.object("local").text("path")
            completion(path.isEmpty ? nil : URL(fileURLWithPath: path))
        }
    }

    func react(_ message: TelegramMessage, emoji: String) {
        command("addMessageReaction", [
            "chat_id": message.chatID, "message_id": message.id,
            "reaction_type": ["@type": "reactionTypeEmoji", "emoji": emoji],
            "is_big": false, "update_recent_reactions": true
        ])
    }

    func delete(_ message: TelegramMessage) {
        command("deleteMessages", ["chat_id": message.chatID, "message_ids": [message.id], "revoke": true])
    }

    func edit(_ message: TelegramMessage, newText: String) {
        command("editMessageText", [
            "chat_id": message.chatID, "message_id": message.id,
            "input_message_content": ["@type": "inputMessageText",
                                      "text": ["@type": "formattedText", "text": newText, "entities": []]]
        ])
    }

    func forward(_ message: TelegramMessage, to targetID: Int64) {
        command("forwardMessages", [
            "chat_id": targetID, "from_chat_id": message.chatID,
            "message_ids": [message.id], "send_copy": false,
            "remove_caption": false, "only_preview": false
        ])
    }

    func setPinned(chatID: Int64, value: Bool) {
        command("toggleChatIsPinned", ["chat_list": ["@type": archived ? "chatListArchive" : "chatListMain"],
                                       "chat_id": chatID, "is_pinned": value])
    }

    func archiveChat(chatID: Int64, value: Bool) {
        command("addChatToList", ["chat_id": chatID,
                                 "chat_list": ["@type": value ? "chatListArchive" : "chatListMain"]])
    }

    func markUnread(chatID: Int64) {
        command("toggleChatIsMarkedAsUnread", ["chat_id": chatID, "is_marked_as_unread": true])
    }

    func deleteChat(chatID: Int64) {
        command("deleteChatHistory", ["chat_id": chatID, "remove_from_chat_list": true, "revoke": false])
    }

    func search(_ query: String) {
        if query.isEmpty { searchResults = []; return }
        request("searchChatsOnServer", ["query": query, "limit": 30]) { [weak self] result in
            guard let self else { return }
            let ids = result.intIDs("chat_ids")
            self.searchResults = ids.compactMap { self.chatsByID[$0] }
            for id in ids where self.chatsByID[id] == nil {
                self.request("getChat", ["chat_id": id]) { [weak self] object in
                    if object.text("@type") == "chat" {
                        self?.addChat(object)
                        if let chat = self?.chatsByID[id] {
                            self?.searchResults.append(chat)
                        }
                    }
                }
            }
        }
    }

    func botAction(_ button: BotButton, message: TelegramMessage) {
        switch button.kind {
        case "inlineKeyboardButtonTypeUrl":
            if let url = URL(string: button.value) { UIApplication.shared.open(url) }
        case "inlineKeyboardButtonTypeCallback":
            request("getCallbackQueryAnswer", [
                "chat_id": message.chatID, "message_id": message.id,
                "payload": ["@type": "callbackQueryPayloadData", "data": button.value]
            ]) { response in
                if !response.text("text").isEmpty {
                    UIAccessibility.post(notification: .announcement, argument: response.text("text"))
                }
                if let url = URL(string: response.text("url")) { UIApplication.shared.open(url) }
            }
        default:
            if !button.title.isEmpty { sendText(chatID: message.chatID, text: button.title) }
        }
    }

    func translate(_ message: TelegramMessage) {
        let content = message.body
        Task {
            do {
                let translated = try await GoogleTranslate.translate(content)
                thread(message.chatID).setTranslation(message.id, translated: translated)
                UIAccessibility.post(notification: .announcement, argument: translated)
            } catch {
                UIAccessibility.post(notification: .announcement, argument: "翻譯失敗：\(error.localizedDescription)")
            }
        }
    }
}
