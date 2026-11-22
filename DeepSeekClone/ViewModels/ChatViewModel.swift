import Foundation
import SwiftUI

/// 单个会话的聊天状态机：负责发送、流式接收、中断、重试。
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var conversation: Conversation?
    @Published var isStreaming = false
    @Published var errorMessage: String?

    /// 会话内容变化时回调给持久化层（每个 token 不回调，只在关键节点回调）。
    var onConversationChanged: ((Conversation) -> Void)?

    private var streamTask: Task<Void, Never>?
    /// 每发起一次请求就自增，用来丢弃旧请求迟到的回调，避免中断后串到新消息上。
    private var streamGeneration = 0
    /// 流式期间每累积若干片段才回调一次持久化，避免高频写盘。
    private var persistedChunkCount = 0

    func open(_ conversation: Conversation) {
        if isStreaming {
            // 切换会话时静默中断，不回调持久化，避免把已删除的旧会话又写回存储
            streamGeneration += 1
            streamTask?.cancel()
            streamTask = nil
            isStreaming = false
        }
        self.conversation = conversation
        errorMessage = nil
    }

    /// 发送一条用户消息并开始接收回答；返回 false 表示没有发起请求。
    @discardableResult
    func send(_ text: String, settings: AppSettings) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming, var current = conversation else { return false }
        guard settings.hasAPIKey else {
            errorMessage = "还没有配置 API Key。请打开设置，填入 DeepSeek API Key 后再试。"
            return false
        }
        if current.messages.isEmpty {
            current.title = String(trimmed.prefix(24))
        }
        current.messages.append(ChatMessage(role: .user, content: trimmed))
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

    /// 删掉最后一条回答，用同样的上下文重新生成。
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

    // MARK: - 流式接收

    private func startStreaming(settings: AppSettings) {
        guard var current = conversation else { return }

        let model = settings.resolvedModel.rawValue
        if current.model != model {
            current.model = model
            conversation = current
        }

        let apiMessages = composeMessages(from: current.messages, systemPrompt: settings.systemPrompt)
        let client = DeepSeekClient(apiKey: settings.apiKey, baseURL: settings.baseURL)
        let temperature = settings.temperature
        let placeholderIndex = current.messages.count - 1
        streamGeneration += 1
        let generation = streamGeneration
        persistedChunkCount = 0

        isStreaming = true
        errorMessage = nil

        streamTask = Task { [weak self] in
            do {
                for try await event in client.streamChat(model: model, messages: apiMessages, temperature: temperature) {
                    guard let self else { return }
                    switch event {
                    case .reasoning(let chunk):
                        self.append(chunk, asReasoning: true, at: placeholderIndex, generation: generation)
                    case .content(let chunk):
                        self.append(chunk, asReasoning: false, at: placeholderIndex, generation: generation)
                    }
                }
                self?.finishStreaming(generation: generation)
            } catch is CancellationError {
                self?.finishStreaming(generation: generation)
            } catch {
                self?.failStreaming(with: error, generation: generation)
            }
        }
    }

    private func append(_ chunk: String, asReasoning: Bool, at index: Int, generation: Int) {
        guard generation == streamGeneration else { return }
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

    /// 把当前会话（含流式中的内容）立刻同步给持久化层，App 进入后台前调用。
    func flushToStore() {
        guard let current = conversation else { return }
        onConversationChanged?(current)
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
              !last.hasReasoning else { return }
        current.messages.removeLast()
        conversation = current
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

    private func composeMessages(from messages: [ChatMessage], systemPrompt: String) -> [APIMessage] {
        var result: [APIMessage] = []
        let system = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !system.isEmpty {
            result.append(APIMessage(role: "system", content: system))
        }
        for message in messages {
            switch message.role {
            case .system:
                continue
            case .user:
                if !message.content.isEmpty {
                    result.append(APIMessage(role: "user", content: message.content))
                }
            case .assistant:
                if !message.content.isEmpty {
                    result.append(APIMessage(role: "assistant", content: message.content))
                }
            }
        }
        return result
    }
}
