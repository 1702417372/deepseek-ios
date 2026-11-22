import Foundation

/// 内置兜底模型；真实列表由 ModelCatalog 从 /models 动态拉取。
enum DeepSeekModel: String, CaseIterable, Identifiable {
    case flash = "deepseek-flash"
    case pro = "deepseek-v4-pro"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flash: return "DeepSeek-V4.1-Flash"
        case .pro: return "DeepSeek-V4-Pro"
        }
    }

    var subtitle: String {
        switch self {
        case .flash: return "多模态 · 支持图片与文件 · 快"
        case .pro: return "纯文本 · 推理更强"
        }
    }

    var icon: String {
        switch self {
        case .flash: return "bolt.fill"
        case .pro: return "brain"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var apiKey: String = ""
    var baseURL: String = "https://api.deepseek.com"
    var model: String = DeepSeekModel.flash.rawValue
    var temperature: Double = 1.0

    /// 思考模式开关（thinking.type）
    var thinkingEnabled: Bool = true
    /// 思考强度（reasoning_effort）：low / high / max
    var reasoningEffort: String = "high"
    /// 联网搜索工具（deepseek_web_search）
    var webSearchEnabled: Bool = false
    /// 阅读链接工具（deepseek_read_url）
    var readURLEnabled: Bool = false
    /// 会话标题由服务端生成（title.enabled）
    var autoTitleEnabled: Bool = true
    /// 内容安全校验（safety_check）
    var safetyCheckEnabled: Bool = false

    var systemPrompt: String = ""
    /// 发送历史的最大字符数，超出时丢弃最早的消息
    var contextCharacterLimit: Int = 60000
    /// 消息字号缩放（0.85 / 1.0 / 1.15 / 1.3）
    var fontScale: Double = 1.0

    init() {}

    private enum CodingKeys: String, CodingKey {
        case apiKey
        case baseURL
        case model
        case temperature
        case thinkingEnabled
        case reasoningEffort
        case webSearchEnabled
        case readURLEnabled
        case autoTitleEnabled
        case safetyCheckEnabled
        case systemPrompt
        case contextCharacterLimit
        case fontScale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? "https://api.deepseek.com"
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? DeepSeekModel.flash.rawValue
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 1.0
        thinkingEnabled = try container.decodeIfPresent(Bool.self, forKey: .thinkingEnabled) ?? true
        reasoningEffort = try container.decodeIfPresent(String.self, forKey: .reasoningEffort) ?? "high"
        webSearchEnabled = try container.decodeIfPresent(Bool.self, forKey: .webSearchEnabled) ?? false
        readURLEnabled = try container.decodeIfPresent(Bool.self, forKey: .readURLEnabled) ?? false
        autoTitleEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoTitleEnabled) ?? true
        safetyCheckEnabled = try container.decodeIfPresent(Bool.self, forKey: .safetyCheckEnabled) ?? false
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? ""
        contextCharacterLimit = try container.decodeIfPresent(Int.self, forKey: .contextCharacterLimit) ?? 60000
        fontScale = try container.decodeIfPresent(Double.self, forKey: .fontScale) ?? 1.0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(model, forKey: .model)
        try container.encode(temperature, forKey: .temperature)
        try container.encode(thinkingEnabled, forKey: .thinkingEnabled)
        try container.encode(reasoningEffort, forKey: .reasoningEffort)
        try container.encode(webSearchEnabled, forKey: .webSearchEnabled)
        try container.encode(readURLEnabled, forKey: .readURLEnabled)
        try container.encode(autoTitleEnabled, forKey: .autoTitleEnabled)
        try container.encode(safetyCheckEnabled, forKey: .safetyCheckEnabled)
        try container.encode(systemPrompt, forKey: .systemPrompt)
        try container.encode(contextCharacterLimit, forKey: .contextCharacterLimit)
        try container.encode(fontScale, forKey: .fontScale)
    }

    var resolvedModel: DeepSeekModel {
        DeepSeekModel(rawValue: model) ?? .flash
    }

    var trimmedBaseURL: String {
        let url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return url.isEmpty ? "https://api.deepseek.com" : url
    }

    var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
