import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var conversationStore: ConversationStore
    @EnvironmentObject private var modelCatalog: ModelCatalog
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var chat = ChatViewModel()
    @StateObject private var toast = ToastCenter()
    @StateObject private var sync = SyncService()

    @State private var sidebarOpen = false
    @State private var didBootstrap = false
    @State private var activeSheet: ActiveSheet?
    @State private var confirmClearChat = false

    private enum ActiveSheet: Identifiable {
        case settings
        case share(URL)
        case rename(Conversation)

        var id: String {
            switch self {
            case .settings: return "settings"
            case .share(let url): return "share-" + url.absoluteString
            case .rename(let conversation): return "rename-" + conversation.id.uuidString
            }
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            ChatScreen(
                chat: chat,
                onMenu: { setSidebar(true) },
                onNewChat: { newChat() },
                onOpenSettings: { activeSheet = .settings },
                onToast: { toast.show($0) }
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
                    onRename: { conversation in
                        setSidebar(false)
                        activeSheet = .rename(conversation)
                    },
                    onExport: { conversation in
                        setSidebar(false)
                        export(conversation)
                    },
                    onTogglePin: { conversation in
                        conversationStore.togglePin(conversation.id)
                    },
                    onSettings: {
                        setSidebar(false)
                        activeSheet = .settings
                    }
                )
                .frame(width: sidebarWidth)
                .transition(.move(edge: .leading))
                .zIndex(1)
            }
        }
        .overlay(alignment: .bottom) { toastOverlay }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: sidebarOpen)
        .animation(.easeInOut(duration: 0.2), value: toast.message)
        .onAppear(perform: bootstrap)
        .task {
            await refreshModelsIfNeeded()
            await autoSyncIfConfigured()
        }
        .onChange(of: settingsStore.settings.apiKey) { _ in
            Task { await refreshModelsIfNeeded() }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                chat.flushToStore()
                conversationStore.saveNow()
            }
        }
        .onChange(of: conversationStore.conversations.map(\.id)) { ids in
            guard let current = chat.conversation, !ids.contains(current.id) else { return }
            if let next = conversationStore.sorted.first {
                chat.open(next)
            } else {
                let conversation = conversationStore.createConversation(model: settingsStore.settings.model)
                chat.open(conversation)
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .settings:
                SettingsView()
                    .environmentObject(settingsStore)
                    .environmentObject(conversationStore)
                    .environmentObject(modelCatalog)
                    .environmentObject(sync)
            case .share(let url):
                ShareSheet(url: url)
            case .rename(let conversation):
                RenameSheet(conversation: conversation) { newTitle in
                    conversationStore.rename(conversation.id, to: newTitle)
                    if var current = chat.conversation, current.id == conversation.id {
                        current.title = newTitle
                        chat.open(current)
                    }
                }
            }
        }
        .confirmationDialog("清空当前对话？", isPresented: $confirmClearChat, titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                chat.clearCurrentConversation()
            }
            Button("取消", role: .cancel) { }
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let message = toast.message {
            ToastView(text: message)
                .padding(.bottom, 120)
                .transition(.opacity)
                .allowsHitTesting(false)
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

        if let screen = DemoSupport.requestedScreen {
            setupDemo(screen)
            return
        }

        if let existing = conversationStore.sorted.first {
            chat.open(existing)
        } else {
            let conversation = conversationStore.createConversation(model: settingsStore.settings.model)
            chat.open(conversation)
        }
    }

    private func setupDemo(_ screen: String) {
        var conversation: Conversation
        if screen == "home" {
            conversation = Conversation(model: settingsStore.settings.model)
        } else {
            conversation = DemoSupport.demoConversation()
        }
        conversationStore.upsert(conversation)
        chat.open(conversation)

        if screen == "drawer" {
            sidebarOpen = true
        } else if screen == "settings" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                activeSheet = .settings
            }
        }
    }

    /// 启动时后台做一次双向同步（配置了同步地址才执行）。
    private func autoSyncIfConfigured() async {
        let settings = settingsStore.settings
        guard settings.autoSyncEnabled,
              SyncService.isReady(urlString: settings.syncURL, key: settings.syncKey) else { return }
        do {
            let merged = try await sync.syncBoth(
                local: conversationStore.all,
                urlString: settings.syncURL,
                key: settings.syncKey
            )
            conversationStore.replaceAll(merged)
        } catch {
            // 启动同步失败保持静默，用户在设置页手动同步能看到具体错误
        }
    }

    private func refreshModelsIfNeeded() async {
        let settings = settingsStore.settings
        guard settings.hasAPIKey else { return }
        await modelCatalog.refresh(apiKey: settings.apiKey, baseURL: settings.baseURL)
    }

    private func newChat() {
        // 当前会话是空的时候先删掉，避免侧边栏堆一堆空对话
        if let current = chat.conversation, current.isEmpty {
            conversationStore.delete(current.id)
        }
        let conversation = conversationStore.createConversation(model: settingsStore.settings.model)
        chat.open(conversation)
        toast.show("已新建对话")
        _ = UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func export(_ conversation: Conversation) {
        do {
            let url = try ConversationExporter.writeTemporaryFile(for: conversation)
            activeSheet = .share(url)
        } catch {
            toast.show("导出失败：\(error.localizedDescription)")
        }
    }
}
