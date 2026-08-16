# 🌌 Lux Nova (新光)

> **"捕捉意识的微光，重塑思维的星海。"**

![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)
![iOS](https://img.shields.io/badge/iOS-17.0+-blue.svg)
![AI](https://img.shields.io/badge/AI-LLM_Powered-purple.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

## 📖 哲学隐喻 (The Philosophy)
**Lux Nova** 取自中世纪教堂中的“新光”。光是世间唯一“看得见、摸不着”的东西。当普通的太阳光（物质）穿透彩色的玻璃，变成绚丽的神秘光束（非物质）洒在石壁上时，人们认为这就完成了从世俗向神圣的过渡。

人类的思维同样如此：它是网状的、立体的、跳跃的。传统的线性笔记像是一个个冰冷的抽屉，而 **Lux Nova** 试图成为那面“彩色玻璃”——它作为物质与非物质的桥梁，负责捕捉人们脑海中转瞬即逝的“意识流”，并将其折射为结构化、可生长的**思维星海**。

---

## ✨ 核心特性 (Features)

### 1. 虚空捕获 (The Void)
*   **极简流体交互**：摒弃一切干扰，主界面由一个响应声音湍流与呼吸的 3D 粒子球体（TDParticleSphere）构成，带来沉浸式的冥想录制体验。
*   **无界录制与思维打点**：无时间限制的流式语音记录。支持在说话过程中随时“打点（Highlight）”标记高光时刻，绝不打断心流。

### 2. 思维折射 (The Prism)
*   **黑洞吸积盘加载 (Vortex Loading)**：AI 处理时，界面浮现基于开普勒旋转定律与 3D 透视渲染的几千个粒子构成的流体涡流。
*   **物理引擎图谱 (Thought Graph)**：AI 逆向拆解思维演进过程，严格区分“主线推导”与“发散旁支”。通过纯手写的力导向物理引擎（Force-Directed Graph），节点在屏幕上呈现真实的排斥与引力。
*   **闭环反思**：在图谱界面支持直接修改原文并重新保存，或点击“继续思考”带着当前上下文开启新一轮录制。

### 3. 意识星海 (The Galaxy)
*   **增量式星系网络**：完全摒弃列表式的历史记录。所有过往闪念均化作星海中的“光团”。大模型会在不破坏原有连接的基础上，智能侦测新旧想法之间的深层逻辑并建立“引力虚线”。
*   **神经重塑 (Neural Reshaping)**：
    *   **🗣 语音指挥**：直接用自然语言（如：“把关于APP开发的想法关联起来”）命令 AI 重构历史图谱。
    *   **👆 手动修剪**：一键开启连线模式，手动点击光团建立/斩断引力，支持重命名与湮灭（删除）。

### 4. 掌控环境 (Environment)
*   **模型与物理场定制**：在设置中自由调节 LLM 的“热度（Temperature）”以控制发散力；开放物理引擎的“排斥力”与“引力”参数调节，实时改变星系的动态。
*   **多语言无缝切换 (i18n)**：基于 `String Catalog` 深度本地化，支持跟随系统或强制切换中/英双语，LLM 亦会动态侦测环境输出对应语种。

---

## 🛠 技术架构 (Under the Hood)

Lux Nova 的流畅与惊艳，建立在严谨的数学模型、底层绘图 API 以及巧妙的 LLM 提示词工程之上。

*   **高性能流体视觉 (SwiftUI Canvas)**：彻底放弃传统 View 动画，使用底层 `Canvas` + `TimelineView` 结合加色混合模式 (`.plusLighter`)，以 60fps 渲染数千个具有 3D 景深与高斯分布的粒子。
*   **纯手写力导向引擎**：零第三方依赖。基于库仑定律（斥力）与胡克定律（引力）构建的 `GraphViewModel` 物理世界，带有针对骨架主线的强力坐标锚点约束。
*   **结构化 AI 吐出 (Prompt Engineering)**：利用 `response_format: { "type": "json_object" }` 配合极度严苛的 System Prompt，要求模型稳定输出 `topic`、`summary` 以及 `nodes/edges`。
*   **增量图谱算法**：在历史记录连线时，通过拆分 `allThoughts` 和 `newThoughts`，实现了罕见且高效的知识图谱增量更新能力。

---

## 🚀 快速开始 (Getting Started)

### 环境要求
*   macOS 14.0+
*   Xcode 15.0+
*   iOS 17.0+ 物理设备 (因需使用麦克风与高性能渲染，不建议使用模拟器)

### 安装与配置
1. 克隆本项目：
   ```bash
   git clone [https://github.com/YourUsername/Lux_Nova.git](https://github.com/YourUsername/Lux_Nova.git)

2. 使用 Xcode 打开 Mindflow.xcodeproj。
3. 配置 API Key：
   * 项目默认集成了硅基流动 (SiliconFlow) 的 DeepSeek 模型端点。
     * 方法 A：直接在 App 的“系统设置” UI 中填入你的 API Key。
      * 方法 B：在代码 LLMService.swift 中修改默认的回退 Key 或端点（也支持替换为本地 LM Studio / Ollama 的 http://127.0.0.1:1234/v1 端点实现完全断网运行）。
      * 选择你的 iPhone 设备，点击 Run (⌘+R) 编译并在真机上运行。

### 🗺 未来路线图 (Roadmap)
[ ] SwiftData & iCloud 同步：重构底层存储，实现跨设备的秒级静默同步。
[ ] 星系折叠聚类：支持 100+ 节点时的宏观星座视角与微观图谱视角的无缝缩放。
[ ] 矛盾侦测引擎：AI 主动寻找并高亮历史思维中的逻辑冲突。
[ ] VisionOS 空间计算版：在 3D 空间中用手势拨弄发光的思维粒子。

### 🤝 贡献与反馈 (Contributing)
如果你对认知心理学、知识图谱构建、SwiftUI 高性能渲染或是大模型应用感兴趣，非常欢迎提交 Pull Request 或开 Issue 讨论！

### 📄 许可证 (License)
本项目采用 MIT License 开源许可证。
