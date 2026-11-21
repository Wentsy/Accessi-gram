import SwiftUI

/// Searches Telegram's entire conversation history and lets VoiceOver jump
/// directly from a result to its original message in the chat timeline.
struct AccessibleChatSearchSheet: View {
    let chatID: Int64
    @ObservedObject var service: TelegramService
    let onSelect: (TelegramMessage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [TelegramMessage] = []
    @State private var searching = false
    @State private var hasSearched = false
    @State private var requestToken = UUID()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    TextField("輸入聊天關鍵字", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .onSubmit(performSearch)
                        .accessibilityLabel("搜尋聊天內容，支援簡繁中文")
                    Button("搜尋", action: performSearch)
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(12)

                if searching {
                    ProgressView("正在搜尋聊天紀錄")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if hasSearched {
                    Text(results.isEmpty ? "找不到符合的訊息" : "找到 \(results.count) 則訊息")
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .accessibilityAddTraits(.updatesFrequently)
                } else {
                    Text("輸入繁體或簡體中文都能搜尋，結果會包含較早的聊天紀錄。")
                        .font(.footnote)
                        .padding()
                }

                List(results) { message in
                    Button {
                        onSelect(message)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(message.sender)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(message.body)
                                .foregroundStyle(.primary)
                            Text(TelegramMessage.timestamp.string(from: message.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel(message.spoken)
                    .accessibilityHint("點兩下回到聊天室並跳至這則訊息")
                }
                .listStyle(.plain)
            }
            .navigationTitle("搜尋聊天內容")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
        }
    }

    private func performSearch() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        requestToken = UUID()
        let token = requestToken
        searching = true
        hasSearched = false
        results = []
        service.searchChatMessages(chatID: chatID, query: text) { messages in
            guard requestToken == token else { return }
            results = messages
            searching = false
            hasSearched = true
        }
    }
}
