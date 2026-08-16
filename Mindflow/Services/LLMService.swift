//
//  LLMError.swift
//  Mindflow
//
//  Created by Maverick Tang on 2026/8/15.
//


//
//  LLMService.swift
//  Mindflow
//

import Foundation

enum LLMError: Error {
    case invalidURL
    case invalidResponse
    case apiError(String)
    case decodingError
}

class LLMService {
    static let shared = LLMService()
    
    // ⚠️ 请在这里替换为你实际使用的服务商的 API Key 和 Base URL
    // 比如如果是 Kimi: https://api.moonshot.cn/v1/chat/completions (模型名 moonshot-v1-8k)
    // 比如如果是 DeepSeek: https://api.deepseek.com/chat/completions (模型名 deepseek-chat)
//        private let apiKey = "sk-wggosgrabsswfvpvasxfhhiryjjndgyfaoqkinjwnjnnanqw"
//    // 硅基流动 (SiliconFlow) 的标准 OpenAI 兼容端点与模型名称
//        private let endpointURL = "https://api.siliconflow.cn/v1/chat/completions"
//        private let modelName = "deepseek-ai/DeepSeek-R1-0528-Qwen3-8B"
    
    // 从 UserDefaults 动态读取配置
        private var apiKey: String {
            let api=UserDefaults.standard.string(forKey: "llm_api_key") ?? ""
            return api.isEmpty ? "sk-wggosgrabsswfvpvasxfhhiryjjndgyfaoqkinjwnjnnanqw" : api
        }
        
        private var endpointURL: String {
            let url = UserDefaults.standard.string(forKey: "llm_endpoint_url") ?? ""
            return url.isEmpty ? "https://api.siliconflow.cn/v1/chat/completions" : url
        }
        
        private var modelName: String {
            let name = UserDefaults.standard.string(forKey: "llm_model_name") ?? ""
            return name.isEmpty ? "deepseek-ai/DeepSeek-R1-0528-Qwen3-8B" : name
        }
    
    // 获取当前要求 LLM 输出的语言
        private var llmTargetLanguage: String {
            let lang = UserDefaults.standard.string(forKey: "app_language") ?? "system"
            if lang == "en" { return "English" }
            if lang == "zh-Hans" { return "Simplified Chinese" }
            
            // 如果是跟随系统，判断系统第一语言是不是中文
            let systemLang = Locale.preferredLanguages.first ?? "en"
            return systemLang.hasPrefix("zh") ? "Simplified Chinese" : "English"
        }
    
    // 【新增】读取动态热度
        private var temperature: Double {
            let temp = UserDefaults.standard.object(forKey: "llm_temperature") as? Double
            return temp ?? 0.3
        }
        
        private init() {}
        
        func generateThoughtGraph(from text: String) async throws -> String {
            guard let url = URL(string: endpointURL) else {
                throw LLMError.invalidURL
            }
            
            // 允许本地端点无 Key 访问
            let isLocalHost = endpointURL.contains("localhost") || endpointURL.contains("127.0.0.1")
            if apiKey.isEmpty && !isLocalHost {
                throw LLMError.apiError("请先在设置中配置 API Key。")
            }
            let systemPrompt = """
                        你是一个顶级的认知心理学分析系统。你的任务是分析用户的“自言自语”或思维碎片，从中提取出思考的路径，并将其转化为结构化的 JSON 图数据。
                        
                        【规则】
                        1. 识别用户的核心议题(topic)、主要观点(idea)、面临的痛点(problem)、解决方案(solution)或优缺点(pros/cons)。
                        2. 梳理这些节点之间的逻辑关系。你必须构建一个**网状结构**，而不仅仅是单行线。
                        3. 选出一条核心推导链路，将其 isMainline 设为 true。
                        4. 【极其重要】除了主线，你**必须**从文本中提取出发散思维、补充说明或延伸思考，将其 isMainline 设为 false，并将它们作为旁支连接到相关的主线节点上。不要只生成一条直线！
                        5. 根据用户的全段内容，提炼出一段100字以内的核心摘要(summary)。
                        6. 【极度重要】无论用户输入什么语言，你生成的全部内容（包括 topic, summary, label, detail, relation 等）必须使用 \(llmTargetLanguage) 语种输出！！！
                        7. 最终输出必须且只能是合法的 JSON 格式。千万不要包含任何额外的解释文本。
                        
                        【JSON 格式约束样例（请严格遵循键名，并同时包含主线与发散节点）】
                        {
                          "topic": "核心议题的简短提炼",
                          "summary": "100字以内的核心内容摘要",
                          "nodes": [
                            { "id": "1", "label": "核心起点", "type": "problem", "detail": "主线思考的起点", "isMainline": true },
                            { "id": "2", "label": "推导结果", "type": "solution", "detail": "主线思考的结论", "isMainline": true },
                            { "id": "3", "label": "发散联想", "type": "idea", "detail": "由起点引发的旁支思考", "isMainline": false }
                          ],
                          "edges": [
                            { "source": "1", "target": "2", "relation": "推导出" },
                            { "source": "1", "target": "3", "relation": "联想到" }
                          ]
                        }
                        """
            
            let parameters: [String: Any] = [
                "model": modelName,
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": text]
                ],
                "temperature": temperature, // 【修改】使用用户设置的热度
                "response_format": ["type": "json_object"]
            ]
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown Error"
                throw LLMError.apiError(errorMsg)
            }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                return cleanJSONString(content)
            } else {
                throw LLMError.decodingError
            }
        }
        
        /// 清洗返回字符串：过滤 R1 模型的 <think> 思考链标签以及 markdown 包裹符
        private func cleanJSONString(_ raw: String) -> String {
            var cleaned = raw
            
            // 1. 去除 DeepSeek-R1 推理模型的 <think>...</think> 标签内容
            if let thinkEndIndex = cleaned.range(of: "</think>")?.upperBound {
                cleaned = String(cleaned[thinkEndIndex...])
            }
            
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 2. 去除 Markdown 标记
            if cleaned.hasPrefix("```json") {
                cleaned.removeFirst(7)
            } else if cleaned.hasPrefix("```") {
                cleaned.removeFirst(3)
            }
            if cleaned.hasSuffix("```") {
                cleaned.removeLast(3)
            }
            
            return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    
    
    /// 1. 增量分析星系连线：只寻找新节点与所有节点之间的联系
        func generateIncrementalGraph(newThoughts: [SavedThought], allThoughts: [SavedThought]) async throws -> [HistoryEdge] {
            guard let url = URL(string: endpointURL) else { throw LLMError.invalidURL }
            
//            let allDict = allThoughts.map { ["id": $0.id.uuidString, "topic": $0.topic, "summary": $0.summary ?? "无"] }
//            let newDict = newThoughts.map { ["id": $0.id.uuidString, "topic": $0.topic] }
            // 【修复 1】过滤出真正的“旧节点”，避免大模型把新节点自己跟自己连起来导致逻辑崩溃
            let oldThoughts = allThoughts.filter { old in !newThoughts.contains(where: { $0.id == old.id }) }
                    
            // 【修复 2】提取字典时，把新旧节点的 summary 毫无保留地全传给大模型！
            let oldDict = oldThoughts.map { ["id": $0.id.uuidString, "topic": $0.topic, "summary": $0.summary ?? "无摘要"] }
            let newDict = newThoughts.map { ["id": $0.id.uuidString, "topic": $0.topic, "summary": $0.summary ?? "无摘要"] }
            
            let oldJSON = String(data: try! JSONSerialization.data(withJSONObject: oldDict), encoding: .utf8) ?? ""
            let newJSON = String(data: try! JSONSerialization.data(withJSONObject: newDict), encoding: .utf8) ?? ""
//            let allJSON = String(data: try! JSONSerialization.data(withJSONObject: allDict), encoding: .utf8) ?? ""
//            let newJSON = String(data: try! JSONSerialization.data(withJSONObject: newDict), encoding: .utf8) ?? ""
//            
            let systemPrompt = """
                    你是一个知识图谱专家。
                    请仔细阅读【本次新增想法】与【已有星系图想法】，判断它们之间是否存在逻辑联系。
                    
                    规则：
                    1. 仅寻找【新增想法】和【已有想法】之间的联系。绝不改变现有连线！
                    2. 【极其重要】除了强因果关系，如果两个节点探讨的是同一话题的不同侧面、相似的项目、或者存在灵感上的递进（例如两个节点都在谈论“软件开发”或“同一个地点/项目”），尤其如果存在节点间的关键词重复，你**必须**将它们连接起来。
                    3. relation 字段用2-4个字概括（如：功能延伸、同类项目、灵感补充、迭代思考、日程关联）。
                    4. 只输出合法 JSON。
                    5. 无论用户输入什么语言，你生成的全部内容必须使用 \(llmTargetLanguage) 语种输出！！！
                    
                    【输出格式样例】
                    {
                      "edges": [ 
                        { "source": "新增想法的ID", "target": "已有想法的ID", "relation": "灵感递进" }
                      ]
                    }
                    """
            
            
            let parameters: [String: Any] = [
                        "model": modelName,
                        "messages": [
                            ["role": "system", "content": systemPrompt],
                            ["role": "user", "content": "已有星系图想法：\n\(oldJSON)\n\n本次新增想法：\n\(newJSON)"]
                        ],
                        // 【修复 3】动态提高温度，让模型在增量时具备更强的发散和联想能力
                        "temperature": min(temperature + 0.2, 0.8),
                        "response_format": ["type": "json_object"]
                    ]
                    
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
                    
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { throw LLMError.apiError("网络错误") }
                    
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let choices = json["choices"] as? [[String: Any]], let msg = choices.first?["message"] as? [String: Any], let content = msg["content"] as? String {
                        if let resultData = cleanJSONString(content).data(using: .utf8), let decoded = try? JSONDecoder().decode([String: [HistoryEdge]].self, from: resultData), let edges = decoded["edges"] {
                            return edges
                        }
                    }
                    return []
        }
        
        /// 2. 语音直接指挥修改星系
        func modifyEdgesByVoice(command: String, thoughts: [SavedThought], currentEdges: [HistoryEdge]) async throws -> [HistoryEdge] {
            guard let url = URL(string: endpointURL) else { throw LLMError.invalidURL }
            
            let thoughtsList = thoughts.map { ["id": $0.id.uuidString, "topic": $0.topic] }
            let edgesList = currentEdges.map { ["source": $0.source, "target": $0.target, "relation": $0.relation] }
            let contextJSON = try! JSONSerialization.data(withJSONObject: ["nodes": thoughtsList, "current_edges": edgesList])
            
            let systemPrompt = """
            你是图谱数据架构师。用户会用语音描述他们想如何修改当前的连接图谱。
            你要根据用户的自然语言指令（如“把关于设计的两个点连起来”或“删掉A和B的连线”），在 `current_edges` 的基础上进行添加或删除，输出最终的完整连线数组。
            
            规则：
            1. 匹配用户提到的 topic 找到对应的 id。
            2. 严格返回完整的最新 edges 数组（保留没被要求删除的，加上要求新增的）。
            3. 仅返回 JSON。
            4. 【极度重要】无论用户输入什么语言，你生成的全部内容（包括 topic, summary, label, detail, relation 等）必须使用 \(llmTargetLanguage) 语种输出！！！
            
            【输出格式】
            {
              "edges": [ { "source": "id", "target": "id", "relation": "关系" } ]
            }
            """
            
            let parameters: [String: Any] = [
                "model": modelName,
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": "当前图谱状态：\n\(String(data: contextJSON, encoding: .utf8)!)\n\n用户的语音指令：\n“\(command)”"]
                ],
                "temperature": temperature,
                "response_format": ["type": "json_object"]
            ]
            
            var request = URLRequest(url: url); request.httpMethod = "POST"; request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let choices = json["choices"] as? [[String: Any]], let msg = choices.first?["message"] as? [String: Any], let content = msg["content"] as? String {
                if let resultData = cleanJSONString(content).data(using: .utf8), let decoded = try? JSONDecoder().decode([String: [HistoryEdge]].self, from: resultData), let edges = decoded["edges"] {
                    return edges
                }
            }
            return currentEdges // 失败则原样返回
        }
    
    
    
//    /// 让大模型分析所有历史闪念，找出潜在逻辑联系
//    func generateHistoryGraph(thoughts: [SavedThought]) async throws -> [HistoryEdge] {
//            guard let url = URL(string: endpointURL) else { throw LLMError.invalidURL }
//            
//            // 【修改】同时将 topic 和 summary 喂给大模型
//            let thoughtsList = thoughts.map { [
//                "id": $0.id.uuidString,
//                "topic": $0.topic,
//                "summary": $0.summary ?? "无摘要"
//            ] }
//            let thoughtsJSON = String(data: try! JSONSerialization.data(withJSONObject: thoughtsList), encoding: .utf8) ?? ""
//            
//            let systemPrompt = """
//            你是一个认知心理学和知识图谱构建专家。请仔细阅读以下用户历史想法列表（包含主题 topic 和核心摘要 summary），找出它们之间的逻辑联系。
//                    
//                    【连接规则】：
//                    1. 只要两个想法属于同一个核心项目（例如：都是关于同一个App的开发、设计或体验）、或者探讨高度相似的领域，就请将它们连接起来。
//                    2. 如果两个想法属于完全不同的生活维度（比如“做菜技巧”与“编程调试”），请不要连线。
//                    3. 返回合法的 JSON 格式，包含一个 edges 数组。
//                    4. relation 字段请用2-4个字概括（如：功能延伸、体验优化、同类项目、灵感迭代）。
//
//                    【JSON 格式约束】
//                    {
//                      "edges": [
//                        { "source": "源想法的ID", "target": "目标想法的ID", "relation": "关系描述" }
//                      ]
//                    }
//            """
//            
//            let parameters: [String: Any] = [
//                "model": modelName,
//                "messages": [
//                    ["role": "system", "content": systemPrompt],
//                    ["role": "user", "content": "历史想法列表：\n\(thoughtsJSON)"]
//                ],
//                // 温度调低，保持逻辑严谨性，不乱瞎连
//                "temperature": 0.4,
//                "response_format": ["type": "json_object"]
//            ]
//            
//            // ... (下方发起网络请求的代码保持不变) ...
//            
//            var request = URLRequest(url: url)
//            request.httpMethod = "POST"
//            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
//            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
//            
//            let (data, response) = try await URLSession.shared.data(for: request)
//            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
//                throw LLMError.apiError("星系连线请求失败")
//            }
//            
//            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
//               let choices = json["choices"] as? [[String: Any]],
//               let message = choices.first?["message"] as? [String: Any],
//               let content = message["content"] as? String {
//                
//                let cleaned = cleanJSONString(content)
//                if let resultData = cleaned.data(using: .utf8),
//                   let decoded = try? JSONDecoder().decode([String: [HistoryEdge]].self, from: resultData),
//                   let edges = decoded["edges"] {
//                    return edges
//                }
//            }
//            return []
//        }
    
    }
