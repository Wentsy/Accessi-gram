import SwiftUI
import UIKit

/// A single SwiftUI sheet avoids nesting UIKit navigation and search
/// controllers inside another modal while VoiceOver is dismissing an action sheet.
struct AccessibleForwardSheet: View {
    let message: TelegramMessage
    @ObservedObject var service: TelegramService
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var sending = false
    @State private var showError = false
    @State private var errorText = ""

    private var recipients: [TelegramChat] {
        service.chats.filter {
            query.isEmpty || $0.title.localizedStandardContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if recipients.isEmpty {
                    Text("沒有符合的對話")
                        .accessibilityLabel("沒有符合的對話")
                }
                ForEach(recipients) { chat in
                    Button {
                        forward(to: chat)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(chat.title)
                                .font(.body)
                            Text(chat.isChannel ? "頻道" :
                                 (chat.isGroupOrChannel ? "群組" : "私人對話"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("轉寄給 \(chat.title)")
                    .accessibilityHint("點兩下將原訊息和附件一起轉寄")
                    .disabled(sending)
                }
                if sending {
                    ProgressView("正在提交轉寄")
                        .accessibilityLabel("正在提交轉寄")
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "搜尋最近聯絡人、群組或頻道")
            .navigationTitle("轉寄訊息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(sending)
                }
            }
            .alert("轉寄失敗", isPresented: $showError) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorText)
            }
        }
    }

    private func forward(to chat: TelegramChat) {
        sending = true
        service.forward(message, to: chat.id) { success, reason in
            sending = false
            if success {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    UIAccessibility.post(notification: .announcement,
                                         argument: "已提交轉寄給 \(chat.title)，正在傳送")
                }
            } else {
                errorText = reason
                showError = true
            }
        }
    }
}
