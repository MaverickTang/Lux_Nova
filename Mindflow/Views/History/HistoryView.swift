//
//  HistoryView.swift
//  Mindflow
//

import SwiftUI
import Combine

class HistoryGraphViewModel: ObservableObject {
    @Published var positions: [UUID: CGPoint] = [:]
    private var velocities: [UUID: CGPoint] = [:]
    private var displayLinkTimer: AnyCancellable?
    var isDraggingNode: UUID? = nil; var dragTarget: CGPoint = .zero; var graphSize: CGSize = .zero
    
    func updateThoughts(_ thoughts: [SavedThought], size: CGSize) {
        self.graphSize = size
        for thought in thoughts {
            if positions[thought.id] == nil { positions[thought.id] = CGPoint(x: size.width / 2 + CGFloat.random(in: -60...60), y: size.height / 2 + CGFloat.random(in: -60...60)); velocities[thought.id] = .zero }
        }
    }
    func startPhysicsEngine(thoughts: [SavedThought], edges: [HistoryEdge]) { displayLinkTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.calculatePhysicsTick(thoughts: thoughts, edges: edges) } }
    func stopPhysicsEngine() { displayLinkTimer?.cancel() }
    
    private func calculatePhysicsTick(thoughts: [SavedThought], edges: [HistoryEdge]) {
        guard graphSize.width > 0 else { return }
        let center = CGPoint(x: graphSize.width / 2, y: graphSize.height / 2)
        var forces: [UUID: CGPoint] = [:]
        let time = Date().timeIntervalSince1970
        let gravityForce: CGFloat = 0.0015; let repulsionForce: CGFloat = 8000.0; let attractionForce: CGFloat = 0.02; let linkLength: CGFloat = 160.0; let friction: CGFloat = 0.75
        
        for (index, thought) in thoughts.enumerated() {
            forces[thought.id] = .zero
            guard let pos = positions[thought.id] else { continue }
            forces[thought.id]!.x += (center.x - pos.x) * gravityForce; forces[thought.id]!.y += (center.y - pos.y) * gravityForce
            for other in thoughts where other.id != thought.id {
                guard let otherPos = positions[other.id] else { continue }
                let dx = pos.x - otherPos.x; let dy = pos.y - otherPos.y
                let dist = max(sqrt(dx*dx + dy*dy), 30)
                let force = repulsionForce / (dist * dist)
                forces[thought.id]!.x += (dx / dist) * force; forces[thought.id]!.y += (dy / dist) * force
            }
            forces[thought.id]!.x += CGFloat(sin(time * 1.2 + Double(index))) * 0.3; forces[thought.id]!.y += CGFloat(cos(time * 0.9 + Double(index))) * 0.3
        }
        
        for edge in edges {
            guard let source = UUID(uuidString: edge.source), let target = UUID(uuidString: edge.target), let sourcePos = positions[source], let targetPos = positions[target] else { continue }
            let dx = targetPos.x - sourcePos.x; let dy = targetPos.y - sourcePos.y
            let dist = max(sqrt(dx*dx + dy*dy), 10)
            let force = (dist - linkLength) * attractionForce
            let fx = (dx / dist) * force; let fy = (dy / dist) * force
            forces[source]!.x += fx; forces[source]!.y += fy; forces[target]!.x -= fx; forces[target]!.y -= fy
        }
        
        for thought in thoughts {
            if isDraggingNode == thought.id { positions[thought.id] = dragTarget; velocities[thought.id] = .zero; continue }
            var vel = velocities[thought.id] ?? .zero; let f = forces[thought.id] ?? .zero
            vel.x = min(max((vel.x + f.x) * friction, -12.0), 12.0); vel.y = min(max((vel.y + f.y) * friction, -12.0), 12.0)
            velocities[thought.id] = vel
            if let pos = positions[thought.id] { positions[thought.id] = CGPoint(x: pos.x + vel.x, y: pos.y + vel.y) }
        }
    }
}

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = HistoryManager.shared
    @StateObject private var viewModel = HistoryGraphViewModel()
    
    @State private var selectedGraphJSON = ""
    @State private var selectedTranscript = ""
    @State private var selectedAudioURL: URL? = nil
    @State private var selectedDuration: TimeInterval = 0
    @State private var selectedThoughtId: UUID? = nil
    @State private var showGraph = false
    
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0; @State private var lastOffset: CGSize = .zero
    @State private var dragStartPositions: [UUID: CGPoint] = [:]

    // 【新增】交互状态
    @State private var isLinkMode = false
    @State private var selectedNodesForLink: [UUID] = []
    @State private var showVoiceLinker = false
    
    var combinedGesture: some Gesture {
        let drag = DragGesture().onChanged { v in self.offset = CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height) }.onEnded { _ in self.lastOffset = self.offset }
        let mag = MagnificationGesture().onChanged { v in self.scale = lastScale * v.magnitude }.onEnded { _ in self.lastScale = self.scale }
        return drag.simultaneously(with: mag)
    }
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea().gesture(combinedGesture)
                    
                    if manager.savedThoughts.isEmpty {
                        Text("宇宙寂静无声。\n尚未捕捉到任何闪念。")
                            .font(.system(size: 14, weight: .light, design: .serif)).foregroundColor(.white.opacity(0.4)).multilineTextAlignment(.center).lineSpacing(8)
                    } else {
                        ZStack {
                            // 连线
                            ForEach(manager.historyEdges) { edge in
                                if let sourceID = UUID(uuidString: edge.source), let targetID = UUID(uuidString: edge.target), let p1 = viewModel.positions[sourceID], let p2 = viewModel.positions[targetID] {
                                    let midPoint = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
                                    ZStack {
                                        Path { path in path.move(to: p1); path.addCurve(to: p2, control1: CGPoint(x: p1.x, y: (p1.y + p2.y)/2), control2: CGPoint(x: p2.x, y: (p1.y + p2.y)/2)) }.stroke(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [5])).allowsHitTesting(false)
                                        Text(edge.relation).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundColor(Color.white).shadow(color: Color.black, radius: 2, x: 0, y: 0).position(midPoint)
                                    }
                                }
                            }
                            
                            // 光团节点
                            ForEach(manager.savedThoughts) { thought in
                                if let pos = viewModel.positions[thought.id] {
                                    HistoryOrbNode(
                                        thought: thought,
                                        isLinkMode: isLinkMode,
                                        isSelectedForLink: selectedNodesForLink.contains(thought.id),
                                        onOpen: { json, transcript in
                                            selectedGraphJSON = json; selectedTranscript = transcript; selectedAudioURL = manager.getAudioURL(for: thought.audioFileName); selectedDuration = thought.duration ?? 0; selectedThoughtId = thought.id; showGraph = true
                                        },
                                        onLinkTap: { handleLinkSelection(thought.id) },
                                        onDelete: { withAnimation { manager.deleteThought(id: thought.id) } },
                                        onRename: { newName in manager.updateTopic(id: thought.id, newTopic: newName) }
                                    )
                                    .position(pos)
                                    .gesture(DragGesture().onChanged { value in viewModel.isDraggingNode = thought.id; if dragStartPositions[thought.id] == nil { dragStartPositions[thought.id] = pos }; let currentScale = scale == 0 ? 1 : scale; viewModel.dragTarget = CGPoint(x: dragStartPositions[thought.id]!.x + value.translation.width / currentScale, y: dragStartPositions[thought.id]!.y + value.translation.height / currentScale) }.onEnded { _ in viewModel.isDraggingNode = nil; dragStartPositions.removeValue(forKey: thought.id) })
                                }
                            }
                        }
                        .scaleEffect(scale).offset(offset)
                    }
                    
                    // 连线模式提示浮层
                    if isLinkMode {
                        VStack {
                            Spacer()
                            Text(selectedNodesForLink.count == 0 ? "请点选第一个意识光团" : "请点选第二个以建立/断开引力")
                                .font(.system(size: 13, weight: .medium)).foregroundColor(.black)
                                .padding(.horizontal, 20).padding(.vertical, 10).background(Color(red: 0.1, green: 0.8, blue: 1.0)).clipShape(Capsule()).padding(.bottom, 40)
                        }.transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .onAppear {
                    viewModel.updateThoughts(manager.savedThoughts, size: geometry.size)
                    viewModel.startPhysicsEngine(thoughts: manager.savedThoughts, edges: manager.historyEdges)
                    // 已经被移到 HistoryManager 的 saveThought 里了
//                    Task { await manager.syncNewThoughtsConnections() }
                }
                .onDisappear { viewModel.stopPhysicsEngine() }
                .onChange(of: geometry.size) { _, newSize in viewModel.updateThoughts(manager.savedThoughts, size: newSize) }
                .onChange(of: manager.savedThoughts.count) { _ in
                    viewModel.updateThoughts(manager.savedThoughts, size: geometry.size)
                }
                // 【核心修复】当后台增量分析完成，更新了 historyEdges 时，强制重启物理引擎来绘制新连线！
                .onChange(of: manager.historyEdges) { _ in
                    viewModel.stopPhysicsEngine()
                    viewModel.startPhysicsEngine(thoughts: manager.savedThoughts, edges: manager.historyEdges)
                }
//                .onChange(of: manager.savedThoughts.count) { _ in viewModel.updateThoughts(manager.savedThoughts, size: geometry.size) }*/
            }
            .navigationTitle("意识星海")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar).toolbarBackground(Color.black, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                // 【新增工具栏】
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showVoiceLinker = true }) { Image(systemName: "waveform").foregroundColor(Color(red: 0.1, green: 0.8, blue: 1.0)) }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 20) {
                        Button(action: { withAnimation { isLinkMode.toggle(); selectedNodesForLink.removeAll() } }) { Image(systemName: isLinkMode ? "link.circle.fill" : "link").foregroundColor(isLinkMode ? Color(red: 0.1, green: 0.8, blue: 1.0) : .white.opacity(0.7)) }
                        Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").foregroundColor(.white.opacity(0.7)) }
                    }
                }
            }
            .sheet(isPresented: $showGraph) {
                ThoughtGraphView(jsonString: selectedGraphJSON, transcript: selectedTranscript, audioURL: selectedAudioURL, duration: selectedDuration, thoughtId: selectedThoughtId).id(selectedGraphJSON)
            }
            .sheet(isPresented: $showVoiceLinker) {
                HistoryVoiceLinkerView(manager: manager)
            }
        }
    }
    
    // 处理手动连线逻辑
    private func handleLinkSelection(_ id: UUID) {
        let generator = UIImpactFeedbackGenerator(style: .medium); generator.impactOccurred()
        if selectedNodesForLink.contains(id) {
            selectedNodesForLink.removeAll { $0 == id }
        } else {
            selectedNodesForLink.append(id)
            if selectedNodesForLink.count == 2 {
                withAnimation {
                    manager.toggleEdge(source: selectedNodesForLink[0], target: selectedNodesForLink[1])
                    selectedNodesForLink.removeAll()
                    isLinkMode = false
                }
            }
        }
    }
}

private struct HistoryOrbNode: View {
    let thought: SavedThought
    let isLinkMode: Bool
    let isSelectedForLink: Bool
    let onOpen: (String, String) -> Void
    let onLinkTap: () -> Void
    let onDelete: () -> Void
    let onRename: (String) -> Void
    
    @State private var isActivated = false
    @State private var showRenameAlert = false
    @State private var newNameInput = ""
    
    var body: some View {
        VStack(spacing: 16) {
            Text(thought.topic).font(.system(size: 15, weight: .medium, design: .serif))
                .foregroundColor(isSelectedForLink ? Color(red: 0.1, green: 0.8, blue: 1.0) : .white)
                .opacity(isActivated || isLinkMode ? 1 : 0).offset(y: isActivated || isLinkMode ? 0 : 10)
            
            ZStack {
                let color = colorForTopic(thought.topic)
                Circle().fill(RadialGradient(gradient: Gradient(colors: [color.opacity(isActivated || isSelectedForLink ? 0.7 : 0.3), Color.black.opacity(0.0)]), center: .center, startRadius: 0, endRadius: isActivated || isSelectedForLink ? 75 : 50))
                    .frame(width: 140, height: 140).scaleEffect(isActivated || isSelectedForLink ? 1.1 : 1.0)
                    .animation(isActivated || isSelectedForLink ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true) : .easeOut, value: isActivated || isSelectedForLink)
                Circle().fill(Color.white.opacity(isActivated || isSelectedForLink ? 1.0 : 0.5)).frame(width: isActivated ? 6 : 4, height: isActivated ? 6 : 4).shadow(color: color, radius: 4)
                
                if isSelectedForLink {
                    Circle().stroke(Color(red: 0.1, green: 0.8, blue: 1.0), lineWidth: 1.5).frame(width: 30, height: 30)
                }
            }
            .contentShape(Circle())
            .onTapGesture {
                if isLinkMode { onLinkTap() } else { handleTap() }
            }
            .contextMenu {
                Button { newNameInput = thought.topic; showRenameAlert = true } label: { Label("重新命名", systemImage: "pencil") }
                Button(role: .destructive) { onDelete() } label: { Label("湮灭此闪念", systemImage: "trash") }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isActivated)
        // iOS 16+ 弹窗改名
        .alert("修改意识命名", isPresented: $showRenameAlert) {
            TextField("输入新的名字", text: $newNameInput)
            Button("取消", role: .cancel) { }
            Button("保存") { onRename(newNameInput) }
        }
    }
    
    private func handleTap() {
        if isActivated { onOpen(thought.graphJSON, thought.transcript); isActivated = false }
        else { let generator = UIImpactFeedbackGenerator(style: .light); generator.impactOccurred(); isActivated = true; DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { isActivated = false } }
    }
    private func colorForTopic(_ topic: String) -> Color {
        var hash = 0; for char in topic.utf8 { hash = (hash << 5) &- hash &+ Int(char) }
        return Color(hue: Double(abs(hash) % 360) / 360.0, saturation: 0.85, brightness: 0.95)
    }
}

// MARK: - 语音重塑星系悬浮窗
struct HistoryVoiceLinkerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: HistoryManager
    @StateObject private var recorder = SpeechRecorder() // 复用录音服务
    @State private var isProcessing = false
    
    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()
            VStack(spacing: 30) {
                Text("神经重塑").font(.system(size: 20, weight: .bold, design: .serif)).foregroundColor(.white).padding(.top, 40)
                Text("用语音描述你想如何改变星系连线\n如：“把关于APP开发的想法关联起来”")
                    .font(.system(size: 14)).foregroundColor(.white.opacity(0.5)).multilineTextAlignment(.center)
                
                Spacer()
                
                if isProcessing {
                    ProgressView().scaleEffect(1.5).tint(Color(red: 0.1, green: 0.8, blue: 1.0))
                    Text("大模型正在解析指令并重组引力场...").font(.system(size: 12)).foregroundColor(.white.opacity(0.6)).padding(.top, 10)
                } else {
                    Button(action: { Task { await recorder.toggleRecording() } }) {
                        ZStack {
                            Circle().fill(recorder.isRecording ? Color.red.opacity(0.2) : Color(red: 0.1, green: 0.8, blue: 1.0).opacity(0.2)).frame(width: 100, height: 100)
                            Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill").font(.system(size: 32)).foregroundColor(recorder.isRecording ? .red : Color(red: 0.1, green: 0.8, blue: 1.0))
                        }
                    }
                    Text(recorder.isRecording ? "正在倾听..." : "点击开始指挥").font(.system(size: 13)).foregroundColor(.white.opacity(0.6))
                    
                    if !recorder.transcript.isEmpty {
                        Text(recorder.transcript).font(.system(size: 14)).foregroundColor(.white).padding().background(Color.white.opacity(0.1)).cornerRadius(12).padding(.horizontal, 40)
                        
                        Button("执行重塑") { executeCommand() }
                            .font(.system(size: 16, weight: .bold)).foregroundColor(.black).frame(width: 200, height: 44).background(Color(red: 0.1, green: 0.8, blue: 1.0)).cornerRadius(22)
                    }
                }
                Spacer()
            }
        }
    }
    
    private func executeCommand() {
        isProcessing = true
        Task {
            if recorder.isRecording { await recorder.toggleRecording() }
            let command = recorder.transcript
            try? await manager.processVoiceCommandToModifyEdges(command: command)
            await MainActor.run { dismiss() }
        }
    }
}





////
////  HistoryView.swift
////  Mindflow
////
//
//import SwiftUI
//import Combine
//
//class HistoryGraphViewModel: ObservableObject {
//    @Published var positions: [UUID: CGPoint] = [:]
//    private var velocities: [UUID: CGPoint] = [:]
//    private var displayLinkTimer: AnyCancellable?
//    
//    var isDraggingNode: UUID? = nil
//    var dragTarget: CGPoint = .zero
//    var graphSize: CGSize = .zero
//    
//    func updateThoughts(_ thoughts: [SavedThought], size: CGSize) {
//        self.graphSize = size
//        for thought in thoughts {
//            if positions[thought.id] == nil {
//                positions[thought.id] = CGPoint(
//                    x: size.width / 2 + CGFloat.random(in: -60...60),
//                    y: size.height / 2 + CGFloat.random(in: -60...60)
//                )
//                velocities[thought.id] = .zero
//            }
//        }
//    }
//    
//    func startPhysicsEngine(thoughts: [SavedThought], edges: [HistoryEdge]) {
//        displayLinkTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect().sink { [weak self] _ in
//            self?.calculatePhysicsTick(thoughts: thoughts, edges: edges)
//        }
//    }
//    
//    func stopPhysicsEngine() { displayLinkTimer?.cancel() }
//    
//    private func calculatePhysicsTick(thoughts: [SavedThought], edges: [HistoryEdge]) {
//        guard graphSize.width > 0 else { return }
//        let center = CGPoint(x: graphSize.width / 2, y: graphSize.height / 2)
//        var forces: [UUID: CGPoint] = [:]
//        let time = Date().timeIntervalSince1970
//        
//        let gravityForce: CGFloat = 0.0015
//        let repulsionForce: CGFloat = 8000.0
//        let attractionForce: CGFloat = 0.02
//        let linkLength: CGFloat = 160.0
//        let friction: CGFloat = 0.75
//        
//        for (index, thought) in thoughts.enumerated() {
//            forces[thought.id] = .zero
//            guard let pos = positions[thought.id] else { continue }
//            
//            forces[thought.id]!.x += (center.x - pos.x) * gravityForce
//            forces[thought.id]!.y += (center.y - pos.y) * gravityForce
//            
//            for other in thoughts where other.id != thought.id {
//                guard let otherPos = positions[other.id] else { continue }
//                let dx = pos.x - otherPos.x
//                let dy = pos.y - otherPos.y
//                let dist = max(sqrt(dx*dx + dy*dy), 30)
//                let force = repulsionForce / (dist * dist)
//                forces[thought.id]!.x += (dx / dist) * force
//                forces[thought.id]!.y += (dy / dist) * force
//            }
//            
//            forces[thought.id]!.x += CGFloat(sin(time * 1.2 + Double(index))) * 0.3
//            forces[thought.id]!.y += CGFloat(cos(time * 0.9 + Double(index))) * 0.3
//        }
//        
//        // 【修改】只对 LLM 认为有联系的节点施加引力
//        for edge in edges {
//            guard let source = UUID(uuidString: edge.source), let target = UUID(uuidString: edge.target) else { continue }
//            guard let sourcePos = positions[source], let targetPos = positions[target] else { continue }
//            
//            let dx = targetPos.x - sourcePos.x
//            let dy = targetPos.y - sourcePos.y
//            let dist = max(sqrt(dx*dx + dy*dy), 10)
//            
//            let force = (dist - linkLength) * attractionForce
//            let fx = (dx / dist) * force
//            let fy = (dy / dist) * force
//            
//            forces[source]!.x += fx
//            forces[source]!.y += fy
//            forces[target]!.x -= fx
//            forces[target]!.y -= fy
//        }
//        
//        for thought in thoughts {
//            if isDraggingNode == thought.id {
//                positions[thought.id] = dragTarget
//                velocities[thought.id] = .zero
//                continue
//            }
//            var vel = velocities[thought.id] ?? .zero
//            let f = forces[thought.id] ?? .zero
//            vel.x = min(max((vel.x + f.x) * friction, -12.0), 12.0)
//            vel.y = min(max((vel.y + f.y) * friction, -12.0), 12.0)
//            velocities[thought.id] = vel
//            if let pos = positions[thought.id] { positions[thought.id] = CGPoint(x: pos.x + vel.x, y: pos.y + vel.y) }
//        }
//    }
//}
//
//struct HistoryView: View {
//    @Environment(\.dismiss) private var dismiss
//    @StateObject private var manager = HistoryManager.shared
//    @StateObject private var viewModel = HistoryGraphViewModel()
//    
//    @State private var selectedGraphJSON = ""
//    @State private var selectedTranscript = ""
//    @State private var selectedAudioURL: URL? = nil
//    @State private var selectedDuration: TimeInterval = 0
//    @State private var selectedThoughtId: UUID? = nil
//    @State private var showGraph = false
//    
//    @State private var scale: CGFloat = 1.0
//    @State private var offset: CGSize = .zero
//    @State private var lastScale: CGFloat = 1.0
//    @State private var lastOffset: CGSize = .zero
//    @State private var dragStartPositions: [UUID: CGPoint] = [:]
//
//    var combinedGesture: some Gesture {
//        let drag = DragGesture().onChanged { v in self.offset = CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height) }.onEnded { _ in self.lastOffset = self.offset }
//        let mag = MagnificationGesture().onChanged { v in self.scale = lastScale * v.magnitude }.onEnded { _ in self.lastScale = self.scale }
//        return drag.simultaneously(with: mag)
//    }
//    
//    var body: some View {
//        NavigationView {
//            GeometryReader { geometry in
//                ZStack {
//                    Color.black.ignoresSafeArea().gesture(combinedGesture)
//                    
//                    if manager.savedThoughts.isEmpty {
//                        Text("宇宙寂静无声。\n尚未捕捉到任何闪念。")
//                            .font(.system(size: 14, weight: .light, design: .serif))
//                            .foregroundColor(.white.opacity(0.4)).multilineTextAlignment(.center).lineSpacing(8)
//                    } else {
//                        ZStack {
//                            // 【修改】绘制 LLM 找出的智能连线 (复刻思维图谱的高级发光虚线与文字)
//                            ForEach(manager.historyEdges) { edge in
//                                if let sourceID = UUID(uuidString: edge.source),
//                                   let targetID = UUID(uuidString: edge.target),
//                                   let p1 = viewModel.positions[sourceID],
//                                   let p2 = viewModel.positions[targetID] {
//                                    
//                                    let midPoint = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
//                                    ZStack {
//                                        Path { path in
//                                            path.move(to: p1)
//                                            path.addCurve(to: p2, control1: CGPoint(x: p1.x, y: (p1.y + p2.y)/2), control2: CGPoint(x: p2.x, y: (p1.y + p2.y)/2))
//                                        }
//                                        .stroke(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [5]))
//                                        .allowsHitTesting(false)
//                                        
//                                        Text(edge.relation)
//                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
//                                            .foregroundColor(Color.white)
//                                            .shadow(color: Color.black, radius: 2, x: 0, y: 0)
//                                            .position(midPoint)
//                                    }
//                                }
//                            }
//                            
//                            ForEach(manager.savedThoughts) { thought in
//                                if let pos = viewModel.positions[thought.id] {
//                                    HistoryOrbNode(thought: thought) { json, transcript in
//                                        selectedGraphJSON = json
//                                        selectedTranscript = transcript
//                                        selectedAudioURL = manager.getAudioURL(for: thought.audioFileName)
//                                        selectedDuration = thought.duration ?? 0
//                                        selectedThoughtId = thought.id
//                                        showGraph = true
//                                    } onDelete: {
//                                        withAnimation { manager.deleteThought(id: thought.id) }
//                                    }
//                                    .position(pos)
//                                    .gesture(
//                                        DragGesture()
//                                            .onChanged { value in
//                                                viewModel.isDraggingNode = thought.id
//                                                if dragStartPositions[thought.id] == nil { dragStartPositions[thought.id] = pos }
//                                                let currentScale = scale == 0 ? 1 : scale
//                                                viewModel.dragTarget = CGPoint(x: dragStartPositions[thought.id]!.x + value.translation.width / currentScale, y: dragStartPositions[thought.id]!.y + value.translation.height / currentScale)
//                                            }
//                                            .onEnded { _ in viewModel.isDraggingNode = nil; dragStartPositions.removeValue(forKey: thought.id) }
//                                    )
//                                }
//                            }
//                        }
//                        .scaleEffect(scale).offset(offset)
//                    }
//                }
//                .onAppear {
//                    viewModel.updateThoughts(manager.savedThoughts, size: geometry.size)
//                    viewModel.startPhysicsEngine(thoughts: manager.savedThoughts, edges: manager.historyEdges)
//                }
//                .onDisappear { viewModel.stopPhysicsEngine() }
//                .onChange(of: geometry.size) { _, newSize in viewModel.updateThoughts(manager.savedThoughts, size: newSize) }
//                .onChange(of: manager.savedThoughts.count) { _ in
//                    viewModel.updateThoughts(manager.savedThoughts, size: geometry.size)
//                }
//            }
//            .navigationTitle("意识星海")
//            .navigationBarTitleDisplayMode(.inline)
//            .toolbarColorScheme(.dark, for: .navigationBar)
//            .toolbarBackground(Color.black, for: .navigationBar)
//            .toolbarBackground(.visible, for: .navigationBar)
//            .toolbar {
//                ToolbarItem(placement: .navigationBarTrailing) {
//                    Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").foregroundColor(.white.opacity(0.7)) }
//                }
//            }
//            .sheet(isPresented: $showGraph) {
//                // 将音频数据和 UUID 传给思维图谱
//                ThoughtGraphView(
//                    jsonString: selectedGraphJSON,
//                    transcript: selectedTranscript,
//                    audioURL: selectedAudioURL,
//                    duration: selectedDuration,
//                    thoughtId: selectedThoughtId
//                ).id(selectedGraphJSON)
//            }
//        }
//    }
//}
//
//private struct HistoryOrbNode: View {
//    let thought: SavedThought
//    let onOpen: (String, String) -> Void
//    let onDelete: () -> Void
//    @State private var isActivated = false
//    
//    var body: some View {
//        VStack(spacing: 16) {
//            Text(thought.topic)
//                .font(.system(size: 15, weight: .medium, design: .serif))
//                .foregroundColor(.white).opacity(isActivated ? 1 : 0).offset(y: isActivated ? 0 : 10)
//            
//            ZStack {
//                let color = colorForTopic(thought.topic)
//                Circle()
//                    .fill(RadialGradient(gradient: Gradient(colors: [color.opacity(isActivated ? 0.6 : 0.3), Color.black.opacity(0.0)]), center: .center, startRadius: 0, endRadius: isActivated ? 70 : 50))
//                    .frame(width: 140, height: 140)
//                    .scaleEffect(isActivated ? 1.1 : 1.0)
//                    .animation(isActivated ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true) : .easeOut, value: isActivated)
//                
//                Circle()
//                    .fill(Color.white.opacity(isActivated ? 1.0 : 0.5))
//                    .frame(width: isActivated ? 6 : 4, height: isActivated ? 6 : 4)
//                    .shadow(color: color, radius: 4)
//            }
//            .contentShape(Circle())
//            .onTapGesture { handleTap() }
//            .contextMenu {
//                Button(role: .destructive) { onDelete() } label: { Label("湮灭此闪念", systemImage: "trash") }
//            }
//            
//            // 【修改】这里删除了底下显示时间的 Text 组件
//        }
//        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isActivated)
//    }
//    
//    private func handleTap() {
//        if isActivated { onOpen(thought.graphJSON, thought.transcript); isActivated = false }
//        else { let generator = UIImpactFeedbackGenerator(style: .light); generator.impactOccurred(); isActivated = true; DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { isActivated = false } }
//    }
//    
//    private func colorForTopic(_ topic: String) -> Color {
//        var hash = 0
//        for char in topic.utf8 { hash = (hash << 5) &- hash &+ Int(char) }
//        return Color(hue: Double(abs(hash) % 360) / 360.0, saturation: 0.85, brightness: 0.95)
//    }
//}
