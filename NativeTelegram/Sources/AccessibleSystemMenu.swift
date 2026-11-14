import UIKit

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

/// Native UIKit action sheets and alerts use the iOS accessibility tree
/// directly. No SwiftUI hosting overlays, hidden table views or nested
/// presentation controllers can swallow VoiceOver focus.
@MainActor
enum AccessibleSystemMenu {
    static func present(title: String,
                        choices: [AccessibleMenuChoice],
                        onSelect: @escaping (String) -> Void) {
        guard let presenter = visibleController() else { return }
        let sheet = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        for choice in choices {
            let style: UIAlertAction.Style = choice.id == "delete" ? .destructive : .default
            sheet.addAction(UIAlertAction(title: choice.title, style: style) { _ in
                onSelect(choice.id)
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX,
                                        y: presenter.view.bounds.midY,
                                        width: 1, height: 1)
        }
        presenter.present(sheet, animated: true) {
            UIAccessibility.post(notification: .screenChanged, argument: sheet.view)
        }
    }

    static func editMessage(initial: String,
                            onSave: @escaping (String) -> Void) {
        guard let presenter = visibleController() else { return }
        let alert = UIAlertController(title: "編輯訊息", message: nil,
                                      preferredStyle: .alert)
        alert.addTextField { input in
            input.text = initial
            input.accessibilityLabel = "編輯訊息文字"
            input.accessibilityHint = "輸入修改後的訊息內容"
            input.accessibilityLanguage = "zh-TW"
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "儲存修改", style: .default) { _ in
            onSave(alert.textFields?.first?.text ?? "")
        })
        presenter.present(alert, animated: true) {
            UIAccessibility.post(notification: .screenChanged,
                                 argument: alert.textFields?.first)
        }
    }

    private static func visibleController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .windows.first(where: \.isKeyWindow)

        var controller = window?.rootViewController
        while true {
            if let presented = controller?.presentedViewController {
                controller = presented
            } else if let navigation = controller as? UINavigationController {
                controller = navigation.visibleViewController
            } else if let tab = controller as? UITabBarController {
                controller = tab.selectedViewController
            } else {
                break
            }
        }
        return controller
    }
}
