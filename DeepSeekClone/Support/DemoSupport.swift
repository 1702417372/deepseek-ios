import Foundation

/// 仅用于 CI 截图：通过启动参数 `--demo-screen=home|chat|drawer|settings` 注入演示数据。
enum DemoSupport {
    private static let marker = "--demo-screen="

    static var requestedScreen: String? {
        for argument in ProcessInfo.processInfo.arguments where argument.hasPrefix(marker) {
            return String(argument.dropFirst(marker.count))
        }
        return nil
    }

    static var isActive: Bool { requestedScreen != nil }

    static func demoConversation() -> Conversation {
        var conversation = Conversation(model: "deepseek-flash")
        conversation.title = "iOS 接入多模态 API"
        conversation.updatedAt = Date()

        var user = ChatMessage(role: .user, content: "帮我看看这张架构图，再给我一段 Swift 示例，说明怎么把图片传给多模态接口。")
        user.createdAt = Date().addingTimeInterval(-320)
        user.attachments = [
            ChatAttachment(kind: .image, name: "architecture.png", text: "客户端 → 网关 → 模型服务，SSE 回传", imageBase64JPEG: nil, fileID: nil, thumbnailData: nil, byteCount: 240_000),
            ChatAttachment(kind: .text, name: "接口说明.md", text: "content 数组支持 text / image_url / file 三种 block。", imageBase64JPEG: nil, fileID: nil, thumbnailData: nil, byteCount: 1_800)
        ]
        conversation.messages.append(user)

        var assistant = ChatMessage(role: .assistant, content: "")
        assistant.reasoning = """
        用户想要两件事：①解读架构图；②给出 Swift 传图的示例代码。注意 DeepSeek 的多模态接口走 OpenAI 兼容的 content 数组，图片用 base64 data URL 或 Files API 的 file_id。
        """
        assistant.content = """
        看完架构图了，整体是「客户端 → 网关 → 模型服务」三段式，中间用 SSE 回传流式结果。下面是 Swift 里把图片放进 messages 的写法：

        \u{0060}\u{0060}\u{0060}swift
        enum ContentPart: Encodable {
            case text(String)
            case image(String)   // data:image/jpeg;base64,...

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .text(let value):
                    try container.encode("text", forKey: .type)
                    try container.encode(value, forKey: .text)
                case .image(let base64):
                    try container.encode("image_url", forKey: .type)
                    try container.encode(["url": base64], forKey: .imageURL)
                }
            }
        }
        \u{0060}\u{0060}\u{0060}

        **几个要点：**

        1. 图片先压到长边 1400px、JPEG 质量 0.8，再 base64，避免请求体超过 48 MiB；
        2. 只有 DeepSeek-V4.1-Flash 支持图片输入，V4-Pro 是纯文本模型；
        3. 流式响应按 data: 行解析，最后一个 chunk 会带上引用和标题。

        如果你要我把这段接进现有的 DeepSeekClient，我可以直接改。
        """
        assistant.createdAt = Date().addingTimeInterval(-300)
        conversation.messages.append(assistant)

        var user2 = ChatMessage(role: .user, content: "顺便把「联网搜索」也打开，回答里带上来源。")
        user2.createdAt = Date().addingTimeInterval(-120)
        conversation.messages.append(user2)

        var assistant2 = ChatMessage(role: .assistant, content: "")
        assistant2.reasoning = "需要打开 deepseek_web_search 工具，然后按返回的引用块渲染来源角标。"
        assistant2.searchQueries = ["DeepSeek V4.1 更新", "多模态 API 定价"]
        assistant2.sources = [
            SearchSource(url: "https://api-docs.deepseek.com/zh-cn/news/news261017/", title: "DeepSeek V4.1 Flash 新版本发布", snippet: nil, siteName: "DeepSeek 官方文档", publishedAt: "2026-10-17"),
            SearchSource(url: "https://api-docs.deepseek.com/zh-cn/guides/build_a_chatbot", title: "构建 Chatbot：联网搜索、文件输入与阅读链接", snippet: nil, siteName: "DeepSeek 官方文档", publishedAt: "2026-11-13")
        ]
        assistant2.citations = [
            Citation(url: "https://api-docs.deepseek.com/zh-cn/news/news261017/", title: "DeepSeek V4.1 Flash 新版本发布"),
            Citation(url: "https://api-docs.deepseek.com/zh-cn/guides/build_a_chatbot", title: "构建 Chatbot")
        ]
        assistant2.content = "已开启联网搜索。这个能力由服务端执行检索，客户端只需要展示返回的来源卡片和引用链接；V4-Pro 是纯文本模型，联网请用 V4.1-Flash。"
        assistant2.createdAt = Date().addingTimeInterval(-100)
        conversation.messages.append(assistant2)

        return conversation
    }
}
