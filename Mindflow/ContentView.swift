//
//  ContentView.swift
//  Mindflow
//

import SwiftUI
import UIKit
import AVFoundation
import Combine

struct ContentView: View {
    @StateObject private var recorder = SpeechRecorder()
    @State private var compression = false
    @State private var expandGlow = false

    @State private var showThoughtGraph = false
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var generatedGraphJSON: String = ""
    
    @State private var recordingDuration: TimeInterval = 0
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    // 1. 全局纯黑背景
    private let background = Color.black

    var body: some View {
        GeometryReader { geometry in
            let safeArea = geometry.safeAreaInsets

            ZStack {
                background.ignoresSafeArea()

                // 白噪点
                AmbientNoise()
                    .opacity(0.12)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    Button(action: toggleRecording) {
                        TDParticleSphere(
                            isRecording: recorder.isRecording,
                            audioLevel: recorder.audioLevel,
                            compression: compression,
                            expandGlow: expandGlow
                        )
                        // 1. 【解决黑边】将 Frame 放开，占满整个屏幕宽度，给渐变留足褪去到透明的空间
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.width
                        )
                        // 保持点击热区为一个适当大小的圆，防止误触
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)

                    ZStack {
                        if recorder.isRecording {
                            // 2. 文字改为纯白色
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

                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        Button(action: { showHistory = true }) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 20, weight: .light))
                                .foregroundColor(Color.white.opacity(0.6)) // 图标改为白色
                                .padding(16)
                                .contentShape(Rectangle())
                        }
                        Spacer()
                        Button(action: { showSettings = true }) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 20, weight: .light))
                                .foregroundColor(Color.white.opacity(0.6)) // 图标改为白色
                                .padding(16)
                                .contentShape(Rectangle())
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, max(16, safeArea.bottom))
                }
            }
        }
        .onReceive(timer) { _ in
            if recorder.isRecording {
                recordingDuration += 1
            }
        }
        .onChange(of: recorder.isRecording) { isRecording in
            if !isRecording {
                recordingDuration = 0
            }
        }
//        .fullScreenCover(item: $recorder.completedResult) { result in
//            RecordingResultView(result: result, background: background)
//        }
        // 修改 fullScreenCover，闭包中传入了 onGenerate 回调
        .fullScreenCover(item: $recorder.completedResult) { result in
                    // 接收两个参数：jsonString 和 transcript
                    RecordingResultView(result: result, background: background) { jsonString, transcript in
                        
                        // 【新增】将这次的思考固化存入本地历史记录
                        HistoryManager.shared.saveThought(transcript: transcript, graphJSON: jsonString)
                        
                        self.generatedGraphJSON = jsonString
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            self.showThoughtGraph = true
                        }
                    }
                }
        .sheet(isPresented: $showThoughtGraph) {
//            ThoughtGraphView()
            ThoughtGraphView(jsonString: generatedGraphJSON)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showHistory) {
//            Text("历史记录界面预留 (光团列表)").f/*oregroundColor(.white).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black)*/
            HistoryView()
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

// MARK: - TD 风格 3D 流体粒子球 (Lux Nova 终极形态 - 修复初始全黑)
private struct TDParticleSphere: View {
    let isRecording: Bool
    let audioLevel: CGFloat
    let compression: Bool
    let expandGlow: Bool

    // 1. 【修复】直接在内存中初始化点阵，跳过 .onAppear，保证渲染第一帧就有数据
    @State private var baseParticles: [(x: Double, y: Double, z: Double)] = TDParticleSphere.generateOrganicSphere(count: 5000)
    
    private let particleCount = 5000

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                
                let easedLevel = pow(max(0.02, min(audioLevel, 1)), 0.5)
                // 球体最终大小由球体半径和声音放大系数共同决定
//                let baseRadius = min(size.width, size.height) * (isRecording ? 0.32 : 0.28)
                let baseRadius = min(size.width, size.height) * (isRecording ? 0.4 : 0.4)
                let radius = baseRadius * (1 + easedLevel * 0.15) * (compression ? 0.85 : 1)
                
                let gradient = Gradient(colors: [
                    Color.black.opacity(isRecording ? 1.0 : 0.85),
                    Color.black.opacity(0.0)
                ])
                context.fill(
                    Path(ellipseIn: CGRect(x: 0, y: 0, width: size.width, height: size.height)),
                    with: .radialGradient(gradient, center: center, startRadius: radius * 0.3, endRadius: radius * 1.5)
                )

                context.blendMode = .plusLighter
                
                let rotationTime = elapsed * (isRecording ? 0.25 : 0.08)
                let fluidTime = elapsed * (isRecording ? 0.8 : 0.25)
                let flowAmplitude = isRecording ? (0.35 + Double(easedLevel) * 0.6) : 0.25
                
                let cosY = cos(rotationTime)
                let sinY = sin(rotationTime)
                let cosX = cos(rotationTime * 0.6)
                let sinX = sin(rotationTime * 0.6)

                for particle in baseParticles {
                    let rx = particle.x * cosY + particle.z * sinY
                    var ry = particle.y
                    let rz = -particle.x * sinY + particle.z * cosY

                    let finalY = ry * cosX - rz * sinX
                    let finalZ = ry * sinX + rz * cosX
                    ry = finalY
                    
                    let freq: Double = 2.4
                    let flowX = sin(ry * freq + fluidTime) * cos(finalZ * freq - fluidTime)
                    let flowY = sin(finalZ * freq + fluidTime) * cos(rx * freq - fluidTime)
                    let flowZ = sin(rx * freq + fluidTime) * cos(ry * freq - fluidTime)
                    
                    let turbFreq: Double = 5.2
                    let turbX = sin(ry * turbFreq - fluidTime * 1.5) * 0.2
                    let turbY = sin(finalZ * turbFreq - fluidTime * 1.5) * 0.2
                    let turbZ = sin(rx * turbFreq - fluidTime * 1.5) * 0.2
                    
                    let dx = rx + (flowX + turbX) * flowAmplitude
                    let dy = ry + (flowY + turbY) * flowAmplitude
                    let dz = finalZ + (flowZ + turbZ) * flowAmplitude

                    let length = sqrt(dx * dx + dy * dy + dz * dz)
                    let cx = (dx / length) * radius
                    let cy = (dy / length) * radius
                    let cz = (dz / length) * radius

                    let depthFactor = (cz + radius) / (2 * radius)
                    if depthFactor > 0.55 { continue }

                    let energy = abs(flowX * flowY * flowZ) * 8.0
                    let densityClump = pow(energy, 1.5)

                    let focalLength: Double = 800.0
                    let perspectiveScale = focalLength / (focalLength + cz)
                    let screenX = center.x + cx * perspectiveScale
                    let screenY = center.y + cy * perspectiveScale

                    // 2. 【修复】提高待机（非录制）状态下的基础尺寸，让静态脉络更清晰
//                    单个点的大小并不是统一的，而是根据它在 3D 空间中的前后深度（近大远小）以及它所处的能量密度（聚集处更大）动态计算的。
                    let sizeBase = max(0.4, (1.0 - depthFactor))
                    //sizeBase * (isRecording ? 2.5 : 1.6)：这是粒子的基础大小。2.5 是录制时的大小，1.6 是待机时的大小。把它们调大，整个球体会显得更“雾化、厚重”；调小，则显得更“锐利、稀疏”
//                    let dotSize = sizeBase * (isRecording ? 2.5 : 1.6) + min(densityClump * (isRecording ? 3.0 : 2.0), 3.5)
                    let dotSize = sizeBase * (isRecording ? 1 : 1) + min(densityClump * (isRecording ? 3.0 : 2.0), 3.5)
                    
                    // 3. 【修复】大幅提高待机状态的透明度倍率 (从 0.6 提升到 0.85)，基础底色从 0.1 提升到 0.15
                    let alphaBase = (1.0 - (depthFactor / 0.55))
                    let opacity = min(max(alphaBase * (0.15 + densityClump), 0.1), 0.95) * (isRecording ? 1.0 : 0.85)

                    let isCore = min(densityClump, 1.0)
                    let particleColor = Color(
                        red: 0.3 + 0.7 * isCore,
                        green: 0.7 + 0.3 * isCore,
                        blue: 1.0
                    ).opacity(opacity)

                    let rect = CGRect(
                        x: screenX - dotSize / 2,
                        y: screenY - dotSize / 2,
                        width: dotSize,
                        height: dotSize
                    )
                    var path = Path()
                    path.addEllipse(in: rect)
                    context.fill(path, with: .color(particleColor))
                }
            }
        }
        // 删除原来的 .onAppear 逻辑，完全依靠属性直接初始化
    }

    private static func generateOrganicSphere(count: Int) -> [(Double, Double, Double)] {
        var points: [(Double, Double, Double)] = []
        let phi = .pi * (3.0 - sqrt(5.0))
        for i in 0..<count {
            let y = 1.0 - (Double(i) / Double(count - 1)) * 2.0
            let r = sqrt(1.0 - y * y)
            let theta = phi * Double(i)
            
            let jitterX = Double.random(in: -0.05...0.05)
            let jitterY = Double.random(in: -0.05...0.05)
            let jitterZ = Double.random(in: -0.05...0.05)
            
            let x = cos(theta) * r + jitterX
            let z = sin(theta) * r + jitterZ
            let ny = y + jitterY
            
            let len = sqrt(x*x + ny*ny + z*z)
            points.append((x/len, ny/len, z/len))
        }
        return points
    }
}

// 5. 噪点组件反转：背景变为黑色后，原本黑色的噪点无法显示，需改为白色并使用 screen 混合模式
private struct AmbientNoise: View {
    private let specks = (0..<260).map { index in
        NoiseSpeck(
            x: Double((index * 47) % 101) / 100,
            y: Double((index * 83) % 103) / 102,
            opacity: Double((index * 19) % 29) / 100 + 0.02
        )
    }

    var body: some View {
        Canvas { context, size in
            for speck in specks {
                let rect = CGRect(
                    x: speck.x * size.width,
                    y: speck.y * size.height,
                    width: 1.5,
                    height: 1.5
                )
                context.opacity = speck.opacity
                context.fill(Path(ellipseIn: rect), with: .color(.white)) // 噪点变白
            }
        }
        .blendMode(.screen)
    }
}

private struct NoiseSpeck {
    let x: Double
    let y: Double
    let opacity: Double
}


private struct RecordingResultView: View {
    let result: SpeechRecordingResult
    let background: Color
    
    // 【新增】用于在生成成功后，将 JSON 回传给主界面的闭包
//    let onGenerate: (String) -> Void
    // 【修改】同时回传 JSON 和 编辑后的文本
    let onGenerate: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var player: RecordingAudioPlayer
    @State private var copied = false
    @State private var editableTranscript: String
    
    // 【新增】网络请求相关的状态
    @State private var isGenerating = false
    @State private var errorMessage: String? = nil

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
                // ... (ResultHeader, AudioPlayerPanel, ScrollView 等保持不变)
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
                    .padding(.bottom, 150) // 【调整】给底部按钮留出更多空间
                }
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
            
            // 【新增】底部居中的“生成思维导图”按钮
            VStack {
                Spacer()
                
                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                        .padding(.bottom, 8)
                }
                
                Button(action: generateGraph) {
                    HStack(spacing: 8) {
                        if isGenerating {
                            ProgressView().tint(.black)
                            Text("神经突触连接中...")
                        } else {
                            Image(systemName: "sparkles")
                            Text("生成思维图谱")
                        }
                    }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .frame(width: 220, height: 50)
                    .background(Color(red: 0.1, green: 0.8, blue: 1.0)) // 科技亮蓝
                    .cornerRadius(25)
                    .shadow(color: Color(red: 0.1, green: 0.8, blue: 1.0).opacity(0.5), radius: 12, y: 6)
                }
                .disabled(isGenerating || editableTranscript.isEmpty)
                .padding(.bottom, 36)
            }
            .frame(maxWidth: .infinity, alignment: .center) // 强制居中对齐

            // 右下角原有的复制按钮
            CopyTranscriptButton(copied: copied) {
                UIPasteboard.general.string = editableTranscript
                crispCopyTap()
                withAnimation(.spring(response: 0.26, dampingFraction: 0.76)) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                    withAnimation(.easeOut(duration: 0.24)) { copied = false }
                }
            }
            .padding(.trailing, 22)
            .padding(.bottom, 24)
        }
        .onDisappear {
            player.stop()
        }
    }
    
    // 【新增】网络请求与状态处理函数
    private func generateGraph() {
        // 收起键盘
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        isGenerating = true
        errorMessage = nil
        
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        Task {
            do {
                // 调用你封装好的 LLMService
                let jsonResult = try await LLMService.shared.generateThoughtGraph(from: editableTranscript)
                
                await MainActor.run {
                    isGenerating = false
                    player.stop()
                    // 【修改】将 JSON 和文本一起传回主界面的闭包
                    onGenerate(jsonResult, editableTranscript)
                    // 关闭当前录制结果页
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    self.errorMessage = "生成失败，请检查网络或 API Key: \(error.localizedDescription)"
                }
            }
        }
    }

    private func crispCopyTap() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.55)
    }
}

private struct ResultHeader: View {
    let onClose: () -> Void

    var body: some View {
        HStack {
            Text("∅")
                .font(.system(size: 27, weight: .light, design: .serif))
                // 【修改】左上角 Logo 改为白色
                .foregroundStyle(Color.white.opacity(0.6))

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .light))
                    .frame(width: 38, height: 38)
                    // 【修改】关闭按钮改为白色
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
                        // 【修改】播放按钮颜色适配暗黑模式
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
                    // 【修改】进度条主题色改为亮蓝色，呼应球体
                    .tint(Color(red: 0.1, green: 0.8, blue: 1.0))

                    HStack {
                        Text(Self.timeString(player.currentTime))
                        Spacer()
                        Text(Self.timeString(max(player.duration, duration)))
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .tracking(0)
                    // 【修改】时间文字改为白色
                    .foregroundStyle(Color.white.opacity(0.6))
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        // 【修改】面板背景改为深色半透明
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
                    // 【修改】时间轴底色改为白色半透明
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 1)

                ForEach(nodes) { node in
                    Circle()
                        // 打点颜色保留科技感的亮色（金黄色/蓝色均可）
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
                        // 【修改】节点时间文字改为白色
                        .foregroundStyle(Color.white.opacity(0.6))
                        .monospacedDigit()

                    Text(node.excerpt.isEmpty ? "节点" : node.excerpt)
                        .font(.system(size: 13, weight: .regular, design: .serif))
                        .lineLimit(2)
                        // 【修改】节点摘要文字改为白色
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
                // 【修改】复制图标改为纯白
                .foregroundStyle(Color.white)
                // 【修改】复制按钮背景改为半透明，融入纯黑背景
                .background(Color.white.opacity(0.15), in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy")
    }
}

private final class RecordingAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}


// MARK: - 历史记录持久化模型
struct SavedThought: Identifiable, Codable {
    var id = UUID()
    let date: Date
    let topic: String
    let transcript: String
    let graphJSON: String
}

class HistoryManager: ObservableObject {
    static let shared = HistoryManager()
    @Published var savedThoughts: [SavedThought] = []

    private let storageKey = "lux_nova_history_v1"

    init() {
        load()
    }

    func saveThought(transcript: String, graphJSON: String) {
        // 从大模型返回的 JSON 中解析出 topic
        var extractedTopic = "未命名意识"
        if let data = graphJSON.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let topic = dict["topic"] as? String {
            extractedTopic = topic
        }
        
        let newThought = SavedThought(
            date: Date(),
            topic: extractedTopic,
            transcript: transcript,
            graphJSON: graphJSON
        )
        
        // 插入到最前面
        savedThoughts.insert(newThought, at: 0)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(savedThoughts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([SavedThought].self, from: data) {
            self.savedThoughts = decoded
        }
    }
}
