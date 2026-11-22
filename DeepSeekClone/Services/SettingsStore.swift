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
