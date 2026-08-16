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
            2. 梳理这些节点之间的因果、转折或递进关系。
            3. 选出一条核心推导链路，将其 isMainline 设为 true；旁支发散思维设为 false。
            4. 最终输出必须且只能是合法的 JSON 格式。千万不要包含任何额外的解释文本、Markdown 代码块标记（如 ```json 等）。
            
            【JSON 格式约束】
            {
              "topic": "核心议题的简短提炼",
              "nodes": [
                { "id": "1", "label": "简短词汇", "type": "problem/solution/idea/pros", "detail": "一句话解释", "isMainline": true }
              ],
              "edges": [
                { "source": "1", "target": "2", "relation": "导致/启发/转折" }
              ]
            }
            """
            
            let parameters: [String: Any] = [
                "model": modelName,
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": text]
                ],
                "temperature": 0.3,
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
    }
