import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// iOS 18 Files document picker. A UIKit coordinator owns the selection
/// callback, avoiding SwiftUI fileImporter silently losing its completion
/// when nested in a UIHostingController inside UINavigationController.
struct AccessibleDocumentPicker: UIViewControllerRepresentable {
    let onSelect: ([URL]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.item], asCopy: true
        )
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .formSheet
        picker.view.accessibilityLanguage = "zh-TW"
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController,
                                context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onSelect: ([URL]) -> Void
        let onCancel: () -> Void

        init(onSelect: @escaping ([URL]) -> Void,
             onCancel: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            UIAccessibility.post(
                notification: .announcement,
                argument: "已選擇 \(urls.count) 個檔案，正在準備傳送"
            )
            onSelect(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
