import Foundation

/// 一条聊天消息。
struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable {
        case system
        case user
        case assistant
    }

    var id: UUID = UUID()
    var role: Role
    var content: String = ""
    /// 思考模式返回的思维链（reasoning_content）。
    var reasoning: String?
    var createdAt: Date = Date()
    /// 用户消息附带的图片 / 文件。
    var attachments: [ChatAttachment]?
    /// 由附件文字拼成、不展示在气泡里的补充上下文。
    var attachmentPrompt: String?
    /// 联网搜索命中的来源（用于展示来源卡片）。
    var sources: [SearchSource]?
    /// 本轮搜索用到的查询词。
    var searchQueries: [String]?
    /// 正文里的引用（url_citation）。
    var citations: [Citation]?
    /// 服务端工具调用原始 JSON，下一轮必须原样回传。
    var serverToolJSON: String?
    var finishReason: String?
    var refusalText: String?

    var hasReasoning: Bool {
        guard let reasoning else { return false }
        return !reasoning.isEmpty
    }

    var hasAttachments: Bool {
        guard let attachments else { return false }
        return !attachments.isEmpty
    }

    var isRefused: Bool {
        finishReason == "content_filter" || (refusalText?.isEmpty == false)
    }
}

/// 联网搜索的一条来源。
struct SearchSource: Codable, Equatable, Identifiable {
    var url: String
    var title: String
    var snippet: String?
    var siteName: String?
    var publishedAt: String?

    var id: String { url }
}

/// 正文中的引用角标来源。
struct Citation: Codable, Equatable, Identifiable {
    var url: String
    var title: String

    var id: String { url + title }
}

/// 一个会话（对话）。
struct Conversation: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String = "新对话"
    var model: String = DeepSeekModel.flash.rawValue
    var messages: [ChatMessage] = []
    var updatedAt: Date = Date()
    var isPinned: Bool? = false

    var isEmpty: Bool { messages.isEmpty }

    var preview: String {
        if let last = messages.last(where: { !$0.content.isEmpty }) {
            let single = last.content.replacingOccurrences(of: "\n", with: " ")
            return String(single.prefix(60))
        }
        if let last = messages.last, last.hasAttachments {
            return "附件消息"
        }
        return "暂无消息"
    }
}
