//
//  MindflowApp.swift
//  Mindflow
//

import SwiftUI

@main
struct MindflowApp: App {
    // 【关键1】必须在最顶层声明 AppStorage，这样设置改变时，整个 App 才会重新渲染
    @AppStorage("app_language") private var appLanguage: String = "system"
    
    // 【关键2】动态计算当前的语言环境
    var currentLocale: Locale {
        if appLanguage == "system" {
            return Locale.current
        } else {
            return Locale(identifier: appLanguage)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // 【关键3】强制将计算好的语言环境注入到整个 App 的视图树中
                .environment(\.locale, currentLocale)
        }
    }
}



//import SwiftUI
//
//@main
//struct MindflowApp: App {
//    var body: some Scene {
//        WindowGroup {
//            // 临时将入口改为 VortexTestView 以便测试
////            VortexTestView()
//            
//            ContentView()
//        }
//    }
//}

//import SwiftUI
//
//@main
//struct MindflowApp: App {
//    var body: some Scene {
//        WindowGroup {
//            APITestView() // 临时用于测试 API
//        }
//    }
//}
