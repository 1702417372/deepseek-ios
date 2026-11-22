import SwiftUI

@main
struct DeepSeekCloneApp: App {
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var conversationStore = ConversationStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settingsStore)
                .environmentObject(conversationStore)
        }
    }
}
