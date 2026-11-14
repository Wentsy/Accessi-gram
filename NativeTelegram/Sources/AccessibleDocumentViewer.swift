import UIKit
import SwiftUI
import QuickLook

struct AccessibleDocumentViewer: UIViewControllerRepresentable {
    let url: URL
    let description: String

    func makeUIViewController(context: Context) -> NativeDocumentViewer {
        let controller = NativeDocumentViewer()
        controller.configure(url: url, description: description)
        return controller
    }

    func updateUIViewController(_ controller: NativeDocumentViewer, context: Context) {}
}

@MainActor
final class NativeDocumentViewer: UIViewController, QLPreviewControllerDataSource {
    private var fileURL: URL?
    private var text = ""
    private let nameLabel = UILabel()
    private let previewButton = UIButton(type: .system)
    private let shareButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        nameLabel.numberOfLines = 0
        nameLabel.textAlignment = .center
        nameLabel.font = .preferredFont(forTextStyle: .body)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.isAccessibilityElement = true
        nameLabel.accessibilityLanguage = "zh-TW"
        previewButton.setTitle("預覽檔案", for: .normal)
        previewButton.accessibilityLabel = "預覽檔案"
        previewButton.accessibilityHint = "點兩下使用 iOS Quick Look 檢視文件"
        shareButton.setTitle("使用其他 App 開啟或分享", for: .normal)
        shareButton.accessibilityLabel = "使用其他 App 開啟或分享檔案"
        shareButton.accessibilityHint = "點兩下開啟 iOS 分享選單"

        for button in [previewButton, shareButton] {
            button.accessibilityLanguage = "zh-TW"
            button.accessibilityTraits = .button
            button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        }
        previewButton.addTarget(self, action: #selector(preview), for: .touchUpInside)
        shareButton.addTarget(self, action: #selector(share), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [nameLabel, previewButton, shareButton])
        stack.axis = .vertical
        stack.spacing = 22
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
        ])
        nameLabel.text = text
        nameLabel.accessibilityLabel = text
    }

    func configure(url: URL, description: String) {
        fileURL = url
        text = description.isEmpty ? url.lastPathComponent : description
        if isViewLoaded {
            nameLabel.text = text
            nameLabel.accessibilityLabel = text
        }
    }

    @objc private func preview() {
        let viewer = QLPreviewController()
        viewer.dataSource = self
        present(viewer, animated: true)
    }

    @objc private func share() {
        guard let fileURL else { return }
        let sheet = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = shareButton
            popover.sourceRect = shareButton.bounds
        }
        present(sheet, animated: true)
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        fileURL! as NSURL
    }
}
