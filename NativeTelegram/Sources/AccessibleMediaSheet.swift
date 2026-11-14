import SwiftUI
import UIKit
import AVKit

/// A fully UIKit-owned attachment screen. SwiftUI no longer nests media,
/// QuickLook and voice playback controls inside another inaccessible sheet.
struct AccessibleMediaSheet: UIViewControllerRepresentable {
    let message: TelegramMessage
    let service: TelegramService
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UINavigationController {
        let screen = NativeMediaScreen(message: message, service: service) {
            dismiss()
        }
        return UINavigationController(rootViewController: screen)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}

@MainActor
final class NativeMediaScreen: UIViewController {
    private let message: TelegramMessage
    private let service: TelegramService
    private let onClose: () -> Void
    private let status = UILabel()
    private var localURL: URL?

    init(message: TelegramMessage, service: TelegramService,
         onClose: @escaping () -> Void) {
        self.message = message
        self.service = service
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(message:service:onClose:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = message.fileKind == "voice" || message.fileKind == "audio"
            ? "播放語音訊息" : "檢視附件"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "關閉", style: .plain, target: self, action: #selector(close)
        )
        navigationItem.leftBarButtonItem?.accessibilityLabel = "關閉附件視窗"

        status.text = "正在下載附件"
        status.accessibilityLabel = "正在下載附件"
        status.accessibilityLanguage = "zh-TW"
        status.isAccessibilityElement = true
        status.font = .preferredFont(forTextStyle: .body)
        status.textAlignment = .center
        status.numberOfLines = 0
        status.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(status)
        NSLayoutConstraint.activate([
            status.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            status.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            status.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20)
        ])

        service.download(message.fileID) { [weak self] url in
            guard let self else { return }
            if let url {
                self.render(url)
            } else {
                self.status.text = "附件下載失敗"
                self.status.accessibilityLabel = "附件下載失敗"
                UIAccessibility.post(notification: .announcement, argument: "附件下載失敗")
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if localURL == nil {
            UIAccessibility.post(notification: .screenChanged, argument: status)
        }
    }

    private func render(_ url: URL) {
        localURL = url
        status.isHidden = true
        status.isAccessibilityElement = false

        let content: UIViewController
        switch message.fileKind {
        case "voice", "audio":
            let screen = VoicePlayerController()
            screen.configure(url: url, description: message.body)
            content = screen
        case "video":
            let player = AVPlayerViewController()
            player.player = AVPlayer(url: url)
            player.showsPlaybackControls = true
            player.view.accessibilityLanguage = "zh-TW"
            content = player
        case "photo":
            let photo = UIViewController()
            photo.view.backgroundColor = .systemBackground
            let image = UIImageView(image: UIImage(contentsOfFile: url.path))
            image.contentMode = .scaleAspectFit
            image.isAccessibilityElement = true
            image.accessibilityTraits = [.image]
            image.accessibilityLabel = "照片，\(message.body)"
            image.accessibilityLanguage = "zh-TW"
            image.translatesAutoresizingMaskIntoConstraints = false
            photo.view.addSubview(image)
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: photo.view.leadingAnchor),
                image.trailingAnchor.constraint(equalTo: photo.view.trailingAnchor),
                image.topAnchor.constraint(equalTo: photo.view.topAnchor),
                image.bottomAnchor.constraint(equalTo: photo.view.bottomAnchor)
            ])
            content = photo
        default:
            let document = NativeDocumentViewer()
            document.configure(url: url, description: message.body)
            content = document
        }

        addChild(content)
        content.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content.view)
        NSLayoutConstraint.activate([
            content.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            content.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            content.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            content.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        content.didMove(toParent: self)

        let share = UIBarButtonItem(title: "分享", style: .plain,
                                    target: self, action: #selector(share))
        share.accessibilityLabel = "分享或儲存附件"
        navigationItem.rightBarButtonItem = share
        UIAccessibility.post(notification: .screenChanged, argument: content.view)
    }

    @objc private func close() {
        onClose()
    }

    @objc private func share() {
        guard let url = localURL else { return }
        let sheet = UIActivityViewController(activityItems: [url],
                                             applicationActivities: nil)
        if let popover = sheet.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(sheet, animated: true)
    }
}
