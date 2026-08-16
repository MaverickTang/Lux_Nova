//
//  ContentView.swift
//  Mindflow
//

import SwiftUI
import UIKit
import Combine

struct ContentView: View {
    @StateObject private var recorder = SpeechRecorder()
    @State private var compression = false
    @State private var expandGlow = false

    @State private var showThoughtGraph = false
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var generatedGraphJSON = ""

    @State private var recordingDuration: TimeInterval = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let background = Color.black

    var body: some View {
        GeometryReader { geometry in
            let safeArea = geometry.safeAreaInsets

            ZStack {
                background.ignoresSafeArea()

                AmbientNoise()
                    .opacity(0.12)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    recordButton(width: geometry.size.width)
                    recordingStatus
                }

                bottomNavigation(safeArea: safeArea)
            }
        }
        .onReceive(timer) { _ in
            if recorder.isRecording {
                recordingDuration += 1
            }
        }
        .onChange(of: recorder.isRecording) { _, isRecording in
            if !isRecording {
                recordingDuration = 0
            }
        }
        .fullScreenCover(item: $recorder.completedResult) { result in
                RecordingResultView(result: result, background: background) { jsonString, transcript in
                        // 【修改】获取音频文件名和时长，一并保存
//                        let fileName = result.audioURL.lastPathComponent
//                        HistoryManager.shared.saveThought(
//                            transcript: transcript,
//                            graphJSON: jsonString,
//                            audioFileName: fileName,
//                            duration: result.duration
//                        )
                        self.generatedGraphJSON = jsonString
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            self.showThoughtGraph = true
                    }
                }
            }
//        .fullScreenCover(item: $recorder.completedResult) { result in
//            RecordingResultView(result: result, background: background) { jsonString, transcript in
//                HistoryManager.shared.saveThought(transcript: transcript, graphJSON: jsonString)
//                generatedGraphJSON = jsonString
//
//                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
//                    showThoughtGraph = true
//                }
//            }
//        }
//        .sheet(isPresented: $showThoughtGraph) {
//            ThoughtGraphView(jsonString: generatedGraphJSON)
//        }
        // 在 ContentView.swift 中修改此处：
        .sheet(isPresented: $showThoughtGraph) {
            ThoughtGraphView(jsonString: generatedGraphJSON, transcript: "") {
                // 点击“继续记录”时，直接拉起录音
            toggleRecording()
            }
            // 【新增这行】防止主界面的缓存问题
            .id(generatedGraphJSON)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showHistory) {
            HistoryView()
        }
    }

    private func recordButton(width: CGFloat) -> some View {
        Button(action: toggleRecording) {
            TDParticleSphere(
                isRecording: recorder.isRecording,
                audioLevel: recorder.audioLevel,
                compression: compression,
                expandGlow: expandGlow
            )
            .frame(width: width, height: width)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var recordingStatus: some View {
        ZStack {
            if recorder.isRecording {
                Text(timeString(recordingDuration))
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.9))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text("点击开始记录")
                    .font(.system(size: 14, weight: .light, design: .serif))
                    .foregroundColor(Color.white.opacity(0.6))
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: recorder.isRecording)
    }

    private func bottomNavigation(safeArea: EdgeInsets) -> some View {
        VStack {
            Spacer()

            HStack(alignment: .bottom) {
                Button(action: { showHistory = true }) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 20, weight: .light))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(16)
                        .contentShape(Rectangle())
                }

                Spacer()

                Button(action: { showSettings = true }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 20, weight: .light))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(16)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, max(16, safeArea.bottom))
        }
    }

    private func toggleRecording() {
        crispTap(intensity: recorder.isRecording ? 0.45 : 0.72)

        Task {
            await recorder.toggleRecording()
        }
    }

    private func crispTap(intensity: CGFloat, sharpness: CGFloat = 0.95) {
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred(intensity: intensity)

        if sharpness > 0.96 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.045) {
                let secondTap = UIImpactFeedbackGenerator(style: .light)
                secondTap.prepare()
                secondTap.impactOccurred(intensity: 0.35)
            }
        }
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
