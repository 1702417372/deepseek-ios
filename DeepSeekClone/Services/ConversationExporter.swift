import Foundation

enum ConversationExporter {
    static func markdown(for conversation: Conversation) -> String {
        var lines: [String] = []
        lines.append("# \(conversation.title)")
        lines.append("")
        lines.append("导出自 DeepSeek 客户端 · \(formattedDate(conversation.updatedAt))")
        lines.append("")
        for message in conversation.messages {
            switch message.role {
            case .user:
                lines.append("## 我")
            case .assistant:
                lines.append("## DeepSeek")
            case .system:
                lines.append("## 系统")
            }
            if let reasoning = message.reasoning, !reasoning.isEmpty {
                lines.append("")
                lines.append("> 思考过程：")
                lines.append(reasoning.split(separator: "\n").map { "> " + $0 }.joined(separator: "\n"))
            }
            if !message.content.isEmpty {
                lines.append("")
                lines.append(message.content)
            }
            if let attachments = message.attachments, !attachments.isEmpty {
                lines.append("")
                for attachment in attachments {
                    lines.append("- 附件：\(attachment.name)（\(attachment.badgeText)）")
                }
            }
            lines.append("")
            lines.append("---")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func writeTemporaryFile(for conversation: Conversation) throws -> URL {
        let content = markdown(for: conversation)
        let safeTitle = conversation.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let filename = "\(safeTitle.isEmpty ? "对话" : safeTitle).md"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
