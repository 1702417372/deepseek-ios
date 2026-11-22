import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var conversationStore: ConversationStore
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var chat = ChatViewModel()

    @State private var sidebarOpen = false
    @State private var showSettings = false
    @State private var didBootstrap = false
    @State private var confirmClearChat = false

    var body: some View {
        ZStack(alignment: .leading) {
            ChatScreen(
                chat: chat,
                settings: settingsStore.settings,
                onMenu: { setSidebar(true) },
                onNewChat: { newChat() },
                onOpenSettings: { showSettings = true },
                onSelectModel: { selectModel($0) },
                onClear: { confirmClearChat = true }
            )
            .disabled(sidebarOpen)

            if sidebarOpen {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { setSidebar(false) }

                SidebarView(
                    conversations: conversationStore.sorted,
                    selectedID: chat.conversation?.id,
                    onSelect: { conversation in
                        setSidebar(false)
                        chat.open(conversation)
                    },
                    onNewChat: {
                        setSidebar(false)
                        newChat()
                    },
                    onDelete: { id in
                        conversationStore.delete(id)
                    },
                    onSettings: {
                        setSidebar(false)
                        showSettings = true
                    }
                )
                .frame(width: sidebarWidth)
                .transition(.move(edge: .leading))
                .zIndex(1)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: sidebarOpen)
        .onAppear(perform: bootstrap)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settingsStore)
                .environmentObject(conversationStore)
        }
        .alert("清空当前对话？", isPresented: $confirmClearChat) {
            Button("清空", role: .destructive) {
                chat.clearCurrentConversation()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("只会清空当前会话里的消息。")
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                // 先把流式中的内容同步给存储层，再立即写盘
                chat.flushToStore()
                conversationStore.saveNow()
            }
        }
        .onChange(of: conversationStore.conversations.map(\.id)) { ids in
            // 当前会话被删除（单条删除或清空全部）时，自动切到最近会话或新建
            guard let current = chat.conversation, !ids.contains(current.id) else { return }
            if let next = conversationStore.sorted.first {
                chat.open(next)
            } else {
                // 不能调 newChat()：当前会话为空时它会提前 return，导致 chat 仍指向已删除的会话
                let conversation = conversationStore.createConversation(model: settingsStore.settings.model)
                chat.open(conversation)
            }
        }
    }

    private var sidebarWidth: CGFloat {
        let width = UIScreen.main.bounds.width
        return min(max(width * 0.84, 280), 340)
    }

    private func setSidebar(_ open: Bool) {
        if open {
            _ = UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        sidebarOpen = open
    }

    private func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        chat.onConversationChanged = { conversation in
            conversationStore.upsert(conversation)
        }
        if let existing = conversationStore.sorted.first {
            chat.open(existing)
        } else {
            let conversation = conversationStore.createConversation(model: settingsStore.settings.model)
            chat.open(conversation)
        }
    }

    private func newChat() {
        if let current = chat.conversation, current.isEmpty {
            return
        }
        let conversation = conversationStore.createConversation(model: settingsStore.settings.model)
        chat.open(conversation)
    }

    private func selectModel(_ model: DeepSeekModel) {
        var updated = settingsStore.settings
        updated.model = model.rawValue
        settingsStore.settings = updated
    }
}
