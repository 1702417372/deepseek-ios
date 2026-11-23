import Foundation

/// 会话导出 / 导入 / 合并。格式与网页版约定一致。
enum ConversationArchive {
    static let formatName = "deepseek-clone"
    static let formatVersion = 1

    struct Envelope: Codable {
        var format: String = ConversationArchive.formatName
        var version: Int = ConversationArchive.formatVersion
        var exportedAt: Date = Date()
        var conversations: [Conversation]

        private enum CodingKeys: String, CodingKey {
            case format
            case version
            case exportedAt
            case conversations
        }

        init(conversations: [Conversation]) {
            self.conversations = conversations
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            format = try container.decodeIfPresent(String.self, forKey: .format) ?? ConversationArchive.formatName
            version = try container.decodeIfPresent(Int.self, forKey: .version) ?? ConversationArchive.formatVersion
            exportedAt = try container.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
            conversations = try container.decodeIfPresent([Conversation].self, forKey: .conversations) ?? []
        }
    }

    static func exportData(_ conversations: [Conversation]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Envelope(conversations: conversations))
    }

    static func suggestedFileName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return "deepseek-clone-export-\(formatter.string(from: Date())).json"
    }

    /// 尽量宽松地解析：本 App 格式 → [Conversation] → 通用 {title, messages} → Markdown / 纯文本。
    static func decode(_ data: Data) throws -> [Conversation] {
        let iso = JSONDecoder()
        iso.dateDecodingStrategy = .iso8601
        if let envelope = try? iso.decode(Envelope.self, from: data), !envelope.conversations.isEmpty {
            return envelope.conversations
        }
        let plain = JSONDecoder()
        if let list = try? plain.decode([Conversation].self, from: data), !list.isEmpty {
            return list
        }
        if let object = try? JSONSerialization.jsonObject(with: data) {
            // 只要是合法 JSON，就只按 JSON 解析；解析不出来直接报错，绝不把 JSON 当 Markdown 文本
            let generic = decodeGeneric(object)
            if !generic.isEmpty { return generic }
            throw DeepSeekError(message: "这是 JSON 文件，但没有识别出会话（conversations/messages）字段。")
        }
        if let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return decodeMarkdown(text)
        }
        throw DeepSeekError(message: "这个文件认不出来，请选择本 App 或网页版导出的 JSON。")
    }

    // MARK: - 通用 JSON

    private static func decodeGeneric(_ object: Any) -> [Conversation] {
        if let array = object as? [Any] {
            return array.compactMap(decodeGenericConversation)
        }
        if let dictionary = object as? [String: Any] {
            for key in ["conversations", "sessions", "chats", "data"] {
                if let array = dictionary[key] as? [Any] {
                    let result = array.compactMap(decodeGenericConversation)
                    if !result.isEmpty { return result }
                }
            }
            if let single = decodeGenericConversation(dictionary) {
                return [single]
            }
        }
        return []
    }

    private static func decodeGenericConversation(_ object: Any) -> Conversation? {
        guard let dictionary = object as? [String: Any] else { return nil }
        let title = (dictionary["title"] as? String)
            ?? (dictionary["name"] as? String)
            ?? (dictionary["subject"] as? String)
            ?? "导入的对话"

        let rawMessages = (dictionary["messages"] as? [Any])
            ?? (dictionary["message_list"] as? [Any])
            ?? (dictionary["history"] as? [Any])
            ?? []
        var messages: [ChatMessage] = []
        for raw in rawMessages {
            guard let item = raw as? [String: Any] else { continue }
            let roleString = (item["role"] as? String) ?? (item["sender"] as? String) ?? "user"
            let role: ChatMessage.Role
            switch roleString.lowercased() {
            case "assistant", "ai", "bot", "deepseek", "model":
                role = .assistant
            case "system":
                role = .system
            default:
                role = .user
            }
            var content = ""
            if let text = item["content"] as? String {
                content = text
            } else if let parts = item["content"] as? [Any] {
                content = parts.compactMap { part -> String? in
                    if let part = part as? [String: Any] {
                        return (part["text"] as? String) ?? (part["content"] as? String)
                    }
                    return part as? String
                }.joined(separator: "\n")
            } else if let text = item["text"] as? String {
                content = text
            }
            guard !content.isEmpty else { continue }
            messages.append(ChatMessage(role: role, content: content))
        }
        // 允许空会话（官方格式里「新对话」可能没有任何消息）
        var conversation = Conversation(model: "deepseek-flash")
        conversation.title = title
        conversation.messages = messages
        conversation.updatedAt = Date()
        return conversation
    }

    // MARK: - Markdown / 文本

    private static func decodeMarkdown(_ text: String) -> [Conversation] {
        var conversation = Conversation(model: "deepseek-flash")
        var lines = text.components(separatedBy: "\n")
        if let first = lines.first, first.hasPrefix("# ") {
            conversation.title = String(first.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            lines.removeFirst()
        } else {
            conversation.title = String(text.prefix(24)).replacingOccurrences(of: "\n", with: " ")
        }

        var currentRole: ChatMessage.Role = .user
        var buffer: [String] = []
        var messages: [ChatMessage] = []

        func flush() {
            let content = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeAll()
            guard !content.isEmpty else { return }
            messages.append(ChatMessage(role: currentRole, content: content))
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            switch trimmed {
            case "## 我", "## 用户", "## User", "## user":
                flush()
                currentRole = .user
            case "## DeepSeek", "## AI", "## Assistant":
                flush()
                currentRole = .assistant
            case "---":
                continue
            default:
                buffer.append(line)
            }
        }
        flush()

        if messages.isEmpty {
            messages = [ChatMessage(role: .user, content: text)]
        }
        conversation.messages = messages
        conversation.updatedAt = Date()
        return [conversation]
    }

    // MARK: - 合并

    /// 按 id 合并：同 id 保留 updatedAt 较新的；本地独有的保留；远端独有的追加。
    static func merge(_ incoming: [Conversation], into existing: [Conversation]) -> [Conversation] {
        var byID: [UUID: Conversation] = [:]
        var order: [UUID] = []
        for conversation in existing {
            if byID[conversation.id] == nil { order.append(conversation.id) }
            byID[conversation.id] = conversation
        }
        for conversation in incoming {
            if let current = byID[conversation.id] {
                if conversation.updatedAt > current.updatedAt {
                    byID[conversation.id] = conversation
                }
            } else {
                byID[conversation.id] = conversation
                order.append(conversation.id)
            }
        }
        return order.compactMap { byID[$0] }
    }
}
