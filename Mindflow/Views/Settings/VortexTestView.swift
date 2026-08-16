//
//  VortexTestView.swift
//  Mindflow
//
//  Created by Maverick Tang on 2026/8/16.
//


//
//  VortexTestView.swift
//  Mindflow
//

import SwiftUI

struct VortexTestView: View {
    var body: some View {
        ZStack {
            // 纯黑背景，模拟暗色模式
            Color.black.ignoresSafeArea()
            
            // 涡流动画主体
            VortexLoadingView()
                .frame(width: 360, height: 360)
            
            // Loading 提示文案，放置在黑洞的正下方
//            Text("神 经 突 触 连 接 中 ...")
//                .font(.system(size: 13, weight: .semibold, design: .rounded))
//                .foregroundColor(Color(red: 0.4, green: 0.7, blue: 1.0))
//                .shadow(color: Color(red: 0.1, green: 0.8, blue: 1.0), radius: 6)
//                .offset(y: 130)
        }
    }
}

// 提供预览，你可以直接在 Xcode 右侧的 Canvas 中看到效果
struct VortexTestView_Previews: PreviewProvider {
    static var previews: some View {
        VortexTestView()
    }
}
