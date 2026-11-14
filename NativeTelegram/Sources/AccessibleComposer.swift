import SwiftUI
import UIKit

/// Native UIKit composer. A real UITextView retains iOS VoiceOver's typing,
/// character / word rotor and Chinese text editing behaviors.
struct AccessibleComposer: UIViewRepresentable {
    @Binding var text: String
    let isRecording: Bool
    let onPhotos: () -> Void
    let onFiles: () -> Void
    let onAction: () -> Void
    let onCancelRecording: () -> Void

    func makeUIView(context: Context) -> ComposerBarView {
        ComposerBarView()
    }

    func updateUIView(_ view: ComposerBarView, context: Context) {
        view.onTextChanged = { value in
            if text != value { text = value }
        }
        view.onPhotos = onPhotos
        view.onFiles = onFiles
        view.onAction = onAction
        view.onCancelRecording = onCancelRecording
        view.configure(text: text, recording: isRecording)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ComposerBarView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 375, height: 64)
    }
}

final class ComposerBarView: UIView, UITextViewDelegate {
    static weak var active: ComposerBarView?

    func focusFirstAttachment() {
        UIAccessibility.post(notification: .layoutChanged, argument: photo)
    }

    var onTextChanged: ((String) -> Void)?
    var onPhotos: (() -> Void)?
    var onFiles: (() -> Void)?
    var onAction: (() -> Void)?
    var onCancelRecording: (() -> Void)?

    private let photo = UIButton(type: .system)
    private let files = UIButton(type: .system)
    private let editor = UITextView()
    private let placeholder = UILabel()
    private let action = UIButton(type: .system)
    private let cancel = UIButton(type: .system)
    private let row = UIStackView()
    private var recording = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        ComposerBarView.active = self
        isAccessibilityElement = false
        backgroundColor = .secondarySystemBackground

        photo.setImage(UIImage(systemName: "photo.on.rectangle"), for: .normal)
        files.setImage(UIImage(systemName: "paperclip"), for: .normal)
        cancel.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        photo.accessibilityLabel = "傳送照片或影片"
        photo.accessibilityHint = "點兩下選擇相簿中的照片或影片"
        files.accessibilityLabel = "傳送檔案或附件"
        files.accessibilityHint = "點兩下從檔案 App 選擇附件"
        cancel.accessibilityLabel = "取消錄音"
        cancel.accessibilityHint = "放棄這段語音，不會傳送"
        for button in [photo, files, action, cancel] {
            button.accessibilityLanguage = "zh-TW"
            button.isAccessibilityElement = true
            button.accessibilityTraits = .button
            button.tintColor = .systemBlue
            button.titleLabel?.font = .preferredFont(forTextStyle: .body)
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        }

        editor.delegate = self
        editor.backgroundColor = .systemBackground
        editor.layer.cornerRadius = 10
        editor.layer.borderWidth = 0.5
        editor.layer.borderColor = UIColor.separator.cgColor
        editor.font = .preferredFont(forTextStyle: .body)
        editor.adjustsFontForContentSizeCategory = true
        editor.autocorrectionType = .yes
        editor.textContainerInset = UIEdgeInsets(top: 9, left: 6, bottom: 9, right: 6)
        editor.isScrollEnabled = true
        editor.accessibilityLabel = "訊息編輯框"
        editor.accessibilityHint = "點兩下開始輸入聊天訊息，輸入完成後移至傳送按鈕"
        editor.accessibilityLanguage = "zh-TW"
        editor.isAccessibilityElement = true

        placeholder.text = "輸入訊息"
        placeholder.font = .preferredFont(forTextStyle: .body)
        placeholder.adjustsFontForContentSizeCategory = true
        placeholder.textColor = .placeholderText
        placeholder.isAccessibilityElement = false
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        editor.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.leadingAnchor.constraint(equalTo: editor.leadingAnchor, constant: 12),
            placeholder.topAnchor.constraint(equalTo: editor.topAnchor, constant: 9)
        ])
        editor.heightAnchor.constraint(equalToConstant: 46).isActive = true
        editor.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 6
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        row.isAccessibilityElement = false
        for item in [photo, files, editor, action, cancel] {
            row.addArrangedSubview(item)
        }
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7)
        ])

        photo.addTarget(self, action: #selector(openPhotos), for: .touchUpInside)
        files.addTarget(self, action: #selector(openFiles), for: .touchUpInside)
        action.addTarget(self, action: #selector(performAction), for: .touchUpInside)
        cancel.addTarget(self, action: #selector(cancelRecording), for: .touchUpInside)
        configure(text: "", recording: false)
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func configure(text: String, recording: Bool) {
        if editor.text != text { editor.text = text }
        placeholder.isHidden = !text.isEmpty
        self.recording = recording

        if recording {
            action.setImage(UIImage(systemName: "stop.circle.fill"), for: .normal)
            action.accessibilityLabel = "停止錄音並傳送語音訊息"
            action.accessibilityHint = "點兩下結束錄音並將語音送給對方"
        } else if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            action.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
            action.accessibilityLabel = "傳送文字訊息"
            action.accessibilityHint = "點兩下送出編輯框內的文字"
        } else {
            action.setImage(UIImage(systemName: "mic.fill"), for: .normal)
            action.accessibilityLabel = "開始錄製語音訊息"
            action.accessibilityHint = "點兩下開始錄音，之後可停止並傳送或取消"
        }

        cancel.isHidden = !recording
        editor.isEditable = !recording
        editor.accessibilityHint = recording
            ? "正在錄音，請使用停止並傳送或取消錄音按鈕"
            : "點兩下開始輸入聊天訊息，輸入完成後移至傳送按鈕"
        accessibilityElements = recording
            ? [photo, files, editor, action, cancel]
            : [photo, files, editor, action]
    }

    func textViewDidChange(_ textView: UITextView) {
        placeholder.isHidden = !textView.text.isEmpty
        onTextChanged?(textView.text)
    }

    @objc private func openPhotos() { onPhotos?() }
    @objc private func openFiles() { onFiles?() }
    @objc private func performAction() {
        // Only starting a voice note dismisses the keyboard. Sending text
        // deliberately retains focus so consecutive text messages are easy.
        if !recording && editor.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            editor.resignFirstResponder()
        }
        onAction?()
    }
    @objc private func cancelRecording() { onCancelRecording?() }
}


struct AccessibleReplyBanner: UIViewRepresentable {
    let sender: String
    let content: String
    let onCancel: () -> Void

    func makeUIView(context: Context) -> ReplyBannerView { ReplyBannerView() }

    func updateUIView(_ view: ReplyBannerView, context: Context) {
        view.configure(sender: sender, content: content, onCancel: onCancel)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ReplyBannerView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 375, height: 48)
    }
}

final class ReplyBannerView: UIView {
    private let label = UILabel()
    private let cancel = UIButton(type: .system)
    private var onCancel: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        backgroundColor = .secondarySystemBackground
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.isAccessibilityElement = true
        label.accessibilityLanguage = "zh-TW"
        cancel.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        cancel.accessibilityLabel = "取消回覆"
        cancel.accessibilityLanguage = "zh-TW"
        cancel.accessibilityTraits = .button
        cancel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [label, cancel])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        accessibilityElements = [label, cancel]
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func configure(sender: String, content: String, onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
        label.text = "回覆 \(sender)：\(content)"
        label.accessibilityLabel = "正在回覆 \(sender)，\(content)"
    }

    @objc private func cancelTapped() { onCancel?() }
}
