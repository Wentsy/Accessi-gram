import UIKit
import CoreImage.CIFilterBuiltins

/// The Share Extension has its own Telegram account authorization.
/// It does not read the main app's Keychain or TDLib files, so it works with
/// signing services that cannot provision the App Groups entitlement.
@MainActor
final class ShareLoginController: UIViewController {
    private let sender: ExtensionTelegramSender
    private let onAuthorized: () -> Void
    private var completed = false

    private let statusLabel = UILabel()
    private let identifier = UITextField()
    private let apiHash = UITextField()
    private let phone = UITextField()
    private let code = UITextField()
    private let password = UITextField()
    private let email = UITextField()
    private let primary = UIButton(type: .system)
    private let qrButton = UIButton(type: .system)
    private let copyButton = UIButton(type: .system)
    private let qrImage = UIImageView()

    init(sender: ExtensionTelegramSender, onAuthorized: @escaping () -> Void) {
        self.sender = sender
        self.onAuthorized = onAuthorized
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(sender:onAuthorized:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "登入分享功能"
        view.backgroundColor = .systemBackground

        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.isAccessibilityElement = true
        statusLabel.accessibilityLanguage = "zh-TW"

        configure(identifier, label: "Telegram API ID", placeholder: "輸入 API ID")
        identifier.keyboardType = .numberPad
        configure(apiHash, label: "Telegram API Hash", placeholder: "輸入 API Hash")
        apiHash.textContentType = .password
        apiHash.autocorrectionType = .no
        apiHash.autocapitalizationType = .none
        configure(phone, label: "Telegram 手機號碼", placeholder: "+886...")
        phone.keyboardType = .phonePad
        phone.textContentType = .telephoneNumber
        configure(code, label: "Telegram 驗證碼", placeholder: "輸入驗證碼")
        code.keyboardType = .numberPad
        code.textContentType = .oneTimeCode
        configure(password, label: "兩步驟驗證密碼", placeholder: "輸入密碼")
        password.isSecureTextEntry = true
        configure(email, label: "電子郵件或郵件驗證碼", placeholder: "輸入電子郵件或驗證碼")
        email.keyboardType = .emailAddress

        primary.accessibilityLanguage = "zh-TW"
        primary.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        primary.addTarget(self, action: #selector(submit), for: .touchUpInside)
        primary.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true

        qrButton.setTitle("改用其他裝置掃描 QR Code", for: .normal)
        qrButton.accessibilityLabel = "改用 QR Code 登入分享功能"
        qrButton.accessibilityLanguage = "zh-TW"
        qrButton.addTarget(self, action: #selector(startQR), for: .touchUpInside)
        qrButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true

        copyButton.setTitle("複製 QR 授權連結", for: .normal)
        copyButton.accessibilityLanguage = "zh-TW"
        copyButton.addTarget(self, action: #selector(copyQRLink), for: .touchUpInside)
        copyButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true

        qrImage.contentMode = .scaleAspectFit
        qrImage.isAccessibilityElement = true
        qrImage.accessibilityLabel = "Telegram 分享功能登入 QR Code，可用已登入的裝置掃描"
        qrImage.accessibilityLanguage = "zh-TW"
        qrImage.heightAnchor.constraint(equalToConstant: 190).isActive = true

        let stack = UIStackView(arrangedSubviews: [
            statusLabel, identifier, apiHash, phone, code, password,
            email, primary, qrButton, qrImage, copyButton
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .interactive
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -44)
        ])

        sender.onStageChanged = { [weak self] stage in
            self?.render(stage)
        }
        sender.onAuthorizationError = { [weak self] explanation in
            self?.statusLabel.text = "Telegram 登入失敗：\(explanation)"
            self?.statusLabel.accessibilityLabel = self?.statusLabel.text
            UIAccessibility.post(notification: .announcement, argument: self?.statusLabel.text)
        }
        render(sender.stage)
    }

    private func configure(_ field: UITextField, label: String, placeholder: String) {
        field.placeholder = placeholder
        field.accessibilityLabel = label
        field.accessibilityLanguage = "zh-TW"
        field.borderStyle = .roundedRect
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
    }

    private func render(_ stage: ShareSignInStage) {
        for field in [identifier, apiHash, phone, code, password, email] {
            field.isHidden = true
        }
        qrButton.isHidden = true
        qrImage.isHidden = true
        copyButton.isHidden = true
        primary.isHidden = false

        switch stage {
        case .apiCredentials:
            statusLabel.text = "首次使用分享功能，請輸入 Telegram API ID 和 API Hash。OC 可以在打包時預置，就不需要手動填寫。此設定與主 App 登入分開保存。"
            identifier.isHidden = false
            apiHash.isHidden = false
            primary.setTitle("儲存 API 並連線 Telegram", for: .normal)
        case .connecting:
            statusLabel.text = "正在連接 Telegram，讀取分享專用登入狀態"
            primary.isHidden = true
        case .phone:
            statusLabel.text = "第一次從其他 App 分享時，需要在分享視窗登入一次 Telegram；日後不必重新登入。"
            phone.isHidden = false
            qrButton.isHidden = false
            primary.setTitle("取得 Telegram 驗證碼", for: .normal)
        case .code:
            statusLabel.text = "請輸入 Telegram 傳送給你的登入驗證碼"
            code.isHidden = false
            primary.setTitle("驗證並登入", for: .normal)
        case .password:
            statusLabel.text = "請輸入 Telegram 的兩步驟驗證密碼"
            password.isHidden = false
            primary.setTitle("確認密碼", for: .normal)
        case .email:
            statusLabel.text = "Telegram 要求先驗證電子郵件地址"
            email.isHidden = false
            primary.setTitle("繼續", for: .normal)
        case .emailCode:
            statusLabel.text = "請輸入電子郵件收到的 Telegram 驗證碼"
            email.isHidden = false
            primary.setTitle("驗證電子郵件", for: .normal)
        case .qr(let link):
            statusLabel.text = "使用另一台已登入 Telegram 的裝置掃描 QR Code 完成分享登入"
            qrImage.isHidden = false
            copyButton.isHidden = false
            qrImage.image = makeQR(link)
            primary.isHidden = true
        case .ready:
            statusLabel.text = "分享功能已登入，可以直接選擇聊天並傳送"
            primary.isHidden = true
            if !completed {
                completed = true
                sender.onStageChanged = nil
                sender.onAuthorizationError = nil
                navigationController?.popViewController(animated: true)
                onAuthorized()
            }
        }
        statusLabel.accessibilityLabel = statusLabel.text
    }

    @objc private func submit() {
        let stage = sender.stage
        Task { @MainActor in
            do {
                switch stage {
                case .apiCredentials:
                    try await sender.saveAPI(id: Int(identifier.text ?? "") ?? 0,
                                             hash: apiHash.text ?? "")
                case .phone:
                    try await sender.submitPhone(phone.text ?? "")
                case .code:
                    try await sender.submitCode(code.text ?? "")
                case .password:
                    try await sender.submitPassword(password.text ?? "")
                case .email:
                    try await sender.submitEmail(email.text ?? "")
                case .emailCode:
                    try await sender.submitEmailCode(email.text ?? "")
                default:
                    break
                }
            } catch {
                statusLabel.text = error.localizedDescription
                statusLabel.accessibilityLabel = statusLabel.text
                UIAccessibility.post(notification: .announcement, argument: statusLabel.text)
            }
        }
    }

    @objc private func startQR() {
        Task { @MainActor in
            do {
                try await sender.requestQR()
            } catch {
                statusLabel.text = error.localizedDescription
                UIAccessibility.post(notification: .announcement, argument: statusLabel.text)
            }
        }
    }

    @objc private func copyQRLink() {
        if case let .qr(link) = sender.stage {
            UIPasteboard.general.string = link
            UIAccessibility.post(notification: .announcement, argument: "已複製 Telegram 授權連結")
        }
    }

    private func makeQR(_ link: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(link.utf8)
        let context = CIContext()
        guard let output = filter.outputImage else { return nil }
        let enlarged = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let image = context.createCGImage(enlarged, from: enlarged.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}
