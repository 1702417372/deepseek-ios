import Foundation

/// 业务层错误，message 直接展示给用户。
struct DeepSeekError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// 一次请求用到的全部参数。
struct ChatRequestOptions {
    var model: String
    var thinkingEnabled: Bool
    var reasoningEffort: String
    var webSearchEnabled: Bool
    var readURLEnabled: Bool
    var autoTitleEnabled: Bool
    var safetyCheckEnabled: Bool
    var temperature: Double
    var systemPrompt: String
    var contextCharacterLimit: Int

    init(settings: AppSettings, model: String? = nil) {
        self.model = model ?? settings.model
        self.thinkingEnabled = settings.thinkingEnabled
        self.reasoningEffort = settings.reasoningEffort
        self.webSearchEnabled = settings.webSearchEnabled
        self.readURLEnabled = settings.readURLEnabled
        self.autoTitleEnabled = settings.autoTitleEnabled
        self.safetyCheckEnabled = settings.safetyCheckEnabled
        self.temperature = settings.temperature
        self.systemPrompt = settings.systemPrompt
        self.contextCharacterLimit = max(4000, settings.contextCharacterLimit)
    }
}

enum ChatStreamEvent {
    case reasoning(String)
    case content(String)
    case searchStarted(queries: [String], kind: String)
    case searchCompleted(sources: [SearchSource])
    case final(title: String?, citations: [Citation], serverToolJSON: String?, finishReason: String?, refusal: String?)
}

/// DeepSeek 2026 版 Chat Completions 客户端：思考模式、联网工具、图片/文件输入、会话标题。
final class DeepSeekClient {
    private let apiKey: String
    private let baseURL: String
    private let session: URLSession

    init(apiKey: String, baseURL: String) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 900
        configuration.waitsForConnectivity = true
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - URL

    private func trimmedBase() -> String {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = "https://api.deepseek.com" }
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasSuffix("/chat/completions") {
            base = String(base.dropLast("/chat/completions".count))
        }
        return base
    }

    func chatCompletionsURL() -> URL? {
        URL(string: trimmedBase() + "/chat/completions")
    }

    private func filesURL() -> URL? {
        URL(string: trimmedBase() + "/files")
    }

    // MARK: - 请求构造

    private func makeJSONRequest(url: URL, body: [String: Any]) throws -> URLRequest {
        guard url.scheme?.lowercased() == "https" else {
            throw DeepSeekError(message: "Base URL 必须是 https:// 开头的地址（iOS 的 ATS 会拦截 http 明文请求）。")
        }
        guard !apiKey.isEmpty else {
            throw DeepSeekError(message: "还没有填写 API Key，请打开设置填入 DeepSeek API Key。")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("DeepSeekClone/1.2 (iOS)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func buildMessages(_ messages: [ChatMessage], options: ChatRequestOptions) -> [[String: Any]] {
        var result: [[String: Any]] = []
        let system = options.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !system.isEmpty {
            result.append(["role": "system", "content": system])
        }

        // 按字符上限裁剪历史，保留最近的消息
        var selected: [ChatMessage] = []
        var total = 0
        for message in messages.reversed() {
            let cost = message.content.count + (message.reasoning?.count ?? 0) + (message.attachmentPrompt?.count ?? 0) + 240
            if !selected.isEmpty && total + cost > options.contextCharacterLimit { break }
            total += cost
            selected.insert(message, at: 0)
        }

        for message in selected {
            switch message.role {
            case .system:
                continue
            case .user:
                var userContent = message.content
                if let extra = message.attachmentPrompt, !extra.isEmpty {
                    userContent += "\n\n" + extra
                }
                var parts: [[String: Any]] = []
                if !userContent.isEmpty {
                    parts.append(["type": "text", "text": userContent])
                }
                let attachments = message.attachments ?? []
                var needsArray = false
                for attachment in attachments {
                    if attachment.kind == .image, let base64 = attachment.imageBase64JPEG {
                        needsArray = true
                        parts.append([
                            "type": "image_url",
                            "image_url": ["url": "data:image/jpeg;base64," + base64, "detail": "auto"]
                        ])
                    } else if attachment.kind == .document, let fileID = attachment.fileID {
                        needsArray = true
                        parts.append(["type": "file", "file_id": fileID])
                    }
                }
                if needsArray {
                    result.append(["role": "user", "content": parts])
                } else if let text = parts.first?["text"] as? String {
                    result.append(["role": "user", "content": text])
                }
            case .assistant:
                if message.isRefused { continue }
                guard !message.content.isEmpty else { continue }
                var dictionary: [String: Any] = ["role": "assistant", "content": message.content]
                if options.webSearchEnabled || options.readURLEnabled {
                    if let reasoning = message.reasoning, !reasoning.isEmpty {
                        dictionary["reasoning_content"] = reasoning
                    }
                    if let raw = message.serverToolJSON,
                       let data = raw.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let calls = parsed["server_tool_calls"] { dictionary["server_tool_calls"] = calls }
                        if let annotations = parsed["annotations"] { dictionary["annotations"] = annotations }
                    }
                }
                result.append(dictionary)
            }
        }
        return result
    }

    private func buildBody(messages: [ChatMessage], options: ChatRequestOptions) -> [String: Any] {
        var body: [String: Any] = [
            "model": options.model,
            "messages": buildMessages(messages, options: options),
            "stream": true,
            "stream_options": ["include_usage": true]
        ]

        body["thinking"] = ["type": options.thinkingEnabled ? "enabled" : "disabled"]
        if options.thinkingEnabled {
            body["reasoning_effort"] = options.reasoningEffort
        } else {
            body["temperature"] = min(max(options.temperature, 0), 2)
        }

        // deepseek-v4-pro 不支持服务端工具（联网/阅读链接）与 title 生成，传了会直接 400
        let serverToolsAvailable = options.model != "deepseek-v4-pro"
        var tools: [[String: Any]] = []
        if options.webSearchEnabled, serverToolsAvailable { tools.append(["type": "deepseek_web_search"]) }
        if options.readURLEnabled, serverToolsAvailable { tools.append(["type": "deepseek_read_url"]) }
        if !tools.isEmpty { body["tools"] = tools }
        if options.safetyCheckEnabled { body["safety_check"] = ["level": "high"] }
        if options.autoTitleEnabled, serverToolsAvailable { body["title"] = ["enabled": true] }
        return body
    }

    // MARK: - 流式对话

    func streamChat(messages: [ChatMessage], options: ChatRequestOptions) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = chatCompletionsURL() else {
                        throw DeepSeekError(message: "接口地址不可用，请检查 Base URL。")
                    }
                    let request = try makeJSONRequest(url: url, body: buildBody(messages: messages, options: options))
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw DeepSeekError(message: "服务端返回了无法识别的响应。")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var raw = ""
                        do {
                            for try await line in bytes.lines {
                                raw += line + " "
                                if raw.count > 4000 { break }
                            }
                        } catch {}
                        throw DeepSeekError(message: DeepSeekClient.errorMessage(status: http.statusCode, body: raw))
                    }

                    let decoder = DeepSeekClient.makeDecoder()
                    var title: String?
                    var citations: [Citation] = []
                    var serverToolJSON: String?
                    var finishReason: String?
                    var refusal: String?

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload.isEmpty { continue }
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let chunk = try? decoder.decode(StreamChunk.self, from: data) else { continue }

                        if let error = chunk.error {
                            throw DeepSeekError(message: error.message ?? "服务端返回错误")
                        }
                        guard let choice = chunk.choices.first else { continue }

                        if let event = choice.serverToolEvent {
                            Self.emitToolEvent(event, to: continuation)
                        }

                        if let delta = choice.delta {
                            if let reasoning = delta.reasoningContent, !reasoning.isEmpty {
                                continuation.yield(.reasoning(reasoning))
                            }
                            if let content = delta.content, !content.isEmpty {
                                continuation.yield(.content(content))
                            }
                            if let chunkTitle = delta.title, !chunkTitle.isEmpty { title = chunkTitle }
                            if let chunkRefusal = delta.refusal, !chunkRefusal.isEmpty { refusal = chunkRefusal }
                            if let annotations = delta.annotations, !annotations.isEmpty {
                                citations = Self.citations(from: annotations)
                            }
                            if let calls = delta.serverToolCalls, !calls.isEmpty {
                                let payloadJSON: [String: Any] = [
                                    "server_tool_calls": calls.map { $0.anyValue },
                                    "annotations": (delta.annotations ?? []).map { $0.anyValue }
                                ]
                                serverToolJSON = JSONValue.serializedJSONString(payloadJSON)
                            }
                        }
                        if let reason = choice.finishReason {
                            finishReason = reason
                        }
                    }

                    continuation.yield(.final(
                        title: title,
                        citations: citations,
                        serverToolJSON: serverToolJSON,
                        finishReason: finishReason,
                        refusal: refusal
                    ))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func emitToolEvent(_ event: ServerToolEvent, to continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation) {
        switch event.type {
        case "call_started":
            let queries = event.call?.action?.queries ?? []
            let kind = event.call?.kind ?? ""
            continuation.yield(.searchStarted(queries: queries, kind: kind))
        case "call_completed":
            let sources = (event.call?.sources ?? []).compactMap { payload -> SearchSource? in
                guard let url = payload.url, !url.isEmpty else { return nil }
                return SearchSource(
                    url: url,
                    title: payload.title ?? url,
                    snippet: payload.snippet,
                    siteName: payload.siteName,
                    publishedAt: payload.publishedAt
                )
            }
            if !sources.isEmpty {
                continuation.yield(.searchCompleted(sources: sources))
            }
        default:
            break
        }
    }

    static func citations(from annotations: [JSONValue]) -> [Citation] {
        var result: [Citation] = []
        for annotation in annotations {
            guard case .object(let dictionary) = annotation,
                  case .object(let citation)? = dictionary["url_citation"] else { continue }
            var url = ""
            var title = ""
            if case .string(let value)? = citation["url"] { url = value }
            if case .string(let value)? = citation["title"] { title = value }
            if !url.isEmpty {
                result.append(Citation(url: url, title: title.isEmpty ? url : title))
            }
        }
        return result
    }

    /// 从最终的 server_tool_calls JSON 里再兜底提取一次来源（有些搜索只出现在最后一个 chunk）。
    static func sources(fromServerToolJSON raw: String) -> [SearchSource] {
        guard let data = raw.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let steps = root["server_tool_calls"] as? [[String: Any]] else { return [] }
        var result: [SearchSource] = []
        var seen = Set<String>()
        for step in steps {
            guard let calls = step["calls"] as? [[String: Any]] else { continue }
            for call in calls {
                if let pages = call["sources"] as? [[String: Any]] {
                    for page in pages {
                        guard let url = page["url"] as? String, !url.isEmpty, !seen.contains(url) else { continue }
                        seen.insert(url)
                        result.append(SearchSource(
                            url: url,
                            title: (page["title"] as? String) ?? url,
                            snippet: page["snippet"] as? String,
                            siteName: page["site_name"] as? String ?? page["siteName"] as? String,
                            publishedAt: page["published_at"] as? String ?? page["publishedAt"] as? String
                        ))
                    }
                }
                if let callsPage = call["page"] as? [String: Any], let url = callsPage["url"] as? String {
                    if !seen.contains(url) {
                        seen.insert(url)
                        result.append(SearchSource(url: url, title: (callsPage["title"] as? String) ?? url, snippet: nil, siteName: nil, publishedAt: callsPage["published_at"] as? String))
                    }
                }
            }
        }
        return result
    }

    // MARK: - 文件上传（Files API）

    static func uploadFile(data: Data, filename: String, purpose: String, apiKey: String, baseURL: String) async throws -> String {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = "https://api.deepseek.com" }
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasSuffix("/chat/completions") { base = String(base.dropLast("/chat/completions".count)) }
        guard let url = URL(string: base + "/files"), url.scheme?.lowercased() == "https" else {
            throw DeepSeekError(message: "文件上传地址不可用，请检查 Base URL。")
        }
        let boundary = "DeepSeekCloneBoundary-" + UUID().uuidString
        var body = Data()
        func append(_ text: String) { body.append(contentsOf: Data(text.utf8)) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"purpose\"\r\n\r\n")
        append(purpose + "\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("DeepSeekClone/1.2 (iOS)", forHTTPHeaderField: "User-Agent")
        request.httpBody = body

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekError(message: "文件上传失败：响应异常")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DeepSeekError(message: errorMessage(status: http.statusCode, body: String(data: responseData, encoding: .utf8) ?? ""))
        }
        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let fileID = json["id"] as? String else {
            throw DeepSeekError(message: "文件上传失败：没有拿到 file_id")
        }
        return fileID
    }

    // MARK: - 连接测试

    func testConnection(model: String) async throws -> String {
        guard let url = chatCompletionsURL() else {
            throw DeepSeekError(message: "接口地址不可用，请检查 Base URL。")
        }
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": "ping"]],
            "thinking": ["type": "disabled"],
            "stream": false,
            "max_tokens": 8
        ]
        let request = try makeJSONRequest(url: url, body: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekError(message: "服务端返回了无法识别的响应。")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DeepSeekError(message: DeepSeekClient.errorMessage(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? ""))
        }
        return "连接成功，模型 \(model) 可用 ✅"
    }

    // MARK: - 解码

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    struct APIError: Decodable {
        let message: String?
        let type: String?
        let code: String?
    }

    struct StreamChunk: Decodable {
        struct Choice: Decodable {
            let delta: Delta?
            let serverToolEvent: ServerToolEvent?
            let finishReason: String?
        }
        struct Delta: Decodable {
            let content: String?
            let reasoningContent: String?
            let annotations: [JSONValue]?
            let serverToolCalls: [JSONValue]?
            let title: String?
            let refusal: String?
        }
        let choices: [Choice]
        let error: APIError?
    }

    struct ServerToolEvent: Decodable {
        struct ToolCall: Decodable {
            struct Action: Decodable {
                let type: String?
                let queries: [String]?
                let url: String?
            }
            struct SourcePayload: Decodable {
                let url: String?
                let title: String?
                let snippet: String?
                let siteName: String?
                let publishedAt: String?
            }
            let index: Int?
            let id: String?
            let type: String?
            let kind: String?
            let action: Action?
            let status: String?
            let sources: [SourcePayload]?
        }
        let type: String
        let step: Int?
        let call: ToolCall?
    }

    static func errorMessage(status: Int, body: String) -> String {
        if let data = body.data(using: .utf8),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
                return "\(message)（HTTP \(status)）"
            }
            if let message = json["message"] as? String {
                return "\(message)（HTTP \(status)）"
            }
        }
        switch status {
        case 400: return "请求参数有误（HTTP 400）"
        case 401: return "API Key 无效，请检查是否填写正确（HTTP 401）"
        case 402: return "账户余额不足，请前往 platform.deepseek.com 充值（HTTP 402）"
        case 429: return "请求太频繁了，请稍后再试（HTTP 429）"
        case 500, 502, 503: return "DeepSeek 服务暂时不可用，请稍后重试（HTTP \(status)）"
        default:
            let snippet = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if snippet.isEmpty { return "请求失败（HTTP \(status)）" }
            return "请求失败（HTTP \(status)）：\(String(snippet.prefix(160)))"
        }
    }
}
