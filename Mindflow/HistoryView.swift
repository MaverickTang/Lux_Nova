//
//  HistoryView.swift
//  Mindflow
//
//  Created by Maverick Tang on 2026/8/16.
//


//
//  HistoryView.swift
//  Mindflow
//

import SwiftUI

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = HistoryManager.shared
    
    // 用于在历史界面拉起详情图谱
    @State private var selectedGraphJSON: String = ""
    @State private var showGraph = false
    
    // 双列网格布局
    let columns = [GridItem(.flexible()), GridItem(.flexible())]
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if manager.savedThoughts.isEmpty {
                    Text("宇宙寂静无声。\n尚未捕捉到任何闪念。")
                        .font(.system(size: 14, weight: .light, design: .serif))
                        .foregroundColor(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .lineSpacing(8)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 40) {
                            ForEach(manager.savedThoughts) { thought in
                                HistoryOrbNode(thought: thought) { json in
                                    selectedGraphJSON = json
                                    showGraph = true
                                }
                            }
                        }
                        .padding(.vertical, 40)
                        .padding(.horizontal, 24)
                    }
                }
            }
            .navigationTitle("意识星海")
            .navigationBarTitleDisplayMode(.inline)
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
            // 嵌套拉起图谱视图
            .sheet(isPresented: $showGraph) {
                ThoughtGraphView(jsonString: selectedGraphJSON)
            }
        }
    }
}

private struct HistoryOrbNode: View {
    let thought: SavedThought
    let onOpen: (String) -> Void
    
    // 状态机：是否处于第一阶段（已唤醒）
    @State private var isActivated = false
    
    var body: some View {
        VStack(spacing: 16) {
            // 1. 悬浮的 Topic (仅唤醒时显示)
            Text(thought.topic)
                .font(.system(size: 15, weight: .medium, design: .serif))
                .foregroundColor(.white)
                .opacity(isActivated ? 1 : 0)
                .offset(y: isActivated ? 0 : 10)
            
            // 2. 光团本体
            ZStack {
                let color = colorForTopic(thought.topic)
                
                // 外围辉光 (唤醒时放大并呼吸)
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [color.opacity(isActivated ? 0.6 : 0.3), Color.black.opacity(0.0)]),
                            center: .center,
                            startRadius: 0,
                            endRadius: isActivated ? 70 : 50
                        )
                    )
                    .frame(width: 140, height: 140)
                    .scaleEffect(isActivated ? 1.1 : 1.0)
                    .animation(isActivated ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true) : .easeOut, value: isActivated)
                
                // 核心星点
                Circle()
                    .fill(Color.white.opacity(isActivated ? 1.0 : 0.5))
                    .frame(width: isActivated ? 6 : 4, height: isActivated ? 6 : 4)
                    .shadow(color: color, radius: 4)
            }
            .contentShape(Circle())
            .onTapGesture {
                handleTap()
            }
            
            // 3. 时间戳
            Text(formatDate(thought.date))
                .font(.system(size: 11, weight: .light, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isActivated)
    }
    
    private func handleTap() {
        if isActivated {
            // 第二次点击：执行转场
            onOpen(thought.graphJSON)
            isActivated = false // 重置状态
        } else {
            // 第一次点击：唤醒光团
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            isActivated = true
            
            // 5秒后如果不操作，自动休眠
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                isActivated = false
            }
        }
    }
    
    // 核心算法：通过 Topic 的哈希值映射出一个固定的科技感颜色
    private func colorForTopic(_ topic: String) -> Color {
        var hash = 0
        for char in topic.utf8 {
            hash = (hash << 5) &- hash &+ Int(char)
        }
        // 保证色相在 0.0 ~ 1.0 之间
        let hue = Double(abs(hash) % 360) / 360.0
        // 保持高饱和度与明度，确保在黑底上发光
        return Color(hue: hue, saturation: 0.85, brightness: 0.95)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM.dd HH:mm"
        return formatter.string(from: date)
    }
}