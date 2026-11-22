import Foundation
import SwiftUI

/// 单个会话的聊天状态机：发送（含图片/文件）、流式接收、联网搜索进度、中断、重试。
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var conversation: Conversation?
    @Published var isStreaming = false
    @Published var errorMessage: String?

    var onConversationChanged: ((Conversation) -> Void)?

    private var streamTask: Task<Void, Never>?
    private var streamGeneration = 0
    private var persistedChunkCount = 0

    func open(_ conversation: Conversation) {
        if isStreaming {
            streamGeneration += 1
            streamTask?.cancel()
            streamTask = nil
            isStreaming = false
        }
        self.conversation = conversation
        errorMessage = nil
    }

    @discardableResult
    func send(_ text: String, attachments: [ChatAttachment] = [], settings: AppSettings) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!trimmed.isEmpty || !attachments.isEmpty), !isStreaming, var current = conversation else { return false }
        guard settings.hasAPIKey else {
            errorMessage = "还没有配置 API Key。请打开设置，填入 DeepSeek API Key 后再试。"
            return false
        }

        if current.messages.isEmpty {
            current.title = Self.fallbackTitle(text: trimmed, attachments: attachments)
        }

        var userMessage = ChatMessage(role: .user, content: trimmed)
        userMessage.attachments = attachments.isEmpty ? nil : attachments
        let prompt = AttachmentService.promptBlock(for: attachments)
        userMessage.attachmentPrompt = prompt.isEmpty ? nil : prompt
        current.messages.append(userMessage)
        current.messages.append(ChatMessage(role: .assistant, content: ""))
        current.updatedAt = Date()
        conversation = current
        onConversationChanged?(current)
        startStreaming(settings: settings)
        return true
    }

    func stop() {
        streamGeneration += 1
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        trimEmptyAssistantIfNeeded()
        if let current = conversation {
            onConversationChanged?(current)
        }
    }

    func regenerate(settings: AppSettings) {
        guard !isStreaming, var current = conversation else { return }
        guard settings.hasAPIKey else {
            errorMessage = "还没有配置 API Key。请打开设置，填入 DeepSeek API Key 后再试。"
            return
        }
        guard let lastUserIndex = current.messages.lastIndex(where: { $0.role == .user }) else { return }
        if lastUserIndex + 1 < current.messages.count {
            current.messages.removeSubrange((lastUserIndex + 1)..<current.messages.count)
        }
        current.messages.append(ChatMessage(role: .assistant, content: ""))
        current.updatedAt = Date()
        conversation = current
        onConversationChanged?(current)
        startStreaming(settings: settings)
    }

    func deleteMessage(_ id: UUID) {
        guard !isStreaming, var current = conversation else { return }
        current.messages.removeAll { $0.id == id }
        current.updatedAt = Date()
        conversation = current
        onConversationChanged?(current)
    }

    func clearCurrentConversation() {
        guard var current = conversation else { return }
        streamGeneration += 1
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        current.messages.removeAll()
        current.title = "新对话"
        current.updatedAt = Date()
        conversation = current
        onConversationChanged?(current)
    }

    /// 把当前会话（含流式中的内容）立刻同步给持久化层，App 进入后台前调用。
    func flushToStore() {
        guard let current = conversation else { return }
        onConversationChanged?(current)
    }

    // MARK: - 流式接收

    private func startStreaming(settings: AppSettings) {
        guard var current = conversation else { return }

        let model = settings.model
        if current.model != model {
            current.model = model
            conversation = current
        }

        let history = Array(current.messages.dropLast())
        let options = ChatRequestOptions(settings: settings, model: model)
        let client = DeepSeekClient(apiKey: settings.apiKey, baseURL: settings.baseURL)
        let placeholderIndex = current.messages.count - 1
        streamGeneration += 1
        let generation = streamGeneration
        persistedChunkCount = 0

        isStreaming = true
        errorMessage = nil

        streamTask = Task { [weak self] in
            do {
                for try await event in client.streamChat(messages: history, options: options) {
                    guard let self else { return }
                    self.apply(event, at: placeholderIndex)
                }
                self?.finishStreaming(generation: generation)
            } catch is CancellationError {
                self?.finishStreaming(generation: generation)
            } catch {
                self?.failStreaming(with: error, generation: generation)
            }
        }
    }

    private func apply(_ event: ChatStreamEvent, at index: Int) {
        switch event {
        case .reasoning(let chunk):
            append(chunk, asReasoning: true, at: index)
        case .content(let chunk):
            append(chunk, asReasoning: false, at: index)
        case .searchStarted(let queries, let kind):
            guard var current = conversation, current.messages.indices.contains(index) else { return }
            var existing = current.messages[index].searchQueries ?? []
            for query in queries where !existing.contains(query) {
                existing.append(query)
            }
            _ = kind
            current.messages[index].searchQueries = existing.isEmpty ? nil : existing
            conversation = current
        case .searchCompleted(let sources):
            guard var current = conversation, current.messages.indices.contains(index) else { return }
            var existing = current.messages[index].sources ?? []
            let known = Set(existing.map { $0.url })
            for source in sources where !known.contains(source.url) {
                existing.append(source)
            }
            current.messages[index].sources = existing.isEmpty ? nil : existing
            conversation = current
        case .final(let title, let citations, let serverToolJSON, let finishReason, let refusal):
            applyFinal(title: title, citations: citations, serverToolJSON: serverToolJSON, finishReason: finishReason, refusal: refusal, at: index)
        }
    }

    private func applyFinal(title: String?, citations: [Citation], serverToolJSON: String?, finishReason: String?, refusal: String?, at index: Int) {
        guard var current = conversation, current.messages.indices.contains(index) else { return }
        if let title, !title.isEmpty {
            current.title = title
        }
        current.messages[index].citations = citations.isEmpty ? nil : citations
        current.messages[index].serverToolJSON = serverToolJSON
        current.messages[index].finishReason = finishReason
        if let refusal, !refusal.isEmpty {
            current.messages[index].refusalText = refusal
        }
        if finishReason == "content_filter" {
            current.messages[index].content = ""
            current.messages[index].reasoning = nil
            if current.messages[index].refusalText == nil {
                current.messages[index].refusalText = "内容被安全策略拦截，请换一种说法再试。"
            }
        }
        if let raw = serverToolJSON, (current.messages[index].sources ?? []).isEmpty {
            let parsed = DeepSeekClient.sources(fromServerToolJSON: raw)
            if !parsed.isEmpty {
                current.messages[index].sources = parsed
            }
        }
        current.updatedAt = Date()
        conversation = current
    }

    private func append(_ chunk: String, asReasoning: Bool, at index: Int) {
        guard var current = conversation, current.messages.indices.contains(index) else { return }
        if asReasoning {
            current.messages[index].reasoning = (current.messages[index].reasoning ?? "") + chunk
        } else {
            current.messages[index].content += chunk
        }
        conversation = current

        persistedChunkCount += 1
        if persistedChunkCount >= 40 {
            persistedChunkCount = 0
            onConversationChanged?(current)
        }
    }

    private func finishStreaming(generation: Int) {
        guard generation == streamGeneration else { return }
        streamTask = nil
        isStreaming = false
        trimEmptyAssistantIfNeeded()
        if var current = conversation {
            current.updatedAt = Date()
            conversation = current
            onConversationChanged?(current)
        }
    }

    private func failStreaming(with error: Error, generation: Int) {
        guard generation == streamGeneration else { return }
        streamTask = nil
        isStreaming = false

        if error is CancellationError {
            finishStreaming(generation: generation)
            return
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            finishStreaming(generation: generation)
            return
        }

        trimEmptyAssistantIfNeeded()
        if var current = conversation {
            current.updatedAt = Date()
            conversation = current
            onConversationChanged?(current)
        }
        errorMessage = ChatViewModel.friendlyMessage(for: error)
    }

    private func trimEmptyAssistantIfNeeded() {
        guard var current = conversation,
              let last = current.messages.last,
              last.role == .assistant,
              last.content.isEmpty,
              !last.hasReasoning,
              last.refusalText == nil else { return }
        current.messages.removeLast()
        conversation = current
    }

    private static func fallbackTitle(text: String, attachments: [ChatAttachment]) -> String {
        if !text.isEmpty {
            return String(text.prefix(24))
        }
        let hasImage = attachments.contains { $0.kind == .image }
        if hasImage { return "图片对话" }
        return "文件对话"
    }

    private static func friendlyMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "网络连接失败，请检查网络后重试。"
            case .timedOut:
                return "请求超时了，请稍后再试。"
            case .secureConnectionFailed, .serverCertificateUntrusted:
                return "HTTPS 连接失败，请检查 Base URL 或代理证书。"
            default:
                break
            }
        }
        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
            return localized
        }
        return error.localizedDescription
    }
}
