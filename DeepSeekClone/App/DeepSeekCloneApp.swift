import SwiftUI

@main
struct DeepSeekCloneApp: App {
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var conversationStore = ConversationStore()
    @StateObject private var modelCatalog = ModelCatalog()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settingsStore)
                .environmentObject(conversationStore)
                .environmentObject(modelCatalog)
        }
    }
}
