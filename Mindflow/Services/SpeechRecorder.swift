//
//  SpeechRecorder.swift
//  Mindflow
//
//  Created by Maverick Tang on 2026/6/14.
//

import AVFoundation
import Combine
import Speech
import SwiftUI

final class SpeechRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var audioLevel: CGFloat = 0.06
    @Published private(set) var transcript = ""
    @Published private(set) var nodes: [SpeechThoughtNode] = []
    @Published private(set) var lastError: String?
    @Published var completedResult: SpeechRecordingResult?

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN"))
    private let recognitionLock = NSLock()
    private let audioWriteLock = NSLock()

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioFile: AVAudioFile?
    private var audioFileURL: URL?
    private var restartTimer: Timer?
    private var recordingStartedAt: Date?
    private var committedTranscript = ""
    private var partialTranscript = ""
    private var smoothedLevel: CGFloat = 0.06
    private var recognitionGeneration = 0

    func toggleRecording() async {
        if isRecording {
            stopRecording(produceResult: true)
        } else {
            await startRecording()
        }
    }

    func markNode() -> SpeechThoughtNode? {
        guard isRecording else {
            return nil
        }

        let elapsed = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let source = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let excerpt = source.isEmpty ? "" : String(source.suffix(42))
        let node = SpeechThoughtNode(timestamp: elapsed, excerpt: excerpt)
        nodes.append(node)
        return node
    }

    private func startRecording() async {
        guard !isRecording else {
            return
        }

        lastError = nil
        completedResult = nil

        guard await requestPermissions() else {
            lastError = "需要麦克风和语音识别权限。"
            return
        }

        do {
            try configureAudioSession()
            try startAudioEngine()

            guard startRecognitionTask() else {
                throw SpeechRecorderError.recognitionUnavailable
            }

            recordingStartedAt = Date()
            committedTranscript = ""
            partialTranscript = ""
            transcript = ""
            nodes = []
            isRecording = true
            scheduleRecognitionRollover()
        } catch {
            lastError = error.localizedDescription
            stopRecording(produceResult: false)
        }
    }

    private func stopRecording(produceResult: Bool) {
        guard isRecording || audioEngine.isRunning else {
            return
        }

        isRecording = false
        restartTimer?.invalidate()
        restartTimer = nil
        commitPartialTranscript()

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionLock.lock()
        let request = recognitionRequest
        recognitionRequest = nil
        recognitionLock.unlock()

        request?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil

        closeAudioFile()

        if produceResult, let audioFileURL {
            completedResult = SpeechRecordingResult(
                audioURL: audioFileURL,
                transcript: transcript.trimmingCharacters(in: .whitespacesAndNewlines),
                nodes: nodes,
                duration: recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0,
                createdAt: Date()
            )
        }

        audioFileURL = nil
        recordingStartedAt = nil

        withAnimation(.easeOut(duration: 0.28)) {
            audioLevel = 0.06
        }

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestPermissions() async -> Bool {
        let microphoneGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        return microphoneGranted && speechStatus == .authorized
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()

        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.mixWithOthers, .allowBluetoothHFP, .allowBluetoothA2DP]
        )
        try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try session.setActive(true, options: [])
    }

    private func startAudioEngine() throws {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        try openAudioFile(format: recordingFormat)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.handleAudioBuffer(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    private func startRecognitionTask() -> Bool {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            lastError = "当前语音识别服务不可用。"
            return false
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        
        // [新增] 自动推断并添加标点符号 (逗号、句号等)
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }

        recognitionLock.lock()
        recognitionRequest = request
        recognitionLock.unlock()

        recognitionGeneration += 1
        let generation = recognitionGeneration

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else {
                return
            }

            DispatchQueue.main.async {
                guard self.isRecording, generation == self.recognitionGeneration else {
                    return
                }

                if let result {
                    self.partialTranscript = result.bestTranscription.formattedString
                    self.transcript = Self.joinTranscript(self.committedTranscript, self.partialTranscript)

                    if result.isFinal {
                        self.commitPartialTranscript()
                        self.rollRecognitionTask()
                    }
                }

                if let error {
                    self.lastError = error.localizedDescription
                    self.rollRecognitionTask()
                }
            }
        }

        return true
    }

    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionLock.lock()
        let request = recognitionRequest
        recognitionLock.unlock()

        writeAudioBuffer(buffer)
        request?.append(buffer)
        publishAudioLevel(from: buffer)
    }

    private func publishAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else {
            return
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else {
            return
        }

        var sum: Float = 0
        for index in 0..<frameLength {
            let sample = channelData[index]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frameLength))
        let averagePower = 20 * log10(max(rms, 0.000_01))
        let normalized = CGFloat((averagePower + 58) / 58).clamped(to: 0...1)
        let shaped = pow(normalized, 0.72)

        DispatchQueue.main.async {
            self.smoothedLevel = self.smoothedLevel * 0.68 + shaped * 0.32

            withAnimation(.easeInOut(duration: 0.12)) {
                self.audioLevel = self.smoothedLevel
            }
        }
    }

    private func scheduleRecognitionRollover() {
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 52, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.rollRecognitionTask()
            }
        }
    }

    private func rollRecognitionTask() {
        guard isRecording else {
            return
        }

        commitPartialTranscript()

        recognitionLock.lock()
        let previousRequest = recognitionRequest
        recognitionRequest = nil
        recognitionLock.unlock()

        previousRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil

        if !startRecognitionTask() {
            stopRecording(produceResult: true)
        }
    }

    private func openAudioFile(format: AVAudioFormat) throws {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory
            .appendingPathComponent("null-set-\(Self.fileTimestamp()).caf")
        let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)

        audioWriteLock.lock()
        audioFileURL = fileURL
        audioFile = file
        audioWriteLock.unlock()
    }

    private func writeAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        audioWriteLock.lock()
        defer {
            audioWriteLock.unlock()
        }

        guard let audioFile else {
            return
        }

        do {
            try audioFile.write(from: buffer)
        } catch {
            DispatchQueue.main.async {
                self.lastError = error.localizedDescription
            }
        }
    }

    private func closeAudioFile() {
        audioWriteLock.lock()
        audioFile = nil
        audioWriteLock.unlock()
    }

    private func commitPartialTranscript() {
        let cleanPartial = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPartial.isEmpty else {
            return
        }

        committedTranscript = Self.joinTranscript(committedTranscript, cleanPartial)
        partialTranscript = ""
        transcript = committedTranscript
    }

    private static func joinTranscript(_ first: String, _ second: String) -> String {
        let cleanFirst = first.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSecond = second.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleanFirst.isEmpty {
            return cleanSecond
        }

        if cleanSecond.isEmpty {
            return cleanFirst
        }

        return "\(cleanFirst)\n\(cleanSecond)"
    }

    private static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: Date())
    }
}

private enum SpeechRecorderError: LocalizedError {
    case recognitionUnavailable

    var errorDescription: String? {
        "当前语音识别服务不可用。"
    }
}

struct SpeechThoughtNode: Identifiable, Equatable {
    let id = UUID()
    let timestamp: TimeInterval
    let excerpt: String
}

struct SpeechRecordingResult: Identifiable, Equatable {
    let id = UUID()
    let audioURL: URL
    let transcript: String
    let nodes: [SpeechThoughtNode]
    let duration: TimeInterval
    let createdAt: Date
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
