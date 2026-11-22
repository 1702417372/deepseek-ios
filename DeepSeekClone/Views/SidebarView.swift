import SwiftUI

struct SidebarView: View {
    let conversations: [Conversation]
    let selectedID: UUID?

    var onSelect: (Conversation) -> Void
    var onNewChat: () -> Void
    var onDelete: (UUID) -> Void
    var onSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            newChatButton
            Divider().opacity(0.5)
            conversationList
            Divider().opacity(0.5)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DSTheme.sidebar.ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: 10) {
            AssistantAvatar(size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("DeepSeek")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(DSTheme.textPrimary)
                Text("本地客户端")
                    .font(.system(size: 10))
                    .foregroundStyle(DSTheme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var newChatButton: some View {
        Button(action: onNewChat) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text("新建对话")
                    .font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(DSTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var conversationList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if conversations.isEmpty {
                    Text("还没有对话记录")
                        .font(.system(size: 13))
                        .foregroundStyle(DSTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 36)
                } else {
                    Text("最近对话")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DSTheme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 4)

                    ForEach(conversations) { conversation in
                        row(for: conversation)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
    }

    private func row(for conversation: Conversation) -> some View {
        let selected = conversation.id == selectedID
        return Button {
            onSelect(conversation)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? DSTheme.accent : DSTheme.textSecondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .font(.system(size: 14, weight: selected ? .semibold : .regular))
                        .foregroundStyle(DSTheme.textPrimary)
                        .lineLimit(1)
                    Text(conversation.preview)
                        .font(.system(size: 11))
                        .foregroundStyle(DSTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Text(DSTheme.dateString(conversation.updatedAt))
                    .font(.system(size: 10))
                    .foregroundStyle(DSTheme.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                selected ? DSTheme.accent.opacity(0.13) : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                onDelete(conversation.id)
            } label: {
                Label("删除对话", systemImage: "trash")
            }
        }
    }

    private var footer: some View {
        Button(action: onSettings) {
            HStack(spacing: 10) {
                Image(systemName: "gearshape")
                    .font(.system(size: 15))
                Text("设置")
                    .font(.system(size: 14, weight: .medium))
                Spacer(minLength: 0)
                Text("API / 模型")
                    .font(.system(size: 11))
                    .foregroundStyle(DSTheme.textSecondary)
            }
            .foregroundStyle(DSTheme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 12)
    }
}
