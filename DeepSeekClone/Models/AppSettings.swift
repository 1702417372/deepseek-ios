import Foundation

/// 可选模型。
enum DeepSeekModel: String, CaseIterable, Identifiable {
    case chat = "deepseek-chat"
    case reasoner = "deepseek-reasoner"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: return "DeepSeek-V3"
        case .reasoner: return "DeepSeek-R1"
        }
    }

    var subtitle: String {
        switch self {
        case .chat: return "快速回答，适合日常对话"
        case .reasoner: return "深度思考，推理更强（较慢）"
        }
    }

    var icon: String {
        switch self {
        case .chat: return "bolt.fill"
        case .reasoner: return "brain"
        }
    }
}

/// App 设置。API Key 单独存放在钥匙串里（见 SettingsStore）。
struct AppSettings: Codable, Equatable {
    var apiKey: String = ""
    var baseURL: String = "https://api.deepseek.com"
    var model: String = DeepSeekModel.chat.rawValue
    var temperature: Double = 1.0
    var systemPrompt: String = ""

    init() {}

    private enum CodingKeys: String, CodingKey {
        case apiKey
        case baseURL
        case model
        case temperature
        case systemPrompt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? "https://api.deepseek.com"
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? DeepSeekModel.chat.rawValue
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 1.0
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(model, forKey: .model)
        try container.encode(temperature, forKey: .temperature)
        try container.encode(systemPrompt, forKey: .systemPrompt)
    }

    var resolvedModel: DeepSeekModel {
        DeepSeekModel(rawValue: model) ?? .chat
    }

    var trimmedBaseURL: String {
        let url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return url.isEmpty ? "https://api.deepseek.com" : url
    }

    var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
