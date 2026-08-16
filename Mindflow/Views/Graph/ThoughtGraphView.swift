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
    private var targetAnchors: [String: CGPoint] = [:] // 全局节点的目标锚点
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
    
    // 【全新重构】基于图论拓扑深度的完美树状排版
    func updateSkeleton(size: CGSize) {
        guard let graph = graph, !graph.nodes.isEmpty else { return }
        self.graphSize = size
        
        // 1. 构建邻接表与入度 (用于寻找源头)
        var inDegree: [String: Int] = [:]
        var outEdges: [String: [String]] = [:]
        for node in graph.nodes { inDegree[node.id] = 0; outEdges[node.id] = [] }
        for edge in graph.edges {
            outEdges[edge.source]?.append(edge.target)
            inDegree[edge.target, default: 0] += 1
        }
        
        // 2. 广度优先搜索 (BFS) 计算节点的层级 (Level)
        var levels: [String: Int] = [:]
        // 找出所有的起点 (入度为0的节点)
        var queue = graph.nodes.filter { inDegree[$0.id] == 0 }.map { $0.id }
        if queue.isEmpty { queue.append(graph.nodes[0].id) } // 防御性回退：处理死循环
        
        var currentLevel = 0
        while !queue.isEmpty {
            let nextQueue = queue.flatMap { outEdges[$0] ?? [] }
            for id in queue {
                if levels[id] == nil { levels[id] = currentLevel }
            }
            queue = Array(Set(nextQueue)).filter { levels[$0] == nil }
            currentLevel += 1
        }
        // 防止孤岛节点漏掉
        for node in graph.nodes where levels[node.id] == nil {
            levels[node.id] = currentLevel
        }
        
        // 3. 按 Level 进行坐标分配 (解决节点拥挤与并列问题)
        let maxLevel = levels.values.max() ?? 0
        // 设置一个合理的最大层高间距，防止节点拉得太开
        let stepY = min(size.height / CGFloat(maxLevel + 2), 120.0)
        let startY = (size.height - (CGFloat(maxLevel) * stepY)) / 2
        
        var nodesByLevel: [Int: [ThoughtNode]] = [:]
        for node in graph.nodes {
            let lvl = levels[node.id] ?? 0
            nodesByLevel[lvl, default: []].append(node)
        }
        
        for lvl in 0...maxLevel {
            guard let lvlNodes = nodesByLevel[lvl] else { continue }
            
            // 将主线节点和旁支节点分开处理
            let mainlines = lvlNodes.filter { $0.isMainline }.sorted { $0.id < $1.id }
            let branches = lvlNodes.filter { !$0.isMainline }.sorted { $0.id < $1.id }
            
            var sortedNodes: [ThoughtNode] = []
            // 旁支节点均匀分配在左右两端
            var isLeft = true
            for branch in branches {
                if isLeft { sortedNodes.insert(branch, at: 0) }
                else { sortedNodes.append(branch) }
                isLeft.toggle()
            }
            // 无论这一层有几个主线节点，都强行插入在最中间！
            let midIndex = sortedNodes.count / 2
            sortedNodes.insert(contentsOf: mainlines, at: midIndex)
            
            // 固定水平间距，避免拉得太开
            let spacingX: CGFloat = 170.0
            let totalWidth = CGFloat(sortedNodes.count - 1) * spacingX
            let startX = (size.width - totalWidth) / 2
            let yTarget = startY + CGFloat(lvl) * stepY
            
            for (index, node) in sortedNodes.enumerated() {
                let xTarget = startX + CGFloat(index) * spacingX
                let target = CGPoint(x: xTarget, y: yTarget)
                targetAnchors[node.id] = target
                
                if nodePositions[node.id] == nil {
                    // 加入极小的随机数以平滑启动动画
                    nodePositions[node.id] = CGPoint(x: target.x + CGFloat.random(in: -10...10), y: target.y + CGFloat.random(in: -10...10))
                    velocities[node.id] = .zero
                }
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
    
    // 【全新物理引力场】基于锚点强约束
    private func calculatePhysicsTick() {
        guard let graph = graph, graphSize.width > 0 else { return }
        var forces: [String: CGPoint] = [:]
        let time = Date().timeIntervalSince1970
        let linkLength: CGFloat = 100.0
        let friction: CGFloat = 0.70
        
        // 大幅强化对完美拓扑锚点的引力，使其不容易被杂乱的物理力拉歪
        let skeletonForce: CGFloat = 0.18
        let branchSkeletonForce: CGFloat = 0.14
        
        let savedRepulsion = UserDefaults.standard.object(forKey: "physics_repulsion") as? Double
        let repulsionForce = savedRepulsion != nil ? CGFloat(savedRepulsion!) : 5000.0
        // 将线段本身的引力调弱，一切以拓扑网格计算的完美排版为主
        let savedAttraction = UserDefaults.standard.object(forKey: "physics_attraction") as? Double
        let attractionForce = savedAttraction != nil ? CGFloat(savedAttraction!) : 0.015
        
        for (index, node) in graph.nodes.enumerated() {
            forces[node.id] = .zero
            guard let pos = nodePositions[node.id] else { continue }
            
            for other in graph.nodes where other.id != node.id {
                guard let otherPos = nodePositions[other.id] else { continue }
                let dx = pos.x - otherPos.x; let dy = pos.y - otherPos.y
                let dist = max(sqrt(dx*dx + dy*dy), 25)
                let force = repulsionForce / (dist * dist)
                forces[node.id]!.x += (dx / dist) * force; forces[node.id]!.y += (dy / dist) * force
            }
            forces[node.id]!.x += CGFloat(sin(time * 1.5 + Double(index))) * 0.3; forces[node.id]!.y += CGFloat(cos(time * 1.2 + Double(index))) * 0.4
            
            // 【核心】将节点强力吸附至计算好的完美网格位置
            if let target = targetAnchors[node.id] {
                let alignForce = node.isMainline ? skeletonForce : branchSkeletonForce
                forces[node.id]!.x += (target.x - pos.x) * alignForce
                forces[node.id]!.y += (target.y - pos.y) * alignForce
            }
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
            
            .sheet(isPresented: $showTranscriptSheet) {
                NavigationView {
                    VStack(spacing: 0) {
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
                                    if let id = thoughtId { HistoryManager.shared.updateTranscript(id: id, newTranscript: newValue) }
                                }
                        }
                        .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
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

struct NodeMinimalView: View {
    let node: ThoughtNode
    let isSelected: Bool
    let isVisible: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            // 根据要求，主线节点常态下也显示专属颜色
            Text(node.label)
                .font(.system(size: node.isMainline ? 18 : 15, weight: .semibold, design: .serif))
                .foregroundColor(
                    isSelected ? .white :
                    (node.isMainline ? typeColor(for: node.type) : Color.white.opacity(0.6))
                )
                .multilineTextAlignment(.center)
            
            if isSelected {
                VStack(spacing: 4) {
                    Text(node.type.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(typeColor(for: node.type).opacity(0.2))
                        .foregroundColor(typeColor(for: node.type).opacity(0.9))
                        .cornerRadius(4)
                    
                    Text(node.detail)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 130)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.001))
        .scaleEffect(isVisible ? 1.0 : 0.001)
        .opacity(isVisible ? 1.0 : 0)
    }
    
    private func typeColor(for type: String) -> Color {
        switch type.lowercased() {
        case "problem": return Color(red: 1.0, green: 0.4, blue: 0.4)
        case "solution": return Color(red: 0.4, green: 0.9, blue: 0.5)
        case "idea", "pros": return Color(red: 0.1, green: 0.8, blue: 1.0)
        default: return .gray
        }
    }
}

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
//struct ThoughtGraph: Codable { let topic: String; let summary: String; let nodes: [ThoughtNode]; let edges: [ThoughtEdge] }
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
//    func loadJSON(_ jsonString: String) {
//        if let data = jsonString.data(using: .utf8), let decoded = try? JSONDecoder().decode(ThoughtGraph.self, from: data) { self.graph = decoded }
//    }
//    private func loadMockJSON() { loadJSON("{ \"topic\": \"未连接大模型\", \"nodes\": [ { \"id\": \"1\", \"label\": \"请检查设置\", \"type\": \"problem\", \"detail\": \"没有传入有效JSON\", \"isMainline\": true } ], \"edges\": [] }") }
//    
//    func updateSkeleton(size: CGSize) {
//        guard let graph = graph else { return }
//        self.graphSize = size
//        let mainlines = graph.nodes.filter { $0.isMainline }
//        let isLandscape = size.width > size.height
//        let step = (isLandscape ? size.width : size.height) / CGFloat(mainlines.count + 1)
//        for (index, node) in mainlines.enumerated() {
//            let position = CGFloat(index + 1) * step
//            let target = isLandscape ? CGPoint(x: position, y: size.height / 2) : CGPoint(x: size.width / 2, y: position)
//            mainlineTargets[node.id] = target
//            if nodePositions[node.id] == nil { nodePositions[node.id] = target; velocities[node.id] = .zero }
//        }
//        let branches = graph.nodes.filter { !$0.isMainline }
//        for branch in branches {
//            if nodePositions[branch.id] == nil {
//                if let edge = graph.edges.first(where: { $0.target == branch.id }), let sourceTarget = mainlineTargets[edge.source] {
//                    nodePositions[branch.id] = CGPoint(x: sourceTarget.x + CGFloat.random(in: -40...40), y: sourceTarget.y + CGFloat.random(in: -40...40))
//                } else { nodePositions[branch.id] = CGPoint(x: size.width/2, y: size.height/2) }
//                velocities[branch.id] = .zero
//            }
//        }
//    }
//    
//    func animateIn() {
//        guard let graph = graph else { return }
//        visibleNodes.removeAll()
//        let sortedNodes = graph.nodes.sorted { if $0.isMainline == $1.isMainline { return $0.id < $1.id }; return $0.isMainline && !$1.isMainline }
//        for (index, node) in sortedNodes.enumerated() { DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.12) { withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { _ = self.visibleNodes.insert(node.id) } } }
//    }
//    
//    func startPhysicsEngine() { displayLinkTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.calculatePhysicsTick() } }
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
//            if !node.isMainline { forces[node.id]!.x += (center.x - pos.x) * gravityForce; forces[node.id]!.y += (center.y - pos.y) * gravityForce }
//            for other in graph.nodes where other.id != node.id {
//                guard let otherPos = nodePositions[other.id] else { continue }
//                let dx = pos.x - otherPos.x; let dy = pos.y - otherPos.y
//                let dist = max(sqrt(dx*dx + dy*dy), 20)
//                let force = repulsionForce / (dist * dist)
//                forces[node.id]!.x += (dx / dist) * force; forces[node.id]!.y += (dy / dist) * force
//            }
//            forces[node.id]!.x += CGFloat(sin(time * 1.5 + Double(index))) * 0.4; forces[node.id]!.y += CGFloat(cos(time * 1.2 + Double(index))) * 0.5
//            if node.isMainline, let target = mainlineTargets[node.id] { forces[node.id]!.x += (target.x - pos.x) * skeletonForce; forces[node.id]!.y += (target.y - pos.y) * skeletonForce }
//        }
//        for edge in graph.edges {
//            guard let sourcePos = nodePositions[edge.source], let targetPos = nodePositions[edge.target] else { continue }
//            let dx = targetPos.x - sourcePos.x; let dy = targetPos.y - sourcePos.y
//            let dist = max(sqrt(dx*dx + dy*dy), 10)
//            let force = (dist - linkLength) * attractionForce
//            let fx = (dx / dist) * force; let fy = (dy / dist) * force
//            forces[edge.source]!.x += fx; forces[edge.source]!.y += fy; forces[edge.target]!.x -= fx; forces[edge.target]!.y -= fy
//        }
//        for node in graph.nodes {
//            if isDraggingNode == node.id { nodePositions[node.id] = dragTarget; velocities[node.id] = .zero; continue }
//            var vel = velocities[node.id] ?? .zero; let f = forces[node.id] ?? .zero
//            vel.x = min(max((vel.x + f.x) * friction, -15.0), 15.0); vel.y = min(max((vel.y + f.y) * friction, -15.0), 15.0)
//            velocities[node.id] = vel
//            if let pos = nodePositions[node.id] { nodePositions[node.id] = CGPoint(x: pos.x + vel.x, y: pos.y + vel.y) }
//        }
//    }
//}
//
//struct ThoughtGraphView: View {
//    @Environment(\.dismiss) private var dismiss
//    @StateObject var viewModel: GraphViewModel
//    
//    let transcript: String
//    let onContinue: (() -> Void)?
//    
//    // 【修改】加入音频控制、时长和绑定记录 ID
//    @StateObject private var player: RecordingAudioPlayer
//    @State private var editableTranscript: String
//    let duration: TimeInterval
//    let thoughtId: UUID?
//    
//    @State private var showTranscriptSheet = false
//    
//    init(jsonString: String = "", transcript: String = "", audioURL: URL? = nil, duration: TimeInterval = 0, thoughtId: UUID? = nil, onContinue: (() -> Void)? = nil) {
//        _viewModel = StateObject(wrappedValue: GraphViewModel(jsonString: jsonString))
//        self.transcript = transcript
//        self.duration = duration
//        self.thoughtId = thoughtId
//        self.onContinue = onContinue
//        _editableTranscript = State(initialValue: transcript)
//        
//        if let url = audioURL {
//            _player = StateObject(wrappedValue: RecordingAudioPlayer(url: url))
//        } else {
//            let dummy = URL(fileURLWithPath: NSTemporaryDirectory())
//            _player = StateObject(wrappedValue: RecordingAudioPlayer(url: dummy))
//        }
//    }
//    
//    @State private var scale: CGFloat = 1.0
//    @State private var offset: CGSize = .zero
//    @State private var lastScale: CGFloat = 1.0
//    @State private var lastOffset: CGSize = .zero
//    @State private var dragStartPositions: [String: CGPoint] = [:]
//    
//    var combinedGesture: some Gesture {
//        let drag = DragGesture().onChanged { value in self.offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height) }.onEnded { _ in self.lastOffset = self.offset }
//        let mag = MagnificationGesture().onChanged { value in self.scale = lastScale * value.magnitude }.onEnded { _ in self.lastScale = self.scale }
//        return drag.simultaneously(with: mag)
//    }
//    
//    var body: some View {
//        NavigationView {
//            GeometryReader { geometry in
//                ZStack {
//                    Color.black.ignoresSafeArea().gesture(combinedGesture).onTapGesture { withAnimation(.spring()) { viewModel.selectedNodeIDs.removeAll(); viewModel.selectedEdgeIDs.removeAll() } }
//                    ZStack {
//                        if let graph = viewModel.graph {
//                            ForEach(graph.edges) { edge in EdgeView(edge: edge, viewModel: viewModel) }
//                            ForEach(graph.nodes) { node in
//                                if let position = viewModel.nodePositions[node.id] {
//                                    NodeMinimalView(node: node, isSelected: viewModel.selectedNodeIDs.contains(node.id), isVisible: viewModel.visibleNodes.contains(node.id))
//                                        .position(position)
//                                        .gesture(DragGesture().onChanged { v in viewModel.isDraggingNode = node.id; if dragStartPositions[node.id] == nil { dragStartPositions[node.id] = position }; let c = scale == 0 ? 1 : scale; viewModel.dragTarget = CGPoint(x: dragStartPositions[node.id]!.x + v.translation.width / c, y: dragStartPositions[node.id]!.y + v.translation.height / c) }.onEnded { _ in viewModel.isDraggingNode = nil; dragStartPositions.removeValue(forKey: node.id) })
//                                        .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { if viewModel.selectedNodeIDs.contains(node.id) { _ = viewModel.selectedNodeIDs.remove(node.id) } else { _ = viewModel.selectedNodeIDs.insert(node.id) }; triggerHapticFeedback() } }
//                                }
//                            }
//                        }
//                    }
//                    .scaleEffect(scale).offset(offset)
//                    
//                    VStack {
//                        Spacer()
//                        HStack(spacing: 24) {
//                            if !transcript.isEmpty {
//                                Button(action: { showTranscriptSheet = true }) {
//                                    HStack { Image(systemName: "doc.text"); Text("回顾原文") }.font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(.white).padding(.horizontal, 20).padding(.vertical, 12).background(Color.white.opacity(0.15)).clipShape(Capsule()).shadow(color: .black.opacity(0.3), radius: 8)
//                                }
//                            }
//                            if let continueAction = onContinue {
//                                Button(action: { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { continueAction() } }) {
//                                    HStack { Image(systemName: "mic.fill"); Text("继续思考") }.font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(.black).padding(.horizontal, 20).padding(.vertical, 12).background(Color(red: 0.1, green: 0.8, blue: 1.0)).clipShape(Capsule()).shadow(color: Color(red: 0.1, green: 0.8, blue: 1.0).opacity(0.4), radius: 8)
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
//            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill").foregroundColor(.white.opacity(0.7)) } } }
//            
//            // 【修改】升级的回顾界面：包含播放器和可编辑的 TextField
//            .sheet(isPresented: $showTranscriptSheet) {
//                NavigationView {
//                    VStack(spacing: 0) {
//                        // 播放器组件
//                        if player.duration > 0 || duration > 0 {
//                            AudioPlayerPanel(player: player, duration: duration)
//                                .padding(.horizontal, 24)
//                                .padding(.top, 24)
//                        }
//                        
//                        ScrollView {
//                            TextField("记录内容", text: $editableTranscript, axis: .vertical)
//                                .font(.system(size: 16, design: .serif))
//                                .lineSpacing(8)
//                                .foregroundColor(.white.opacity(0.85))
//                                .padding(24)
//                                .frame(maxWidth: .infinity, alignment: .leading)
//                                .onChange(of: editableTranscript) { newValue in
//                                    // 用户一旦修改，自动同步到历史记录
//                                    if let id = thoughtId {
//                                        HistoryManager.shared.updateTranscript(id: id, newTranscript: newValue)
//                                    }
//                                }
//                        }
//                        .onTapGesture {
//                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
//                        }
//                    }
//                    .background(Color(white: 0.05).ignoresSafeArea())
//                    .navigationTitle("原始记录")
//                    .navigationBarTitleDisplayMode(.inline)
//                    .toolbarColorScheme(.dark, for: .navigationBar)
//                    .toolbarBackground(Color(white: 0.05), for: .navigationBar)
//                    .toolbarBackground(.visible, for: .navigationBar)
//                    .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("关闭") { showTranscriptSheet = false; player.stop() }.foregroundColor(Color(red: 0.1, green: 0.8, blue: 1.0)) } }
//                }
//                .presentationDetents([.medium, .large])
//                .onDisappear { player.stop() }
//            }
//        }
//    }
//    private func triggerHapticFeedback() { let generator = UIImpactFeedbackGenerator(style: .light); generator.prepare(); generator.impactOccurred() }
//}
//
//struct EdgeView: View { let edge: ThoughtEdge; @ObservedObject var viewModel: GraphViewModel; var body: some View { let isVisible = viewModel.visibleNodes.contains(edge.source) && viewModel.visibleNodes.contains(edge.target); if let startPos = viewModel.nodePositions[edge.source], let endPos = viewModel.nodePositions[edge.target] { let isSelected = viewModel.selectedEdgeIDs.contains(edge.id); let midPoint = CGPoint(x: (startPos.x + endPos.x) / 2, y: (startPos.y + endPos.y) / 2); ZStack { Path { path in path.move(to: startPos); path.addCurve(to: endPos, control1: CGPoint(x: startPos.x, y: (startPos.y + endPos.y)/2), control2: CGPoint(x: endPos.x, y: (startPos.y + endPos.y)/2)) }.stroke(Color.white.opacity(0.001), lineWidth: 40).onTapGesture { withAnimation(.spring()) { if viewModel.selectedEdgeIDs.contains(edge.id) { _ = viewModel.selectedEdgeIDs.remove(edge.id) } else { _ = viewModel.selectedEdgeIDs.insert(edge.id) } } }; Path { path in path.move(to: startPos); path.addCurve(to: endPos, control1: CGPoint(x: startPos.x, y: (startPos.y + endPos.y)/2), control2: CGPoint(x: endPos.x, y: (startPos.y + endPos.y)/2)) }.stroke(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.25), style: StrokeStyle(lineWidth: isSelected ? 2.5 : 1.5, dash: [5])).allowsHitTesting(false); if isSelected { Text(edge.relation).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundColor(Color.white).shadow(color: Color.black, radius: 2, x: 0, y: 0).shadow(color: Color.black, radius: 2, x: 0, y: 0).position(midPoint).transition(.opacity.animation(.easeInOut(duration: 0.2))) } }.opacity(isVisible ? 1 : 0) } } }
//struct NodeMinimalView: View { let node: ThoughtNode; let isSelected: Bool; let isVisible: Bool; var body: some View { VStack(spacing: 8) { Text(node.label).font(.system(size: node.isMainline ? 18 : 15, weight: .semibold, design: .serif)).foregroundColor(Color.white.opacity(isSelected ? 1.0 : (node.isMainline ? 0.9 : 0.6))).multilineTextAlignment(.center); if isSelected { VStack(spacing: 4) { Text(node.type.uppercased()).font(.system(size: 9, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 2).background(typeColor(for: node.type).opacity(0.2)).foregroundColor(typeColor(for: node.type).opacity(0.9)).cornerRadius(4); Text(node.detail).font(.system(size: 11, weight: .regular)).foregroundColor(.white.opacity(0.7)).multilineTextAlignment(.center).frame(maxWidth: 130) }.transition(.move(edge: .top).combined(with: .opacity)) } }.padding(14).background(Color.white.opacity(0.001)).scaleEffect(isVisible ? 1.0 : 0.001).opacity(isVisible ? 1.0 : 0) }; private func typeColor(for type: String) -> Color { switch type { case "problem": return Color(red: 1.0, green: 0.4, blue: 0.4); case "solution": return Color(red: 0.4, green: 0.9, blue: 0.5); case "idea", "pros": return Color(red: 0.1, green: 0.8, blue: 1.0); default: return .gray } } }
//
//// 供回顾界面使用的音频控制面板
//private struct AudioPlayerPanel: View {
//    @ObservedObject var player: RecordingAudioPlayer
//    let duration: TimeInterval
//    var body: some View {
//        HStack(spacing: 16) {
//            Button(action: player.togglePlayback) {
//                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
//                    .font(.system(size: 15, weight: .medium)).frame(width: 42, height: 42).foregroundStyle(Color.black).background(Color.white.opacity(0.9), in: Circle()).contentShape(Circle())
//            }.buttonStyle(.plain)
//            VStack(spacing: 9) {
//                Slider(value: $player.currentTime, in: 0...max(player.duration, duration, 0.1)) { editing in player.setScrubbing(editing) }.tint(Color(red: 0.1, green: 0.8, blue: 1.0))
//                HStack { Text(Self.timeString(player.currentTime)); Spacer(); Text(Self.timeString(max(player.duration, duration))) }.font(.system(size: 11, weight: .medium, design: .rounded)).tracking(0).foregroundStyle(Color.white.opacity(0.6))
//            }
//        }.padding(.vertical, 14).padding(.horizontal, 16).background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
//    }
//    private static func timeString(_ interval: TimeInterval) -> String { guard interval.isFinite else { return "0:00" }; let s = max(0, Int(interval.rounded())); return "\(s / 60):\(String(format: "%02d", s % 60))" }
//}
