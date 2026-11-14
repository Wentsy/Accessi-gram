import UIKit
import SwiftUI

struct AccessibleMenuChoice: Identifiable {
    let id: String
    let title: String
    let detail: String

    init(_ id: String, _ title: String, _ detail: String = "") {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

/// Replaces SwiftUI confirmationDialog's occasionally silent text and
/// nested focus elements with native one-row-per-action UITableView.
struct AccessibleChoiceSheet: UIViewControllerRepresentable {
    let title: String
    let choices: [AccessibleMenuChoice]
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = AccessibleChoiceController(title: title, choices: choices) { id in
            dismiss()
            onSelect(id)
        }
        let navigation = UINavigationController(rootViewController: controller)
        return navigation
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}

@MainActor
final class AccessibleChoiceController: UITableViewController {
    private let options: [AccessibleMenuChoice]
    private let onSelect: (String) -> Void

    init(title: String, choices: [AccessibleMenuChoice],
         onSelect: @escaping (String) -> Void) {
        self.options = choices
        self.onSelect = onSelect
        super.init(style: .insetGrouped)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError("Use init(title:choices:onSelect:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(AccessibleSettingCell.self, forCellReuseIdentifier: "choice")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 58
        tableView.accessibilityLanguage = "zh-TW"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "關閉", style: .plain, target: self, action: #selector(cancel)
        )
        navigationItem.leftBarButtonItem?.accessibilityLabel = "關閉選單"
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        options.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt path: IndexPath) -> UITableViewCell {
        let option = options[path.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "choice", for: path) as! AccessibleSettingCell
        cell.display(title: option.title, detail: option.detail, button: true)
        cell.accessibilityLanguage = "zh-TW"
        cell.accessibilityHint = "點兩下執行 \(option.title)"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt path: IndexPath) {
        onSelect(options[path.row].id)
    }
}
