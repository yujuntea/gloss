import CryptoKit
import Foundation

/// 响应缓存：键 = sha256(归一化输入 | kind | kindParams | model | version(for:kind) [| ctx 摘要])。
/// LRU（依赖访问时间淘汰）；持久化经 DataStore 回写（容器不可用时仅内存）。
final class CacheStore {
    static let shared = CacheStore()
    static let maxEntries = 2000
    static let maxBytes = 50 * 1024 * 1024

    private let lock = NSLock()
    private var entries: [String: (response: String, lastAccess: Date)] = [:]
    private var lastTouch: [String: Date] = [:] // 命中回写自节流（K3-P2-7：避免命中路径持锁做 DB 读）
    var persistPut: ((String, String, Date) -> Void)?
    var persistLoader: (() -> [(String, String, Date)])?
    var persistTouch: ((String, Date) -> Void)?

    func loadPersisted() {
        guard let loader = persistLoader else { return }
        lock.lock()
        for (k, r, d) in loader() { entries[k] = (r, d) }
        evictIfNeeded()
        lock.unlock()
    }

    static func makeKey(normalizedInput: String, kind: QueryKind, params: KindParams?, model: String, context: String? = nil) -> String {
        var payload = "\(normalizedInput)|\(kind.rawValue)|\(model)|\(PromptLibrary.version(for: kind))"
        if let p = params?.point {
            // 1% 网格量化：防同图不同点词互相命中，也防浮点抖动永不命中（K-P1-5 修复）
            payload += String(format: "|pt:%d,%d", Int((p.x * 100).rounded()), Int((p.y * 100).rounded()))
        }
        if let pi = params?.pageIndex { payload += "|pg:\(pi)" }
        // 语境入键（D-b）：同一词在不同语境下语境义不同，不入键会串味；ctx 摘要先归一，同语境空白变体同键
        if kind == .word, let c = context, !c.isEmpty {
            payload += "|ctx:" + glossSHA256(QueryRouter.cacheNormalized(c)).prefix(8)
        }
        return glossSHA256(payload)
    }

    func get(_ key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard var e = entries[key] else { return nil }
        e.lastAccess = Date()
        entries[key] = e
        if let lt = lastTouch[key], e.lastAccess.timeIntervalSince(lt) < 60 {
            // 60s 内已回写过，跳过
        } else {
            lastTouch[key] = e.lastAccess
            persistTouch?(key, e.lastAccess)
        }
        return e.response
    }

    func put(_ key: String, _ response: String) {
        lock.lock()
        entries[key] = (response, Date())
        evictIfNeeded()
        lock.unlock()
        persistPut?(key, response, Date())
    }

    func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return entries.count
    }

    var approxBytes: Int {
        lock.lock(); defer { lock.unlock() }
        return entries.values.reduce(0) { $0 + $1.response.utf8.count }
    }

    private func evictIfNeeded() {
        func bytes() -> Int { entries.values.reduce(0) { $0 + $1.response.utf8.count } }
        while entries.count > CacheStore.maxEntries || bytes() > CacheStore.maxBytes {
            guard let oldest = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess }) else { break }
            entries.removeValue(forKey: oldest.key)
        }
    }
}
