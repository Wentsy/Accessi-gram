import UIKit
import Social
import UniformTypeIdentifiers

private enum ShareImportError: LocalizedError {
    case imageUnavailable
    case invalidFile

    var errorDescription: String? {
        switch self {
        case .imageUnavailable: return "截圖圖片無法讀取，請從截圖預覽重新分享"
        case .invalidFile: return "分享來源沒有提供有效的附件資料"
        }
    }
}

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
            self.pushConfigurationViewController(ShareRecipientPicker(sender: self.directSender) { [weak self] chosen in
                self?.recipient = chosen
                self?.reloadConfigurationItems()
                self?.popConfigurationViewController()
            })
        }
        return [item]
    }

    /// iOS screenshot editor can supply a PNG as Data, UIImage, an ephemeral
    /// file URL, or several representations at once. The older implementation
    /// force-cast the provider result and could terminate the extension before
    /// its failure alert appeared.
    private func loadScreenshot(_ provider: NSItemProvider, draftID: String,
                                completion: @escaping (Result<ShareAttachment, Error>) -> Void) {
        let imageTypes = [UTType.png.identifier, UTType.jpeg.identifier,
                          UTType.heic.identifier, UTType.image.identifier]
        let type = imageTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0) })
            ?? provider.registeredTypeIdentifiers.first(where: {
                UTType($0)?.conforms(to: .image) == true
            }) ?? UTType.image.identifier

        func stage(_ bytes: Data, typeIdentifier: String) {
            do {
                // Keep original PNG bytes for screenshot fidelity and avoid
                // throwing a large full-page screenshot through JPEG encoding.
                let fileType = UTType(typeIdentifier)
                let name: String
                let savedData: Data
                if fileType?.conforms(to: .png) == true {
                    name = "截圖.png"
                    savedData = bytes
                } else if fileType?.conforms(to: .jpeg) == true {
                    name = "分享圖片.jpg"
                    savedData = bytes
                } else if fileType?.conforms(to: .heic) == true {
                    name = "分享圖片.heic"
                    savedData = bytes
                } else if let image = UIImage(data: bytes), let png = image.pngData() {
                    name = "截圖.png"
                    savedData = png
                } else {
                    throw ShareImportError.imageUnavailable
                }
                let temporary = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: temporary,
                                                        withIntermediateDirectories: true)
                let source = temporary.appendingPathComponent(name)
                try savedData.write(to: source, options: .atomic)
                let attachment = try ShareMailbox.stageFile(source, name: name, id: draftID)
                try FileManager.default.removeItem(at: temporary)
                completion(.success(attachment))
            } catch {
                completion(.failure(error))
            }
        }

        func loadAsObject() {
            if provider.canLoadObject(ofClass: UIImage.self) {
                _ = provider.loadObject(ofClass: UIImage.self) { image, error in
                    if let image = image as? UIImage, let png = image.pngData() {
                        stage(png, typeIdentifier: UTType.png.identifier)
                    } else {
                        loadAsItem()
                    }
                }
            } else {
                loadAsItem()
            }
        }

        func loadAsItem() {
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
                if let image = item as? UIImage, let data = image.pngData() {
                    stage(data, typeIdentifier: UTType.png.identifier)
                } else if let data = item as? Data {
                    stage(data, typeIdentifier: type)
                } else if let url = item as? URL, url.isFileURL {
                    do {
                        let attachment = try ShareMailbox.stageFile(
                            url, name: url.lastPathComponent, id: draftID
                        )
                        completion(.success(attachment))
                    } catch {
                        completion(.failure(error))
                    }
                } else {
                    completion(.failure(error ?? ShareImportError.imageUnavailable))
                }
            }
        }

        _ = provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
            if let data, !data.isEmpty {
                stage(data, typeIdentifier: type)
            } else {
                loadAsObject()
            }
        }
    }

    override func didSelectPost() {
        guard let recipient else { return }
        let draftID = UUID().uuidString
        let input = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
        let itemProviders = input.flatMap { $0.attachments ?? [] }
        let group = DispatchGroup()
        let lock = NSLock()
        var attachments: [ShareAttachment] = []
        var texts: [String] = []
        var errors: [String] = []

        for provider in itemProviders {
            group.enter()
            let finished: (Result<ShareAttachment, Error>) -> Void = { result in
                lock.lock()
                switch result {
                case .success(let attachment): attachments.append(attachment)
                case .failure(let error): errors.append(error.localizedDescription)
                }
                lock.unlock()
                group.leave()
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) {
                    item, error in
                    if let url = item as? URL, url.isFileURL {
                        do {
                            let accessed = url.startAccessingSecurityScopedResource()
                            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                            finished(.success(try ShareMailbox.stageFile(
                                url, name: url.lastPathComponent, id: draftID
                            )))
                        } catch {
                            finished(.failure(error))
                        }
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                        // Screenshot preview may advertise fileURL even when it
                        // actually provides a transient in-memory screenshot.
                        self.loadScreenshot(provider, draftID: draftID, completion: finished)
                    } else {
                        finished(.failure(error ?? ShareImportError.invalidFile))
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                self.loadScreenshot(provider, draftID: draftID, completion: finished)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) {
                    item, error in
                    lock.lock()
                    if let url = item as? URL {
                        texts.append(url.absoluteString)
                    } else if let url = item as? String {
                        texts.append(url)
                    } else {
                        errors.append((error ?? ShareImportError.invalidFile).localizedDescription)
                    }
                    lock.unlock()
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) {
                    item, error in
                    lock.lock()
                    if let content = item as? String {
                        texts.append(content)
                    } else if let data = item as? Data,
                              let content = String(data: data, encoding: .utf8) {
                        texts.append(content)
                    } else {
                        errors.append((error ?? ShareImportError.invalidFile).localizedDescription)
                    }
                    lock.unlock()
                    group.leave()
                }
            } else if let selectedType = provider.registeredTypeIdentifiers.first(where: {
                $0 != UTType.plainText.identifier && $0 != UTType.url.identifier
            }) {
                provider.loadFileRepresentation(forTypeIdentifier: selectedType) {
                    url, error in
                    do {
                        guard let url else { throw error ?? ShareImportError.invalidFile }
                        finished(.success(try ShareMailbox.stageFile(
                            url, name: url.lastPathComponent, id: draftID
                        )))
                    } catch {
                        finished(.failure(error))
                    }
                }
            } else {
                finished(.failure(ShareImportError.invalidFile))
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
            guard !attachments.isEmpty || !caption.isEmpty else {
                self.showFailure("沒有取得可傳送的截圖或文字。請保留截圖編輯畫面並重新分享。")
                return
            }
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
@MainActor
final class ShareRecipientPicker: UITableViewController, UISearchResultsUpdating {
    private let onSelect: (ShareRecipient) -> Void
    private let sender: ExtensionTelegramSender
    private var all: [ShareRecipient] = []
    private let search = UISearchController(searchResultsController: nil)
    private var filtered: [ShareRecipient] = []
    private var loadingRecipients = false
    private let status = UILabel()

    init(sender: ExtensionTelegramSender, onSelect: @escaping (ShareRecipient) -> Void) {
        self.sender = sender
        self.onSelect = onSelect
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) { fatalError("Use init(sender:onSelect:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "最近聊天"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "recipient")
        tableView.rowHeight = 55
        tableView.accessibilityLanguage = "zh-TW"
        search.searchBar.placeholder = "搜尋最近的私聊、群組或頻道"
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = search
        definesPresentationContext = true

        status.numberOfLines = 0
        status.textAlignment = .center
        status.text = "正在從 Telegram 取得最近聊天"
        status.accessibilityLabel = status.text
        status.accessibilityLanguage = "zh-TW"
        status.isAccessibilityElement = true

        all = ShareMailbox.recipients()
        refresh()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { @MainActor in
            do {
                try await sender.start()
                if sender.stage == .ready {
                    loadChats()
                } else {
                    openSignIn()
                }
            } catch {
                status.text = "無法連線 Telegram：\(error.localizedDescription)"
                status.accessibilityLabel = status.text
                refresh()
            }
        }
    }

    private func openSignIn() {
        guard navigationController?.topViewController === self else { return }
        let login = ShareLoginController(sender: sender) { [weak self] in
            self?.loadChats()
        }
        navigationController?.pushViewController(login, animated: true)
    }

    private func loadChats() {
        guard !loadingRecipients else { return }
        loadingRecipients = true
        status.text = "正在從 Telegram 取得最近聊天"
        status.accessibilityLabel = status.text
        refresh()
        Task { @MainActor in
            do {
                let latest = try await sender.recentRecipients()
                if !latest.isEmpty { all = latest }
                loadingRecipients = false
                status.text = all.isEmpty ? "目前沒有可選擇的最近聊天" : ""
                status.accessibilityLabel = status.text
                refresh()
                if let first = tableView.cellForRow(at: IndexPath(row: 0, section: 0)) {
                    UIAccessibility.post(notification: .layoutChanged, argument: first)
                }
            } catch {
                loadingRecipients = false
                status.text = all.isEmpty
                    ? "無法讀取 Telegram 最近聊天：\(error.localizedDescription)"
                    : "無法更新最近聊天，顯示先前取得的對話"
                status.accessibilityLabel = status.text
                refresh()
            }
        }
    }

    func updateSearchResults(for searchController: UISearchController) {
        refresh()
    }

    private func refresh() {
        let query = search.searchBar.text ?? ""
        filtered = query.isEmpty ? all :
            all.filter { $0.title.localizedCaseInsensitiveContains(query) }
        tableView.backgroundView = filtered.isEmpty ? status : nil
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
        cell.accessibilityLabel = "分享給 \(entry.title)"
        cell.accessibilityHint = "點兩下選擇此聊天室"
        cell.accessibilityTraits = [.button]
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt path: IndexPath) {
        onSelect(filtered[path.row])
    }
}
