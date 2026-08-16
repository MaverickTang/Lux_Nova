//
//  SettingsView.swift
//  Mindflow
//
//  Created by Maverick Tang on 2026/8/15.
//


//
//  SettingsView.swift
//  Mindflow
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    // 大语言模型配置
    @AppStorage("llm_api_key") private var apiKey: String = ""
    @AppStorage("llm_endpoint_url") private var endpointURL: String = "https://api.siliconflow.cn/v1/chat/completions"
    @AppStorage("llm_model_name") private var modelName: String = "deepseek-ai/DeepSeek-R1-0528-Qwen3-8B"
    
    // 物理引擎参数
    @AppStorage("physics_repulsion") private var repulsionForce: Double = 4000.0
    @AppStorage("physics_attraction") private var attractionForce: Double = 0.03

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                Form {
                    Section(
                        header: Text("大语言模型配置").foregroundColor(.white.opacity(0.6)),
                        footer: Text("支持任何 OpenAI 格式的云端或本地端点。若使用本地部署模型工作流，端点通常为 http://127.0.0.1:1234/v1/chat/completions，此时无需填写 API Key。")
                            .foregroundColor(.white.opacity(0.4))
                    ) {
                        SecureField("API Key", text: $apiKey)
                            .foregroundColor(.white)
                            .tint(Color(red: 0.1, green: 0.8, blue: 1.0))
                        
                        TextField("Base URL", text: $endpointURL)
                            .foregroundColor(.white)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .tint(Color(red: 0.1, green: 0.8, blue: 1.0))
                        
                        TextField("Model Name", text: $modelName)
                            .foregroundColor(.white)
                            .autocapitalization(.none)
                            .tint(Color(red: 0.1, green: 0.8, blue: 1.0))
                    }
                    .listRowBackground(Color.white.opacity(0.1))
                    
                    Section(
                        header: Text("思维流引力场 (物理引擎)").foregroundColor(.white.opacity(0.6)),
                        footer: Text("实时控制思维导图节点的物理属性，修改后在图谱界面立即生效。").foregroundColor(.white.opacity(0.4))
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("节点排斥力 (发散度): \(Int(repulsionForce))")
                                .foregroundColor(.white.opacity(0.8))
                                .font(.system(size: 14))
                            
                            Slider(value: $repulsionForce, in: 1000...8000, step: 100)
                                .tint(Color(red: 0.1, green: 0.8, blue: 1.0))
                        }
                        .padding(.vertical, 8)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("节点引力 (聚合度): \(String(format: "%.3f", attractionForce))")
                                .foregroundColor(.white.opacity(0.8))
                                .font(.system(size: 14))
                            
                            Slider(value: $attractionForce, in: 0.005...0.1, step: 0.005)
                                .tint(Color(red: 0.1, green: 0.8, blue: 1.0))
                        }
                        .padding(.vertical, 8)
                    }
                    .listRowBackground(Color.white.opacity(0.1))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("系统设置")
            .navigationBarTitleDisplayMode(.inline)
            // 确保顶部导航条为深色风格
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
        }
    }
}