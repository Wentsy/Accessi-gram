import UIKit
import AVFoundation
import MediaPlayer
import SwiftUI

/// UIKit playback controls remain individually reachable via VoiceOver, even
/// for Ogg/Opus files downloaded from Telegram.
struct TelegramVoicePlayer: UIViewControllerRepresentable {
    let url: URL
    let description: String

    func makeUIViewController(context: Context) -> VoicePlayerController {
        let player = VoicePlayerController()
        player.configure(url: url, description: description)
        return player
    }

    func updateUIViewController(_ controller: VoicePlayerController, context: Context) {}

    static func dismantleUIViewController(_ controller: VoicePlayerController, coordinator: ()) {
        controller.stop()
    }
}

@MainActor
final class VoicePlayerController: UIViewController, AVAudioPlayerDelegate {
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let elapsed = UILabel()
    private let slider = UISlider()
    private let playButton = UIButton(type: .system)
    private let rateButton = UIButton(type: .system)
    private var player: AVAudioPlayer?
    private var ticker: Timer?
    private var remotePlayTarget: Any?
    private var remotePauseTarget: Any?
    private var remoteToggleTarget: Any?
    private var remoteSeekTarget: Any?
    private var rateIndex = 0
    private let rates: [Float] = [1.0, 1.5, 2.0]

    private var pendingURL: URL?
    private var descriptionText = "語音訊息"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center
        titleLabel.accessibilityLanguage = "zh-TW"

        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.textAlignment = .center
        statusLabel.text = "正在準備語音播放器"
        statusLabel.accessibilityLanguage = "zh-TW"

        elapsed.text = "00:00／00:00"
        elapsed.textAlignment = .center
        elapsed.font = .monospacedDigitSystemFont(ofSize: 17, weight: .regular)
        elapsed.accessibilityLanguage = "zh-TW"

        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.accessibilityLabel = "語音播放進度"
        slider.accessibilityHint = "上下滑動調整播放時間"
        slider.accessibilityLanguage = "zh-TW"
        slider.addTarget(self, action: #selector(seek), for: .valueChanged)

        playButton.setTitle("播放語音訊息", for: .normal)
        playButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        playButton.accessibilityLabel = "播放語音訊息"
        playButton.accessibilityLanguage = "zh-TW"
        playButton.addTarget(self, action: #selector(togglePlay), for: .touchUpInside)
        rateButton.setTitle("播放速度 1 倍", for: .normal)
        rateButton.accessibilityLabel = "播放速度 1 倍"
        rateButton.accessibilityLanguage = "zh-TW"
        rateButton.addTarget(self, action: #selector(nextRate), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            titleLabel, statusLabel, elapsed, slider, playButton, rateButton
        ])
        stack.axis = .vertical
        stack.spacing = 20
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 25),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -25),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            playButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            rateButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        for label in [titleLabel, statusLabel, elapsed] {
            label.isAccessibilityElement = true
            label.accessibilityTraits = .staticText
        }

        if let url = pendingURL { prepare(url) }
    }

    func configure(url: URL, description: String) {
        descriptionText = description
        pendingURL = url
        if isViewLoaded { prepare(url) }
    }

    private func prepare(_ url: URL) {
        titleLabel.text = descriptionText
        titleLabel.accessibilityLabel = descriptionText
        statusLabel.text = "正在準備播放"
        statusLabel.accessibilityLabel = "正在準備播放"

        Task {
            do {
                let playable = try await Task.detached(priority: .userInitiated) {
                    try OggOpusTranscoder.playableURL(for: url)
                }.value
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playback, mode: .default)
                try audioSession.setActive(true)
                let audio = try AVAudioPlayer(contentsOf: playable)
                audio.delegate = self
                audio.enableRate = true
                audio.rate = rates[rateIndex]
                audio.prepareToPlay()
                player = audio
                slider.maximumValue = Float(max(audio.duration, 0.1))
                updateTime()
                audio.play()
                installRemoteControls()
                startTicker()
                updateControls()
            } catch {
                statusLabel.text = "無法播放語音：\(error.localizedDescription)"
                statusLabel.accessibilityLabel = statusLabel.text
                UIAccessibility.post(notification: .announcement, argument: statusLabel.text)
            }
        }
    }

    @objc private func togglePlay() {
        if player?.isPlaying == true { pausePlayback() }
        else { resumePlayback() }
    }

    /// VoiceOver two-finger double-tap (Magic Tap) on the audio player.
    /// Return false while no audio is loaded so other system gestures can work.
    override func accessibilityPerformMagicTap() -> Bool {
        guard player != nil else { return false }
        togglePlay()
        return true
    }

    private func resumePlayback() {
        guard let player else { return }
        if player.currentTime >= player.duration { player.currentTime = 0 }
        player.rate = rates[rateIndex]
        player.play()
        updateControls()
    }

    private func pausePlayback() {
        player?.pause()
        updateControls()
    }

    @objc private func seek() {
        player?.currentTime = TimeInterval(slider.value)
        updateTime()
        updateNowPlaying()
    }

    @objc private func nextRate() {
        rateIndex = (rateIndex + 1) % rates.count
        player?.rate = rates[rateIndex]
        updateNowPlaying()
        rateButton.setTitle("播放速度 \(rates[rateIndex]) 倍", for: .normal)
        rateButton.accessibilityLabel = "播放速度 \(rates[rateIndex]) 倍"
        UIAccessibility.post(notification: .announcement, argument: rateButton.accessibilityLabel)
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.updateTime()
        }
    }

    private func updateTime() {
        guard let audio = player else { return }
        slider.value = Float(audio.currentTime)
        let current = Int(audio.currentTime)
        let total = Int(audio.duration)
        elapsed.text = String(format: "%02d:%02d／%02d:%02d",
                              current / 60, current % 60, total / 60, total % 60)
        elapsed.accessibilityLabel = "已播放 \(current) 秒，共 \(total) 秒"
    }

    private func updateControls() {
        let playing = player?.isPlaying == true
        playButton.setTitle(playing ? "暫停語音" : "播放語音訊息", for: .normal)
        playButton.accessibilityLabel = playing ? "暫停語音" : "播放語音訊息"
        statusLabel.text = playing ? "正在播放" : "已暫停"
        statusLabel.accessibilityLabel = statusLabel.text
        updateNowPlaying()
    }

    private func updateNowPlaying() {
        guard let player else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: descriptionText,
            MPMediaItemPropertyArtist: "Accessi Gram",
            MPMediaItemPropertyPlaybackDuration: player.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying ? Double(rates[rateIndex]) : 0.0
        ]
    }

    private func installRemoteControls() {
        UIApplication.shared.beginReceivingRemoteControlEvents()
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.isEnabled = true
        commands.pauseCommand.isEnabled = true
        commands.togglePlayPauseCommand.isEnabled = true
        commands.changePlaybackPositionCommand.isEnabled = true
        remotePlayTarget = commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resumePlayback() }
            return .success
        }
        remotePauseTarget = commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pausePlayback() }
            return .success
        }
        // Lock-screen VoiceOver Magic Tap is dispatched through the system
        // media command center, not the app's UIViewController responder chain.
        remoteToggleTarget = commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlay() }
            return .success
        }
        remoteSeekTarget = commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in
                self?.player?.currentTime = event.positionTime
                self?.updateTime()
                self?.updateNowPlaying()
            }
            return .success
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        updateControls()
        statusLabel.text = "播放結束"
        statusLabel.accessibilityLabel = "播放結束"
        UIAccessibility.post(notification: .announcement, argument: "語音播放結束")
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        player?.stop()
        player = nil
        UIApplication.shared.endReceivingRemoteControlEvents()
        let commands = MPRemoteCommandCenter.shared()
        if let target = remotePlayTarget { commands.playCommand.removeTarget(target) }
        if let target = remotePauseTarget { commands.pauseCommand.removeTarget(target) }
        if let target = remoteToggleTarget { commands.togglePlayPauseCommand.removeTarget(target) }
        if let target = remoteSeekTarget { commands.changePlaybackPositionCommand.removeTarget(target) }
        remotePlayTarget = nil
        remotePauseTarget = nil
        remoteToggleTarget = nil
        remoteSeekTarget = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stop()
    }
}
