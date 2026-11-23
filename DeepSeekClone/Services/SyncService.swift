import Foundation

/// 与用户自建同步服务（Cloudflare Worker / 任意 HTTP 服务）交换全部会话。
@MainActor
final class SyncService: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published var statusText: String?
    @Published private(set) var lastSyncDate: Date?

    private let session: URLSession
    private let deviceID: String

    struct Payload: Codable {
        var format: String = ConversationArchive.formatName
        var version: Int = ConversationArchive.formatVersion
        var device: String
        var updatedAt: Date
        var conversations: [Conversation]
    }

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 90
        self.session = URLSession(configuration: configuration)
        let key = "deepseek_clone_device_id"
        if let stored = UserDefaults.standard.string(forKey: key) {
            deviceID = stored
        } else {
            let generated = UUID().uuidString
            UserDefaults.standard.set(generated, forKey: key)
            deviceID = generated
        }
    }

    var isConfigured: Bool { true }

    static func isReady(urlString: String, key: String) -> Bool {
        let url = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return url.hasPrefix("https://") && !secret.isEmpty && URL(string: url) != nil
    }

    /// 从云端拉取。
    func pull(urlString: String, key: String) async throws -> [Conversation] {
        guard let url = Self.makeURL(urlString) else {
            throw DeepSeekError(message: "同步地址无效，需要以 https:// 开头。")
        }
        let request = try makeRequest(url: url, method: "GET", key: key, body: nil)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekError(message: "同步服务返回了无法识别的响应。")
        }
        if http.statusCode == 404 {
            return []
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DeepSeekError(message: "下载失败（HTTP \(http.statusCode)）：\(String((String(data: data, encoding: .utf8) ?? "").prefix(160)))")
        }
        if data.isEmpty || data == Data("{}{}".utf8) { return [] }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let empty = json["conversations"] as? [Any], empty.isEmpty {
            return []
        }
        return try ConversationArchive.decode(data)
    }

    /// 上传到云端（覆盖）。
    func push(_ conversations: [Conversation], urlString: String, key: String) async throws {
        guard let url = Self.makeURL(urlString) else {
            throw DeepSeekError(message: "同步地址无效，需要以 https:// 开头。")
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = Payload(device: deviceID, updatedAt: Date(), conversations: conversations)
        let body = try encoder.encode(payload)
        let request = try makeRequest(url: url, method: "PUT", key: key, body: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw DeepSeekError(message: "上传失败（HTTP \(status)）：\(String((String(data: data, encoding: .utf8) ?? "").prefix(160)))")
        }
    }

    /// 双向同步：先拉取合并，再整体上传，返回合并后的结果。
    func syncBoth(local: [Conversation], urlString: String, key: String) async throws -> [Conversation] {
        let remote = try await pull(urlString: urlString, key: key)
        let merged = ConversationArchive.merge(remote, into: local)
        try await push(merged, urlString: urlString, key: key)
        lastSyncDate = Date()
        return merged
    }

    private func makeRequest(url: URL, method: String, key: String, body: Data?) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue(key, forHTTPHeaderField: "X-Sync-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("DeepSeekClone/1.5 (iOS)", forHTTPHeaderField: "User-Agent")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }

    private static func makeURL(_ urlString: String) -> URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("https://"), let url = URL(string: trimmed) else { return nil }
        return url
    }
}
