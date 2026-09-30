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

/// 流式空闲超时的原因（两级口径，见 VisibleIdleMonitor）
enum VisibleIdleTimeout {
    /// 超过 eventLimit 无**任何** delta（连思考都没有）：流假活/SSE 空转/连接半死
    case noEvent
    /// 持续有思考 delta 但超过 thinkingLimit 零正文：模型思考死循环
    case thinkingOnly
}

/// 流外空闲计时器（与流消费 `async let` 竞速），两级超时口径：
///
/// ① `eventLimit`（20s）无任何 delta——网络超时管不住「连接活着但一个事件都不发」的假活流；
/// ② `thinkingLimit`（90s）持续有思考流但零正文——思考死循环兜底。
///
/// 思考流**展示给用户**（ReasoningPreview）后即为进展，故 reasoning delta 视作事件、
/// 重置①；但它不是内容，不重置②——否则「只思考不出字」的流永远不会被拦下
/// （2026-09-29 实测图上点词纯思考 4–14s、密集页 20s+，旧「20s 无正文即超时」口径会误杀长思考）。
///
/// 为什么计时必须在 `for try await` 循环体**外**（2026-09-29 实机验收实证）：
/// 循环体内判超时只在有事件到达时才被检查，模型建连后零事件时循环体一次都不执行，
/// 守卫形同虚设，卡片永远停在 loading 且不报错。
///
/// 线程安全：`mark*` 由消费协程调、`waitForTimeout` 由计时协程调，NSLock 保护时间戳。
final class VisibleIdleMonitor: @unchecked Sendable {
    /// ①上限：无任何事件
    static let eventLimit: TimeInterval = 20
    /// ②上限：有事件但零正文（纯思考）
    static let thinkingLimit: TimeInterval = 90
    /// 解除计时的轮询粒度：决定 `finish()` 后最迟多久被感知（同时决定忙等粒度）
    static let finishPollInterval: TimeInterval = 0.25

    private let eventLimit: TimeInterval
    private let thinkingLimit: TimeInterval
    private let lock = NSLock()
    private var lastEventAt = Date()
    private var lastContentAt = Date()
    private var cancelled = false

    init(eventLimit: TimeInterval = VisibleIdleMonitor.eventLimit,
         thinkingLimit: TimeInterval = VisibleIdleMonitor.thinkingLimit) {
        self.eventLimit = eventLimit
        self.thinkingLimit = thinkingLimit
    }

    /// 收到思考 delta：证明流活着（重置①），但用户还没拿到内容（不重置②）
    func markEvent() {
        lock.lock(); defer { lock.unlock() }
        lastEventAt = Date()
    }

    /// 收到正文：两级计时都重置
    func markVisible() {
        lock.lock(); defer { lock.unlock() }
        lastEventAt = Date()
        lastContentAt = Date()
    }

    /// 消费结束（流已终止）后调用，解除计时器
    func finish() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
    }

    /// 距上次任意事件的秒数（诊断用）
    func eventIdleSeconds() -> TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return Date().timeIntervalSince(lastEventAt)
    }

    /// 挂起直到两级超时之一触发（返回原因）；`finish()` 后返回 nil。
    ///
    /// 睡眠**必须切片**（≤ `finishPollInterval`）：父协程先等本方法返回，若单次睡满整个剩余时长，
    /// 则 `finish()` 无法打断——断网/401/重试尽后的错误要等计时器自然醒才上卡，界面假 loading 最长
    /// 达 eventLimit，是相对「错误即时上卡」的回归（2026-09-29 复审实证）。
    func waitForTimeout() async -> VisibleIdleTimeout? {
        while true {
            let (isDone, eventRemaining, thinkingRemaining): (Bool, TimeInterval, TimeInterval) = lock.withLock {
                let now = Date()
                return (cancelled,
                        eventLimit - now.timeIntervalSince(lastEventAt),
                        thinkingLimit - now.timeIntervalSince(lastContentAt))
            }
            if isDone { return nil }
            if eventRemaining <= 0 { return .noEvent }
            if thinkingRemaining <= 0 { return .thinkingOnly }
            let slice = min(min(eventRemaining, thinkingRemaining), Self.finishPollInterval)
            try? await Task.sleep(nanoseconds: UInt64(slice * 1_000_000_000))
        }
    }
}

enum AppError: Error, LocalizedError {
    case noAPIKey
    case network(String)
    case http(Int, String)
    case parse(String)
    case timeout
    case thinkingTimeout
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
        case .thinkingTimeout: return "模型思考时间过长，请重试"
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
