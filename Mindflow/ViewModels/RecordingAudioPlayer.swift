//
//  RecordingAudioPlayer.swift
//  Mindflow
//

import AVFoundation
import Combine

final class RecordingAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0 {
        didSet {
            guard isScrubbing else {
                return
            }

            audioPlayer?.currentTime = currentTime
        }
    }
    @Published var duration: TimeInterval = 0

    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private var isScrubbing = false

    init(url: URL) {
        super.init()

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            audioPlayer = player
            duration = player.duration
        } catch {
            audioPlayer = nil
        }
    }

    func togglePlayback() {
        guard let audioPlayer else {
            return
        }

        if audioPlayer.isPlaying {
            audioPlayer.pause()
            stopTimer()
            isPlaying = false
        } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
            audioPlayer.play()
            startTimer()
            isPlaying = true
        }
    }

    func setScrubbing(_ editing: Bool) {
        isScrubbing = editing

        guard let audioPlayer else {
            return
        }

        if !editing {
            audioPlayer.currentTime = currentTime
        }
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        currentTime = 0
        isPlaying = false
        stopTimer()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        currentTime = 0
        stopTimer()
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
            guard let self, !self.isScrubbing else {
                return
            }

            self.currentTime = self.audioPlayer?.currentTime ?? 0
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
