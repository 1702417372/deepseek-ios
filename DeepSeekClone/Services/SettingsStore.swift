import Foundation

/// 设置持久化：普通字段写 JSON，API Key 单独进钥匙串。
@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { persist() }
    }

    private let fileURL: URL
    private let apiKeyAccount = "deepseek-api-key"

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("settings.json")

        var loaded = AppSettings()
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            loaded = decoded
        }
        // 旧版本保存过 deepseek-chat / reasoner 等模型名，新版 API 已停用，迁移到 deepseek-flash
        let legacyModelIDs: Set<String> = [
            "deepseek-chat", "deepseek-reasoner", "deepseek-v3", "deepseek-r1",
            "deepseek-v3.2", "deepseek-v4-flash", "deepseek-v4-flash-vision-exp"
        ]
        if legacyModelIDs.contains(loaded.model) {
            loaded.model = "deepseek-flash"
        }
        loaded.apiKey = KeychainHelper.read(for: apiKeyAccount) ?? ""
        settings = loaded
    }

    private func persist() {
        var copy = settings
        copy.apiKey = ""
        if let data = try? JSONEncoder().encode(copy) {
            try? data.write(to: fileURL, options: .atomic)
        }
        if !KeychainHelper.save(settings.apiKey, for: apiKeyAccount) {
            NSLog("DeepSeekClone: 保存 API Key 到钥匙串失败")
        }
    }
}
