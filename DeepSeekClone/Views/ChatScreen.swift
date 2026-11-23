import SwiftUI
import UIKit

struct ChatScreen: View {
    @ObservedObject var chat: ChatViewModel
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var modelCatalog: ModelCatalog

    var onMenu: () -> Void
    var onNewChat: () -> Void
    var onOpenSettings: () -> Void
    var onToast: (String) -> Void

    @State private var draft = ""
    @State private var attachments: [ChatAttachment] = []
    @State private var showModelSheet = false
    @StateObject private var tts = TTSPlayer()
    @FocusState private var isInputFocused: Bool

    private let bottomID = "chat-bottom"

    private var conversation: Conversation? { chat.conversation }
    private var settings: AppSettings { settingsStore.settings }
    private var modelOption: ModelOption? { modelCatalog.option(for: settings.model) }
    private var modelName: String { modelOption?.shortName ?? settings.resolvedModel.title }
    private var isHome: Bool { conversation?.isEmpty ?? true }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if !settings.hasAPIKey {
                apiKeyBanner
            }
            messageList
        }
        .background(DSTheme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ComposerBar(
                text: $draft,
                isFocused: $isInputFocused,
                attachments: $attachments,
                isStreaming: chat.isStreaming,
                showsQuickActions: isHome,
                modelName: modelName,
                settings: settings,
                onSend: sendDraft,
                onStop: { chat.stop() },
                onSelectModel: { showModelSheet = true },
                onToggleThinking: toggleThinking,
                onToggleWebSearch: toggleWebSearch,
                onNewChat: onNewChat,
                onClearConversation: { chat.clearCurrentConversation() },
                onOpenSettings: onOpenSettings,
                onToast: onToast
            )
        }
        .sheet(isPresented: $showModelSheet) {
            ModelPickerSheet()
                .environmentObject(settingsStore)
                .environmentObject(modelCatalog)
        }
        .onChange(of: tts.errorMessage) { message in
            if let message, !message.isEmpty {
                onToast(message)
                tts.errorMessage = nil
            }
        }
        .onChange(of: chat.isStreaming) { streaming in
            guard !streaming, settings.autoReadAnswers else { return }
            guard let last = conversation?.messages.last else { return }
            guard last.role == .assistant, !last.content.isEmpty, !last.isRefused else { return }
            speak(last)
        }
        .alert("请求失败", isPresented: errorBinding) {
            Button("重试") { chat.regenerate(settings: settings) }
            Button("好", role: .cancel) { chat.errorMessage = nil }
        } message: {
            Text(chat.errorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { chat.errorMessage != nil },
            set: { newValue in
                if !newValue { chat.errorMessage = nil }
            }
        )
    }

    // MARK: - 顶栏

    @ViewBuilder
    private var topBar: some View {
        if isHome {
            HStack(spacing: 10) {
                circleButton("line.3.horizontal", action: onMenu)
                Spacer(minLength: 0)
                circleButton(settings.autoReadAnswers ? "speaker.wave.2.fill" : "speaker.slash", action: toggleAutoRead)
                circleButton("plus", action: onNewChat)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 6)
        } else {
            HStack(spacing: 4) {
                circleButton("line.3.horizontal", action: onMenu)
                Spacer(minLength: 0)
                VStack(spacing: 1) {
                    Text("DeepSeek")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(DSTheme.textPrimary)
                    Text(modelName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DSTheme.textSecondary)
                }
                Spacer(minLength: 0)
                circleButton("plus", action: onNewChat)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(DSTheme.background)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(DSTheme.hairline.opacity(0.25))
                    .frame(height: 0.5)
            }
        }
    }

    private func circleButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(DSTheme.textPrimary)
                .frame(width: 40, height: 40)
                .background(DSTheme.surface, in: Circle())
                .overlay(Circle().stroke(DSTheme.hairline.opacity(0.25), lineWidth: 0.5))
                .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var apiKeyBanner: some View {
        Button(action: onOpenSettings) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("还没配置 API Key，点这里填写后开始对话")
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(DSTheme.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(DSTheme.accent.opacity(0.09))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 消息列表

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if let conversation, !conversation.isEmpty {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(Array(conversation.messages.enumerated()), id: \.element.id) { index, message in
                            MessageRow(
                                message: message,
                                isStreaming: chat.isStreaming && index == conversation.messages.count - 1,
                                isLastAssistant: isLastAssistantMessage(at: index, in: conversation),
                                fontScale: CGFloat(settings.fontScale),
                                isSpeaking: tts.speakingMessageID == message.id,
                                onCopy: {
                                    UIPasteboard.general.string = message.content
                                    onToast("已复制")
                                },
                                onDelete: { chat.deleteMessage(message.id) },
                                onRegenerate: { chat.regenerate(settings: settings) },
                                onSpeak: { speak(message) }
                            )
                        }
                        Color.clear
                            .frame(height: 1)
                            .id(bottomID)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                } else {
                    WelcomeView()
                        .padding(.top, 8)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: conversation?.messages.count) { _ in
                scrollToBottom(proxy)
            }
            .onChange(of: lastMessageSignature) { _ in
                scrollToBottom(proxy)
            }
            .onChange(of: isInputFocused) { focused in
                if focused { scrollToBottom(proxy) }
            }
            .onChange(of: conversation?.id) { _ in
                attachments = []
                tts.stop()
                scrollToBottom(proxy)
            }
        }
    }

    private var lastMessageSignature: Int {
        let content = conversation?.messages.last?.content.count ?? 0
        let reasoning = conversation?.messages.last?.reasoning?.count ?? 0
        return content * 1_000_000 + reasoning
    }

    private func isLastAssistantMessage(at index: Int, in conversation: Conversation) -> Bool {
        guard conversation.messages.indices.contains(index) else { return false }
        guard conversation.messages[index].role == .assistant else { return false }
        return index == conversation.messages.count - 1
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let conversation, !conversation.isEmpty else { return }
        proxy.scrollTo(bottomID, anchor: .bottom)
    }

    private func sendDraft() {
        if chat.send(draft, attachments: attachments, settings: settings) {
            draft = ""
            attachments = []
        } else if !settings.hasAPIKey {
            onToast("先在设置里填 API Key")
        }
    }

    private func speak(_ message: ChatMessage) {
        tts.speak(
            messageID: message.id,
            text: message.content,
            voice: settings.ttsVoice,
            apiKey: settings.apiKey,
            baseURL: settings.baseURL
        )
    }

    private func toggleAutoRead() {
        var updated = settingsStore.settings
        updated.autoReadAnswers.toggle()
        settingsStore.settings = updated
        onToast(updated.autoReadAnswers ? "已开启自动朗读" : "已关闭自动朗读")
    }

    private func toggleThinking() {
        var updated = settingsStore.settings
        updated.thinkingEnabled.toggle()
        settingsStore.settings = updated
    }

    private func toggleWebSearch() {
        var updated = settingsStore.settings
        updated.webSearchEnabled.toggle()
        if updated.webSearchEnabled, updated.model == "deepseek-v4-pro" {
            onToast("V4-Pro 不支持联网搜索，已切到 V4.1-Flash")
            updated.model = "deepseek-flash"
        }
        settingsStore.settings = updated
    }
}
