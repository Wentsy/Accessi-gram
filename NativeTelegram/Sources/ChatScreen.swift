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
    @State private var menuMessage: TelegramMessage?
    @State private var showingMessageMenu = false
    @State private var botMessage: TelegramMessage?
    @State private var showingBotMenu = false
    @State private var mediaMessage: TelegramMessage?
    @State private var forwardMessage: TelegramMessage?
    @State private var showingForward = false
    @State private var showingReactions = false
    @State private var showingEdit = false
    @State private var editedText = ""

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
                onMenu: { message in
                    menuMessage = message
                    showingMessageMenu = true
                },
                onReply: { message in thread.replyTo = message },
                onMedia: { message in mediaMessage = message },
                onBotMenu: { message in
                    botMessage = message
                    showingBotMenu = true
                }
            )
            if thread.loading && thread.messages.isEmpty {
                ProgressView("載入訊息中")
                    .accessibilityLabel("正在載入訊息")
            }
            Divider()
            if let reply = thread.replyTo {
                HStack {
                    Text("回覆 \(reply.sender)：\(reply.body)")
                        .lineLimit(1)
                        .accessibilityLabel("目前回覆 \(reply.sender)，\(reply.body)")
                    Spacer()
                    Button { thread.replyTo = nil } label: { Label("取消回覆", systemImage: "xmark") }
                        .labelStyle(.iconOnly)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            composer
        }
        .navigationTitle(service.chatTitle(chatID))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { service.open(chatID) }
        .onDisappear { service.close(chatID) }
        .confirmationDialog("訊息操作", isPresented: $showingMessageMenu, titleVisibility: .visible) {
            if let message = menuMessage {
                Button("翻譯成繁體中文並朗讀") { service.translate(message) }
                Button("回覆") { thread.replyTo = message }
                Button("複製訊息") {
                    UIPasteboard.general.string = message.body
                    UIAccessibility.post(notification: .announcement, argument: "訊息已複製")
                }
                if message.fileID > 0 {
                    Button("開啟附件") { mediaMessage = message }
                }
                if !message.buttons.isEmpty || !message.keyboardButtons.isEmpty {
                    Button("展開機器人選單") {
                        botMessage = message
                        showingBotMenu = true
                    }
                }
                Button("表情回應") { showingReactions = true }
                Button("轉寄") {
                    forwardMessage = message
                    showingForward = true
                }
                if message.outgoing {
                    if message.fileKind.isEmpty {
                        Button("編輯") {
                            editedText = message.body
                            showingEdit = true
                        }
                    }
                    Button("刪除訊息", role: .destructive) {
                        service.delete(message)
                    }
                }
            }
        }
        .confirmationDialog("機器人互動選單", isPresented: $showingBotMenu, titleVisibility: .visible) {
            if let message = botMessage {
                ForEach(message.buttons + message.keyboardButtons) { button in
                    Button(button.title) {
                        service.botAction(button, message: message)
                    }
                }
            } else if let message = keyboardMessage {
                ForEach(message.keyboardButtons) { button in
                    Button(button.title) {
                        service.botAction(button, message: message)
                    }
                }
            }
        }
        .confirmationDialog("選擇表情回應", isPresented: $showingReactions, titleVisibility: .visible) {
            if let message = menuMessage {
                ForEach(["👍", "❤️", "😂", "🎉", "😮", "🙏"], id: \.self) { emoji in
                    Button(emoji) { service.react(message, emoji: emoji) }
                }
            }
        }
        .alert("編輯訊息", isPresented: $showingEdit) {
            TextField("訊息", text: $editedText)
            Button("儲存") {
                if let message = menuMessage { service.edit(message, newText: editedText) }
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(item: $mediaMessage) { message in
            MediaViewer(message: message, service: service, recorder: voice)
        }
        .sheet(isPresented: $showingForward) {
            if let message = forwardMessage {
                ForwardPicker(message: message, service: service)
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) {
            result in
            guard case let .success(urls) = result else { return }
            for url in urls {
                let accessing = url.startAccessingSecurityScopedResource()
                let local = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
                try? FileManager.default.copyItem(at: url, to: local)
                if accessing { url.stopAccessingSecurityScopedResource() }
                let type = UTType(filenameExtension: local.pathExtension)
                let kind: String
                if type?.conforms(to: .image) == true { kind = "photo" }
                else if type?.conforms(to: .movie) == true { kind = "video" }
                else { kind = "document" }
                service.sendMedia(chatID: chatID, fileURL: local, kind: kind)
            }
        }
        .onChange(of: selectedPhoto) { selected in
            guard let selected else { return }
            Task {
                let isMovie = selected.supportedContentTypes.contains { $0.conforms(to: .movie) }
                if isMovie {
                    if let movie = try? await selected.loadTransferable(type: ImportedMovie.self) {
                        service.sendMedia(chatID: chatID, fileURL: movie.url, kind: "video")
                    }
                } else if let data = try? await selected.loadTransferable(type: Data.self) {
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
                    try? data.write(to: url)
                    service.sendMedia(chatID: chatID, fileURL: url, kind: "photo")
                }
                selectedPhoto = nil
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 10) {
                PhotosPicker(selection: $selectedPhoto, matching: .any(of: [.images, .videos])) {
                    Image(systemName: "photo.on.rectangle")
                }
                .accessibilityLabel("傳送照片或影片")

                Button { showFiles = true } label: {
                    Image(systemName: "paperclip")
                }
                .accessibilityLabel("傳送檔案或附件")

                TextField("輸入訊息", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .accessibilityLabel("訊息編輯框")

                if voice.isRecording {
                    Button {
                        if let url = voice.stop() {
                            service.sendMedia(chatID: chatID, fileURL: url, kind: "voice")
                        }
                    } label: { Label("停止並傳送", systemImage: "stop.circle.fill") }
                    .labelStyle(.iconOnly)
                    Button { voice.cancel() } label: { Label("取消錄音", systemImage: "xmark.circle") }
                        .labelStyle(.iconOnly)
                } else if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button { sendDraft() } label: { Label("傳送", systemImage: "arrow.up.circle.fill") }
                        .labelStyle(.iconOnly)
                        .accessibilityHint("傳送文字訊息")
                } else {
                    Button { voice.start() } label: {
                        Image(systemName: "mic.fill")
                    }
                    .accessibilityLabel("開始錄製語音訊息")
                }
            }
            .buttonStyle(.borderless)
            .font(.title3)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            if keyboardMessage != nil {
                Button("展開機器人鍵盤") {
                    botMessage = keyboardMessage
                    showingBotMenu = true
                }
                .font(.footnote)
                .padding(.bottom, 4)
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

struct ForwardPicker: View {
    let message: TelegramMessage
    @ObservedObject var service: TelegramService
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var choices: [TelegramChat] {
        service.chats.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(choices) { chat in
                    Button(chat.title) {
                        service.forward(message, to: chat.id)
                        dismiss()
                        UIAccessibility.post(notification: .announcement,
                                             argument: "已將訊息轉寄到 \(chat.title)")
                    }
                }
            }
            .searchable(text: $query, prompt: "搜尋要轉寄的聊天")
            .navigationTitle("轉寄給")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("取消") { dismiss() } } }
        }
    }
}
