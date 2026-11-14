import SwiftUI
import UIKit

/// Single, shared timeline for personal chats, channels and groups.
struct AccessibleMessageTimeline: UIViewRepresentable {
    @ObservedObject var thread: MessageThread
    let service: TelegramService
    let onMenu: (TelegramMessage) -> Void
    let onReply: (TelegramMessage) -> Void
    let onMedia: (TelegramMessage) -> Void
    let onBotMenu: (TelegramMessage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(thread: thread, service: service, onMenu: onMenu,
                    onReply: onReply, onMedia: onMedia, onBotMenu: onBotMenu)
    }

    func makeUIView(context: Context) -> PagingTableView {
        let table = PagingTableView(frame: .zero, style: .plain)
        table.backgroundColor = UIColor.systemBackground
        table.separatorStyle = .none
        table.estimatedRowHeight = 72
        table.rowHeight = UITableView.automaticDimension
        table.register(MessageRow.self, forCellReuseIdentifier: "Message")
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.olderAction = { [weak coordinator = context.coordinator] in
            coordinator?.loadOlder()
        }
        table.keyboardDismissMode = .interactive
        return table
    }

    func updateUIView(_ table: PagingTableView, context: Context) {
        context.coordinator.onMenu = onMenu
        context.coordinator.onReply = onReply
        context.coordinator.onMedia = onMedia
        context.coordinator.onBotMenu = onBotMenu
        context.coordinator.apply(thread.messages, to: table)
    }

    @MainActor
    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        let thread: MessageThread
        let service: TelegramService
        var rendered: [TelegramMessage] = []
        var initialScrollDone = false
        var onMenu: (TelegramMessage) -> Void
        var onReply: (TelegramMessage) -> Void
        var onMedia: (TelegramMessage) -> Void
        var onBotMenu: (TelegramMessage) -> Void

        init(thread: MessageThread, service: TelegramService,
             onMenu: @escaping (TelegramMessage) -> Void,
             onReply: @escaping (TelegramMessage) -> Void,
             onMedia: @escaping (TelegramMessage) -> Void,
             onBotMenu: @escaping (TelegramMessage) -> Void) {
            self.thread = thread
            self.service = service
            self.onMenu = onMenu
            self.onReply = onReply
            self.onMedia = onMedia
            self.onBotMenu = onBotMenu
        }

        func loadOlder() { service.older(thread.chatID) }
        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            rendered.count
        }

        func tableView(_ tableView: UITableView, cellForRowAt path: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: "Message", for: path) as! MessageRow
            configure(cell, message: rendered[path.row], index: path.row)
            return cell
        }

        func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt path: IndexPath) {
            // Load well before VoiceOver reaches the beginning; no focus notification here.
            if path.row < 30 && thread.hasMore && !thread.loading { loadOlder() }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if scrollView.contentOffset.y < 750 && thread.hasMore && !thread.loading && !rendered.isEmpty {
                loadOlder()
            }
        }

        func tableView(_ tableView: UITableView, didSelectRowAt path: IndexPath) {
            onMenu(rendered[path.row])
            tableView.deselectRow(at: path, animated: false)
        }

        private func configure(_ cell: MessageRow, message: TelegramMessage, index: Int) {
            let copy = message
            cell.configure(copy) { [weak self] in
                guard let self else { return }
                if index < 30 { self.loadOlder() }
            } onActivate: { [weak self] in
                self?.onMenu(copy)
            } onMedia: { [weak self] in
                self?.onMedia(copy)
            } onTranslate: { [weak self] in
                self?.service.translate(copy)
            } onReply: { [weak self] in
                self?.onReply(copy)
            } onBot: { [weak self] in
                self?.onBotMenu(copy)
            } onDelete: { [weak self] in
                self?.service.delete(copy)
            }
        }

        func apply(_ messages: [TelegramMessage], to table: UITableView) {
            if rendered == messages { return }
            let old = rendered
            let oldIDs = old.map(\.id)
            let newIDs = messages.map(\.id)

            if oldIDs == newIDs {
                rendered = messages
                for path in table.indexPathsForVisibleRows ?? [] {
                    if let cell = table.cellForRow(at: path) as? MessageRow, path.row < messages.count,
                       old[path.row] != messages[path.row] {
                        configure(cell, message: messages[path.row], index: path.row)
                    }
                }
                return
            }

            let firstVisible = table.indexPathsForVisibleRows?.first
            let anchorID = firstVisible.flatMap { $0.row < old.count ? old[$0.row].id : nil }
            let anchorOffset = firstVisible.map { table.rectForRow(at: $0).minY - table.contentOffset.y } ?? 0
            let atBottom = table.contentSize.height - table.contentOffset.y - table.bounds.height < 100
            let firstLoad = old.isEmpty

            let difference = newIDs.difference(from: oldIDs)
            let removed = difference.compactMap { change -> IndexPath? in
                if case .remove(let offset, _, _) = change { return IndexPath(row: offset, section: 0) }
                return nil
            }
            let added = difference.compactMap { change -> IndexPath? in
                if case .insert(let offset, _, _) = change { return IndexPath(row: offset, section: 0) }
                return nil
            }
            rendered = messages

            if firstLoad {
                table.reloadData()
                table.layoutIfNeeded()
                if !initialScrollDone, !messages.isEmpty {
                    initialScrollDone = true
                    let end = IndexPath(row: messages.count - 1, section: 0)
                    table.scrollToRow(at: end, at: .bottom, animated: false)
                    // Focus is left to the system: do not steal it from the navigation title.
                }
                return
            }

            UIView.performWithoutAnimation {
                table.performBatchUpdates {
                    if !removed.isEmpty { table.deleteRows(at: removed, with: .none) }
                    if !added.isEmpty { table.insertRows(at: added, with: .none) }
                } completion: { [weak self] _ in
                    guard let self else { return }
                    if atBottom && !UIAccessibility.isVoiceOverRunning,
                       newIDs.last != oldIDs.last, let last = newIDs.indices.last {
                        table.scrollToRow(at: IndexPath(row: last, section: 0), at: .bottom, animated: false)
                    } else if let anchorID, let index = newIDs.firstIndex(of: anchorID) {
                        // Keep the identical message in precisely the same visual position
                        // after older history rows are inserted above it.
                        let y = table.rectForRow(at: IndexPath(row: index, section: 0)).minY - anchorOffset
                        table.setContentOffset(CGPoint(x: 0, y: max(-table.adjustedContentInset.top, y)), animated: false)
                    }
                    // Reconfigure changed visible rows without table reload or VoiceOver notifications.
                    for path in table.indexPathsForVisibleRows ?? [] {
                        if path.row < messages.count, let cell = table.cellForRow(at: path) as? MessageRow {
                            self.configure(cell, message: messages[path.row], index: path.row)
                        }
                    }
                }
            }
        }
    }
}

final class PagingTableView: UITableView {
    var olderAction: (() -> Void)?
    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        if direction == .down || direction == .up { olderAction?() }
        return super.accessibilityScroll(direction)
    }
}

final class MessageRow: UITableViewCell {
    private var onFocus: (() -> Void)?
    private var onActivate: (() -> Void)?
    private let content = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        isAccessibilityElement = true
        accessibilityLanguage = "zh-TW"
        accessibilityTraits = [.staticText]
        content.isAccessibilityElement = false
        content.translatesAutoresizingMaskIntoConstraints = false
        content.numberOfLines = 0
        content.font = UIFont.preferredFont(forTextStyle: .body)
        content.adjustsFontForContentSizeCategory = true
        contentView.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            content.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(
        _ message: TelegramMessage,
        onFocus: @escaping () -> Void,
        onActivate: @escaping () -> Void,
        onMedia: @escaping () -> Void,
        onTranslate: @escaping () -> Void,
        onReply: @escaping () -> Void,
        onBot: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        content.text = "\(message.sender)\n\(message.body)\n\(TelegramMessage.timestamp.string(from: message.date))"
        accessibilityLabel = message.spoken
        accessibilityLanguage = "zh-TW"
        accessibilityHint = "上下滑動選擇翻譯、回覆或其他操作，點兩下開啟訊息選單"
        self.onFocus = onFocus
        self.onActivate = onActivate
        var actions = [
            UIAccessibilityCustomAction(name: "翻譯成繁體中文") { _ in onTranslate(); return true },
            UIAccessibilityCustomAction(name: "回覆") { _ in onReply(); return true },
            UIAccessibilityCustomAction(name: "複製訊息") { _ in
                UIPasteboard.general.string = message.body
                UIAccessibility.post(notification: .announcement, argument: "已複製訊息")
                return true
            },
            UIAccessibilityCustomAction(name: "更多操作") { _ in onActivate(); return true }
        ]
        if message.fileID > 0 {
            actions.append(UIAccessibilityCustomAction(name: "開啟附件") { _ in onMedia(); return true })
        }
        if !message.buttons.isEmpty || !message.keyboardButtons.isEmpty {
            actions.append(UIAccessibilityCustomAction(name: "展開機器人選單") { _ in onBot(); return true })
        }
        if message.outgoing {
            actions.append(UIAccessibilityCustomAction(name: "刪除訊息") { _ in onDelete(); return true })
        }
        accessibilityCustomActions = actions
    }

    override func accessibilityElementDidBecomeFocused() {
        super.accessibilityElementDidBecomeFocused()
        // VoiceOver swipes from the composer into a message: dismiss
        // the keyboard without moving the current VoiceOver message focus.
        if UIAccessibility.isVoiceOverRunning {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
        }
        onFocus?()
    }

    override func accessibilityActivate() -> Bool {
        onActivate?()
        return true
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onFocus = nil
        onActivate = nil
        accessibilityCustomActions = nil
    }
}
