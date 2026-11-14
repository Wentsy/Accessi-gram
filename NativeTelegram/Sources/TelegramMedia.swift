import SwiftUI
import AVFoundation
import AVKit
import PhotosUI
import UniformTypeIdentifiers
import CoreImage.CIFilterBuiltins

@MainActor
final class VoiceRecorder: ObservableObject {
    @Published var isRecording = false
    private(set) var lastDuration = 0
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
        lastDuration = max(1, Int(ceil(recorder?.currentTime ?? 0)))
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

// Media, document, voice and video display are handled by AccessibleMediaSheet.swift.
