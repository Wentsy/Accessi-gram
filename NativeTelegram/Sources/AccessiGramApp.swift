import SwiftUI

@main
struct AccessiGramNativeApp: App {
    @StateObject private var service = TelegramService.shared

    var body: some Scene {
        WindowGroup {
            RootScreen()
                .environmentObject(service)
                .environment(\.locale, Locale(identifier: "zh_TW"))
                .task { service.start() }
        }
    }
}

struct RootScreen: View {
    @EnvironmentObject private var service: TelegramService
    var body: some View {
        Group {
            if service.authStage == .ready {
                ConversationsScreen()
            } else {
                AuthorizationScreen()
            }
        }
        .alert("Telegram 提示", isPresented: Binding(
            get: { !service.errorMessage.isEmpty },
            set: { if !$0 { service.errorMessage = "" } }
        )) {
            Button("確定") { service.errorMessage = "" }
        } message: { Text(service.errorMessage) }
    }
}

struct AuthorizationScreen: View {
    @EnvironmentObject private var service: TelegramService
    @State private var apiID = "37253223"
    @State private var apiHash = "aca2ec3d1e441897a84b1de89c4cb739"
    @State private var phone = ""
    @State private var code = ""
    @State private var password = ""
    @State private var email = ""

    var body: some View {
        NavigationStack {
            Form {
                switch service.authStage {
                case .credentials:
                    Section {
                        TextField("API ID", text: $apiID)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                        SecureField("API Hash", text: $apiHash)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("儲存並連線") {
                            service.configure(id: Int(apiID) ?? 0, hash: apiHash)
                        }
                        .disabled(apiID.isEmpty || apiHash.isEmpty)
                    } header: { Text("Telegram 應用程式金鑰") }
                    footer: {
                        Text("第一次登入需在 my.telegram.org 取得自己的 API ID 和 API Hash。金鑰只存放在本機鑰匙圈。")
                    }
                    Link("前往 Telegram API 開發頁面", destination: URL(string: "https://my.telegram.org")!)
                case .phone:
                    Section("以手機號碼登入") {
                        TextField("國際格式手機號碼，例如 +8869…", text: $phone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                        Button("取得驗證碼") { service.phone(phone) }
                            .disabled(phone.isEmpty)
                        Button("改用 QR Code 登入") { service.startQR() }
                    }
                case .code:
                    Section("輸入 Telegram 驗證碼") {
                        TextField("驗證碼", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                        Button("驗證並登入") { service.code(code) }.disabled(code.isEmpty)
                    }
                case .password:
                    Section("兩步驟驗證密碼") {
                        if !service.passwordHint.isEmpty { Text("提示：\(service.passwordHint)") }
                        SecureField("密碼", text: $password)
                        Button("登入") { service.password(password) }.disabled(password.isEmpty)
                    }
                case .email:
                    Section("驗證電子郵件") {
                        TextField("電子郵件", text: $email)
                            .textContentType(.emailAddress).keyboardType(.emailAddress)
                        Button("繼續") { service.email(email) }
                    }
                case .emailCode:
                    Section("輸入電子郵件驗證碼") {
                        TextField("驗證碼", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                        Button("驗證") { service.emailCode(code) }
                    }
                case .qr:
                    Section("使用已登入的 Telegram 掃描") {
                        if !service.qrLink.isEmpty {
                            QRCodeView(content: service.qrLink)
                            Text("在另一台已登入的 Telegram 裝置中，開啟裝置管理並掃描上方的 QR Code。")
                            Button("複製登入連結") {
                                UIPasteboard.general.string = service.qrLink
                                UIAccessibility.post(notification: .announcement, argument: "已複製登入連結")
                            }
                            .accessibilityHint("可供另一台裝置使用")
                        } else {
                            ProgressView("準備 QR Code 中")
                        }
                    }
                case .unknown:
                    Section {
                        ProgressView("正在連線 Telegram…")
                        Button("重新取得登入狀態") { service.command("getAuthorizationState") }
                    }
                case .ready:
                    EmptyView()
                }
            }
            .navigationTitle("Accessi Gram")
        }
    }
}

struct ConversationsScreen: View {
    @EnvironmentObject private var service: TelegramService
    @State private var searchText = ""
    @State private var showSettings = false

    var visibleChats: [TelegramChat] {
        if searchText.isEmpty { return service.chats }
        let local = service.chats.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
        let extra = service.searchResults.filter { result in
            !local.contains(where: { $0.id == result.id })
        }
        return local + extra
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(visibleChats) { chat in
                    NavigationLink {
                        ChatScreen(chatID: chat.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(chat.title)
                                    .font(.headline)
                                Spacer()
                                if chat.isPinned { Image(systemName: "pin.fill").accessibilityHidden(true) }
                                if chat.unreadCount > 0 {
                                    Text("\(chat.unreadCount) 未讀")
                                        .font(.subheadline)
                                }
                            }
                            if !chat.lastPreview.isEmpty {
                                Text(chat.lastPreview)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 5)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(chat.spoken)
                        .accessibilityHint("點兩下開啟對話；上下滑動可選擇其他操作")
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(chat.isArchived ? "取消封存" : "封存") {
                            service.archiveChat(chatID: chat.id, value: !chat.isArchived)
                        }
                        Button(chat.isPinned ? "取消置頂" : "置頂") {
                            service.setPinned(chatID: chat.id, value: !chat.isPinned)
                        }
                        Button("標記未讀") { service.markUnread(chatID: chat.id) }
                    }
                    .onAppear {
                        if searchText.isEmpty && chat.id == service.chats.last?.id { service.loadMoreChats() }
                    }
                    .contextMenu {
                        Button("標記未讀") { service.markUnread(chatID: chat.id) }
                        Button(chat.isPinned ? "取消置頂" : "置頂") {
                            service.setPinned(chatID: chat.id, value: !chat.isPinned)
                        }
                        Button(chat.isArchived ? "取消封存" : "封存") {
                            service.archiveChat(chatID: chat.id, value: !chat.isArchived)
                        }
                        Button("刪除對話", role: .destructive) { service.deleteChat(chatID: chat.id) }
                    }
                }
                if service.loadingChats { ProgressView("載入對話中") }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "搜尋聊天室與聯絡人")
            .onChange(of: searchText) { query in service.search(query) }
            .navigationTitle(service.archived ? "封存的對話" : "聊天")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(service.archived ? "返回聊天" : "封存") { service.toggleArchive() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink { NewChatScreen() } label: { Label("新增聊天", systemImage: "square.and.pencil") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: { Label("設定", systemImage: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsScreen() }
        }
    }
}

struct SettingsScreen: View {
    @EnvironmentObject private var service: TelegramService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("無障礙閱讀") {
                    Label("訊息朗讀順序：發送者、內容、時間", systemImage: "speaker.wave.2")
                    Label("歷史訊息於接近邊界時預先載入", systemImage: "arrow.up.arrow.down")
                    Label("訊息上下滑動可直接翻譯並朗讀", systemImage: "translate")
                }
                Section("語言") {
                    LabeledContent("介面語言", value: "繁體中文")
                    LabeledContent("翻譯目標", value: "繁體中文")
                }
                Section("翻譯與隱私") {
                    Text("翻譯是主動觸發的功能。選擇翻譯後，該則訊息文字將傳送至 Google Translate 網頁服務，並不使用正式收費 API。")
                }
                Section("帳號") {
                    Button("登出 Telegram", role: .destructive) {
                        service.logOut()
                        dismiss()
                    }
                }
            }
            .navigationTitle("設定")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}
