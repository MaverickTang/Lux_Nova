//
//  APITestView.swift
//  Mindflow
//
//  Created by Maverick Tang on 2026/8/15.
//


//
//  APITestView.swift
//  Mindflow
//

import SwiftUI

struct APITestView: View {
    @State private var isLoading = false
    @State private var jsonResult: String = "点击下方按钮，开始向大模型发送请求..."
    
    // 你提供的测试文本
    let testText = """
    我希望开发一个闪念胶囊类的APP，但是它主要是帮助冥想的。在冥想的时候，你可以……我不知道，我现在、我现在整个人的感觉就像是我有一个巨大的身躯，但是我的、我的嘴巴、我的……跟不上我的思考。我希望它能够就是它的界面非常简单，就三个页面。然后第一个，然后就三个、三个按钮，一个非常大的录制的按钮，然后再点击之后，你说什么，它都会记录上去，就是记转成文字记录，记录在上面，然后再按一下是停止、停止记录。
    这个APP它的第二个按钮应该是帮你去记录，就是你在说重点的时候，或者说你认为这是一个比较重要的思维阶段的时候，你按下这个按钮，然后它会告诉你这些，它会记录下来，表示你思维的一个节点。然后第三个按钮，我希望它能，就是我在按它的时候，它能帮我扩展。就比如说我突然想到，就是比如说我说突然想到这个话题，它与禅修，它与那个，嗯，就是那些自己一些思维有关，然后这个是我一按，不是它一记录，然后OK。对，它不会像这个APP一样有时间限制，这个太难受了。
    我在然后在每一次思考的最后，我都希望他能够就是打开一个界面，他有非常详细的是你的思路的一个延伸，就是通过AI来分析。他会分析你的思路是如何从这一个观点到下一个观点的，呃，他们是这两个观点之间内在的联系是什么？对吧，然后久甚至就是久而久之，就是这是这是版本二了呀，版本二的话就是它它能通过你过往的这些对话逐步建帮你建立起一个你的知识图谱。还有你的专门的一个，你的思维是怎么活动的一个笔记方式。
    """
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("LLM 接口测试")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top)
                
                // 测试输入内容预览
                VStack(alignment: .leading, spacing: 8) {
                    Text("发送的原始文本：")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(testText)
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                        .lineLimit(4) // 折叠显示，避免占满屏幕
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                
                // 核心测试按钮
                Button(action: {
                    Task {
                        await runTest()
                    }
                }) {
                    HStack {
                        if isLoading {
                            ProgressView().tint(.white)
                        }
                        Text(isLoading ? "大模型正在思考中..." : "发射！测试大模型 API")
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(isLoading ? Color.gray : Color.blue)
                    .cornerRadius(14)
                }
                .disabled(isLoading)
                
                // 结果展示区
                VStack(alignment: .leading, spacing: 8) {
                    Text("大模型返回的 JSON：")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(jsonResult)
                        .font(.system(size: 13, design: .monospaced))
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.green.opacity(0.05))
                .cornerRadius(12)
            }
            .padding()
        }
    }
    
    func runTest() async {
        isLoading = true
        jsonResult = "正在请求 API...\n网络请求可能需要几秒钟，请稍候。"
        
        do {
            // 调用我们写的 LLMService
            let result = try await LLMService.shared.generateThoughtGraph(from: testText)
            jsonResult = result
            print("=== API 测试成功 ===")
            print(result)
        } catch {
            jsonResult = "请求失败：\n\(error.localizedDescription)"
            print("=== API 测试失败 ===")
            print(error)
        }
        
        isLoading = false
    }
}