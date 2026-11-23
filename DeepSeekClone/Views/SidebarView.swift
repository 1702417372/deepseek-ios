import SwiftUI

/// 侧边栏：对齐官方 App —— 搜索、置顶/7天内/30天内分组、选择模式（置顶/删除）、底部账号行。
struct SidebarView: View {
    let conversations: [Conversation]
    let selectedID: UUID?

    var onSelect: (Conversation) -> Void
    var onNewChat: () -> Void
    var onDelete: (UUID) -> Void
    var onRename: (Conversation) -> Void
    var onExport: (Conversation) -> Void
    var onTogglePin: (Conversation) -> Void
    var onSettings: () -> Void

    @State private var query = ""
    @State private var selectionMode = false
    @State private var selected: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            topBar
            searchField
            if selectionMode { selectionHeader }
            conversationList
            Divider().opacity(0.4)
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DSTheme.sidebar.ignoresSafeArea())
    }

    // MARK: - 顶部

    private var topBar: some View {
        HStack(spacing: 10) {
            Text("DeepSeek")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(DSTheme.textPrimary)
            Spacer(minLength: 0)
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    selectionMode.toggle()
                    if !selectionMode { selected.removeAll() }
                }
            } label: {
                Text(selectionMode ? "取消" : "选择")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DSTheme.accent)
            }
            .buttonStyle(.plain)

            Button(action: onNewChat) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(DSTheme.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(DSTheme.surface, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DSTheme.textSecondary)
            TextField("搜索对话内容…", text: $query)
                .font(.system(size: 14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(DSTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(DSTheme.surface, in: Capsule())
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var selectionHeader: some View {
        HStack {
            Text("选择对话")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DSTheme.textSecondary)
            Spacer(minLength: 0)
            Text(selected.isEmpty ? "未选择" : "已选 \(selected.count) 个")
                .font(.system(size: 12))
                .foregroundStyle(DSTheme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: - 分组列表

    private var filtered: [Conversation] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return conversations }
        return conversations.filter { $0.title.localizedCaseInsensitiveContains(keyword) || $0.messages.contains { $0.content.localizedCaseInsensitiveContains(keyword) } }
    }

    private var groups: [(String, [Conversation])] {
        let now = Date()
        var pinned: [Conversation] = []
        var week: [Conversation] = []
        var month: [Conversation] = []
        var older: [Conversation] = []
        for conversation in filtered {
            if conversation.isPinned == true {
                pinned.append(conversation)
            } else if now.timeIntervalSince(conversation.updatedAt) <= 7 * 86400 {
                week.append(conversation)
            } else if now.timeIntervalSince(conversation.updatedAt) <= 30 * 86400 {
                month.append(conversation)
            } else {
                older.append(conversation)
            }
        }
        var result: [(String, [Conversation])] = []
        if !pinned.isEmpty { result.append(("置顶", pinned)) }
        if !week.isEmpty { result.append(("7天内", week)) }
        if !month.isEmpty { result.append(("30天内", month)) }
        if !older.isEmpty { result.append(("更早", older)) }
        return result
    }

    private var conversationList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if filtered.isEmpty {
                    Text(query.isEmpty ? "还没有对话记录" : "没有匹配的对话")
                        .font(.system(size: 13))
                        .foregroundStyle(DSTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 36)
                } else {
                    ForEach(groups, id: \.0) { group in
                        Text(group.0)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DSTheme.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                        ForEach(group.1) { conversation in
                            row(for: conversation)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
    }

    private func row(for conversation: Conversation) -> some View {
        let isSelected = selected.contains(conversation.id)
        let isCurrent = selectedID == conversation.id
        return HStack(spacing: 10) {
            if selectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(isSelected ? DSTheme.accent : DSTheme.hairline)
            }
            Text(conversation.title.isEmpty ? "新对话" : conversation.title)
                .font(.system(size: 15, weight: isCurrent && !selectionMode ? .semibold : .regular))
                .foregroundStyle(DSTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selectionMode && isSelected ? DSTheme.accent.opacity(0.10) : (isCurrent && !selectionMode ? DSTheme.surface : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if selectionMode {
                if isSelected { selected.remove(conversation.id) } else { selected.insert(conversation.id) }
            } else {
                onSelect(conversation)
            }
        }
        .contextMenu {
            Button {
                onTogglePin(conversation)
            } label: {
                Label(conversation.isPinned == true ? "取消置顶" : "置顶", systemImage: "pin")
            }
            Button {
                onRename(conversation)
            } label: {
                Label("重命名", systemImage: "pencil")
            }
            Button {
                onExport(conversation)
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                onDelete(conversation.id)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    // MARK: - 底部

    @ViewBuilder
    private var bottomBar: some View {
        if selectionMode {
            HStack(spacing: 0) {
                selectionAction(title: "置顶", icon: "pin") {
                    for id in selected { if let conversation = conversations.first(where: { $0.id == id }) { onTogglePin(conversation) } }
                    selected.removeAll()
                }
                Divider().frame(height: 24).opacity(0.4)
                selectionAction(title: "删除", icon: "trash", destructive: true) {
                    for id in selected { onDelete(id) }
                    selected.removeAll()
                }
            }
            .padding(.vertical, 6)
            .padding(.bottom, 6)
        } else {
            Button(action: onSettings) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(LinearGradient(colors: [DSTheme.accent.opacity(0.85), DSTheme.accent.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.white)
                        )
                    Text("Blue")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(DSTheme.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(DSTheme.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 6)
        }
    }

    private func selectionAction(title: String, icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(destructive ? Color.red : DSTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(selected.isEmpty)
        .opacity(selected.isEmpty ? 0.4 : 1)
    }
}
