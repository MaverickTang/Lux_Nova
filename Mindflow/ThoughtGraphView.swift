//
//  ThoughtGraphView.swift
//  Mindflow
//

import SwiftUI
import Combine
import Foundation

// MARK: - 1. 数据模型
struct ThoughtGraph: Codable {
    let topic: String
    let nodes: [ThoughtNode]
    let edges: [ThoughtEdge]
}

struct ThoughtNode: Codable, Identifiable {
    let id: String
    let label: String
    let type: String
    let detail: String
    let isMainline: Bool
}

struct ThoughtEdge: Codable, Identifiable {
    var id: String { source + "-" + target }
    let source: String
    let target: String
    let relation: String
}

// MARK: - 2. 具有真实物理引擎的视图模型
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
    
    // 【修改】初始化时接收 JSON 字符串
    init(jsonString: String? = nil) {
        if let json = jsonString, !json.isEmpty {
            loadJSON(json)
        } else {
            loadMockJSON()
        }
    }
    
    // 【修改】解析外部传入的 JSON
    func loadJSON(_ jsonString: String) {
        if let data = jsonString.data(using: .utf8) {
            if let decoded = try? JSONDecoder().decode(ThoughtGraph.self, from: data) {
                self.graph = decoded
            } else {
                print("JSON 解析失败，请检查 LLM 输出格式")
            }
        }
    }
    
    // 预留的 Mock 数据（当没有传入数据时使用）
    private func loadMockJSON() {
        let jsonString = """
        {
          "topic": "未连接大模型",
          "nodes": [
            { "id": "1", "label": "请检查设置", "type": "problem", "detail": "没有传入有效JSON", "isMainline": true }
          ],
          "edges": []
        }
        """
        loadJSON(jsonString)
    }
    
    // ... (后续的 updateSkeleton, animateIn 等物理引擎代码保持不变)

//// MARK: - 2. 具有真实物理引擎的视图模型
//class GraphViewModel: ObservableObject {
//    @Published var graph: ThoughtGraph?
//    @Published var nodePositions: [String: CGPoint] = [:]
//    
//    @Published var selectedNodeIDs: Set<String> = []
//    @Published var selectedEdgeIDs: Set<String> = []
//    @Published var visibleNodes: Set<String> = []
//    
//    // --- 物理引擎相关状态 ---
//    private var velocities: [String: CGPoint] = [:]
//    private var mainlineTargets: [String: CGPoint] = [:] // [新增] 主轴骨架锚点
//    private var displayLinkTimer: AnyCancellable?
//    
//    var isDraggingNode: String? = nil
//    var dragTarget: CGPoint = .zero
//    var graphSize: CGSize = .zero
//    
//    init() {
//        loadJSON()
//    }
//    
//    func loadJSON() {
//        let jsonString = """
//        {
//          "topic": "冥想辅助闪念胶囊",
//          "nodes": [
//            { "id": "1", "label": "表达的痛点", "type": "problem", "detail": "嘴巴跟不上大脑", "isMainline": true },
//            { "id": "2", "label": "冥想闪念胶囊", "type": "solution", "detail": "极简记录软件", "isMainline": true },
//            { "id": "3", "label": "极简三按钮", "type": "idea", "detail": "仅保留核心功能", "isMainline": true },
//            { "id": "4", "label": "无时长限制", "type": "pros", "detail": "支持持续记录", "isMainline": false },
//            { "id": "5", "label": "录制功能", "type": "idea", "detail": "一键录制转文字", "isMainline": false },
//            { "id": "6", "label": "思维打点", "type": "idea", "detail": "标记核心节点", "isMainline": false },
//            { "id": "7", "label": "发散扩展", "type": "idea", "detail": "AI 关联发散", "isMainline": false },
//            { "id": "8", "label": "思维流分析", "type": "solution", "detail": "可视化推导", "isMainline": true },
//            { "id": "9", "label": "知识图谱", "type": "idea", "detail": "自动构建思维模型", "isMainline": true }
//          ],
//          "edges": [
//            { "source": "1", "target": "2", "relation": "促生灵感" },
//            { "source": "2", "target": "3", "relation": "设计原则" },
//            { "source": "2", "target": "4", "relation": "体验优化" },
//            { "source": "3", "target": "5", "relation": "拆解一" },
//            { "source": "3", "target": "6", "relation": "拆解二" },
//            { "source": "3", "target": "7", "relation": "拆解三" },
//            { "source": "3", "target": "8", "relation": "核心推导" },
//            { "source": "8", "target": "9", "relation": "演进" }
//          ]
//        }
//        """
//        
//        if let data = jsonString.data(using: .utf8) {
//            if let decoded = try? JSONDecoder().decode(ThoughtGraph.self, from: data) {
//                self.graph = decoded
//            }
//        }
//    }
    
    // [修改] 构建主轴骨架并初始化坐标
    func updateSkeleton(size: CGSize) {
        guard let graph = graph else { return }
        self.graphSize = size
        
        let mainlines = graph.nodes.filter { $0.isMainline }
        let isLandscape = size.width > size.height
        let step = (isLandscape ? size.width : size.height) / CGFloat(mainlines.count + 1)
        
        // 1. 计算主线锚点
        for (index, node) in mainlines.enumerated() {
            let position = CGFloat(index + 1) * step
            let target = isLandscape ? CGPoint(x: position, y: size.height / 2) : CGPoint(x: size.width / 2, y: position)
            mainlineTargets[node.id] = target
            
            if nodePositions[node.id] == nil {
                nodePositions[node.id] = target
                velocities[node.id] = .zero
            }
        }
        
        // 2. 随机散布旁支节点，等待物理引擎将它们推开
        let branches = graph.nodes.filter { !$0.isMainline }
        for branch in branches {
            if nodePositions[branch.id] == nil {
                if let edge = graph.edges.first(where: { $0.target == branch.id }), let sourceTarget = mainlineTargets[edge.source] {
                    nodePositions[branch.id] = CGPoint(x: sourceTarget.x + CGFloat.random(in: -40...40),
                                                       y: sourceTarget.y + CGFloat.random(in: -40...40))
                } else {
                    nodePositions[branch.id] = CGPoint(x: size.width/2, y: size.height/2)
                }
                velocities[branch.id] = .zero
            }
        }
    }
    
    func animateIn() {
        guard let graph = graph else { return }
        visibleNodes.removeAll()
        
        let sortedNodes = graph.nodes.sorted {
            if $0.isMainline == $1.isMainline { return $0.id < $1.id }
            return $0.isMainline && !$1.isMainline
        }
        
        for (index, node) in sortedNodes.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.12) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    _ = self.visibleNodes.insert(node.id)
                }
            }
        }
    }
    
    // --- 核心：力导向物理引擎循环 ---
    func startPhysicsEngine() {
        displayLinkTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.calculatePhysicsTick()
            }
    }
    
    func stopPhysicsEngine() {
        displayLinkTimer?.cancel()
    }
    
    private func calculatePhysicsTick() {
        guard let graph = graph, graphSize.width > 0 else { return }
        
        let center = CGPoint(x: graphSize.width / 2, y: graphSize.height / 2)
        var forces: [String: CGPoint] = [:]
        let time = Date().timeIntervalSince1970
        
        let gravityForce: CGFloat = 0.003
//        let attractionForce: CGFloat = 0.03
        let linkLength: CGFloat = 110.0
        let friction: CGFloat = 0.75
        let skeletonForce: CGFloat = 0.08 // [新增] 主轴骨架的强向心力
//        let repulsionForce: CGFloat = 4000.0
        
        // --- 动态读取引力与排斥力 ---
        let savedRepulsion = UserDefaults.standard.object(forKey: "physics_repulsion") as? Double
        let repulsionForce = savedRepulsion != nil ? CGFloat(savedRepulsion!) : 4000.0
        let savedAttraction = UserDefaults.standard.object(forKey: "physics_attraction") as? Double
        let attractionForce = savedAttraction != nil ? CGFloat(savedAttraction!) : 0.03
        
        for (index, node) in graph.nodes.enumerated() {
            forces[node.id] = .zero
            guard let pos = nodePositions[node.id] else { continue }
            
            // 基础引力与排斥力
            if !node.isMainline {
                forces[node.id]!.x += (center.x - pos.x) * gravityForce
                forces[node.id]!.y += (center.y - pos.y) * gravityForce
            }
            
            for other in graph.nodes where other.id != node.id {
                guard let otherPos = nodePositions[other.id] else { continue }
                let dx = pos.x - otherPos.x
                let dy = pos.y - otherPos.y
                let distSq = dx*dx + dy*dy
                let dist = max(sqrt(distSq), 20)
                
                let force = repulsionForce / (dist * dist)
                forces[node.id]!.x += (dx / dist) * force
                forces[node.id]!.y += (dy / dist) * force
            }
            
            // 呼吸感微扰动
            let breathX = CGFloat(sin(time * 1.5 + Double(index))) * 0.4
            let breathY = CGFloat(cos(time * 1.2 + Double(index))) * 0.5
            forces[node.id]!.x += breathX
            forces[node.id]!.y += breathY
            
            // [新增] 骨架约束力：主线节点受到极强的力量被拉回属于自己的位置
            if node.isMainline, let target = mainlineTargets[node.id] {
                forces[node.id]!.x += (target.x - pos.x) * skeletonForce
                forces[node.id]!.y += (target.y - pos.y) * skeletonForce
            }
        }
        
        for edge in graph.edges {
            guard let sourcePos = nodePositions[edge.source],
                  let targetPos = nodePositions[edge.target] else { continue }
            
            let dx = targetPos.x - sourcePos.x
            let dy = targetPos.y - sourcePos.y
            let dist = max(sqrt(dx*dx + dy*dy), 10)
            
            let force = (dist - linkLength) * attractionForce
            let fx = (dx / dist) * force
            let fy = (dy / dist) * force
            
            forces[edge.source]!.x += fx
            forces[edge.source]!.y += fy
            forces[edge.target]!.x -= fx
            forces[edge.target]!.y -= fy
        }
        
        for node in graph.nodes {
            if isDraggingNode == node.id {
                nodePositions[node.id] = dragTarget
                velocities[node.id] = .zero
                continue
            }
            
            var vel = velocities[node.id] ?? .zero
            let f = forces[node.id] ?? .zero
            
            vel.x = (vel.x + f.x) * friction
            vel.y = (vel.y + f.y) * friction
            
            let maxVel: CGFloat = 15.0
            vel.x = min(max(vel.x, -maxVel), maxVel)
            vel.y = min(max(vel.y, -maxVel), maxVel)
            
            velocities[node.id] = vel
            
            if let pos = nodePositions[node.id] {
                nodePositions[node.id] = CGPoint(x: pos.x + vel.x, y: pos.y + vel.y)
            }
        }
    }
}

// MARK: - 3. 视图层 (纯黑修改)
struct ThoughtGraphView: View {
    @Environment(\.dismiss) private var dismiss
//    @StateObject var viewModel = GraphViewModel()
    @StateObject var viewModel: GraphViewModel
    
    init(jsonString: String = "") {
            _viewModel = StateObject(wrappedValue: GraphViewModel(jsonString: jsonString))
    }
    
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    
    @State private var dragStartPositions: [String: CGPoint] = [:]
    
    var combinedGesture: some Gesture {
        let drag = DragGesture()
            .onChanged { value in
                self.offset = CGSize(width: lastOffset.width + value.translation.width,
                                     height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in
                self.lastOffset = self.offset
            }
        
        let mag = MagnificationGesture()
            .onChanged { value in
                self.scale = lastScale * value.magnitude
            }
            .onEnded { _ in
                self.lastScale = self.scale
            }
        
        return drag.simultaneously(with: mag)
    }
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    // 1. 图谱背景改为纯黑
                    Color.black
                        .ignoresSafeArea()
                        .gesture(combinedGesture)
                        .onTapGesture {
                            withAnimation(.spring()) {
                                viewModel.selectedNodeIDs.removeAll()
                                viewModel.selectedEdgeIDs.removeAll()
                            }
                        }
                    
                    ZStack {
                        if let graph = viewModel.graph {
                            ForEach(graph.edges) { edge in
                                EdgeView(edge: edge, viewModel: viewModel)
                            }
                            
                            ForEach(graph.nodes) { node in
                                if let position = viewModel.nodePositions[node.id] {
                                    NodeMinimalView(node: node,
                                                    isSelected: viewModel.selectedNodeIDs.contains(node.id),
                                                    isVisible: viewModel.visibleNodes.contains(node.id))
                                        .position(position)
                                        .gesture(
                                            DragGesture()
                                                .onChanged { value in
                                                    viewModel.isDraggingNode = node.id
                                                    if dragStartPositions[node.id] == nil {
                                                        dragStartPositions[node.id] = position
                                                    }
                                                    let currentScale = scale == 0 ? 1 : scale
                                                    viewModel.dragTarget = CGPoint(
                                                        x: dragStartPositions[node.id]!.x + value.translation.width / currentScale,
                                                        y: dragStartPositions[node.id]!.y + value.translation.height / currentScale
                                                    )
                                                }
                                                .onEnded { _ in
                                                    viewModel.isDraggingNode = nil
                                                    dragStartPositions.removeValue(forKey: node.id)
                                                }
                                        )
                                        .onTapGesture {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                if viewModel.selectedNodeIDs.contains(node.id) {
                                                    _ = viewModel.selectedNodeIDs.remove(node.id)
                                                } else {
                                                    _ = viewModel.selectedNodeIDs.insert(node.id)
                                                }
                                                triggerHapticFeedback()
                                            }
                                        }
                                }
                            }
                        }
                    }
                    .scaleEffect(scale)
                    .offset(offset)
                }
                .onAppear {
                    viewModel.updateSkeleton(size: geometry.size)
                    viewModel.animateIn()
                    viewModel.startPhysicsEngine()
                }
                .onDisappear {
                    viewModel.stopPhysicsEngine()
                }
                .onChange(of: geometry.size) { newSize in
                    viewModel.updateSkeleton(size: newSize)
                }
            }
            .navigationTitle(viewModel.graph?.topic ?? "思维流向")
            .navigationBarTitleDisplayMode(.inline)
            // 确保导航栏是黑底白字
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.white.opacity(0.7))
                    }
                }
            }
        }
    }
    
    private func triggerHapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }
}

// MARK: - 4. 极简连线组件 (纯黑修改)
struct EdgeView: View {
    let edge: ThoughtEdge
    @ObservedObject var viewModel: GraphViewModel
    
    var body: some View {
        let isVisible = viewModel.visibleNodes.contains(edge.source) && viewModel.visibleNodes.contains(edge.target)
        
        if let startPos = viewModel.nodePositions[edge.source],
           let endPos = viewModel.nodePositions[edge.target] {
            
            let isSelected = viewModel.selectedEdgeIDs.contains(edge.id)
            let midPoint = CGPoint(x: (startPos.x + endPos.x) / 2, y: (startPos.y + endPos.y) / 2)
            
            ZStack {
                // 点击热区
                Path { path in
                    path.move(to: startPos)
                    path.addCurve(to: endPos, control1: CGPoint(x: startPos.x, y: (startPos.y + endPos.y)/2), control2: CGPoint(x: endPos.x, y: (startPos.y + endPos.y)/2))
                }
                .stroke(Color.white.opacity(0.001), lineWidth: 40)
                .onTapGesture {
                    withAnimation(.spring()) {
                        if viewModel.selectedEdgeIDs.contains(edge.id) {
                            _ = viewModel.selectedEdgeIDs.remove(edge.id)
                        } else {
                            _ = viewModel.selectedEdgeIDs.insert(edge.id)
                        }
                    }
                }
                
                // 实体线条段：未选中为暗白/灰白，选中为高亮白
                Path { path in
                    path.move(to: startPos)
                    path.addCurve(to: endPos, control1: CGPoint(x: startPos.x, y: (startPos.y + endPos.y)/2), control2: CGPoint(x: endPos.x, y: (startPos.y + endPos.y)/2))
                }
                .stroke(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.25),
                        style: StrokeStyle(lineWidth: isSelected ? 2.5 : 1.5, dash: [5]))
                .allowsHitTesting(false)
                
                if isSelected {
                    // 线条文字描述
                    Text(edge.relation)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.white) // 文字变为纯白
                        .shadow(color: Color.black, radius: 2, x: 0, y: 0) // 描边阴影变为黑色
                        .shadow(color: Color.black, radius: 2, x: 0, y: 0)
                        .position(midPoint)
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                }
            }
            .opacity(isVisible ? 1 : 0)
        }
    }
}

// MARK: - 5. 极简节点组件 (纯黑修改)
struct NodeMinimalView: View {
    let node: ThoughtNode
    let isSelected: Bool
    let isVisible: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            // 节点标题，统一改为白色，靠透明度区分层级
            Text(node.label)
                .font(.system(size: node.isMainline ? 18 : 15, weight: .semibold, design: .serif))
                .foregroundColor(Color.white.opacity(isSelected ? 1.0 : (node.isMainline ? 0.9 : 0.6)))
                .multilineTextAlignment(.center)
            
            if isSelected {
                VStack(spacing: 4) {
                    Text(node.type.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        // 分类标签背景色适应黑底
                        .background(typeColor(for: node.type).opacity(0.2))
                        .foregroundColor(typeColor(for: node.type).opacity(0.9))
                        .cornerRadius(4)
                    
                    Text(node.detail)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.white.opacity(0.7)) // 细节描述改为浅白
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
    
    // 调整分类颜色，使其在纯黑背景下更具科技发光感
    private func typeColor(for type: String) -> Color {
        switch type {
        case "problem": return Color(red: 1.0, green: 0.4, blue: 0.4) // 亮红
        case "solution": return Color(red: 0.4, green: 0.9, blue: 0.5) // 荧光绿
        case "idea", "pros": return Color(red: 0.1, green: 0.8, blue: 1.0) // 亮蓝 (呼应球体)
        default: return .gray
        }
    }
}
