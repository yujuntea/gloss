import Foundation

struct SSEChunk: Equatable {
    var content: String? = nil
    var reasoning: String? = nil
    var done: Bool = false
}

/// SSE 行解析（独立可测）：data: 行缓冲、[DONE]、多 choice 取 [0]、reasoning_content。
struct SSEParser {
    private var buffer: [String] = []

    mutating func feed(_ line: String) -> SSEChunk? {
        let l = line.hasSuffix("\r") ? String(line.dropLast()) : line
        if l.isEmpty {
            guard !buffer.isEmpty else { return nil }
            let payload = buffer.joined(separator: "\n")
            buffer.removeAll()
            return Self.parse(payload)
        }
        if l.hasPrefix("data:") {
            let rest = l.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if rest == "[DONE]" {
                // 先 flush 缓冲再终止：服务器可能省略 [DONE] 前的空行（L2a P2-5）
                // flush 出的内容与 done 合并为一个 chunk 返回
                var merged = SSEChunk(done: true)
                if !buffer.isEmpty {
                    let payload = buffer.joined(separator: "\n")
                    buffer.removeAll()
                    if var parsed = Self.parse(payload) {
                        parsed.done = true
                        merged = parsed
                    }
                }
                buffer.removeAll()
                return merged
            }
            buffer.append(rest)
            return nil
        }
        return nil // event:/id:/注释/其他忽略
    }

    static func parse(_ payload: String) -> SSEChunk? {
        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let choices = obj["choices"] as? [[String: Any]], let first = choices.first else { return nil }
        let delta = (first["delta"] as? [String: Any]) ?? (first["message"] as? [String: Any]) ?? [:]
        let content = delta["content"] as? String
        let reasoning = (delta["reasoning_content"] as? String) ?? (delta["reasoning"] as? String)
        if content == nil && reasoning == nil { return nil }
        return SSEChunk(content: content, reasoning: reasoning)
    }
}
