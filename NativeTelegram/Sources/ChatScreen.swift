import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ChatScreen: View {
    let chatID: Int64
    @ObservedObject private var service = TelegramService.shared
    @StateObject private var thread: MessageThread
    @StateObject private var voice = VoiceRecorder()
    @State private var draft = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showFiles = false
    @State private var attachmentStatus = ""
    @State private var showPhotos = false
    @State private var mediaMessage: TelegramMessage?
    @State private var forwardMessage: TelegramMessage?
    @State private var showingForward = false

    init(chatID: Int64) {
        self.chatID = chatID
        _thread = StateObject(wrappedValue: TelegramService.shared.thread(chatID))
    }

    private var keyboardMessage: TelegramMessage? {
        thread.messages.last(where: { !$0.keyboardButtons.isEmpty })
    }

    var body: some View {
        VStack(spacing: 0) {
            AccessibleMessageTimeline(
                thread: thread,
                service: service,
                onMenu: { message in showMessageMenu(message) },
                onReply: { message in thread.replyTo = message },
                onMedia: { message in mediaMessage = message },
                onBotMenu: { message in showBotMenu(message) }
            )
            if thread.loading && thread.messages.isEmpty {
                ProgressView("載入訊息中")
                    .accessibilityLabel("正在載入訊息")
            }
            Divider()
            if let reply = thread.replyTo {
                AccessibleReplyBanner(sender: reply.sender, content: reply.body) {
                    thread.replyTo = nil
                }
            }
            composer
            if !attachmentStatus.isEmpty {
                Text(attachmentStatus)
                    .font(.footnote)
                    .accessibilityLabel(attachmentStatus)
            }
        }
        .navigationTitle(service.chatTitle(chatID))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { service.open(chatID) }
        .onDisappear { service.close(chatID) }
        .sheet(item: $mediaMessage) { message in
            AccessibleMediaSheet(message: message, service: service)
        }
        .sheet(isPresented: $showingForward) {
            if let message = forwardMessage {
                AccessibleForwardSheet(message: message, service: service)
            }
        }
        .photosPicker(isPresented: $showPhotos, selection: $selectedPhoto, matching: .any(of: [.images, .videos]))
        .sheet(isPresented: $showFiles) {
            AccessibleDocumentPicker(
                onSelect: { urls in
                    showFiles = false
                    attachmentStatus = "正在準備 \(urls.count) 個檔案"
                    Task {
                        for url in urls {
                            do {
                                let local = try await AttachmentPreparation.copyFromFiles(url)
                                service.sendMedia(chatID: chatID, fileURL: local, kind: "document")
                                UIAccessibility.post(notification: .announcement,
                                                     argument: "正在傳送 \(url.lastPathComponent)")
                            } catch {
                                let reason = "無法傳送 \(url.lastPathComponent)：\(error.localizedDescription)"
                                service.errorMessage = reason
                                UIAccessibility.post(notification: .announcement, argument: reason)
                            }
                        }
                        attachmentStatus = ""
                    }
                },
                onCancel: {
                    showFiles = false
                    attachmentStatus = ""
                }
            )
        }
        .onChange(of: selectedPhoto) { selection in
            guard let selection else { return }
            Task {
                defer { selectedPhoto = nil }
                do {
                    let isMovie = selection.supportedContentTypes.contains {
                        $0.conforms(to: .movie)
                    }
                    if isMovie {
                        guard let movie = try await selection.loadTransferable(type: ImportedMovie.self) else {
                            throw AttachmentPreparation.Failure.unreadableFile
                        }
                        let mp4 = try await AttachmentPreparation.videoForTelegram(movie.url)
                        service.sendMedia(chatID: chatID, fileURL: mp4, kind: "video")
                    } else {
                        guard let data = try await selection.loadTransferable(type: Data.self) else {
                            throw AttachmentPreparation.Failure.unreadableFile
                        }
                        let jpeg = try AttachmentPreparation.photoFromPicker(data)
                        service.sendMedia(chatID: chatID, fileURL: jpeg, kind: "photo")
                    }
                } catch {
                    service.errorMessage = "無法傳送選取的照片或影片：\(error.localizedDescription)"
                }
            }
        }
    }

    private func messageMenuChoices(_ message: TelegramMessage) -> [AccessibleMenuChoice] {
        var choices: [AccessibleMenuChoice] = [
            .init("translate", "翻譯成繁體中文並朗讀"),
            .init("reply", "回覆訊息"),
            .init("copy", "複製訊息"),
        ]
        if message.fileID > 0 {
            choices.append(.init("open", message.fileKind == "voice" || message.fileKind == "audio"
                                 ? "播放語音訊息" : "開啟附件"))
        }
        if !message.buttons.isEmpty || !message.keyboardButtons.isEmpty {
            choices.append(.init("bot", "展開機器人互動選單"))
        }
        choices += [.init("react", "表情回應"), .init("forward", "轉寄訊息")]
        if message.outgoing {
            if message.fileKind.isEmpty { choices.append(.init("edit", "編輯訊息")) }
            choices.append(.init("delete", "刪除訊息"))
        }
        return choices
    }

    private func showMessageMenu(_ message: TelegramMessage) {
        AccessibleSystemMenu.present(title: "訊息操作",
            choices: messageMenuChoices(message)) { id in
            performMessageAction(id, for: message)
        }
    }

    private func showBotMenu(_ message: TelegramMessage) {
        let items = message.buttons + message.keyboardButtons
        AccessibleSystemMenu.present(title: "機器人互動選單",
            choices: items.map { AccessibleMenuChoice($0.id, $0.title) }) { id in
            if let button = items.first(where: { $0.id == id }) {
                service.botAction(button, message: message)
            }
        }
    }

    private func showReactionMenu(_ message: TelegramMessage) {
        AccessibleSystemMenu.present(title: "選擇表情回應",
            choices: ["👍", "❤️", "😂", "🎉", "😮", "🙏"].map {
                AccessibleMenuChoice($0, "回應 \($0)")
            }) { emoji in
            service.react(message, emoji: emoji)
        }
    }

    private func performMessageAction(_ id: String, for message: TelegramMessage) {
        switch id {
        case "translate":
            service.translate(message)
        case "reply":
            thread.replyTo = message
        case "copy":
            UIPasteboard.general.string = message.body
            UIAccessibility.post(notification: .announcement, argument: "訊息已複製")
        case "open", "bot", "react", "forward", "edit":
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                switch id {
                case "open":
                    mediaMessage = message
                case "bot":
                    showBotMenu(message)
                case "react":
                    showReactionMenu(message)
                case "forward":
                    forwardMessage = message
                    showingForward = true
                case "edit":
                    AccessibleSystemMenu.editMessage(initial: message.body) { newText in
                        service.edit(message, newText: newText)
                    }
                default: break
                }
            }
        case "delete":
            service.delete(message)
        default: break
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            AccessibleComposer(
                text: $draft,
                isRecording: voice.isRecording,
                onPhotos: { showPhotos = true },
                onFiles: { showFiles = true },
                onAction: {
                    if voice.isRecording {
                        if let recording = voice.stop() {
                            service.sendMedia(chatID: chatID, fileURL: recording,
                                              kind: "voice", duration: voice.lastDuration)
                        }
                    } else if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        sendDraft()
                    } else {
                        voice.start()
                    }
                },
                onCancelRecording: { voice.cancel() }
            )
            if keyboardMessage != nil {
                Button("展開機器人鍵盤") {
                    if let keyboardMessage { showBotMenu(keyboardMessage) }
                }
                .accessibilityLabel("展開機器人互動選單")
                .accessibilityHint("點兩下選擇機器人提供的選項")
                .padding(.bottom, 5)
            }
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        service.sendText(chatID: chatID, text: text, replyID: thread.replyTo?.id ?? 0)
        draft = ""
        thread.replyTo = nil
        UIAccessibility.post(notification: .announcement, argument: "訊息已送出")
    }
}

