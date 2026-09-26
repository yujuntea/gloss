import Foundation
import SwiftData

enum DataStore {
    static let container: ModelContainer? = {
        do {
            return try ModelContainer(for: QueryRecord.self, ResponseCache.self)
        } catch {
            GlossLog.error("ModelContainer init failed: \(error)")
            return nil
        }
    }()

    static func warmUp() { _ = container }

    @MainActor
    static func addQuery(inputText: String?, kind: QueryKind, params: KindParams?, origin: InputOrigin,
                         thumbnail: Data?, response: String, model: String) {
        guard let container else { return }
        let paramsJSON: String? = params.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
        let record = QueryRecord(inputText: inputText, inputKind: kind.rawValue, kindParamsJSON: paramsJSON,
                                 origin: origin.rawValue, thumbnail: thumbnail, responseMarkdown: response, model: model)
        let ctx = ModelContext(container)
        ctx.insert(record)
        try? ctx.save()
    }

    @MainActor
    static func allQueries() -> [QueryRecord] {
        guard let container else { return [] }
        let ctx = ModelContext(container)
        let desc = FetchDescriptor<QueryRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? ctx.fetch(desc)) ?? []
    }

    @MainActor
    static func deleteAllQueries() {
        guard let container else { return }
        let ctx = ModelContext(container)
        try? ctx.delete(model: QueryRecord.self)
        try? ctx.save()
    }

    static func cachePut(key: String, response: String, date: Date) {
        guard let container else { return }
        let ctx = ModelContext(container)
        let k = key
        let predicate = #Predicate<ResponseCache> { $0.key == k }
        let existing = try? ctx.fetch(FetchDescriptor(predicate: predicate))
        if let row = existing?.first {
            row.response = response
            row.lastAccessedAt = date
        } else {
            ctx.insert(ResponseCache(key: key, response: response, createdAt: date, lastAccessedAt: date))
        }
        try? ctx.save()
    }

    static func cacheLoadAll() -> [(String, String, Date)] {
        guard let container else { return [] }
        let ctx = ModelContext(container)
        var desc = FetchDescriptor<ResponseCache>(sortBy: [SortDescriptor(\.lastAccessedAt, order: .reverse)])
        desc.fetchLimit = CacheStore.maxEntries
        guard let rows = try? ctx.fetch(desc) else { return [] }
        return rows.map { ($0.key, $0.response, $0.lastAccessedAt) }
    }

    /// 启动清理：删除未被加载（超出 LRU 条数/字节上限）的持久缓存行（tech §4.9 双阈值）
    @MainActor
    static func cachePruneToLoaded() {
        guard let container else { return }
        let loaded = CacheStore.shared.persistLoader?() ?? [] // 已按 lastAccessedAt 降序
        var keep = Set<String>()
        var acc = 0
        for (k, r, _) in loaded {
            acc += r.utf8.count
            if acc > CacheStore.maxBytes { break }
            keep.insert(k)
        }
        let ctx = ModelContext(container)
        let allKeys: [String]
        if let rows = try? ctx.fetch(FetchDescriptor<ResponseCache>()) {
            allKeys = rows.map { $0.key }
        } else { return }
        let stale = allKeys.filter { !keep.contains($0) }
        guard !stale.isEmpty else { return }
        for k in stale {
            let predicate = #Predicate<ResponseCache> { $0.key == k }
            try? ctx.delete(model: ResponseCache.self, where: predicate)
        }
        try? ctx.save()
        GlossLog.info("cache pruned \(stale.count) rows")
    }

    /// 命中回写 lastAccessedAt（节流：仅当落后超过 60s 才写盘）
    static func cacheTouch(key: String, date: Date) {
        guard let container else { return }
        let ctx = ModelContext(container)
        let k = key
        let predicate = #Predicate<ResponseCache> { $0.key == k }
        if let row = (try? ctx.fetch(FetchDescriptor(predicate: predicate)))?.first {
            if date.timeIntervalSince(row.lastAccessedAt) > 60 {
                row.lastAccessedAt = date
                try? ctx.save()
            }
        }
    }

    @MainActor
    static func cacheClearAll() {
        guard let container else { return }
        let ctx = ModelContext(container)
        try? ctx.delete(model: ResponseCache.self)
        try? ctx.save()
        CacheStore.shared.clear()
    }

    @MainActor
    static func seedDemoHistory() {
        let demo: [(String, QueryKind, String)] = [
            ("idempotent", .word, "## idempotent\n/ˌaɪdemˈpɒɪtənt/ /ˌaɪdəmˈpɒɪtənt/\n**语境义**：（通用）指同一操作重复执行结果不变。"),
            ("While the system can continue to operate even when some of its nodes fail, this does not mean that it can tolerate an arbitrary number of failures.", .sentence, "**翻译**\n虽然系统在部分节点失效时仍能继续运行，但这并不意味着它能容忍任意数量的故障。"),
            ("Consistency models determine what reads observe after a write. Strong consistency imposes coordination cost; eventual consistency trades immediacy for scale.", .paragraph, "**译文**\n一致性模型决定了写入之后读取能看到什么。强一致性带来协调成本；最终一致性用即时性换取扩展性。"),
        ]
        for (text, kind, response) in demo {
            addQuery(inputText: text, kind: kind, params: nil, origin: .service, thumbnail: nil, response: response, model: "demo")
        }
        GlossLog.info("seeded demo history")
    }
}
