import SwiftUI
import UIKit

struct ChatScreen: View {
    @ObservedObject var chat: ChatViewModel
    let settings: AppSettings

    var onMenu: () -> Void
    var onNewChat: () -> Void
    var onOpenSettings: () -> Void
    var onSelectModel: (DeepSeekModel) -> Void
    var onClear: () -> Void

    @State private var draft = ""
    @FocusState private var isInputFocused: Bool

    private let bottomID = "chat-bottom"

    private var conversation: Conversation? { chat.conversation }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            messageList
        }
        .background(DSTheme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ComposerBar(
                text: $draft,
                isFocused: $isInputFocused,
                isStreaming: chat.isStreaming,
                model: settings.resolvedModel,
                onSend: sendDraft,
                onStop: { chat.stop() },
                onSelectModel: onSelectModel,
                onNewChat: onNewChat,
                onClear: onClear,
                onOpenSettings: onOpenSettings
            )
        }
        .alert("请求失败", isPresented: errorBinding) {
            Button("重试") {
                chat.regenerate(settings: settings)
            }
            Button("好", role: .cancel) {
                chat.errorMessage = nil
            }
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
                Text(settings.resolvedModel.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DSTheme.textSecondary)
            }

            Spacer(minLength: 0)

            iconButton("square.and.pencil", action: onNewChat)
            iconButton("gearshape", action: onOpenSettings)
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
                                onCopy: { UIPasteboard.general.string = message.content },
                                onRegenerate: { chat.regenerate(settings: settings) }
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
        if chat.send(draft, settings: settings) {
            draft = ""
        }
    }
}
