import UIKit
import Social
import UniformTypeIdentifiers

/// A real Share Extension, rather than an URL handler that merely opens the
/// app. The system hosts a caption editor and contact/group picker right here.
final class ShareViewController: SLComposeServiceViewController {
    private var recipient: ShareRecipient?
    private let directSender = ExtensionTelegramSender()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "分享到 Accessi Gram"
        placeholder = "輸入說明文字（選填）"
        textView.accessibilityLabel = "分享說明文字編輯框"
        textView.accessibilityHint = "輸入要和附件一起傳送的說明文字"
        textView.accessibilityLanguage = "zh-TW"
        navigationItem.rightBarButtonItem?.accessibilityLabel = "確認分享"
    }

    override func isContentValid() -> Bool { recipient != nil }

    override func configurationItems() -> [Any]! {
        let item = SLComposeSheetConfigurationItem()!
        item.title = "接收對象"
        item.value = recipient?.title ?? "點兩下選擇聯絡人、群組或頻道"
        item.tapHandler = { [weak self] in
            guard let self else { return }
            self.pushConfigurationViewController(ShareRecipientPicker { [weak self] chosen in
                self?.recipient = chosen
                self?.reloadConfigurationItems()
                self?.popConfigurationViewController()
            })
        }
        return [item]
    }

    override func didSelectPost() {
        guard let recipient else { return }
        let draftID = UUID().uuidString
        let itemProviders = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        let group = DispatchGroup()
        let lock = NSLock()
        var attachments: [ShareAttachment] = []
        var texts: [String] = []
        var errors: [String] = []

        for provider in itemProviders {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) &&
                !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) {
                    item, error in
                    lock.lock()
                    if let url = item as? URL { texts.append(url.absoluteString) }
                    else if let error { errors.append(error.localizedDescription) }
                    lock.unlock()
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) &&
                        !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                _ = provider.loadObject(ofClass: UIImage.self) { image, error in
                    do {
                        let image = image as! UIImage
                        let temporary = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
                        try image.jpegData(compressionQuality: 0.82)!.write(to: temporary)
                        let saved = try ShareMailbox.stageFile(temporary, name: "分享圖片.jpg", id: draftID)
                        lock.lock(); attachments.append(saved); lock.unlock()
                    } catch {
                        lock.lock(); errors.append(error.localizedDescription); lock.unlock()
                    }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) {
                    item, error in
                    do {
                        let url = item as! URL
                        let security = url.startAccessingSecurityScopedResource()
                        defer { if security { url.stopAccessingSecurityScopedResource() } }
                        let saved = try ShareMailbox.stageFile(url, name: url.lastPathComponent, id: draftID)
                        lock.lock(); attachments.append(saved); lock.unlock()
                    } catch {
                        lock.lock(); errors.append(error.localizedDescription); lock.unlock()
                    }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) {
                    item, error in
                    lock.lock()
                    if let content = item as? String { texts.append(content) }
                    else if let data = item as? Data, let content = String(data: data, encoding: .utf8) {
                        texts.append(content)
                    } else if let error { errors.append(error.localizedDescription) }
                    lock.unlock()
                    group.leave()
                }
            } else if let selectedType = provider.registeredTypeIdentifiers.first(where: {
                $0 != UTType.plainText.identifier && $0 != UTType.url.identifier
            }) {
                group.enter()
                provider.loadFileRepresentation(forTypeIdentifier: selectedType) {
                    url, error in
                    do {
                        guard let url else { throw error ?? CocoaError(.fileReadUnknown) }
                        let saved = try ShareMailbox.stageFile(url, name: url.lastPathComponent, id: draftID)
                        lock.lock(); attachments.append(saved); lock.unlock()
                    } catch {
                        lock.lock(); errors.append(error.localizedDescription); lock.unlock()
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            if !errors.isEmpty {
                self.showFailure("讀取分享內容失敗：" + errors.joined(separator: "；"))
                return
            }
            let caption = ([self.contentText ?? ""] + texts)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
            let pending = PendingShare(
                id: draftID, target: recipient, caption: caption, attachments: attachments
            )
            self.sendDirectly(pending)
        }
    }

    private func sendDirectly(_ draft: PendingShare) {
        title = "正在傳送給 \(draft.target.title)"
        navigationItem.prompt = "正在連線 Telegram 並上傳分享內容"
        UIAccessibility.post(notification: .announcement,
                             argument: "正在傳送給 \(draft.target.title)，請保持分享視窗開啟")
        Task { @MainActor in
            do {
                try await directSender.send(draft) { [weak self] status in
                    self?.navigationItem.prompt = status
                }
                ShareMailbox.discardFiles(for: draft)
                navigationItem.prompt = nil
                UIAccessibility.post(notification: .announcement, argument: "Telegram 分享成功")
                extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            } catch {
                navigationItem.prompt = nil
                showFailure(error.localizedDescription) { [weak self] in
                    self?.sendDirectly(draft)
                }
            }
        }
    }

    private func showFailure(_ message: String, retry: (() -> Void)? = nil) {
        let alert = UIAlertController(title: "分享未送出", message: message,
                                      preferredStyle: .alert)
        if let retry {
            alert.addAction(UIAlertAction(title: "重新傳送", style: .default) { _ in retry() })
        }
        alert.addAction(UIAlertAction(title: "返回修改", style: .cancel))
        present(alert, animated: true)
    }
}

/// One VoiceOver element per recipient; search and contact selection work
/// without launching the main application or reaching into its TDLib database.
final class ShareRecipientPicker: UITableViewController, UISearchResultsUpdating {
    private let onSelect: (ShareRecipient) -> Void
    private let all = ShareMailbox.recipients()
    private let search = UISearchController(searchResultsController: nil)
    private var filtered: [ShareRecipient] = []

    init(onSelect: @escaping (ShareRecipient) -> Void) {
        self.onSelect = onSelect
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) { fatalError("Use init(onSelect:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "選擇聯絡人或對話"
        filtered = all
        search.searchBar.placeholder = "搜尋聯絡人或群組"
        search.searchBar.accessibilityLanguage = "zh-TW"
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = search
        definesPresentationContext = true
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "recipient")
        if all.isEmpty {
            let label = UILabel()
            label.text = "尚未同步接收對象。請先開啟 Accessi Gram，讓聊天列表與聯絡人完成同步。"
            label.numberOfLines = 0
            label.textAlignment = .center
            label.isAccessibilityElement = true
            label.accessibilityLabel = label.text
            tableView.backgroundView = label
        }
    }

    func updateSearchResults(for searchController: UISearchController) {
        let query = searchController.searchBar.text ?? ""
        filtered = query.isEmpty ? all :
            all.filter { $0.title.localizedCaseInsensitiveContains(query) }
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filtered.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt path: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "recipient", for: path)
        let entry = filtered[path.row]
        var config = cell.defaultContentConfiguration()
        config.text = entry.title
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        cell.isAccessibilityElement = true
        cell.accessibilityLanguage = "zh-TW"
        cell.accessibilityLabel = "傳送給 \(entry.title)"
        cell.accessibilityTraits = .button
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt path: IndexPath) {
        onSelect(filtered[path.row])
    }
}
