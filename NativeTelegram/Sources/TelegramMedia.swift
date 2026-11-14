import SwiftUI
import AVFoundation
import AVKit
import PhotosUI
import UniformTypeIdentifiers
import CoreImage.CIFilterBuiltins

@MainActor
final class VoiceRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var isPlaying = false
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var recordingURL: URL?

    func start() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            guard granted else {
                Task { @MainActor in
                    UIAccessibility.post(notification: .announcement, argument: "請允許使用麥克風")
                }
                return
            }
            Task { @MainActor in self.beginRecording() }
        }
    }

    private func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        try! session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try! session.setActive(true)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
        recorder = try! AVAudioRecorder(url: url, settings: [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ])
        recorder?.record()
        recordingURL = url
        isRecording = true
        UIAccessibility.post(notification: .announcement, argument: "開始錄音，按停止並傳送完成語音訊息")
    }

    func stop() -> URL? {
        recorder?.stop()
        recorder = nil
        isRecording = false
        UIAccessibility.post(notification: .announcement, argument: "錄音已結束")
        return recordingURL
    }

    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil
        isRecording = false
        UIAccessibility.post(notification: .announcement, argument: "已取消錄音")
    }

    func play(_ url: URL) {
        try! AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try! AVAudioSession.sharedInstance().setActive(true)
        player = try! AVAudioPlayer(contentsOf: url)
        player?.play()
        isPlaying = true
        UIAccessibility.post(notification: .announcement, argument: "播放音訊")
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }
}

struct ImportedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { file in
            let target = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
            try FileManager.default.copyItem(at: file.file, to: target)
            return ImportedMovie(url: target)
        }
    }
}

struct QRCodeView: View {
    let content: String
    var body: some View {
        if let image = makeQR(content) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 240, height: 240)
                .accessibilityLabel("Telegram 登入 QR Code，使用另一台已登入裝置掃描")
                .accessibilityAddTraits(.isImage)
        }
    }

    private func makeQR(_ content: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        let context = CIContext()
        guard let output = filter.outputImage,
              let cgImage = context.createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct MediaViewer: View {
    let message: TelegramMessage
    let service: TelegramService
    @ObservedObject var recorder: VoiceRecorder
    @Environment(\.dismiss) private var dismiss
    @State private var localURL: URL?

    var body: some View {
        NavigationStack {
            Group {
                if let localURL {
                    switch message.fileKind {
                    case "photo":
                        if let image = UIImage(contentsOfFile: localURL.path) {
                            AccessiblePhotoPreview(image: image, description: message.body)
                                .accessibilityHidden(false)
                        } else {
                            Text("無法開啟照片")
                        }
                    case "video":
                        AccessibleVideoPlayer(url: localURL)
                    case "voice", "audio":
                        AccessibleAudioPlayback(
                            description: message.body,
                            url: localURL,
                            recorder: recorder
                        )
                    default:
                        VStack {
                            Text(message.body)
                            ShareLink(item: localURL) { Label("開啟或分享檔案", systemImage: "square.and.arrow.up") }
                        }
                    }
                } else {
                    ProgressView("下載附件中")
                        .accessibilityLabel("正在下載附件")
                }
            }
            .navigationTitle("附件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("關閉") { dismiss() } }
                if let localURL {
                    ToolbarItem(placement: .bottomBar) { ShareLink(item: localURL) { Text("分享附件") } }
                }
            }
            .task {
                service.download(message.fileID) { url in
                    localURL = url
                    UIAccessibility.post(notification: .announcement,
                                         argument: url == nil ? "附件下載失敗" : "附件已準備好")
                }
            }
        }
    }
}


struct AccessiblePhotoPreview: UIViewRepresentable {
    let image: UIImage
    let description: String

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.isAccessibilityElement = true
        view.accessibilityTraits = .image
        view.accessibilityLanguage = "zh-TW"
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        view.image = image
        view.accessibilityLabel = "照片，\(description)"
    }
}

/// Native playback button and metadata for predictable VoiceOver focus.
struct AccessibleAudioPlayback: UIViewRepresentable {
    let description: String
    let url: URL
    @ObservedObject var recorder: VoiceRecorder

    func makeUIView(context: Context) -> NativeAudioPlaybackView {
        NativeAudioPlaybackView()
    }

    func updateUIView(_ view: NativeAudioPlaybackView, context: Context) {
        view.configure(description: description, isPlaying: recorder.isPlaying) {
            if recorder.isPlaying {
                recorder.pause()
            } else {
                recorder.play(url)
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize,
                      uiView: NativeAudioPlaybackView,
                      context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 375, height: 112)
    }
}

final class NativeAudioPlaybackView: UIView {
    private let titleLabel = UILabel()
    private let playButton = UIButton(type: .system)
    private var onToggle: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.accessibilityLanguage = "zh-TW"
        titleLabel.isAccessibilityElement = true
        playButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        playButton.accessibilityLanguage = "zh-TW"
        playButton.accessibilityTraits = .button
        playButton.addTarget(self, action: #selector(toggle), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, playButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            playButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        accessibilityElements = [titleLabel, playButton]
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func configure(description: String, isPlaying: Bool, onToggle: @escaping () -> Void) {
        titleLabel.text = description
        titleLabel.accessibilityLabel = description
        playButton.setTitle(isPlaying ? "暫停播放" : "播放音訊", for: .normal)
        playButton.accessibilityLabel = isPlaying ? "暫停播放音訊" : "播放音訊"
        playButton.accessibilityHint = isPlaying ? "點兩下暫停" : "點兩下開始播放"
        self.onToggle = onToggle
    }

    @objc private func toggle() { onToggle?() }
}


/// AVKit owns its built-in playback controls and their accessibility labels.
struct AccessibleVideoPlayer: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = AVPlayer(url: url)
        controller.showsPlaybackControls = true
        controller.view.accessibilityLanguage = "zh-TW"
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}
}
