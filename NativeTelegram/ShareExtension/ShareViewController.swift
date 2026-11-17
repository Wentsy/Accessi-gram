import UIKit
import Social
import UniformTypeIdentifiers
import ImageIO

private enum ShareImportError: LocalizedError {
    case imageUnavailable(String)
    case invalidFile

    var errorDescription: String? {
        switch self {
        case .imageUnavailable(let types): return "截圖圖片無法讀取。提供的圖片型態：\(types)。請將這段錯誤提供給開發者。"
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

    override func isContentValid() -> Bool {
        guard recipient != nil else { return false }
        let hasAttachments = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .contains { !($0.attachments ?? []).isEmpty }
        return hasAttachments || !(contentText ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        validateContent()
    }

    override func configurationItems() -> [Any]! {
        let item = SLComposeSheetConfigurationItem()!
        item.title = "接收對象"
        item.value = recipient?.title ?? "點兩下選擇聯絡人、群組或頻道"
        item.tapHandler = { [weak self] in
            guard let self else { return }
            self.pushConfigurationViewController(ShareRecipientPicker(sender: self.directSender) { [weak self] chosen in
                guard let self else { return }
                self.recipient = chosen
                self.reloadConfigurationItems()
                self.popConfigurationViewController()
                self.validateContent()
            })
        }
        return [item]
    }

    /// A screenshot shared directly from the iOS editor often registers
    /// public.image and returns UIImage from loadItem, not PNG Data or a file.
    /// Request exact registered identifiers in order instead of assuming that
    /// a conforming public.png representation actually exists.
    private func loadScreenshot(_ provider: NSItemProvider, draftID: String,
                                completion: @escaping (Result<ShareAttachment, Error>) -> Void) {
        var types = provider.registeredTypeIdentifiers.filter { identifier in
            identifier == UTType.image.identifier
                || UTType(identifier)?.conforms(to: .image) == true
        }
        if types.isEmpty {
            types = provider.registeredTypeIdentifiers.filter {
                $0 != UTType.fileURL.identifier
                    && $0 != UTType.url.identifier
                    && $0 != UTType.plainText.identifier
            }
        }
        if !types.contains(UTType.image.identifier) {
            types.append(UTType.image.identifier)
        }

        // True means we have already called completion; false means that
        // representation was unavailable and the next one should be tried.
        func stageData(_ bytes: Data) -> Bool {
            guard !bytes.isEmpty, let image = UIImage(data: bytes) else { return false }
            let source = CGImageSourceCreateWithData(bytes as CFData, nil)
            let imageUTI = source.flatMap { CGImageSourceGetType($0) }
            let actualType: UTType? = imageUTI.flatMap { UTType($0 as String) }
            let name: String
            let content: Data
            if actualType?.conforms(to: .png) == true {
                name = "截圖.png"
                content = bytes
            } else if actualType?.conforms(to: .jpeg) == true {
                name = "分享圖片.jpg"
                content = bytes
            } else if actualType?.conforms(to: .heic) == true {
                name = "分享圖片.heic"
                content = bytes
            } else if actualType?.conforms(to: .webP) == true {
                name = "分享圖片.webp"
                content = bytes
            } else if let png = image.pngData() {
                name = "截圖.png"
                content = png
            } else {
                return false
            }
            do {
                let temporary = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: temporary,
                                                        withIntermediateDirectories: true)
                let file = temporary.appendingPathComponent(name)
                try content.write(to: file, options: .atomic)
                let attachment = try ShareMailbox.stageFile(file, name: name, id: draftID)
                try FileManager.default.removeItem(at: temporary)
                completion(.success(attachment))
            } catch {
                completion(.failure(error))
            }
            return true
        }

        func stageURL(_ url: URL) -> Bool {
            guard url.isFileURL else { return false }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return false }
            return stageData(data)
        }

        func nextType(_ index: Int) {
            if index >= types.count {
                // Some screenshot providers only vend UIImage through their
                // object registration, with no NSData or file representation.
                if provider.canLoadObject(ofClass: UIImage.self) {
                    _ = provider.loadObject(ofClass: UIImage.self) { object, _ in
                        if let image = object as? UIImage,
                           let data = image.pngData(), stageData(data) {
                            return
                        }
                        completion(.failure(ShareImportError.imageUnavailable(
                            provider.registeredTypeIdentifiers.joined(separator: ", ")
                        )))
                    }
                } else {
                    completion(.failure(ShareImportError.imageUnavailable(
                        provider.registeredTypeIdentifiers.joined(separator: ", ")
                    )))
                }
                return
            }
            let type = types[index]
            // loadItem handles UIImage from the screenshot editor directly.
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                if let image = item as? UIImage,
                   let data = image.pngData(), stageData(data) {
                    return
                }
                if let data = item as? Data, stageData(data) {
                    return
                }
                if let url = item as? URL, stageURL(url) {
                    return
                }
                if let path = item as? String,
                   let url = URL(string: path), stageURL(url) {
                    return
                }
                _ = provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                    if let data, stageData(data) { return }
                    _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                        if let url, stageURL(url) { return }
                        nextType(index + 1)
                    }
                }
            }
        }

        nextType(0)
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
