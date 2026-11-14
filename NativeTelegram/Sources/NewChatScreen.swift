import SwiftUI

struct NewChatScreen: View {
    @ObservedObject private var service = TelegramService.shared
    @State private var username = ""
    @State private var searchText = ""
    @State private var openedChatID: Int64?

    var filteredContacts: [(id: Int64, name: String)] {
        if searchText.isEmpty { return service.contacts }
        return service.contacts.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            Section("依 Telegram 使用者名稱尋找") {
                TextField("輸入 @username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Telegram 使用者名稱")
                Button("尋找使用者、群組或頻道") {
                    service.findUsername(username) { openedChatID = $0 }
                }
                .disabled(username.isEmpty)
            }
            Section("聯絡人") {
                ForEach(filteredContacts, id: \.id) { contact in
                    Button(contact.name) {
                        service.createPrivateChat(userID: contact.id) { openedChatID = $0 }
                    }
                    .accessibilityLabel("與 \(contact.name) 開始聊天")
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜尋聯絡人")
        .navigationTitle("新增聊天")
        .onAppear { service.loadContacts() }
        .navigationDestination(isPresented: Binding(
            get: { openedChatID != nil },
            set: { if !$0 { openedChatID = nil } }
        )) {
            if let openedChatID { ChatScreen(chatID: openedChatID) }
        }
    }
}
