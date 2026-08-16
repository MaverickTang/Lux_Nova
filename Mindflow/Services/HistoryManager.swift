import Foundation
import Combine

struct SavedThought: Identifiable, Codable {
    var id = UUID()
    let date: Date
    var topic: String    // 【修改】改为 var，允许修改名字
    var summary: String?
    var transcript: String
    let graphJSON: String
    var audioFileName: String?
    var duration: TimeInterval?
    var isAnalyzedForLinks: Bool? // 【新增】标记是否已经参与过连线分析
}

struct HistoryEdge: Codable, Identifiable, Equatable {
    var id: String { source + "-" + target }
    let source: String
    let target: String
    let relation: String
}

class HistoryManager: ObservableObject {
    static let shared = HistoryManager()
    @Published var savedThoughts: [SavedThought] = []
    @Published var historyEdges: [HistoryEdge] = []

    private let storageKey = "lux_nova_history_v2"
    private let edgesKey = "lux_nova_history_edges_v1"

    init() {
        load()
        loadEdges()
    }

    func saveThought(transcript: String, graphJSON: String, audioFileName: String?, duration: TimeInterval?) {
        var extractedTopic = "未命名意识"
        var extractedSummary = "暂无摘要"
        
        if let data = graphJSON.data(using: .utf8), let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let topic = dict["topic"] as? String { extractedTopic = topic }
            if let summary = dict["summary"] as? String { extractedSummary = summary }
        }
        
        let newThought = SavedThought(
            date: Date(),
            topic: extractedTopic,
            summary: extractedSummary,
            transcript: transcript,
            graphJSON: graphJSON,
            audioFileName: audioFileName,
            duration: duration,
            isAnalyzedForLinks: false // 新节点默认未分析
        )
        
        savedThoughts.insert(newThought, at: 0)
        save()
    }
    
    // 【新增】修改节点名称
    func updateTopic(id: UUID, newTopic: String) {
        if let index = savedThoughts.firstIndex(where: { $0.id == id }) {
            savedThoughts[index].topic = newTopic
            save()
        }
    }
    
    // 【新增】手动连接或断开两个节点
    func toggleEdge(source: UUID, target: UUID, relation: String = "手动关联") {
        let id1 = source.uuidString + "-" + target.uuidString
        let id2 = target.uuidString + "-" + source.uuidString
        
        // 如果已存在连线，则删除
        if let index = historyEdges.firstIndex(where: { $0.id == id1 || $0.id == id2 }) {
            historyEdges.remove(at: index)
        } else {
            // 否则新建连线
            historyEdges.append(HistoryEdge(source: source.uuidString, target: target.uuidString, relation: relation))
        }
        saveEdges()
    }

    func updateTranscript(id: UUID, newTranscript: String) {
        if let index = savedThoughts.firstIndex(where: { $0.id == id }) {
            savedThoughts[index].transcript = newTranscript
            save()
        }
    }

    func deleteThought(id: UUID) {
        savedThoughts.removeAll { $0.id == id }
        historyEdges.removeAll { $0.source == id.uuidString || $0.target == id.uuidString }
        save()
        saveEdges()
    }
    
    // 【修改】增量同步星系连线：绝不改变已有连线，只将新节点和全局网络发送给AI
    func syncNewThoughtsConnections() async {
        let newThoughts = savedThoughts.filter { $0.isAnalyzedForLinks != true }
        guard !newThoughts.isEmpty else { return } // 没有新节点就不分析
        
        do {
            let newEdges = try await LLMService.shared.generateIncrementalGraph(newThoughts: newThoughts, allThoughts: savedThoughts)
            
            DispatchQueue.main.async {
                self.historyEdges.append(contentsOf: newEdges)
                // 标记已分析
                for i in 0..<self.savedThoughts.count {
                    if self.savedThoughts[i].isAnalyzedForLinks != true {
                        self.savedThoughts[i].isAnalyzedForLinks = true
                    }
                }
                self.saveEdges()
                self.save()
            }
        } catch {
            print("增量连线失败: \(error)")
        }
    }
    
    // 【新增】将现有的连线交给大模型，通过语音指令来增删连线
    func processVoiceCommandToModifyEdges(command: String) async throws {
        let newEdges = try await LLMService.shared.modifyEdgesByVoice(command: command, thoughts: savedThoughts, currentEdges: historyEdges)
        DispatchQueue.main.async {
            self.historyEdges = newEdges
            self.saveEdges()
        }
    }
    
    func getAudioURL(for fileName: String?) -> URL? {
        guard let name = fileName else { return nil }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Recordings", isDirectory: true)
        return directory.appendingPathComponent(name)
    }

    private func save() { if let data = try? JSONEncoder().encode(savedThoughts) { UserDefaults.standard.set(data, forKey: storageKey) } }
    private func load() { if let data = UserDefaults.standard.data(forKey: storageKey), let decoded = try? JSONDecoder().decode([SavedThought].self, from: data) { self.savedThoughts = decoded } }
    private func saveEdges() { if let data = try? JSONEncoder().encode(historyEdges) { UserDefaults.standard.set(data, forKey: edgesKey) } }
    private func loadEdges() { if let data = UserDefaults.standard.data(forKey: edgesKey), let decoded = try? JSONDecoder().decode([HistoryEdge].self, from: data) { self.historyEdges = decoded } }
}


//import Foundation
//import Combine
//
//// 升级的数据模型：新增音频路径和时长
//struct SavedThought: Identifiable, Codable {
//    var id = UUID()
//    let date: Date
////    let topic: String
//    var topic: String // 【修改】改为 var，允许修改名字
//    var summary: String? // 【新增】AI 生成的核心摘要
//    var transcript: String
//    let graphJSON: String
//    var audioFileName: String?
//    var duration: TimeInterval?
//}
//
//// 新增：历史星系图的连线结构
//struct HistoryEdge: Codable, Identifiable {
//    var id: String { source + "-" + target }
//    let source: String
//    let target: String
//    let relation: String
//}
//
//class HistoryManager: ObservableObject {
//    static let shared = HistoryManager()
//    @Published var savedThoughts: [SavedThought] = []
//    @Published var historyEdges: [HistoryEdge] = [] // 存储 LLM 找出的联系
//
//    private let storageKey = "lux_nova_history_v2"
//    private let edgesKey = "lux_nova_history_edges_v1"
//
//    init() {
//        load()
//        loadEdges()
//    }
//
//    // 升级的保存方法
//    func saveThought(transcript: String, graphJSON: String, audioFileName: String?, duration: TimeInterval?) {
//        var extractedTopic = "未命名意识"
//        var extractedSummary = "暂无摘要" // 默认摘要
//        
//        if let data = graphJSON.data(using: .utf8),
//                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
//                    if let topic = dict["topic"] as? String {
//                        extractedTopic = topic
//                    }
//                    // 【新增】从 AI 返回的 JSON 中提取 summary
//                    if let summary = dict["summary"] as? String {
//                        extractedSummary = summary
//                    }
//                }
//        let newThought = SavedThought(
//            date: Date(),
//            topic: extractedTopic,
//            summary: extractedSummary, // 【新增】保存摘要
//            transcript: transcript,
//            graphJSON: graphJSON,
//            audioFileName: audioFileName,
//            duration: duration
//        )
//        
//        savedThoughts.insert(newThought, at: 0)
//        save()
//        
//        // 核心机制：每当有新想法加入，触发大模型重新组织星系连线
//        Task {
//            await reorganizeGalaxy()
//        }
//    }
//    
//    // 支持修改历史记录的文本
//    func updateTranscript(id: UUID, newTranscript: String) {
//        if let index = savedThoughts.firstIndex(where: { $0.id == id }) {
//            savedThoughts[index].transcript = newTranscript
//            save()
//        }
//    }
//
//    func deleteThought(id: UUID) {
//        savedThoughts.removeAll { $0.id == id }
//        // 同时删除与该节点相关的连线
//        historyEdges.removeAll { $0.source == id.uuidString || $0.target == id.uuidString }
//        save()
//        saveEdges()
//    }
//    
//    // 调用 LLM 自动寻找思想之间的联系
//    func reorganizeGalaxy() async {
//        guard savedThoughts.count > 1 else { return }
//        do {
//            let edges = try await LLMService.shared.generateHistoryGraph(thoughts: savedThoughts)
//            DispatchQueue.main.async {
//                self.historyEdges = edges
//                self.saveEdges()
//            }
//        } catch {
//            print("星系重组失败: \(error)")
//        }
//    }
//    
//    // 还原音频真实 URL
//    func getAudioURL(for fileName: String?) -> URL? {
//        guard let name = fileName else { return nil }
//        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
//            .appendingPathComponent("Recordings", isDirectory: true)
//        return directory.appendingPathComponent(name)
//    }
//
//    private func save() {
//        if let data = try? JSONEncoder().encode(savedThoughts) { UserDefaults.standard.set(data, forKey: storageKey) }
//    }
//    private func load() {
//        if let data = UserDefaults.standard.data(forKey: storageKey), let decoded = try? JSONDecoder().decode([SavedThought].self, from: data) {
//            self.savedThoughts = decoded
//        }
//    }
//    private func saveEdges() {
//        if let data = try? JSONEncoder().encode(historyEdges) { UserDefaults.standard.set(data, forKey: edgesKey) }
//    }
//    private func loadEdges() {
//        if let data = UserDefaults.standard.data(forKey: edgesKey), let decoded = try? JSONDecoder().decode([HistoryEdge].self, from: data) {
//            self.historyEdges = decoded
//        }
//    }
//}
