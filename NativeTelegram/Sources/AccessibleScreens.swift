import UIKit
import SwiftUI
import Combine

/// UIKit-owned navigation, chat list, settings and contacts. Every visible row is
/// a single explicitly labeled VoiceOver element, instead of depending on
/// SwiftUI List/Form synthesizing nested accessibility children.
struct NativeConversationsView: UIViewControllerRepresentable {
    @ObservedObject var service: TelegramService

    func makeUIViewController(context: Context) -> UINavigationController {
        let screen = AccessibleConversationsController(service: service)
        return UINavigationController(rootViewController: screen)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}

final class AccessibleChatCell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        textLabel?.font = .preferredFont(forTextStyle: .headline)
        textLabel?.adjustsFontForContentSizeCategory = true
        detailTextLabel?.font = .preferredFont(forTextStyle: .subheadline)
        detailTextLabel?.adjustsFontForContentSizeCategory = true
        detailTextLabel?.numberOfLines = 2
        accessoryType = .disclosureIndicator
        isAccessibilityElement = true
        accessibilityLanguage = "zh-TW"
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("Use init(style:reuseIdentifier:)") }

    func display(_ chat: TelegramChat, service: TelegramService) {
        textLabel?.text = chat.title
        detailTextLabel?.text = chat.lastPreview
        accessibilityLabel = chat.spoken
        accessibilityHint = "點兩下開啟對話，上下滑動可選擇聊天操作"
        accessibilityLanguage = "zh-TW"
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "標記未讀") { _ in
                service.markUnread(chatID: chat.id)
                return true
            },
            UIAccessibilityCustomAction(name: chat.isPinned ? "取消置頂" : "置頂") { _ in
                service.setPinned(chatID: chat.id, value: !chat.isPinned)
                return true
            },
            UIAccessibilityCustomAction(name: chat.isArchived ? "移回聊天" : "封存") { _ in
                service.archiveChat(chatID: chat.id, value: !chat.isArchived)
                return true
            }
        ]
    }
}

@MainActor
final class AccessibleConversationsController: UIViewController, UITableViewDelegate, UISearchResultsUpdating {
    private let service: TelegramService
    private let table = UITableView(frame: .zero, style: .plain)
    private let search = UISearchController(searchResultsController: nil)
    private var dataSource: UITableViewDiffableDataSource<Int, Int64>!
    private var subscriptions = Set<AnyCancellable>()
    private var visibleChats: [TelegramChat] = []
    private var byID: [Int64: TelegramChat] = [:]
    private var searchQuery = ""
    private let statusLabel = UILabel()
    private let refresh = UIRefreshControl()

    init(service: TelegramService) {
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(service:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        table.translatesAutoresizingMaskIntoConstraints = false
        table.delegate = self
        table.register(AccessibleChatCell.self, forCellReuseIdentifier: "chat")
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 72
        table.keyboardDismissMode = .onDrag
        view.addSubview(table)
        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        dataSource = UITableViewDiffableDataSource<Int, Int64>(tableView: table) { [weak self] table, path, chatID in
            let cell = table.dequeueReusableCell(withIdentifier: "chat", for: path) as! AccessibleChatCell
            if let self, let chat = self.byID[chatID] { cell.display(chat, service: self.service) }
            return cell
        }
        table.dataSource = dataSource

        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.textColor = .secondaryLabel
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.isAccessibilityElement = true
        statusLabel.accessibilityLanguage = "zh-TW"

        refresh.addTarget(self, action: #selector(refreshChats), for: .valueChanged)
        refresh.accessibilityLabel = "重新同步聊天"
        table.refreshControl = refresh

        search.searchResultsUpdater = self
        search.searchBar.placeholder = "搜尋聊天室、群組或頻道"
        search.searchBar.accessibilityLanguage = "zh-TW"
        search.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        configureToolbar()
        service.$chats.combineLatest(service.$searchResults)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.refreshRows() }
            .store(in: &subscriptions)
        service.$chatSyncStatus.combineLatest(service.$loadingChats)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.updateStatus() }
            .store(in: &subscriptions)
        service.$archived.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.configureToolbar()
                self?.refreshRows()
            }
            .store(in: &subscriptions)
        updateStatus()
        refreshRows()
        if service.chats.isEmpty { service.loadChats() }
    }

    private func configureToolbar() {
        title = service.archived ? "封存的對話" : "聊天"
        let archive = UIBarButtonItem(title: service.archived ? "返回聊天" : "封存",
                                      style: .plain, target: self, action: #selector(toggleArchive))
        archive.accessibilityLabel = service.archived ? "返回聊天列表" : "查看封存聊天"
        navigationItem.leftBarButtonItem = archive

        let newChat = UIBarButtonItem(title: "新增聊天", style: .plain,
                                      target: self, action: #selector(openNewChat))
        newChat.accessibilityLabel = "新增聊天"
        let settings = UIBarButtonItem(title: "設定", style: .plain,
                                       target: self, action: #selector(openSettings))
        settings.accessibilityLabel = "設定"
        navigationItem.rightBarButtonItems = [settings, newChat]
    }

    @objc private func toggleArchive() {
        service.toggleArchive()
    }

    @objc private func openNewChat() {
        navigationController?.pushViewController(AccessibleNewChatController(service: service), animated: true)
    }

    @objc private func openSettings() {
        navigationController?.pushViewController(AccessibleSettingsController(service: service), animated: true)
    }

    @objc private func refreshChats() {
        service.loadChats()
    }

    func updateSearchResults(for searchController: UISearchController) {
        searchQuery = searchController.searchBar.text ?? ""
        service.search(searchQuery)
        refreshRows()
    }

    private func refreshRows() {
        var list = service.chats
        if !searchQuery.isEmpty {
            list = list.filter { $0.title.localizedCaseInsensitiveContains(searchQuery) }
            for result in service.searchResults
            where !list.contains(where: { $0.id == result.id }) {
                list.append(result)
            }
        }
        visibleChats = list
        byID = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })

        var snapshot = NSDiffableDataSourceSnapshot<Int, Int64>()
        snapshot.appendSections([0])
        snapshot.appendItems(list.map(\.id))
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            self?.refreshVisibleCells()
        }
        updateStatus()
    }

    private func refreshVisibleCells() {
        for path in table.indexPathsForVisibleRows ?? [] {
            guard let id = dataSource.itemIdentifier(for: path),
                  let chat = byID[id],
                  let cell = table.cellForRow(at: path) as? AccessibleChatCell else { continue }
            cell.display(chat, service: service)
        }
    }

    private func updateStatus() {
        refresh.endRefreshing()
        statusLabel.text = service.chatSyncStatus
        statusLabel.accessibilityLabel = service.chatSyncStatus
        table.backgroundView = visibleChats.isEmpty ? statusLabel : nil
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        let chat = UIHostingController(rootView: ChatScreen(chatID: id))
        chat.title = byID[id]?.title ?? "對話"
        navigationController?.pushViewController(chat, animated: true)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt path: IndexPath) {
        if searchQuery.isEmpty && path.row >= max(0, visibleChats.count - 12) {
            service.loadMoreChats()
        }
    }
}

final class AccessibleSettingCell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        textLabel?.font = .preferredFont(forTextStyle: .body)
        textLabel?.adjustsFontForContentSizeCategory = true
        detailTextLabel?.font = .preferredFont(forTextStyle: .footnote)
        detailTextLabel?.adjustsFontForContentSizeCategory = true
        detailTextLabel?.numberOfLines = 0
        isAccessibilityElement = true
        accessibilityLanguage = "zh-TW"
    }
    required init?(coder: NSCoder) { fatalError("Use init(style:reuseIdentifier:)") }

    func display(title: String, detail: String, button: Bool = false) {
        textLabel?.text = title
        detailTextLabel?.text = detail
        accessibilityLabel = detail.isEmpty ? title : "\(title)，\(detail)"
        accessibilityTraits = button ? [.button] : [.staticText]
        accessoryType = button ? .disclosureIndicator : .none
    }
}

@MainActor
final class AccessibleSettingsController: UITableViewController {
    private let service: TelegramService
    private var subscriptions = Set<AnyCancellable>()

    init(service: TelegramService) {
        self.service = service
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("Use init(service:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "設定"
        tableView.register(AccessibleSettingCell.self, forCellReuseIdentifier: "setting")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 74
        tableView.accessibilityLanguage = "zh-TW"

        // Update visible status in place rather than reloading a whole section
        // and displacing a VoiceOver cursor in the middle of the page.
        service.$chatSyncStatus.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let path = IndexPath(row: 0, section: 1)
                if let cell = self.tableView.cellForRow(at: path) as? AccessibleSettingCell {
                    cell.display(title: "重新同步對話",
                                 detail: self.service.chatSyncStatus, button: true)
                }
            }
            .store(in: &subscriptions)
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 1 }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["說明與協助", "聊天資料", "帳號"][section]
    }

    override func tableView(_ tableView: UITableView, cellForRowAt path: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "setting", for: path) as! AccessibleSettingCell
        switch path.section {
        case 0:
            cell.display(title: "使用指南", detail: "閱讀旁白翻頁、訊息操作、語音和翻譯說明",
                         button: true)
        case 1:
            cell.display(title: "重新同步對話", detail: service.chatSyncStatus, button: true)
        default:
            cell.display(title: "登出 Telegram", detail: "須再次確認才會登出", button: true)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt path: IndexPath) {
        tableView.deselectRow(at: path, animated: true)
        switch path.section {
        case 0:
            navigationController?.pushViewController(AccessibleHelpController(style: .insetGrouped), animated: true)
        case 1:
            service.loadChats()
            UIAccessibility.post(notification: .announcement,
                                 argument: "已要求重新同步 Telegram 對話")
        default:
            let alert = UIAlertController(title: "確認登出",
                                          message: "登出此裝置上的 Telegram 帳號？",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.addAction(UIAlertAction(title: "登出", style: .destructive) { [weak self] _ in
                self?.service.logOut()
            })
            present(alert, animated: true)
        }
    }
}

@MainActor
final class AccessibleNewChatController: UITableViewController, UISearchResultsUpdating {
    private let service: TelegramService
    private let usernameInput = UITextField()
    private let search = UISearchController(searchResultsController: nil)
    private var allContacts: [TelegramContact] = []
    private var searchQuery = ""
    private var subscriptions = Set<AnyCancellable>()

    init(service: TelegramService) {
        self.service = service
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("Use init(service:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "新增聊天"
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        usernameInput.placeholder = "輸入 @username"
        usernameInput.autocapitalizationType = .none
        usernameInput.autocorrectionType = .no
        usernameInput.accessibilityLabel = "Telegram 使用者名稱"
        usernameInput.accessibilityLanguage = "zh-TW"
        usernameInput.translatesAutoresizingMaskIntoConstraints = false
        search.searchResultsUpdater = self
        search.searchBar.placeholder = "搜尋聯絡人"
        search.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = search
        definesPresentationContext = true
        service.$contacts.receive(on: DispatchQueue.main)
            .sink { [weak self] contacts in
                self?.allContacts = contacts
                self?.tableView.reloadData()
            }.store(in: &subscriptions)
        service.loadContacts()
    }

    private var contacts: [TelegramContact] {
        if searchQuery.isEmpty { return allContacts }
        return allContacts.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }

    func updateSearchResults(for searchController: UISearchController) {
        searchQuery = searchController.searchBar.text ?? ""
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 2 : contacts.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "依使用者名稱搜尋" : "聯絡人"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt path: IndexPath) -> UITableViewCell {
        if path.section == 0 && path.row == 0 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.contentView.addSubview(usernameInput)
            NSLayoutConstraint.activate([
                usernameInput.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
                usernameInput.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12),
                usernameInput.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
                usernameInput.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16)
            ])
            cell.isAccessibilityElement = false
            return cell
        }
        let cell = AccessibleSettingCell(style: .subtitle, reuseIdentifier: nil)
        if path.section == 0 {
            cell.display(title: "尋找使用者或頻道", detail: "以 username 查詢並開啟聊天", button: true)
        } else {
            cell.display(title: contacts[path.row].name, detail: "點兩下開始聊天", button: true)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt path: IndexPath) {
        tableView.deselectRow(at: path, animated: true)
        if path.section == 0 && path.row == 1 {
            service.findUsername(usernameInput.text ?? "") { [weak self] chatID in
                if let chatID { self?.open(chatID) }
            }
        } else if path.section == 1 {
            let userID = contacts[path.row].id
            service.createPrivateChat(userID: userID) { [weak self] chatID in
                if let chatID { self?.open(chatID) }
            }
        }
    }

    private func open(_ chatID: Int64) {
        navigationController?.pushViewController(UIHostingController(rootView: ChatScreen(chatID: chatID)), animated: true)
    }
}
