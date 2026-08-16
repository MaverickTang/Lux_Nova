//
//  ThoughtGraphView.swift
//  Mindflow
//

import SwiftUI
import Combine
import Foundation

struct ThoughtGraph: Codable { let topic: String; let summary: String; let nodes: [ThoughtNode]; let edges: [ThoughtEdge] }
struct ThoughtNode: Codable, Identifiable { let id: String; let label: String; let type: String; let detail: String; let isMainline: Bool }
struct ThoughtEdge: Codable, Identifiable { var id: String { source + "-" + target }; let source: String; let target: String; let relation: String }

class GraphViewModel: ObservableObject {
    @Published var graph: ThoughtGraph?
    @Published var nodePositions: [String: CGPoint] = [:]
    @Published var selectedNodeIDs: Set<String> = []
    @Published var selectedEdgeIDs: Set<String> = []
    @Published var visibleNodes: Set<String> = []
    
    private var velocities: [String: CGPoint] = [:]
    private var mainlineTargets: [String: CGPoint] = [:]
    private var displayLinkTimer: AnyCancellable?
    var isDraggingNode: String? = nil
    var dragTarget: CGPoint = .zero
    var graphSize: CGSize = .zero
    
    init(jsonString: String? = nil) {
        if let json = jsonString, !json.isEmpty { loadJSON(json) } else { loadMockJSON() }
    }
    func loadJSON(_ jsonString: String) {
        if let data = jsonString.data(using: .utf8), let decoded = try? JSONDecoder().decode(ThoughtGraph.self, from: data) { self.graph = decoded }
    }
    private func loadMockJSON() { loadJSON("{ \"topic\": \"未连接大模型\", \"nodes\": [ { \"id\": \"1\", \"label\": \"请检查设置\", \"type\": \"problem\", \"detail\": \"没有传入有效JSON\", \"isMainline\": true } ], \"edges\": [] }") }
    
    func updateSkeleton(size: CGSize) {
        guard let graph = graph else { return }
        self.graphSize = size
        let mainlines = graph.nodes.filter { $0.isMainline }
        let isLandscape = size.width > size.height
        let step = (isLandscape ? size.width : size.height) / CGFloat(mainlines.count + 1)
        for (index, node) in mainlines.enumerated() {
            let position = CGFloat(index + 1) * step
            let target = isLandscape ? CGPoint(x: position, y: size.height / 2) : CGPoint(x: size.width / 2, y: position)
            mainlineTargets[node.id] = target
            if nodePositions[node.id] == nil { nodePositions[node.id] = target; velocities[node.id] = .zero }
        }
        let branches = graph.nodes.filter { !$0.isMainline }
        for branch in branches {
            if nodePositions[branch.id] == nil {
                if let edge = graph.edges.first(where: { $0.target == branch.id }), let sourceTarget = mainlineTargets[edge.source] {
                    nodePositions[branch.id] = CGPoint(x: sourceTarget.x + CGFloat.random(in: -40...40), y: sourceTarget.y + CGFloat.random(in: -40...40))
                } else { nodePositions[branch.id] = CGPoint(x: size.width/2, y: size.height/2) }
                velocities[branch.id] = .zero
            }
        }
    }
    
    func animateIn() {
        guard let graph = graph else { return }
        visibleNodes.removeAll()
        let sortedNodes = graph.nodes.sorted { if $0.isMainline == $1.isMainline { return $0.id < $1.id }; return $0.isMainline && !$1.isMainline }
        for (index, node) in sortedNodes.enumerated() { DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.12) { withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { _ = self.visibleNodes.insert(node.id) } } }
    }
    
    func startPhysicsEngine() { displayLinkTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.calculatePhysicsTick() } }
    func stopPhysicsEngine() { displayLinkTimer?.cancel() }
    
    private func calculatePhysicsTick() {
        guard let graph = graph, graphSize.width > 0 else { return }
        let center = CGPoint(x: graphSize.width / 2, y: graphSize.height / 2)
        var forces: [String: CGPoint] = [:]
        let time = Date().timeIntervalSince1970
        let gravityForce: CGFloat = 0.003
        let linkLength: CGFloat = 110.0
        let friction: CGFloat = 0.75
        let skeletonForce: CGFloat = 0.08
        let savedRepulsion = UserDefaults.standard.object(forKey: "physics_repulsion") as? Double
        let repulsionForce = savedRepulsion != nil ? CGFloat(savedRepulsion!) : 4000.0
        let savedAttraction = UserDefaults.standard.object(forKey: "physics_attraction") as? Double
        let attractionForce = savedAttraction != nil ? CGFloat(savedAttraction!) : 0.03
        
        for (index, node) in graph.nodes.enumerated() {
            forces[node.id] = .zero
            guard let pos = nodePositions[node.id] else { continue }
            if !node.isMainline { forces[node.id]!.x += (center.x - pos.x) * gravityForce; forces[node.id]!.y += (center.y - pos.y) * gravityForce }
            for other in graph.nodes where other.id != node.id {
                guard let otherPos = nodePositions[other.id] else { continue }
                let dx = pos.x - otherPos.x; let dy = pos.y - otherPos.y
                let dist = max(sqrt(dx*dx + dy*dy), 20)
                let force = repulsionForce / (dist * dist)
                forces[node.id]!.x += (dx / dist) * force; forces[node.id]!.y += (dy / dist) * force
            }
            forces[node.id]!.x += CGFloat(sin(time * 1.5 + Double(index))) * 0.4; forces[node.id]!.y += CGFloat(cos(time * 1.2 + Double(index))) * 0.5
            if node.isMainline, let target = mainlineTargets[node.id] { forces[node.id]!.x += (target.x - pos.x) * skeletonForce; forces[node.id]!.y += (target.y - pos.y) * skeletonForce }
        }
        for edge in graph.edges {
            guard let sourcePos = nodePositions[edge.source], let targetPos = nodePositions[edge.target] else { continue }
            let dx = targetPos.x - sourcePos.x; let dy = targetPos.y - sourcePos.y
            let dist = max(sqrt(dx*dx + dy*dy), 10)
            let force = (dist - linkLength) * attractionForce
            let fx = (dx / dist) * force; let fy = (dy / dist) * force
            forces[edge.source]!.x += fx; forces[edge.source]!.y += fy; forces[edge.target]!.x -= fx; forces[edge.target]!.y -= fy
        }
        for node in graph.nodes {
            if isDraggingNode == node.id { nodePositions[node.id] = dragTarget; velocities[node.id] = .zero; continue }
            var vel = velocities[node.id] ?? .zero; let f = forces[node.id] ?? .zero
            vel.x = min(max((vel.x + f.x) * friction, -15.0), 15.0); vel.y = min(max((vel.y + f.y) * friction, -15.0), 15.0)
            velocities[node.id] = vel
            if let pos = nodePositions[node.id] { nodePositions[node.id] = CGPoint(x: pos.x + vel.x, y: pos.y + vel.y) }
        }
    }
}

struct ThoughtGraphView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject var viewModel: GraphViewModel
    
    let transcript: String
    let onContinue: (() -> Void)?
    
    // 【修改】加入音频控制、时长和绑定记录 ID
    @StateObject private var player: RecordingAudioPlayer
    @State private var editableTranscript: String
    let duration: TimeInterval
    let thoughtId: UUID?
    
    @State private var showTranscriptSheet = false
    
    init(jsonString: String = "", transcript: String = "", audioURL: URL? = nil, duration: TimeInterval = 0, thoughtId: UUID? = nil, onContinue: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: GraphViewModel(jsonString: jsonString))
        self.transcript = transcript
        self.duration = duration
        self.thoughtId = thoughtId
        self.onContinue = onContinue
        _editableTranscript = State(initialValue: transcript)
        
        if let url = audioURL {
            _player = StateObject(wrappedValue: RecordingAudioPlayer(url: url))
        } else {
            let dummy = URL(fileURLWithPath: NSTemporaryDirectory())
            _player = StateObject(wrappedValue: RecordingAudioPlayer(url: dummy))
        }
    }
    
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    @State private var dragStartPositions: [String: CGPoint] = [:]
    
    var combinedGesture: some Gesture {
        let drag = DragGesture().onChanged { value in self.offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height) }.onEnded { _ in self.lastOffset = self.offset }
        let mag = MagnificationGesture().onChanged { value in self.scale = lastScale * value.magnitude }.onEnded { _ in self.lastScale = self.scale }
        return drag.simultaneously(with: mag)
    }
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea().gesture(combinedGesture).onTapGesture { withAnimation(.spring()) { viewModel.selectedNodeIDs.removeAll(); viewModel.selectedEdgeIDs.removeAll() } }
                    ZStack {
                        if let graph = viewModel.graph {
                            ForEach(graph.edges) { edge in EdgeView(edge: edge, viewModel: viewModel) }
                            ForEach(graph.nodes) { node in
                                if let position = viewModel.nodePositions[node.id] {
                                    NodeMinimalView(node: node, isSelected: viewModel.selectedNodeIDs.contains(node.id), isVisible: viewModel.visibleNodes.contains(node.id))
                                        .position(position)
                                        .gesture(DragGesture().onChanged { v in viewModel.isDraggingNode = node.id; if dragStartPositions[node.id] == nil { dragStartPositions[node.id] = position }; let c = scale == 0 ? 1 : scale; viewModel.dragTarget = CGPoint(x: dragStartPositions[node.id]!.x + v.translation.width / c, y: dragStartPositions[node.id]!.y + v.translation.height / c) }.onEnded { _ in viewModel.isDraggingNode = nil; dragStartPositions.removeValue(forKey: node.id) })
                                        .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { if viewModel.selectedNodeIDs.contains(node.id) { _ = viewModel.selectedNodeIDs.remove(node.id) } else { _ = viewModel.selectedNodeIDs.insert(node.id) }; triggerHapticFeedback() } }
                                }
                            }
                        }
                    }
                    .scaleEffect(scale).offset(offset)
                    
                    VStack {
                        Spacer()
                        HStack(spacing: 24) {
                            if !transcript.isEmpty {
                                Button(action: { showTranscriptSheet = true }) {
                                    HStack { Image(systemName: "doc.text"); Text("回顾原文") }.font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(.white).padding(.horizontal, 20).padding(.vertical, 12).background(Color.white.opacity(0.15)).clipShape(Capsule()).shadow(color: .black.opacity(0.3), radius: 8)
                                }
                            }
                            if let continueAction = onContinue {
                                Button(action: { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { continueAction() } }) {
                                    HStack { Image(systemName: "mic.fill"); Text("继续思考") }.font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(.black).padding(.horizontal, 20).padding(.vertical, 12).background(Color(red: 0.1, green: 0.8, blue: 1.0)).clipShape(Capsule()).shadow(color: Color(red: 0.1, green: 0.8, blue: 1.0).opacity(0.4), radius: 8)
                                }
                            }
                        }
                        .padding(.bottom, 30)
                    }
                }
                .onAppear { viewModel.updateSkeleton(size: geometry.size); viewModel.animateIn(); viewModel.startPhysicsEngine() }
                .onDisappear { viewModel.stopPhysicsEngine() }
                .onChange(of: geometry.size) { _, newSize in viewModel.updateSkeleton(size: newSize) }
            }
            .navigationTitle(viewModel.graph?.topic ?? "思维流向")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").foregroundColor(.white.opacity(0.7)) } } }
            
            // 【修改】升级的回顾界面：包含播放器和可编辑的 TextField
            .sheet(isPresented: $showTranscriptSheet) {
                NavigationView {
                    VStack(spacing: 0) {
                        // 播放器组件
                        if player.duration > 0 || duration > 0 {
                            AudioPlayerPanel(player: player, duration: duration)
                                .padding(.horizontal, 24)
                                .padding(.top, 24)
                        }
                        
                        ScrollView {
                            TextField("记录内容", text: $editableTranscript, axis: .vertical)
                                .font(.system(size: 16, design: .serif))
                                .lineSpacing(8)
                                .foregroundColor(.white.opacity(0.85))
                                .padding(24)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .onChange(of: editableTranscript) { newValue in
                                    // 用户一旦修改，自动同步到历史记录
                                    if let id = thoughtId {
                                        HistoryManager.shared.updateTranscript(id: id, newTranscript: newValue)
                                    }
                                }
                        }
                        .onTapGesture {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                    }
                    .background(Color(white: 0.05).ignoresSafeArea())
                    .navigationTitle("原始记录")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarColorScheme(.dark, for: .navigationBar)
                    .toolbarBackground(Color(white: 0.05), for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("关闭") { showTranscriptSheet = false; player.stop() }.foregroundColor(Color(red: 0.1, green: 0.8, blue: 1.0)) } }
                }
                .presentationDetents([.medium, .large])
                .onDisappear { player.stop() }
            }
        }
    }
    private func triggerHapticFeedback() { let generator = UIImpactFeedbackGenerator(style: .light); generator.prepare(); generator.impactOccurred() }
}

struct EdgeView: View { let edge: ThoughtEdge; @ObservedObject var viewModel: GraphViewModel; var body: some View { let isVisible = viewModel.visibleNodes.contains(edge.source) && viewModel.visibleNodes.contains(edge.target); if let startPos = viewModel.nodePositions[edge.source], let endPos = viewModel.nodePositions[edge.target] { let isSelected = viewModel.selectedEdgeIDs.contains(edge.id); let midPoint = CGPoint(x: (startPos.x + endPos.x) / 2, y: (startPos.y + endPos.y) / 2); ZStack { Path { path in path.move(to: startPos); path.addCurve(to: endPos, control1: CGPoint(x: startPos.x, y: (startPos.y + endPos.y)/2), control2: CGPoint(x: endPos.x, y: (startPos.y + endPos.y)/2)) }.stroke(Color.white.opacity(0.001), lineWidth: 40).onTapGesture { withAnimation(.spring()) { if viewModel.selectedEdgeIDs.contains(edge.id) { _ = viewModel.selectedEdgeIDs.remove(edge.id) } else { _ = viewModel.selectedEdgeIDs.insert(edge.id) } } }; Path { path in path.move(to: startPos); path.addCurve(to: endPos, control1: CGPoint(x: startPos.x, y: (startPos.y + endPos.y)/2), control2: CGPoint(x: endPos.x, y: (startPos.y + endPos.y)/2)) }.stroke(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.25), style: StrokeStyle(lineWidth: isSelected ? 2.5 : 1.5, dash: [5])).allowsHitTesting(false); if isSelected { Text(edge.relation).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundColor(Color.white).shadow(color: Color.black, radius: 2, x: 0, y: 0).shadow(color: Color.black, radius: 2, x: 0, y: 0).position(midPoint).transition(.opacity.animation(.easeInOut(duration: 0.2))) } }.opacity(isVisible ? 1 : 0) } } }
struct NodeMinimalView: View { let node: ThoughtNode; let isSelected: Bool; let isVisible: Bool; var body: some View { VStack(spacing: 8) { Text(node.label).font(.system(size: node.isMainline ? 18 : 15, weight: .semibold, design: .serif)).foregroundColor(Color.white.opacity(isSelected ? 1.0 : (node.isMainline ? 0.9 : 0.6))).multilineTextAlignment(.center); if isSelected { VStack(spacing: 4) { Text(node.type.uppercased()).font(.system(size: 9, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 2).background(typeColor(for: node.type).opacity(0.2)).foregroundColor(typeColor(for: node.type).opacity(0.9)).cornerRadius(4); Text(node.detail).font(.system(size: 11, weight: .regular)).foregroundColor(.white.opacity(0.7)).multilineTextAlignment(.center).frame(maxWidth: 130) }.transition(.move(edge: .top).combined(with: .opacity)) } }.padding(14).background(Color.white.opacity(0.001)).scaleEffect(isVisible ? 1.0 : 0.001).opacity(isVisible ? 1.0 : 0) }; private func typeColor(for type: String) -> Color { switch type { case "problem": return Color(red: 1.0, green: 0.4, blue: 0.4); case "solution": return Color(red: 0.4, green: 0.9, blue: 0.5); case "idea", "pros": return Color(red: 0.1, green: 0.8, blue: 1.0); default: return .gray } } }

// 供回顾界面使用的音频控制面板
private struct AudioPlayerPanel: View {
    @ObservedObject var player: RecordingAudioPlayer
    let duration: TimeInterval
    var body: some View {
        HStack(spacing: 16) {
            Button(action: player.togglePlayback) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .medium)).frame(width: 42, height: 42).foregroundStyle(Color.black).background(Color.white.opacity(0.9), in: Circle()).contentShape(Circle())
            }.buttonStyle(.plain)
            VStack(spacing: 9) {
                Slider(value: $player.currentTime, in: 0...max(player.duration, duration, 0.1)) { editing in player.setScrubbing(editing) }.tint(Color(red: 0.1, green: 0.8, blue: 1.0))
                HStack { Text(Self.timeString(player.currentTime)); Spacer(); Text(Self.timeString(max(player.duration, duration))) }.font(.system(size: 11, weight: .medium, design: .rounded)).tracking(0).foregroundStyle(Color.white.opacity(0.6))
            }
        }.padding(.vertical, 14).padding(.horizontal, 16).background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    private static func timeString(_ interval: TimeInterval) -> String { guard interval.isFinite else { return "0:00" }; let s = max(0, Int(interval.rounded())); return "\(s / 60):\(String(format: "%02d", s % 60))" }
}


////
////  ThoughtGraphView.swift
////  Mindflow
////
//
//import SwiftUI
//import Combine
//import Foundation
//
//// MARK: - 1. 数据模型 & 2. 具有真实物理引擎的视图模型
//// (这部分保持原有逻辑，压缩了空间展示)
//struct ThoughtGraph: Codable { let topic: String; let nodes: [ThoughtNode]; let edges: [ThoughtEdge] }
//struct ThoughtNode: Codable, Identifiable { let id: String; let label: String; let type: String; let detail: String; let isMainline: Bool }
//struct ThoughtEdge: Codable, Identifiable { var id: String { source + "-" + target }; let source: String; let target: String; let relation: String }
//
//class GraphViewModel: ObservableObject {
//    @Published var graph: ThoughtGraph?
//    @Published var nodePositions: [String: CGPoint] = [:]
//    @Published var selectedNodeIDs: Set<String> = []
//    @Published var selectedEdgeIDs: Set<String> = []
//    @Published var visibleNodes: Set<String> = []
//    
//    private var velocities: [String: CGPoint] = [:]
//    private var mainlineTargets: [String: CGPoint] = [:]
//    private var displayLinkTimer: AnyCancellable?
//    var isDraggingNode: String? = nil
//    var dragTarget: CGPoint = .zero
//    var graphSize: CGSize = .zero
//    
//    init(jsonString: String? = nil) {
//        if let json = jsonString, !json.isEmpty { loadJSON(json) } else { loadMockJSON() }
//    }
//    
//    func loadJSON(_ jsonString: String) {
//        if let data = jsonString.data(using: .utf8), let decoded = try? JSONDecoder().decode(ThoughtGraph.self, from: data) {
//            self.graph = decoded
//        } else { print("JSON 解析失败") }
//    }
//    
//    private func loadMockJSON() {
//        let jsonString = """
//        { "topic": "未连接大模型", "nodes": [ { "id": "1", "label": "请检查设置", "type": "problem", "detail": "没有传入有效JSON", "isMainline": true } ], "edges": [] }
//        """
//        loadJSON(jsonString)
//    }
//    
//    func updateSkeleton(size: CGSize) {
//        guard let graph = graph else { return }
//        self.graphSize = size
//        let mainlines = graph.nodes.filter { $0.isMainline }
//        let isLandscape = size.width > size.height
//        let step = (isLandscape ? size.width : size.height) / CGFloat(mainlines.count + 1)
//        
//        for (index, node) in mainlines.enumerated() {
//            let position = CGFloat(index + 1) * step
//            let target = isLandscape ? CGPoint(x: position, y: size.height / 2) : CGPoint(x: size.width / 2, y: position)
//            mainlineTargets[node.id] = target
//            if nodePositions[node.id] == nil {
//                nodePositions[node.id] = target
//                velocities[node.id] = .zero
//            }
//        }
//        let branches = graph.nodes.filter { !$0.isMainline }
//        for branch in branches {
//            if nodePositions[branch.id] == nil {
//                if let edge = graph.edges.first(where: { $0.target == branch.id }), let sourceTarget = mainlineTargets[edge.source] {
//                    nodePositions[branch.id] = CGPoint(x: sourceTarget.x + CGFloat.random(in: -40...40), y: sourceTarget.y + CGFloat.random(in: -40...40))
//                } else {
//                    nodePositions[branch.id] = CGPoint(x: size.width/2, y: size.height/2)
//                }
//                velocities[branch.id] = .zero
//            }
//        }
//    }
//    
//    func animateIn() {
//        guard let graph = graph else { return }
//        visibleNodes.removeAll()
//        let sortedNodes = graph.nodes.sorted {
//            if $0.isMainline == $1.isMainline { return $0.id < $1.id }
//            return $0.isMainline && !$1.isMainline
//        }
//        for (index, node) in sortedNodes.enumerated() {
//            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.12) {
//                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { _ = self.visibleNodes.insert(node.id) }
//            }
//        }
//    }
//    
//    func startPhysicsEngine() {
//        displayLinkTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.calculatePhysicsTick() }
//    }
//    func stopPhysicsEngine() { displayLinkTimer?.cancel() }
//    
//    private func calculatePhysicsTick() {
//        guard let graph = graph, graphSize.width > 0 else { return }
//        let center = CGPoint(x: graphSize.width / 2, y: graphSize.height / 2)
//        var forces: [String: CGPoint] = [:]
//        let time = Date().timeIntervalSince1970
//        let gravityForce: CGFloat = 0.003
//        let linkLength: CGFloat = 110.0
//        let friction: CGFloat = 0.75
//        let skeletonForce: CGFloat = 0.08
//        let savedRepulsion = UserDefaults.standard.object(forKey: "physics_repulsion") as? Double
//        let repulsionForce = savedRepulsion != nil ? CGFloat(savedRepulsion!) : 4000.0
//        let savedAttraction = UserDefaults.standard.object(forKey: "physics_attraction") as? Double
//        let attractionForce = savedAttraction != nil ? CGFloat(savedAttraction!) : 0.03
//        
//        for (index, node) in graph.nodes.enumerated() {
//            forces[node.id] = .zero
//            guard let pos = nodePositions[node.id] else { continue }
//            if !node.isMainline {
//                forces[node.id]!.x += (center.x - pos.x) * gravityForce
//                forces[node.id]!.y += (center.y - pos.y) * gravityForce
//            }
//            for other in graph.nodes where other.id != node.id {
//                guard let otherPos = nodePositions[other.id] else { continue }
//                let dx = pos.x - otherPos.x
//                let dy = pos.y - otherPos.y
//                let dist = max(sqrt(dx*dx + dy*dy), 20)
//                let force = repulsionForce / (dist * dist)
//                forces[node.id]!.x += (dx / dist) * force
//                forces[node.id]!.y += (dy / dist) * force
//            }
//            forces[node.id]!.x += CGFloat(sin(time * 1.5 + Double(index))) * 0.4
//            forces[node.id]!.y += CGFloat(cos(time * 1.2 + Double(index))) * 0.5
//            if node.isMainline, let target = mainlineTargets[node.id] {
//                forces[node.id]!.x += (target.x - pos.x) * skeletonForce
//                forces[node.id]!.y += (target.y - pos.y) * skeletonForce
//            }
//        }
//        for edge in graph.edges {
//            guard let sourcePos = nodePositions[edge.source], let targetPos = nodePositions[edge.target] else { continue }
//            let dx = targetPos.x - sourcePos.x
//            let dy = targetPos.y - sourcePos.y
//            let dist = max(sqrt(dx*dx + dy*dy), 10)
//            let force = (dist - linkLength) * attractionForce
//            let fx = (dx / dist) * force
//            let fy = (dy / dist) * force
//            forces[edge.source]!.x += fx
//            forces[edge.source]!.y += fy
//            forces[edge.target]!.x -= fx
//            forces[edge.target]!.y -= fy
//        }
//        for node in graph.nodes {
//            if isDraggingNode == node.id {
//                nodePositions[node.id] = dragTarget
//                velocities[node.id] = .zero
//                continue
//            }
//            var vel = velocities[node.id] ?? .zero
//            let f = forces[node.id] ?? .zero
//            vel.x = min(max((vel.x + f.x) * friction, -15.0), 15.0)
//            vel.y = min(max((vel.y + f.y) * friction, -15.0), 15.0)
//            velocities[node.id] = vel
//            if let pos = nodePositions[node.id] {
//                nodePositions[node.id] = CGPoint(x: pos.x + vel.x, y: pos.y + vel.y)
//            }
//        }
//    }
//}
//
//// MARK: - 3. 视图层 (包含继续控制面板)
//struct ThoughtGraphView: View {
//    @Environment(\.dismiss) private var dismiss
//    @StateObject var viewModel: GraphViewModel
//    
//    // 【新增】保存外部传入的原文
//    let transcript: String
//    // 【新增】可选闭包，触发“继续记录”
//    let onContinue: (() -> Void)?
//    
//    // 【新增】控制展示原文的底页
//    @State private var showTranscriptSheet = false
//    
//    init(jsonString: String = "", transcript: String = "", onContinue: (() -> Void)? = nil) {
//        _viewModel = StateObject(wrappedValue: GraphViewModel(jsonString: jsonString))
//        self.transcript = transcript
//        self.onContinue = onContinue
//    }
//    
//    @State private var scale: CGFloat = 1.0
//    @State private var offset: CGSize = .zero
//    @State private var lastScale: CGFloat = 1.0
//    @State private var lastOffset: CGSize = .zero
//    @State private var dragStartPositions: [String: CGPoint] = [:]
//    
//    var combinedGesture: some Gesture {
//        let drag = DragGesture()
//            .onChanged { value in self.offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height) }
//            .onEnded { _ in self.lastOffset = self.offset }
//        let mag = MagnificationGesture()
//            .onChanged { value in self.scale = lastScale * value.magnitude }
//            .onEnded { _ in self.lastScale = self.scale }
//        return drag.simultaneously(with: mag)
//    }
//    
//    var body: some View {
//        NavigationView {
//            GeometryReader { geometry in
//                ZStack {
//                    Color.black.ignoresSafeArea()
//                        .gesture(combinedGesture)
//                        .onTapGesture {
//                            withAnimation(.spring()) {
//                                viewModel.selectedNodeIDs.removeAll()
//                                viewModel.selectedEdgeIDs.removeAll()
//                            }
//                        }
//                    
//                    ZStack {
//                        if let graph = viewModel.graph {
//                            ForEach(graph.edges) { edge in EdgeView(edge: edge, viewModel: viewModel) }
//                            ForEach(graph.nodes) { node in
//                                if let position = viewModel.nodePositions[node.id] {
//                                    NodeMinimalView(node: node, isSelected: viewModel.selectedNodeIDs.contains(node.id), isVisible: viewModel.visibleNodes.contains(node.id))
//                                        .position(position)
//                                        .gesture(
//                                            DragGesture()
//                                                .onChanged { value in
//                                                    viewModel.isDraggingNode = node.id
//                                                    if dragStartPositions[node.id] == nil { dragStartPositions[node.id] = position }
//                                                    let currentScale = scale == 0 ? 1 : scale
//                                                    viewModel.dragTarget = CGPoint(x: dragStartPositions[node.id]!.x + value.translation.width / currentScale, y: dragStartPositions[node.id]!.y + value.translation.height / currentScale)
//                                                }
//                                                .onEnded { _ in viewModel.isDraggingNode = nil; dragStartPositions.removeValue(forKey: node.id) }
//                                        )
//                                        .onTapGesture {
//                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
//                                                if viewModel.selectedNodeIDs.contains(node.id) { _ = viewModel.selectedNodeIDs.remove(node.id) } else { _ = viewModel.selectedNodeIDs.insert(node.id) }
//                                                triggerHapticFeedback()
//                                            }
//                                        }
//                                }
//                            }
//                        }
//                    }
//                    .scaleEffect(scale)
//                    .offset(offset)
//                    
//                    // 【新增】底部控制台：查看原文与继续记录
//                    VStack {
//                        Spacer()
//                        HStack(spacing: 24) {
//                            if !transcript.isEmpty {
//                                Button(action: { showTranscriptSheet = true }) {
//                                    HStack {
//                                        Image(systemName: "doc.text")
//                                        Text("回顾原文")
//                                    }
//                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
//                                    .foregroundColor(.white)
//                                    .padding(.horizontal, 20)
//                                    .padding(.vertical, 12)
//                                    .background(Color.white.opacity(0.15))
//                                    .clipShape(Capsule())
//                                    .shadow(color: .black.opacity(0.3), radius: 8)
//                                }
//                            }
//                            
//                            if let continueAction = onContinue {
//                                Button(action: {
//                                    dismiss()
//                                    // 延迟一点时间等转场动画结束再唤起录音
//                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//                                        continueAction()
//                                    }
//                                }) {
//                                    HStack {
//                                        Image(systemName: "mic.fill")
//                                        Text("继续思考")
//                                    }
//                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
//                                    .foregroundColor(.black)
//                                    .padding(.horizontal, 20)
//                                    .padding(.vertical, 12)
//                                    .background(Color(red: 0.1, green: 0.8, blue: 1.0))
//                                    .clipShape(Capsule())
//                                    .shadow(color: Color(red: 0.1, green: 0.8, blue: 1.0).opacity(0.4), radius: 8)
//                                }
//                            }
//                        }
//                        .padding(.bottom, 30)
//                    }
//                }
//                .onAppear { viewModel.updateSkeleton(size: geometry.size); viewModel.animateIn(); viewModel.startPhysicsEngine() }
//                .onDisappear { viewModel.stopPhysicsEngine() }
//                .onChange(of: geometry.size) { _, newSize in viewModel.updateSkeleton(size: newSize) }
//            }
//            .navigationTitle(viewModel.graph?.topic ?? "思维流向")
//            .navigationBarTitleDisplayMode(.inline)
//            .toolbarColorScheme(.dark, for: .navigationBar)
//            .toolbarBackground(Color.black, for: .navigationBar)
//            .toolbarBackground(.visible, for: .navigationBar)
//            .toolbar {
//                ToolbarItem(placement: .navigationBarTrailing) {
//                    Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").foregroundColor(.white.opacity(0.7)) }
//                }
//            }
//            // 【新增】原文查看底部抽屉
//            .sheet(isPresented: $showTranscriptSheet) {
//                NavigationView {
//                    ScrollView {
//                        Text(transcript)
//                            .font(.system(size: 16, design: .serif))
//                            .lineSpacing(8)
//                            .foregroundColor(.white.opacity(0.85))
//                            .padding(24)
//                            .frame(maxWidth: .infinity, alignment: .leading)
//                    }
//                    .background(Color(white: 0.05).ignoresSafeArea())
//                    .navigationTitle("原始记录")
//                    .navigationBarTitleDisplayMode(.inline)
//                    .toolbarColorScheme(.dark, for: .navigationBar)
//                    .toolbarBackground(Color(white: 0.05), for: .navigationBar)
//                    .toolbarBackground(.visible, for: .navigationBar)
//                    .toolbar {
//                        ToolbarItem(placement: .navigationBarTrailing) {
//                            Button("关闭") { showTranscriptSheet = false }.foregroundColor(Color(red: 0.1, green: 0.8, blue: 1.0))
//                        }
//                    }
//                }
//                .presentationDetents([.medium, .large])
//            }
//        }
//    }
//    
//    private func triggerHapticFeedback() {
//        let generator = UIImpactFeedbackGenerator(style: .light); generator.prepare(); generator.impactOccurred()
//    }
//}
//
//// EdgeView 和 NodeMinimalView 保持不变 (压缩省略)
//struct EdgeView: View { let edge: ThoughtEdge; @ObservedObject var viewModel: GraphViewModel; var body: some View { let isVisible = viewModel.visibleNodes.contains(edge.source) && viewModel.visibleNodes.contains(edge.target); if let startPos = viewModel.nodePositions[edge.source], let endPos = viewModel.nodePositions[edge.target] { let isSelected = viewModel.selectedEdgeIDs.contains(edge.id); let midPoint = CGPoint(x: (startPos.x + endPos.x) / 2, y: (startPos.y + endPos.y) / 2); ZStack { Path { path in path.move(to: startPos); path.addCurve(to: endPos, control1: CGPoint(x: startPos.x, y: (startPos.y + endPos.y)/2), control2: CGPoint(x: endPos.x, y: (startPos.y + endPos.y)/2)) }.stroke(Color.white.opacity(0.001), lineWidth: 40).onTapGesture { withAnimation(.spring()) { if viewModel.selectedEdgeIDs.contains(edge.id) { _ = viewModel.selectedEdgeIDs.remove(edge.id) } else { _ = viewModel.selectedEdgeIDs.insert(edge.id) } } }; Path { path in path.move(to: startPos); path.addCurve(to: endPos, control1: CGPoint(x: startPos.x, y: (startPos.y + endPos.y)/2), control2: CGPoint(x: endPos.x, y: (startPos.y + endPos.y)/2)) }.stroke(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.25), style: StrokeStyle(lineWidth: isSelected ? 2.5 : 1.5, dash: [5])).allowsHitTesting(false); if isSelected { Text(edge.relation).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundColor(Color.white).shadow(color: Color.black, radius: 2, x: 0, y: 0).shadow(color: Color.black, radius: 2, x: 0, y: 0).position(midPoint).transition(.opacity.animation(.easeInOut(duration: 0.2))) } }.opacity(isVisible ? 1 : 0) } } }
//struct NodeMinimalView: View { let node: ThoughtNode; let isSelected: Bool; let isVisible: Bool; var body: some View { VStack(spacing: 8) { Text(node.label).font(.system(size: node.isMainline ? 18 : 15, weight: .semibold, design: .serif)).foregroundColor(Color.white.opacity(isSelected ? 1.0 : (node.isMainline ? 0.9 : 0.6))).multilineTextAlignment(.center); if isSelected { VStack(spacing: 4) { Text(node.type.uppercased()).font(.system(size: 9, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 2).background(typeColor(for: node.type).opacity(0.2)).foregroundColor(typeColor(for: node.type).opacity(0.9)).cornerRadius(4); Text(node.detail).font(.system(size: 11, weight: .regular)).foregroundColor(.white.opacity(0.7)).multilineTextAlignment(.center).frame(maxWidth: 130) }.transition(.move(edge: .top).combined(with: .opacity)) } }.padding(14).background(Color.white.opacity(0.001)).scaleEffect(isVisible ? 1.0 : 0.001).opacity(isVisible ? 1.0 : 0) }
//    private func typeColor(for type: String) -> Color { switch type { case "problem": return Color(red: 1.0, green: 0.4, blue: 0.4); case "solution": return Color(red: 0.4, green: 0.9, blue: 0.5); case "idea", "pros": return Color(red: 0.1, green: 0.8, blue: 1.0); default: return .gray } }
//}
