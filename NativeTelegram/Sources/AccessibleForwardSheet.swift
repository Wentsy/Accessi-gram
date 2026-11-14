import SwiftUI
import UIKit
import Combine

struct AccessibleForwardSheet: UIViewControllerRepresentable {
    let message: TelegramMessage
    let service: TelegramService
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = AccessibleForwardController(
            message: message,
            service: service,
            onFinish: { dismiss() }
        )
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}

@MainActor
final class AccessibleForwardController: UITableViewController, UISearchResultsUpdating {
    private let message: TelegramMessage
    private let service: TelegramService
    private let onFinish: () -> Void
    private let search = UISearchController(searchResultsController: nil)
    private var subscriptions = Set<AnyCancellable>()
    private var dataSource: UITableViewDiffableDataSource<Int, Int64>!
    private var chats: [Int64: TelegramChat] = [:]
    private var query = ""

    init(message: TelegramMessage, service: TelegramService, onFinish: @escaping () -> Void) {
        self.message = message
        self.service = service
        self.onFinish = onFinish
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) { fatalError("Use init(message:service:onFinish:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "轉寄訊息"
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 58
        tableView.accessibilityLanguage = "zh-TW"
        tableView.register(AccessibleSettingCell.self, forCellReuseIdentifier: "recipient")
        dataSource = UITableViewDiffableDataSource<Int, Int64>(tableView: tableView) {
            [weak self] table, path, id in
            let cell = table.dequeueReusableCell(withIdentifier: "recipient", for: path) as! AccessibleSettingCell
            if let chat = self?.chats[id] {
                cell.display(title: chat.title, detail: "點兩下轉寄訊息給此對話", button: true)
                cell.accessibilityLabel = "轉寄給 \(chat.title)"
                cell.accessibilityHint = "點兩下送出轉寄"
                cell.accessibilityLanguage = "zh-TW"
            }
            return cell
        }

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "取消", style: .plain, target: self, action: #selector(cancel)
        )
        search.searchResultsUpdater = self
        search.searchBar.placeholder = "搜尋要轉寄的對話"
        search.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = search
        definesPresentationContext = true

        service.$chats.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
        refresh()
    }

    @objc private func cancel() { onFinish() }

    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text ?? ""
        refresh()
    }

    private func refresh() {
        let all = service.chats.filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
        }
        chats = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int64>()
        snapshot.appendSections([0])
        snapshot.appendItems(all.map(\.id))
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt path: IndexPath) {
        guard let id = dataSource.itemIdentifier(for: path),
              let chat = chats[id] else { return }
        service.forward(message, to: id)
        onFinish()
        UIAccessibility.post(notification: .announcement,
                             argument: "已要求轉寄給 \(chat.title)")
    }
}
