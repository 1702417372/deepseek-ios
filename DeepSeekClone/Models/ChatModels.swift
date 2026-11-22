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
    /// deepseek-reasoner 返回的思维链（reasoning_content），普通模型为空。
    var reasoning: String?
    var createdAt: Date = Date()

    var hasReasoning: Bool {
        guard let reasoning else { return false }
        return !reasoning.isEmpty
    }
}

/// 一个会话（对话）。
struct Conversation: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String = "新对话"
    var model: String = DeepSeekModel.chat.rawValue
    var messages: [ChatMessage] = []
    var updatedAt: Date = Date()

    var isEmpty: Bool { messages.isEmpty }

    var preview: String {
        if let last = messages.last(where: { !$0.content.isEmpty }) {
            let single = last.content.replacingOccurrences(of: "\n", with: " ")
            return String(single.prefix(60))
        }
        return "暂无消息"
    }
}
