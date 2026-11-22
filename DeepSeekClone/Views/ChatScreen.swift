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
                modelOption: modelOption,
                settings: settings,
                onSend: sendDraft,
                onStop: { chat.stop() },
                onSelectModel: { showModelSheet = true },
                onToggleThinking: toggleThinking,
                onToggleWebSearch: toggleWebSearch,
                onNewChat: onNewChat,
                onClear: { chat.clearCurrentConversation() },
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

    private var topBar: some View {
        HStack(spacing: 4) {
            iconButton("line.3.horizontal", action: onMenu)

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

            iconButton("plus", action: onNewChat)
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

    private func iconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(DSTheme.textPrimary)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

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
                    WelcomeView { suggestion in
                        draft = suggestion
                        isInputFocused = true
                    }
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
