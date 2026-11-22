import Foundation

/// 会话持久化：写在 Application Support 目录，流式输出期间做防抖，避免频繁写盘。
@MainActor
final class ConversationStore: ObservableObject {
    @Published private(set) var conversations: [Conversation] = []

    private let fileURL: URL
    private var pendingSave: Task<Void, Never>?

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("conversations.json")
        load()
    }

    var sorted: [Conversation] {
        conversations.sorted { lhs, rhs in
            let leftPinned = lhs.isPinned ?? false
            let rightPinned = rhs.isPinned ?? false
            if leftPinned != rightPinned { return leftPinned }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    func rename(_ id: UUID, to title: String) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].title = title
        conversations[index].updatedAt = Date()
        saveSoon()
    }

    func togglePin(_ id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].isPinned = !(conversations[index].isPinned ?? false)
        saveSoon()
    }

    func conversation(with id: UUID) -> Conversation? {
        conversations.first(where: { $0.id == id })
    }

    @discardableResult
    func createConversation(model: String) -> Conversation {
        let conversation = Conversation(model: model)
        conversations.insert(conversation, at: 0)
        saveSoon()
        return conversation
    }

    func upsert(_ conversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        } else {
            conversations.insert(conversation, at: 0)
        }
        saveSoon()
    }

    func delete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        saveSoon()
    }

    func deleteAll() {
        conversations.removeAll()
        saveSoon()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([Conversation].self, from: data) {
            conversations = decoded
            return
        }
        // 解码失败：把坏文件挪走备份，避免下一次写盘把历史彻底覆盖掉
        let backup = fileURL.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: fileURL, to: backup)
    }

    private func saveSoon() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            self.writeToDisk()
        }
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        writeToDisk()
    }

    private func writeToDisk() {
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
