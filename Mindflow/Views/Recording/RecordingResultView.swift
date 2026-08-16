//
//  RecordingResultView.swift
//  Mindflow
//

import SwiftUI
import UIKit

struct RecordingResultView: View {
    let result: SpeechRecordingResult
    let background: Color
    let onGenerate: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var player: RecordingAudioPlayer
    @State private var copied = false
    @State private var editableTranscript: String
    @State private var isGenerating = false
    @State private var errorMessage: String?

    init(result: SpeechRecordingResult, background: Color, onGenerate: @escaping (String, String) -> Void) {
        self.result = result
        self.background = background
        self.onGenerate = onGenerate
        _player = StateObject(wrappedValue: RecordingAudioPlayer(url: result.audioURL))
        _editableTranscript = State(initialValue: result.transcript.isEmpty ? "未识别到文字。" : result.transcript)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            background.ignoresSafeArea()

            AmbientNoise()
                .opacity(0.12)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ResultHeader(onClose: {
                    player.stop()
                    dismiss()
                })
                .padding(.horizontal, 22)
                .padding(.top, 18)

                AudioPlayerPanel(player: player, duration: result.duration)
                    .padding(.horizontal, 24)
                    .padding(.top, 22)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        if !result.nodes.isEmpty {
                            NodeTimeline(nodes: result.nodes, duration: result.duration)
                            NodeList(nodes: result.nodes)
                        }

                        TextField("识别内容", text: $editableTranscript, axis: .vertical)
                            .font(.system(size: 19, weight: .regular, design: .serif))
                            .lineSpacing(9)
                            .foregroundStyle(Color.white.opacity(0.85))
                            .tint(Color(red: 0.1, green: 0.8, blue: 1.0))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 34)
                    .padding(.bottom, 150)
                }
                .onTapGesture {
                    dismissKeyboard()
                }
            }

            // 仅在非 Loading 状态下显示生成按钮和复制按钮
            if !isGenerating {
                generateButton
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                
                CopyTranscriptButton(copied: copied) {
                    UIPasteboard.general.string = editableTranscript
                    crispCopyTap()

                    withAnimation(.spring(response: 0.26, dampingFraction: 0.76)) {
                        copied = true
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                        withAnimation(.easeOut(duration: 0.24)) {
                            copied = false
                        }
                    }
                }
                .padding(.trailing, 22)
                .padding(.bottom, 24)
                .transition(.scale.combined(with: .opacity))
            }
            
            // ============================================
            // 【新增】沉浸式 Loading 全屏涡流遮罩
            // ============================================
            if isGenerating {
                ZStack {
                    // 背景半透明黑遮罩，压暗底层文字
                    Color.black.opacity(0.85)
                        .ignoresSafeArea()
                    
                    // 调用你刚才写好的涡流组件
                    VortexLoadingView()
                        .frame(width: 360, height: 360)
                    
                    // Loading 提示文案，放置在黑洞的正下方
//                    Text("神 经 突 触 连 接 中 ...")
//                        .font(.system(size: 13, weight: .semibold, design: .rounded))
//                        .foregroundColor(Color(red: 0.4, green: 0.7, blue: 1.0))
//                        .shadow(color: Color(red: 0.1, green: 0.8, blue: 1.0), radius: 6)
//                        .offset(y: 130)
                }
                .zIndex(100) // 确保其在最上层
                // 涡流浮现动画
                .transition(.opacity.combined(with: .scale(scale: 1.1)))
            }
        }
        // 给整个 ZStack 加上状态改变的动画，实现丝滑过渡
        .animation(.easeInOut(duration: 0.6), value: isGenerating)
        .onDisappear {
            player.stop()
        }
    }

    private var generateButton: some View {
        VStack {
            Spacer()

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                    .padding(.bottom, 8)
            }

            Button(action: generateGraph) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("生成思维图谱")
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.black)
                .frame(width: 220, height: 50)
                .background(Color(red: 0.1, green: 0.8, blue: 1.0))
                .cornerRadius(25)
                .shadow(color: Color(red: 0.1, green: 0.8, blue: 1.0).opacity(0.5), radius: 12, y: 6)
            }
            // 因为现在只有 !isGenerating 时才会显示此按钮，所以去掉了 isGenerating 的判断
            .disabled(editableTranscript.isEmpty)
            .padding(.bottom, 36)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func generateGraph() {
        dismissKeyboard()
        isGenerating = true
        errorMessage = nil

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        Task {
            do {
                // 【核心修改】直接调用我们刚写好的打包方法
                // 此时黑洞动画正在播放，大模型会在这段时间内同时完成“生成图谱”和“增量连线”
                let fileName = result.audioURL.lastPathComponent
                let jsonResult = try await HistoryManager.shared.processAndSaveNewThought(
                    transcript: editableTranscript,
                    audioFileName: fileName,
                    duration: result.duration
                )

            await MainActor.run {
                isGenerating = false
                    player.stop()
                    onGenerate(jsonResult, editableTranscript)
                    dismiss()
                    }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    errorMessage = "生成失败，请检查网络或 API Key: \(error.localizedDescription)"
                }
            }
        }
    }

    private func crispCopyTap() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.55)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private struct ResultHeader: View {
    let onClose: () -> Void

    var body: some View {
        HStack {
//            Text("∅")
//                .font(.system(size: 27, weight: .light, design: .serif))
//                .foregroundStyle(Color.white.opacity(0.6))

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .light))
                    .frame(width: 38, height: 38)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }
}

private struct AudioPlayerPanel: View {
    @ObservedObject var player: RecordingAudioPlayer
    let duration: TimeInterval

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Button(action: player.togglePlayback) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 42, height: 42)
                        .foregroundStyle(Color.black)
                        .background(Color.white.opacity(0.9), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                VStack(spacing: 9) {
                    Slider(value: $player.currentTime, in: 0...max(player.duration, duration, 0.1)) { editing in
                        player.setScrubbing(editing)
                    }
                    .tint(Color(red: 0.1, green: 0.8, blue: 1.0))

                    HStack {
                        Text(Self.timeString(player.currentTime))
                        Spacer()
                        Text(Self.timeString(max(player.duration, duration)))
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .tracking(0)
                    .foregroundStyle(Color.white.opacity(0.6))
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private static func timeString(_ interval: TimeInterval) -> String {
        guard interval.isFinite else {
            return "0:00"
        }

        let totalSeconds = max(0, Int(interval.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

private struct NodeTimeline: View {
    let nodes: [SpeechThoughtNode]
    let duration: TimeInterval

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let total = max(duration, nodes.map(\.timestamp).max() ?? 1, 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 1)

                ForEach(nodes) { node in
                    Circle()
                        .fill(Color(red: 0.1, green: 0.8, blue: 1.0))
                        .frame(width: 6, height: 6)
                        .shadow(color: Color(red: 0.1, green: 0.8, blue: 1.0).opacity(0.6), radius: 6)
                        .offset(x: max(0, min(width - 6, width * node.timestamp / total)))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 18)
    }
}

private struct NodeList: View {
    let nodes: [SpeechThoughtNode]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(nodes) { node in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle()
                        .fill(Color(red: 0.1, green: 0.8, blue: 1.0))
                        .frame(width: 5, height: 5)

                    Text(timeString(node.timestamp))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .monospacedDigit()

                    Text(node.excerpt.isEmpty ? "节点" : node.excerpt)
                        .font(.system(size: 13, weight: .regular, design: .serif))
                        .lineLimit(2)
                        .foregroundStyle(Color.white.opacity(0.8))
                }
            }
        }
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

private struct CopyTranscriptButton: View {
    let copied: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 15, weight: .regular))
                .frame(width: 46, height: 46)
                .foregroundStyle(Color.white)
                .background(Color.white.opacity(0.15), in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy")
    }
}



////
////  RecordingResultView.swift
////  Mindflow
////
//
//import SwiftUI
//import UIKit
//
//struct RecordingResultView: View {
//    let result: SpeechRecordingResult
//    let background: Color
//    let onGenerate: (String, String) -> Void
//
//    @Environment(\.dismiss) private var dismiss
//    @StateObject private var player: RecordingAudioPlayer
//    @State private var copied = false
//    @State private var editableTranscript: String
//    @State private var isGenerating = false
//    @State private var errorMessage: String?
//
//    init(result: SpeechRecordingResult, background: Color, onGenerate: @escaping (String, String) -> Void) {
//        self.result = result
//        self.background = background
//        self.onGenerate = onGenerate
//        _player = StateObject(wrappedValue: RecordingAudioPlayer(url: result.audioURL))
//        _editableTranscript = State(initialValue: result.transcript.isEmpty ? "未识别到文字。" : result.transcript)
//    }
//
//    var body: some View {
//        ZStack(alignment: .bottomTrailing) {
//            background.ignoresSafeArea()
//
//            AmbientNoise()
//                .opacity(0.12)
//                .ignoresSafeArea()
//
//            VStack(spacing: 0) {
//                ResultHeader(onClose: {
//                    player.stop()
//                    dismiss()
//                })
//                .padding(.horizontal, 22)
//                .padding(.top, 18)
//
//                AudioPlayerPanel(player: player, duration: result.duration)
//                    .padding(.horizontal, 24)
//                    .padding(.top, 22)
//
//                ScrollView(showsIndicators: false) {
//                    VStack(alignment: .leading, spacing: 24) {
//                        if !result.nodes.isEmpty {
//                            NodeTimeline(nodes: result.nodes, duration: result.duration)
//                            NodeList(nodes: result.nodes)
//                        }
//
//                        TextField("识别内容", text: $editableTranscript, axis: .vertical)
//                            .font(.system(size: 19, weight: .regular, design: .serif))
//                            .lineSpacing(9)
//                            .foregroundStyle(Color.white.opacity(0.85))
//                            .tint(Color(red: 0.1, green: 0.8, blue: 1.0))
//                            .frame(maxWidth: .infinity, alignment: .leading)
//                    }
//                    .padding(.horizontal, 28)
//                    .padding(.top, 34)
//                    .padding(.bottom, 150)
//                }
//                .onTapGesture {
//                    dismissKeyboard()
//                }
//            }
//
//            generateButton
//
//            CopyTranscriptButton(copied: copied) {
//                UIPasteboard.general.string = editableTranscript
//                crispCopyTap()
//
//                withAnimation(.spring(response: 0.26, dampingFraction: 0.76)) {
//                    copied = true
//                }
//
//                DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
//                    withAnimation(.easeOut(duration: 0.24)) {
//                        copied = false
//                    }
//                }
//            }
//            .padding(.trailing, 22)
//            .padding(.bottom, 24)
//        }
//        .onDisappear {
//            player.stop()
//        }
//    }
//
//    private var generateButton: some View {
//        VStack {
//            Spacer()
//
//            if let errorMessage {
//                Text(errorMessage)
//                    .font(.system(size: 12))
//                    .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
//                    .padding(.bottom, 8)
//            }
//
//            Button(action: generateGraph) {
//                HStack(spacing: 8) {
//                    if isGenerating {
//                        ProgressView().tint(.black)
//                        Text("神经突触连接中...")
//                    }
//                    else {
//                        Image(systemName: "sparkles")
//                        Text("生成思维图谱")
//                    }
//                }
//                .font(.system(size: 16, weight: .bold, design: .rounded))
//                .foregroundColor(.black)
//                .frame(width: 220, height: 50)
//                .background(Color(red: 0.1, green: 0.8, blue: 1.0))
//                .cornerRadius(25)
//                .shadow(color: Color(red: 0.1, green: 0.8, blue: 1.0).opacity(0.5), radius: 12, y: 6)
//            }
//            .disabled(isGenerating || editableTranscript.isEmpty)
//            .padding(.bottom, 36)
//        }
//        .frame(maxWidth: .infinity, alignment: .center)
//    }
//
//    private func generateGraph() {
//        dismissKeyboard()
//        isGenerating = true
//        errorMessage = nil
//
//        let generator = UIImpactFeedbackGenerator(style: .medium)
//        generator.impactOccurred()
//
//        Task {
//            do {
//                let jsonResult = try await LLMService.shared.generateThoughtGraph(from: editableTranscript)
//
//                await MainActor.run {
//                    isGenerating = false
//                    player.stop()
//                    onGenerate(jsonResult, editableTranscript)
//                    dismiss()
//                }
//            } catch {
//                await MainActor.run {
//                    isGenerating = false
//                    errorMessage = "生成失败，请检查网络或 API Key: \(error.localizedDescription)"
//                }
//            }
//        }
//    }
//
//    private func crispCopyTap() {
//        let generator = UIImpactFeedbackGenerator(style: .light)
//        generator.prepare()
//        generator.impactOccurred(intensity: 0.55)
//    }
//
//    private func dismissKeyboard() {
//        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
//    }
//}
//
//private struct ResultHeader: View {
//    let onClose: () -> Void
//
//    var body: some View {
//        HStack {
//            Text("∅")
//                .font(.system(size: 27, weight: .light, design: .serif))
//                .foregroundStyle(Color.white.opacity(0.6))
//
//            Spacer()
//
//            Button(action: onClose) {
//                Image(systemName: "xmark")
//                    .font(.system(size: 16, weight: .light))
//                    .frame(width: 38, height: 38)
//                    .foregroundStyle(Color.white.opacity(0.7))
//                    .contentShape(Circle())
//            }
//            .buttonStyle(.plain)
//            .accessibilityLabel("Close")
//        }
//    }
//}
//
//private struct AudioPlayerPanel: View {
//    @ObservedObject var player: RecordingAudioPlayer
//    let duration: TimeInterval
//
//    var body: some View {
//        VStack(spacing: 16) {
//            HStack(spacing: 16) {
//                Button(action: player.togglePlayback) {
//                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
//                        .font(.system(size: 15, weight: .medium))
//                        .frame(width: 42, height: 42)
//                        .foregroundStyle(Color.black)
//                        .background(Color.white.opacity(0.9), in: Circle())
//                        .contentShape(Circle())
//                }
//                .buttonStyle(.plain)
//                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
//
//                VStack(spacing: 9) {
//                    Slider(value: $player.currentTime, in: 0...max(player.duration, duration, 0.1)) { editing in
//                        player.setScrubbing(editing)
//                    }
//                    .tint(Color(red: 0.1, green: 0.8, blue: 1.0))
//
//                    HStack {
//                        Text(Self.timeString(player.currentTime))
//                        Spacer()
//                        Text(Self.timeString(max(player.duration, duration)))
//                    }
//                    .font(.system(size: 11, weight: .medium, design: .rounded))
//                    .tracking(0)
//                    .foregroundStyle(Color.white.opacity(0.6))
//                }
//            }
//        }
//        .padding(.vertical, 14)
//        .padding(.horizontal, 16)
//        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
//    }
//
//    private static func timeString(_ interval: TimeInterval) -> String {
//        guard interval.isFinite else {
//            return "0:00"
//        }
//
//        let totalSeconds = max(0, Int(interval.rounded()))
//        let minutes = totalSeconds / 60
//        let seconds = totalSeconds % 60
//        return "\(minutes):\(String(format: "%02d", seconds))"
//    }
//}
//
//private struct NodeTimeline: View {
//    let nodes: [SpeechThoughtNode]
//    let duration: TimeInterval
//
//    var body: some View {
//        GeometryReader { geometry in
//            let width = max(1, geometry.size.width)
//            let total = max(duration, nodes.map(\.timestamp).max() ?? 1, 1)
//
//            ZStack(alignment: .leading) {
//                Capsule()
//                    .fill(Color.white.opacity(0.15))
//                    .frame(height: 1)
//
//                ForEach(nodes) { node in
//                    Circle()
//                        .fill(Color(red: 0.1, green: 0.8, blue: 1.0))
//                        .frame(width: 6, height: 6)
//                        .shadow(color: Color(red: 0.1, green: 0.8, blue: 1.0).opacity(0.6), radius: 6)
//                        .offset(x: max(0, min(width - 6, width * node.timestamp / total)))
//                }
//            }
//            .frame(maxHeight: .infinity)
//        }
//        .frame(height: 18)
//    }
//}
//
//private struct NodeList: View {
//    let nodes: [SpeechThoughtNode]
//
//    var body: some View {
//        VStack(alignment: .leading, spacing: 10) {
//            ForEach(nodes) { node in
//                HStack(alignment: .firstTextBaseline, spacing: 10) {
//                    Circle()
//                        .fill(Color(red: 0.1, green: 0.8, blue: 1.0))
//                        .frame(width: 5, height: 5)
//
//                    Text(timeString(node.timestamp))
//                        .font(.system(size: 12, weight: .semibold, design: .rounded))
//                        .foregroundStyle(Color.white.opacity(0.6))
//                        .monospacedDigit()
//
//                    Text(node.excerpt.isEmpty ? "节点" : node.excerpt)
//                        .font(.system(size: 13, weight: .regular, design: .serif))
//                        .lineLimit(2)
//                        .foregroundStyle(Color.white.opacity(0.8))
//                }
//            }
//        }
//    }
//
//    private func timeString(_ interval: TimeInterval) -> String {
//        let totalSeconds = max(0, Int(interval.rounded()))
//        let minutes = totalSeconds / 60
//        let seconds = totalSeconds % 60
//        return "\(minutes):\(String(format: "%02d", seconds))"
//    }
//}
//
//private struct CopyTranscriptButton: View {
//    let copied: Bool
//    let action: () -> Void
//
//    var body: some View {
//        Button(action: action) {
//            Image(systemName: copied ? "checkmark" : "doc.on.doc")
//                .font(.system(size: 15, weight: .regular))
//                .frame(width: 46, height: 46)
//                .foregroundStyle(Color.white)
//                .background(Color.white.opacity(0.15), in: Circle())
//                .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
//                .contentShape(Circle())
//        }
//        .buttonStyle(.plain)
//        .accessibilityLabel("Copy")
//    }
//}
