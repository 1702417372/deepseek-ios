import Foundation

/// 一个可用模型（来自 GET /models，失败时用内置兜底）。
struct ModelOption: Identifiable, Equatable, Codable {
    var id: String
    var name: String
    var contextWindow: Int?
    var maxOutputTokens: Int?
    var supportsImages: Bool
    var effortLevels: [String]
    var defaultEffort: String?

    var shortName: String {
        name.isEmpty ? id : name
    }

    var capabilityText: String {
        var parts: [String] = []
        parts.append(supportsImages ? "图文输入" : "纯文本")
        if let contextWindow {
            let k = Double(contextWindow) / 1000.0
            parts.append(k >= 1000 ? String(format: "%.0fM 上下文", k / 1000) : String(format: "%.0fK 上下文", k))
        }
        return parts.joined(separator: " · ")
    }

    static let fallback: [ModelOption] = [
        ModelOption(id: "deepseek-flash", name: "DeepSeek-V4.1-Flash", contextWindow: 1048576, maxOutputTokens: 393216, supportsImages: true, effortLevels: ["low", "high", "max"], defaultEffort: "high"),
        ModelOption(id: "deepseek-v4-pro", name: "DeepSeek-V4-Pro", contextWindow: 1048576, maxOutputTokens: 393216, supportsImages: false, effortLevels: ["low", "high", "max"], defaultEffort: "high")
    ]
}

private struct ModelsResponse: Decodable {
    let data: [ModelPayload]
}

private struct ModelPayload: Decodable {
    let id: String
    let name: String?
    let contextWindow: Int?
    let maxOutputTokens: Int?
    let inputModalities: [String]?
    let effort: EffortPayload?

    struct EffortPayload: Decodable {
        let supportedLevels: [String]?
        let defaultLevel: String?
    }
}

/// 模型目录：启动时先用缓存/兜底，联网后刷新。
@MainActor
final class ModelCatalog: ObservableObject {
    @Published private(set) var options: [ModelOption] = ModelOption.fallback
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?
    @Published var errorMessage: String?

    private let cacheKey = "deepseek_clone_model_catalog_v1"

    init() {
        loadCache()
    }

    func option(for id: String) -> ModelOption? {
        options.first(where: { $0.id == id })
    }

    /// 拿不到模型元数据时的展示名。
    func displayName(for id: String) -> String {
        option(for: id)?.shortName ?? id
    }

    func refresh(apiKey: String, baseURL: String) async {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        guard let url = Self.modelsURL(baseURL: baseURL) else {
            errorMessage = "Base URL 无效"
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw DeepSeekError(message: "模型列表响应异常")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw DeepSeekError(message: DeepSeekClient.errorMessage(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? ""))
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let payload = try decoder.decode(ModelsResponse.self, from: data)
            let mapped = payload.data.map { item in
                ModelOption(
                    id: item.id,
                    name: item.name ?? item.id,
                    contextWindow: item.contextWindow,
                    maxOutputTokens: item.maxOutputTokens,
                    supportsImages: (item.inputModalities ?? []).contains("image"),
                    effortLevels: item.effort?.supportedLevels ?? ["low", "high", "max"],
                    defaultEffort: item.effort?.defaultLevel
                )
            }
            if !mapped.isEmpty {
                options = mapped
                lastUpdated = Date()
                saveCache()
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private static func modelsURL(baseURL: String) -> URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = "https://api.deepseek.com" }
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasSuffix("/chat/completions") {
            base = String(base.dropLast("/chat/completions".count))
        }
        return URL(string: base + "/models")
    }

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode([ModelOption].self, from: data),
              !cached.isEmpty else { return }
        options = cached
    }

    private func saveCache() {
        guard let data = try? JSONEncoder().encode(options) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
}
