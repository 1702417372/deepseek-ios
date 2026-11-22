import Foundation

/// 业务层错误，message 直接展示给用户。
struct DeepSeekError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// 发给接口的一条消息（OpenAI 兼容格式）。
struct APIMessage: Encodable {
    let role: String
    let content: String
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [APIMessage]
    let stream: Bool
    let temperature: Double
}

private struct StreamDelta: Decodable {
    let content: String?
    let reasoningContent: String?
}

private struct StreamChunk: Decodable {
    struct Choice: Decodable {
        let delta: StreamDelta?
    }
    let choices: [Choice]
}

enum ChatStreamEvent {
    case reasoning(String)
    case content(String)
}

/// DeepSeek OpenAI 兼容接口客户端，支持 SSE 流式输出，可中断。
final class DeepSeekClient {
    private let apiKey: String
    private let baseURL: String
    private let session: URLSession

    /// JSONDecoder 不是线程安全的，每个流各自创建一个。
    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    init(apiKey: String, baseURL: String) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 600
        configuration.waitsForConnectivity = true
        self.session = URLSession(configuration: configuration)
    }

    /// 兼容 https://api.deepseek.com、结尾带斜杠、以及已带 /v1 或 /chat/completions 的写法。
    func chatCompletionsURL() -> URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = "https://api.deepseek.com" }
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasSuffix("/chat/completions") { return URL(string: base) }
        return URL(string: base + "/chat/completions")
    }

    private func makeRequest(model: String, messages: [APIMessage], temperature: Double, stream: Bool) throws -> URLRequest {
        guard let url = chatCompletionsURL(), url.scheme?.lowercased() == "https" else {
            throw DeepSeekError(message: "Base URL 必须是 https:// 开头的地址（iOS 的 ATS 会拦截 http 明文请求）。")
        }
        guard !apiKey.isEmpty else {
            throw DeepSeekError(message: "还没有填写 API Key，请打开设置填入 DeepSeek API Key。")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("DeepSeekClone/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        let body = ChatCompletionRequest(model: model, messages: messages, stream: stream, temperature: temperature)
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    /// 流式对话：逐段产出思维链与正文。
    func streamChat(model: String, messages: [APIMessage], temperature: Double) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let decoder = DeepSeekClient.makeDecoder()
                    let request = try makeRequest(model: model, messages: messages, temperature: temperature, stream: true)
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
                        } catch {
                            // 读错误内容失败时忽略，用状态码兜底
                        }
                        throw DeepSeekError(message: DeepSeekClient.errorMessage(status: http.statusCode, body: raw))
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard let event = DeepSeekClient.parse(line: line, decoder: decoder) else { continue }
                        switch event {
                        case .finished:
                            continuation.finish()
                            return
                        case .delta(let delta):
                            if let reasoning = delta.reasoningContent, !reasoning.isEmpty {
                                continuation.yield(.reasoning(reasoning))
                            }
                            if let content = delta.content, !content.isEmpty {
                                continuation.yield(.content(content))
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// 设置页的连通性测试（非流式，消耗极少 token）。
    func testConnection(model: String) async throws -> String {
        let messages: [APIMessage] = [APIMessage(role: "user", content: "ping")]
        let request = try makeRequest(model: model, messages: messages, temperature: 1.0, stream: false)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekError(message: "服务端返回了无法识别的响应。")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw DeepSeekError(message: DeepSeekClient.errorMessage(status: http.statusCode, body: body))
        }
        return "连接成功，模型可用 ✅"
    }

    private enum ParsedLine {
        case delta(StreamDelta)
        case finished
    }

    private static func parse(line: String, decoder: JSONDecoder) -> ParsedLine? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload.isEmpty { return nil }
        if payload == "[DONE]" { return .finished }
        guard let data = payload.data(using: .utf8),
              let chunk = try? decoder.decode(StreamChunk.self, from: data),
              let delta = chunk.choices.first?.delta else {
            return nil
        }
        return .delta(delta)
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
