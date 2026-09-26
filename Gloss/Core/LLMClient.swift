import Foundation

struct LLMConfig: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var presetID: String = "minimax"
    var displayName: String = "MiniMax"
    var baseURL: String = "https://api.minimax.chat"
    var chatPath: String = "/v1/chat/completions"
    var model: String = "MiniMax-M3"
    var temperature: Double = 0.3
    var regionID: String? = nil
}

struct ChatMessage {
    enum Role: String { case system, user }
    var role: Role
    var text: String
    var imageJPEG: Data? = nil
}

enum StreamEvent {
    case reasoningDelta(String)
    case contentDelta(String)
    case done
}

enum AppError: Error, LocalizedError {
    case noAPIKey
    case network(String)
    case http(Int, String)
    case parse(String)
    case timeout
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "未配置 API Key"
        case .network: return "网络连不上，检查后重试"
        case .http(let code, _):
            switch code {
            case 401, 403: return "API Key 无效或已过期"
            case 429: return "请求太频繁，已自动重试仍受限，稍后再试或换个模型配置"
            default: return "服务返回错误（\(code)）"
            }
        case .parse: return "响应解析失败"
        case .timeout: return "模型响应超时"
        case .cancelled: return "已取消"
        }
    }
}

/// MiniMax M3 实测形态（C1 校准）：无 reasoning_content 字段，思考内联在 content 的 <think>…</think>。
/// 流式状态机：跨 chunk 剥离 think 区间→reasoningDelta，其余→contentDelta；对无该标记的模型零影响。
struct InlineThinkFilter {
    private var inThink = false
    private var pending = "" // 可能是标记前缀的尾部，待下一 delta 判定

    mutating func feed(_ delta: String) -> (content: String, reasoning: String) {
        var out = (content: "", reasoning: "")
        var buf = pending + delta
        pending = ""
        while !buf.isEmpty {
            if inThink {
                if let r = buf.range(of: "</think>") {
                    out.reasoning += String(buf[..<r.lowerBound])
                    buf = String(buf[r.upperBound...])
                    inThink = false
                } else {
                    let (safe, hold) = splitBeforePartialMarker(buf, hold: "</think>")
                    out.reasoning += safe
                    pending = hold
                    buf = ""
                }
            } else {
                if let r = buf.range(of: "<think>") {
                    out.content += String(buf[..<r.lowerBound])
                    buf = String(buf[r.upperBound...])
                    inThink = true
                } else {
                    // 正文状态需同时防 <think> 与 </think>（后者防模型裸输出闭合标记被切碎）
                    let (safe1, hold1) = splitBeforePartialMarker(buf, hold: "<think>")
                    let (safe2, hold2) = splitBeforePartialMarker(safe1, hold: "</think>")
                    out.content += safe2
                    pending = hold1.isEmpty ? hold2 : hold1
                    buf = ""
                }
            }
        }
        return out
    }

    /// 流终止时冲洗 pending（done 前）
    mutating func flush() -> (content: String, reasoning: String) {
        let rest = pending
        pending = ""
        return inThink ? ("", rest) : (rest, "")
    }

    /// 把 s 拆成 [安全输出, 是 hold 标记前缀的最长尾部]
    private func splitBeforePartialMarker(_ s: String, hold marker: String) -> (String, String) {
        let maxHold = min(marker.count - 1, s.count)
        if maxHold >= 1, let tailStart = s.index(s.endIndex, offsetBy: -maxHold, limitedBy: s.startIndex) {
            var idx = tailStart
            while idx < s.endIndex {
                let tail = String(s[idx...])
                if marker.hasPrefix(tail) {
                    return (String(s[..<idx]), tail)
                }
                idx = s.index(after: idx)
            }
        }
        return (s, "")
    }
}

/// OpenAI 兼容客户端：SSE 流式 + 多模态 image_url(dataURL)。
/// 重试：仅 429/5xx 且未产出内容时自动重试 2 次（1s/3s 退避）；超时不重试（超时≠限流）。
enum LLMClient {
    static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20 // 连接与流空闲超时
        cfg.timeoutIntervalForResource = 600
        return URLSession(configuration: cfg)
    }()

    static func requestURL(_ config: LLMConfig) -> URL? {
        let base = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let path = config.chatPath.hasPrefix("/") ? config.chatPath : "/" + config.chatPath
        return URL(string: base + path)
    }

    /// URLError → AppError 错误域映射（超时独立成域，文案=「模型响应超时」；自检覆盖）
    static func mapURLError(_ e: URLError) -> AppError {
        if e.code == .cancelled { return .cancelled }
        if e.code == .timedOut { return .timeout }
        return .network(e.localizedDescription)
    }

    static func stream(messages: [ChatMessage], config: LLMConfig, apiKey: String) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var emitted = false
                var attempt = 0
                while true {
                    do {
                        let request = try makeRequest(messages: messages, config: config, apiKey: apiKey)
                        let (bytes, response) = try await session.bytes(for: request)
                        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                            var body = Data()
                            var read = 0
                            for try await b in bytes {
                                body.append(b)
                                read += 1
                                if read > 4096 { break }
                            }
                            let snippet = String(data: body, encoding: .utf8) ?? ""
                            throw AppError.http(http.statusCode, snippet)
                        }
                        var parser = SSEParser()
                        var think = InlineThinkFilter()
                        var lineBuf = Data()
                        // 逐字节分行（保留空行）：URLSession.bytes.lines 会吞空行，
                        // 而 SSE 的空行是事件分隔符——被吞后 parser 缓冲永不 flush（实机验收定位）
                        for try await b in bytes {
                            if Task.isCancelled { throw AppError.cancelled }
                            if b == 0x0A { // \n
                                let line = String(data: lineBuf, encoding: .utf8) ?? ""
                                lineBuf.removeAll()
                                guard let chunk = parser.feed(line) else { continue }
                                // 先 yield 后判 done：[DONE] 合并 flush 的末条内容不能丢（K3-P1-1）
                                if let r = chunk.reasoning { continuation.yield(.reasoningDelta(r)) }
                                if let c = chunk.content {
                                    let (ct, rt) = think.feed(c)
                                    if !rt.isEmpty { continuation.yield(.reasoningDelta(rt)) }
                                    if !ct.isEmpty {
                                        emitted = true
                                        continuation.yield(.contentDelta(ct))
                                    }
                                }
                                if chunk.done {
                                    let (ct, rt) = think.flush()
                                    if !rt.isEmpty { continuation.yield(.reasoningDelta(rt)) }
                                    if !ct.isEmpty {
                                        emitted = true
                                        continuation.yield(.contentDelta(ct))
                                    }
                                    break
                                }
                            } else {
                                lineBuf.append(b)
                            }
                        }
                        continuation.yield(.done)
                        continuation.finish()
                        return
                    } catch let e as AppError {
                        if case .http(let code, _) = e, !emitted, attempt < 2, code == 429 || code >= 500 {
                            attempt += 1
                            try? await Task.sleep(nanoseconds: attempt == 1 ? 1_000_000_000 : 3_000_000_000)
                            continue
                        }
                        continuation.finish(throwing: e)
                        return
                    } catch let e as URLError {
                        continuation.finish(throwing: mapURLError(e))
                        return
                    } catch {
                        continuation.finish(throwing: AppError.parse(String(describing: error)))
                        return
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func makeRequest(messages: [ChatMessage], config: LLMConfig, apiKey: String) throws -> URLRequest {
        guard let url = requestURL(config) else { throw AppError.parse("无效的 baseURL/chatPath") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let msgs: [[String: Any]] = messages.map { m in
            var d: [String: Any] = ["role": m.role.rawValue]
            if let jpeg = m.imageJPEG {
                let dataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
                d["content"] = [["type": "text", "text": m.text],
                                ["type": "image_url", "image_url": ["url": dataURL]]]
            } else {
                d["content"] = m.text
            }
            return d
        }
        let body: [String: Any] = ["model": config.model, "messages": msgs, "stream": true, "temperature": config.temperature]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// 设置页「测试连接」（非流式最小请求，返回毫秒延迟）
    static func testConnection(config: LLMConfig, apiKey: String) async -> Result<Double, AppError> {
        guard let url = requestURL(config) else { return .failure(.parse("无效的 baseURL/chatPath")) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = ["model": config.model,
                                   "messages": [["role": "user", "content": "ping"]],
                                   "stream": false, "max_tokens": 1]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let start = Date()
        do {
            let (_, resp) = try await session.data(for: req)
            let elapsed = Date().timeIntervalSince(start) * 1000
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return .failure(.http(http.statusCode, ""))
            }
            return .success(elapsed)
        } catch let e as URLError {
            return .failure(mapURLError(e)) // 超时/取消口径与 stream 路径一致（K3-P2-1）
        } catch {
            return .failure(.parse(String(describing: error)))
        }
    }
}
