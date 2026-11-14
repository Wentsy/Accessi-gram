import Foundation
import TDLibFramework
import UIKit

// The share target deliberately doesn't link the main app's ObservableObjects.
// It runs a second TDLib client with a separate database snapshot and sends
// messages directly while the system share sheet is open.
private typealias TDJSON = [String: Any]

private extension Dictionary where Key == String, Value == Any {
    func object(_ key: String) -> TDJSON { self[key] as? TDJSON ?? [:] }
    func text(_ key: String) -> String { self[key] as? String ?? "" }
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
}

enum ShareSignInStage: Equatable {
    case apiCredentials, connecting, phone, code, password, email, emailCode
    case qr(String), ready
}

enum ShareSendError: LocalizedError {
    case invalidAPICredentials
    case authorizationRequired
    case noRecipient
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAPICredentials:
            return "分享功能的 Telegram API ID 或 API Hash 無效。請重新輸入 my.telegram.org 取得的正確資料，或請 OC 在分享延伸功能中預置主 App 使用的同一組憑證。"
        case .authorizationRequired:
            return "請先在 Accessi Gram 分享視窗登入 Telegram；分享登入與聊天 App 的登入相互獨立。"
        case .noRecipient:
            return "找不到你選擇的聯絡人或聊天室"
        case .failed(let message):
            return "Telegram 傳送失敗：\(message)"
        }
    }
}

@MainActor
final class ExtensionTelegramSender {
    private var clientID: Int32 = 0
    private var receiverStarted = false
    private var closeWaiter: CheckedContinuation<Void, Never>?
    private var callbacks: [String: (TDJSON) -> Void] = [:]
    private(set) var stage: ShareSignInStage = .connecting
    var onStageChanged: ((ShareSignInStage) -> Void)?
    private var authReady = false
    private var parametersSent = false
    private var configuration: ShareSessionConfiguration?
    private var awaitingMessages: [Int64: CheckedContinuation<Void, Error>] = [:]
    private var completedMessages: [Int64: Result<Void, Error>] = [:]
    private var deliveredShareItems: [String: Set<Int>] = [:]

    private func updateStage(_ next: ShareSignInStage) {
        stage = next
        onStageChanged?(next)
    }

    /// Called by the recipient picker. The extension owns its database and
    /// persists authorization in its private sandbox across share sessions.
    func start() async throws {
        if clientID != 0 { return }
        let config: ShareSessionConfiguration
        do {
            config = try ShareSessionBootstrap.configuration()
        } catch ShareSessionError.missingAPICredentials {
            updateStage(.apiCredentials)
            return
        }
        configuration = config
        updateStage(.connecting)
        clientID = td_create_client_id()
        if !receiverStarted {
            receiverStarted = true
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            while true {
                if let response = td_receive(0.25) {
                    let bytes = Data(String(cString: response).utf8)
                    if let json = try? JSONSerialization.jsonObject(with: bytes) as? TDJSON {
                        Task { @MainActor [weak self] in self?.receive(json) }
                    }
                }
                guard self != nil else { return }
            }
            }
        }
        let response = try await query("getAuthorizationState")
        handleAuthorization(response)
    }

    /// A wrong API pair was already applied to setTdlibParameters, so it
    /// cannot be changed in-place. Close that TDLib client, discard ONLY
    /// the extension's local session and start with the replacement pair.
    func saveAPI(id: Int, hash: String) async throws {
        let validHash = hash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id > 0, validHash.count == 32,
              validHash.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0)
              })
        else {
            throw ShareSendError.invalidAPICredentials
        }

        if clientID != 0 {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                closeWaiter = continuation
                call("close")
            }
        }

        try? ShareSessionBootstrap.reset()
        _ = try ShareSessionBootstrap.saveCredentials(apiID: id, apiHash: validHash)
        parametersSent = false
        authReady = false
        configuration = nil
        updateStage(.connecting)
        try await start()
    }

    func editAPI() {
        updateStage(.apiCredentials)
    }

    private func authorize(_ method: String, _ arguments: TDJSON = [:]) async throws {
        _ = try await query(method, arguments)
        let state = try await query("getAuthorizationState")
        handleAuthorization(state)
    }

    func submitPhone(_ phone: String) async throws {
        try await authorize("setAuthenticationPhoneNumber", [
            "phone_number": phone,
            "settings": [
                "@type": "phoneNumberAuthenticationSettings",
                "allow_flash_call": false,
                "allow_missed_call": false,
                "is_current_phone_number": false,
                "allow_sms_retriever_api": false
            ] as TDJSON
        ])
    }

    func submitCode(_ code: String) async throws {
        try await authorize("checkAuthenticationCode", ["code": code])
    }

    func submitPassword(_ password: String) async throws {
        try await authorize("checkAuthenticationPassword", ["password": password])
    }

    func submitEmail(_ email: String) async throws {
        try await authorize("setAuthenticationEmailAddress", ["email_address": email])
    }

    func submitEmailCode(_ code: String) async throws {
        try await authorize("checkAuthenticationEmailCode", [
            "code": ["@type": "emailAddressAuthenticationCode", "code": code] as TDJSON
        ])
    }

    func requestQR() async throws {
        try await authorize("requestQrCodeAuthentication", ["other_user_ids": [] as [Int64]])
    }

    func connect() async throws {
        try await start()
        guard authReady else { throw ShareSendError.authorizationRequired }
    }

    private func call(_ name: String, _ parameters: TDJSON = [:],
                      callback: ((TDJSON) -> Void)? = nil) {
        var payload = parameters
        payload["@type"] = name
        if let callback {
            let key = UUID().uuidString
            payload["@extra"] = key
            callbacks[key] = callback
        }
        let json = try! JSONSerialization.data(withJSONObject: payload)
        td_send(clientID, String(decoding: json, as: UTF8.self))
    }

    private func query(_ name: String, _ parameters: TDJSON = [:]) async throws -> TDJSON {
        let response = await withCheckedContinuation { (continuation: CheckedContinuation<TDJSON, Never>) in
            call(name, parameters) { continuation.resume(returning: $0) }
        }
        if response.text("@type") == "error" {
            let reason = response.text("message")
            if reason == "API_ID_INVALID" || reason == "CONNECTION_API_ID_INVALID" {
                updateStage(.apiCredentials)
                throw ShareSendError.invalidAPICredentials
            }
            throw ShareSendError.failed(reason)
        }
        return response
    }

    private func receive(_ json: TDJSON) {
        if json["@client_id"] != nil,
           json.number("@client_id") != Int64(clientID) { return }
        if let token = json["@extra"] as? String, let callback = callbacks.removeValue(forKey: token) {
            callback(json)
            return
        }
        switch json.text("@type") {
        case "updateAuthorizationState":
            handleAuthorization(json.object("authorization_state"))
        case "updateMessageSendSucceeded":
            finishMessage(json.number("old_message_id"), result: .success(()))
        case "updateMessageSendFailed":
            let error = json.object("error")
            let description = error.text("message").isEmpty
                ? "伺服器拒絕此訊息" : error.text("message")
            finishMessage(json.number("old_message_id"),
                          result: .failure(ShareSendError.failed(description)))
        default:
            break
        }
    }

    private func finishMessage(_ temporaryID: Int64, result: Result<Void, Error>) {
        if let continuation = awaitingMessages.removeValue(forKey: temporaryID) {
            continuation.resume(with: result)
        } else {
            completedMessages[temporaryID] = result
        }
    }

    private func handleAuthorization(_ state: TDJSON) {
        switch state.text("@type") {
        case "authorizationStateWaitTdlibParameters":
            guard !parametersSent, let config = configuration else { return }
            parametersSent = true
            let database = ShareSessionBootstrap.databaseDirectory
            let files = ShareSessionBootstrap.filesDirectory
            try? FileManager.default.createDirectory(
                at: database, withIntermediateDirectories: true
            )
            try? FileManager.default.createDirectory(
                at: files, withIntermediateDirectories: true
            )
            call("setTdlibParameters", [
                "database_directory": database.path,
                "files_directory": files.path,
                "use_message_database": true,
                "use_file_database": true,
                "use_chat_info_database": true,
                "use_secret_chats": true,
                "enable_storage_optimizer": true,
                "database_encryption_key": config.encryptionKey,
                "api_id": config.apiID,
                "api_hash": config.apiHash,
                "system_language_code": "zh-TW",
                "device_model": UIDevice.current.model,
                "system_version": UIDevice.current.systemVersion,
                "application_version": "1.0",
                "use_test_dc": false
            ]) { [weak self] response in
                if response.text("@type") == "error" {
                    let reason = response.text("message")
                    if reason == "API_ID_INVALID" || reason == "CONNECTION_API_ID_INVALID" {
                        self?.updateStage(.apiCredentials)
                        self?.onAuthorizationError?(ShareSendError.invalidAPICredentials.localizedDescription)
                    } else {
                        self?.onAuthorizationError?(reason)
                    }
                }
            }
        case "authorizationStateReady":
            authReady = true
            updateStage(.ready)
        case "authorizationStateWaitPhoneNumber":
            updateStage(.phone)
        case "authorizationStateWaitCode":
            updateStage(.code)
        case "authorizationStateWaitPassword":
            updateStage(.password)
        case "authorizationStateWaitEmailAddress":
            updateStage(.email)
        case "authorizationStateWaitEmailCode":
            updateStage(.emailCode)
        case "authorizationStateWaitOtherDeviceConfirmation":
            updateStage(.qr(state.text("link")))
        case "authorizationStateClosed":
            let waiter = closeWaiter
            closeWaiter = nil
            clientID = 0
            authReady = false
            parametersSent = false
            if let waiter {
                waiter.resume()
            } else {
                onAuthorizationError?("分享登入工作階段已關閉，請重新開啟分享視窗")
            }
        default:
            break
        }
    }

    var onAuthorizationError: ((String) -> Void)?

    /// Read recent chats from TDLib itself, not a cache of phone contacts.
    /// Telegram sends chat IDs as int64 decimal strings through the JSON API.
    func recentRecipients() async throws -> [ShareRecipient] {
        try await connect()
        let list: TDJSON = ["@type": "chatListMain"]
        // Read already synced recent chats immediately. Waiting for a fresh
        // 100-chat network load can exceed the iOS Share Extension lifetime.
        let cached = try? await query("getChats", ["chat_list": list, "limit": 100])
        var ids = cached?.intIDs("chat_ids") ?? []
        if ids.isEmpty {
            _ = try? await query("loadChats", ["chat_list": list, "limit": 100])
            let fetched = try await query("getChats", ["chat_list": list, "limit": 100])
            ids = fetched.intIDs("chat_ids")
        }
        var result: [ShareRecipient] = []
        for id in ids {
            let raw = try await query("getChat", ["chat_id": id])
            let title = raw.text("title")
            result.append(ShareRecipient(
                id: "chat:\(id)",
                title: title.isEmpty ? "對話 \(id)" : title,
                chatID: "\(id)",
                userID: nil
            ))
        }
        // The same on-device list serves as an instant snapshot for next time.
        if !result.isEmpty { ShareMailbox.saveRecipients(result) }
        return result
    }

    private func targetChatID(_ recipient: ShareRecipient) async throws -> Int64 {
        if let chat = recipient.chatID.flatMap(Int64.init) { return chat }
        if let user = recipient.userID.flatMap(Int64.init) {
            let chat = try await query("createPrivateChat", [
                "user_id": user, "force": false
            ])
            return chat.number("id")
        }
        throw ShareSendError.noRecipient
    }

    private func messageContent(_ file: ShareAttachment, at url: URL,
                                caption: String) -> TDJSON {
        let local: TDJSON = ["@type": "inputFileLocal", "path": url.path]
        let text: TDJSON = ["@type": "formattedText", "text": caption, "entities": []]
        switch file.kind {
        case "photo":
            return [
                "@type": "inputMessagePhoto",
                "photo": [
                    "@type": "inputPhoto", "photo": local,
                    "added_sticker_file_ids": [],
                    "width": 0, "height": 0
                ] as TDJSON,
                "caption": text,
                "show_caption_above_media": false,
                "has_spoiler": false
            ]
        case "video":
            return [
                "@type": "inputMessageVideo",
                "video": [
                    "@type": "inputVideo", "video": local,
                    "added_sticker_file_ids": [],
                    "start_timestamp": 0, "duration": 0,
                    "width": 0, "height": 0, "supports_streaming": true
                ] as TDJSON,
                "caption": text,
                "show_caption_above_media": false,
                "has_spoiler": false
            ]
        default:
            return [
                "@type": "inputMessageDocument",
                "document": [
                    "@type": "inputDocument", "document": local,
                    "disable_content_type_detection": true
                ] as TDJSON,
                "caption": text
            ]
        }
    }

    private func deliver(chatID: Int64, content: TDJSON) async throws {
        let response = try await query("sendMessage", [
            "chat_id": chatID,
            "input_message_content": content
        ])
        let tempID = response.number("id")
        if response.text("@type") != "message" || tempID == 0 {
            throw ShareSendError.failed("Telegram 未接受傳送要求")
        }
        if let result = completedMessages.removeValue(forKey: tempID) {
            try result.get()
            return
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            awaitingMessages[tempID] = continuation
        }
    }

    func send(_ share: PendingShare, progress: @escaping (String) -> Void) async throws {
        try await connect()
        let chatID = try await targetChatID(share.target)

        if share.attachments.isEmpty {
            guard deliveredShareItems[share.id]?.contains(-1) != true else { return }
            let content: TDJSON = [
                "@type": "inputMessageText",
                "text": [
                    "@type": "formattedText",
                    "text": share.caption,
                    "entities": []
                ] as TDJSON,
                "clear_draft": false,
                "disable_web_page_preview": false
            ]
            progress("正在傳送文字")
            try await deliver(chatID: chatID, content: content)
            deliveredShareItems[share.id, default: []].insert(-1)
            return
        }

        for (index, item) in share.attachments.enumerated() {
            // A retry after a partial upload must not duplicate successful
            // attachments from the same share sheet session.
            if deliveredShareItems[share.id]?.contains(index) == true { continue }
            let file = ShareMailbox.url(for: item)
            progress("正在傳送第 \(index + 1) 個附件，共 \(share.attachments.count) 個")
            let caption = index == 0 ? share.caption : ""
            let content = messageContent(item, at: file, caption: caption)
            try await deliver(chatID: chatID, content: content)
            deliveredShareItems[share.id, default: []].insert(index)
        }
    }
}
