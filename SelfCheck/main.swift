import AppKit
import Foundation

/// 逻辑自检入口：swiftc 与核心纯逻辑文件联合编译后运行（替代 XCTest 目标，偏差已在评审声明）。
/// 覆盖：QueryRouter / SSEParser / SectionExtractor / PromptLibrary / CacheStore(LRU+键) / ImagePipeline。
let failures: NSMutableArray = []

func check(_ name: String, _ cond: Bool, _ detail: String = "") {
    if cond {
        print("PASS \(name)")
    } else {
        print("FAIL \(name) \(detail)")
        failures.add(name)
    }
}

// MARK: - QueryRouter

check("router.word.simple", QueryRouter.classify("idempotent") == .word)
check("router.word.hyphen", QueryRouter.classify("state-of-the-art") == .word)
check("router.word.phrase", QueryRouter.classify("kick the bucket") == .word)
check("router.word.three", QueryRouter.classify("big bad wolf") == .word)
check("router.fourWords.notWord", QueryRouter.classify("the big bad wolf") != .word)
check("router.word.rejectComma", QueryRouter.classify("hello, world") != .word, "两词含逗号不应出词卡")
check("router.sentence.short", QueryRouter.classify("This is a test.") == .sentence)
check("router.sentence.60.paragraph", QueryRouter.classify(String(repeating: "word ", count: 59) + "word.") == .paragraph, "恰60词落段落")
check("router.sentence.59", QueryRouter.classify(String(repeating: "word ", count: 58) + "word.") == .sentence)
check("router.paragraph", QueryRouter.classify(String(repeating: "word ", count: 100)) == .paragraph)
check("router.article.400", QueryRouter.classify(String(repeating: "word ", count: 400)) == .article)
check("router.chinese", QueryRouter.isChineseDominant("这是一段中文内容") == true)
check("router.chinese.english", QueryRouter.isChineseDominant("mostly english text here") == false)
check("router.cacheNormalized", QueryRouter.cacheNormalized("  hello   world \n") == "hello world")
check("router.cacheNormalized.case.kept", QueryRouter.cacheNormalized("Hello World") == "Hello World")
check("router.empty", QueryRouter.classify("   ") == .paragraph)

// MARK: - SSEParser

var p = SSEParser()
check("sse.buffering", p.feed("data: {\"choices\":[{\"delta\":{\"content\":\"He\"}}]}") == nil)
let c1 = p.feed("")
check("sse.flushOnEmptyLine", c1?.content == "He", "\(String(describing: c1))")

var p2 = SSEParser()
_ = p2.feed("data: {\"choices\":[{\"delta\":{\"content\":\"ans\",\"reasoning_content\":\"thinking\"}}]}")
let c2 = p2.feed("")
check("sse.reasoning", c2?.reasoning == "thinking" && c2?.content == "ans", "\(String(describing: c2))")

var p3 = SSEParser()
check("sse.done", p3.feed("data: [DONE]")?.done == true)
check("sse.ignoreOther", p3.feed("event: message") == nil && p3.feed(": comment") == nil && p3.feed("id: 1") == nil)

var p5 = SSEParser()
_ = p5.feed("data: {\"choices\":[{\"delta\":{\"content\":\"x\"}}]}")
let c5 = p5.feed("")
check("sse.firstChoice", c5?.content == "x", "\(String(describing: c5))")
check("sse.emptyChoices", SSEParser.parse("{\"usage\":{\"total_tokens\":10}}") == nil)

// MARK: - SectionExtractor

let sample = """
**译文**
这是译文。
**难词表**
| 词/短语 | 音标 | 文中义 | 原文例句 |
|---|---|---|---|
| idempotent | /ˌaɪdemˈpɒɪtənt/ | 幂等的 | An idempotent op. |
| quorum | /ˈkwɔːrəm/ | 法定人数 | needs a quorum |
**本批要点**
- 要点一
- 要点二
"""
check("section.find", SectionExtractor.section(named: "难词表", in: sample)?.contains("quorum") == true)
check("section.missing", SectionExtractor.section(named: "不存在", in: sample) == nil)
let rows = Array(SectionExtractor.tableRows(SectionExtractor.section(named: "难词表", in: sample) ?? "").dropFirst())
check("section.table.rows", rows.count == 2, "\(rows)")
check("section.table.cells", rows.first?.count == 4 && rows.first?[0] == "idempotent")
check("section.table.skipSeparator", !rows.contains { $0.first == "---" })
let items = SectionExtractor.listItems(SectionExtractor.section(named: "本批要点", in: sample) ?? "")
check("section.listItems", items == ["要点一", "要点二"], "\(items)")
check("section.headerColon", SectionExtractor.isSectionHeader("**译文**：") == "译文")
check("section.headerSuffixNote", SectionExtractor.isSectionHeader("**本批术语**（若有）") == "本批术语", "带尾注的节名（模板本批术语行）")
check("section.remove", !SectionExtractor.removingSection(named: "难词表", in: sample).contains("quorum"))
check("section.remove.keepsOthers", SectionExtractor.removingSection(named: "难词表", in: sample).contains("这是译文"))
check("section.notInlineBold", SectionExtractor.isSectionHeader("这是 **粗体** 行内") == nil)

// MARK: - PromptLibrary

let wordPrompt = PromptLibrary.userPrompt(kind: .word, text: "idempotent", context: "ctx")
check("prompt.word.markers", wordPrompt.contains("语境义") && wordPrompt.contains("查询：idempotent") && wordPrompt.contains("语境：ctx"))
let sentPrompt = PromptLibrary.userPrompt(kind: .sentence, text: "S", context: nil)
check("prompt.sentence.difficultWords", sentPrompt.contains("句中难词") && sentPrompt.contains("语境：无"))
check("prompt.paragraph.exampleCol", PromptLibrary.userPrompt(kind: .paragraph, text: "P", context: nil).contains("原文例句"))
let pointPrompt = PromptLibrary.userPrompt(kind: .screenshotWordAt, text: "", context: nil, point: CGPoint(x: 0.3, y: 0.5))
check("prompt.image.point", pointPrompt.contains("（30%，50%）"), pointPrompt)
check("prompt.image.explain", PromptLibrary.userPrompt(kind: .screenshotExplain, text: "", context: nil).contains("识别内容"))

let longText = Array(repeating: String(repeating: "lorem ipsum dolor sit amet ", count: 8), count: 25).joined(separator: "\n\n")
let batches = PromptLibrary.splitBatches(longText)
check("prompt.batches.multi", batches.count >= 2, "count=\(batches.count)")
check("prompt.batch.prompt", PromptLibrary.articleBatchPrompt(text: "X", index: 1, total: 2).contains("本批术语"))
check("prompt.aggregate", PromptLibrary.aggregatePrompt(batchMaterials: "M").contains("去重合并"))
check("prompt.version", PromptLibrary.version == "m1")

// MARK: - CacheStore

let store = CacheStore()
let k1 = CacheStore.makeKey(normalizedInput: "idempotent", kind: .word, params: nil, model: "m")
let k2 = CacheStore.makeKey(normalizedInput: "idempotent", kind: .word, params: nil, model: "m")
let k3 = CacheStore.makeKey(normalizedInput: "idempotent", kind: .sentence, params: nil, model: "m")
let k4 = CacheStore.makeKey(normalizedInput: "idempotent", kind: .screenshotWordAt, params: KindParams(point: CGPoint(x: 0.30, y: 0.50), pageIndex: nil), model: "m")
let k5 = CacheStore.makeKey(normalizedInput: "idempotent", kind: .screenshotWordAt, params: KindParams(point: CGPoint(x: 0.31, y: 0.50), pageIndex: nil), model: "m")
let k6 = CacheStore.makeKey(normalizedInput: "idempotent", kind: .screenshotWordAt, params: KindParams(point: CGPoint(x: 0.301, y: 0.502), pageIndex: nil), model: "m")
check("cache.key.stable", k1 == k2)
check("cache.kind.changesKey", k1 != k3)
check("cache.point.changesKey", k4 != k5)
check("cache.point.quantized", k4 == k6, "1% 网格内量化应同键")
store.put(k1, "resp1")
check("cache.hit", store.get(k1) == "resp1")
check("cache.miss", store.get(k3) == nil)
for i in 0..<2500 {
    let key = glossSHA256("k\(i)|word|m|m1")
    store.put(key, String(repeating: "x", count: 300))
}
check("cache.lru.evict", store.count <= CacheStore.maxEntries, "count=\(store.count)")
check("cache.lru.oldest.evicted", store.get(k1) == nil, "最早条目应被淘汰")

// MARK: - ImagePipeline

let testImage = NSImage(size: NSSize(width: 3000, height: 1200))
testImage.lockFocus()
NSColor.white.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 3000, height: 1200)).fill()
NSColor.black.setFill()
NSBezierPath(rect: NSRect(x: 100, y: 400, width: 800, height: 300)).fill()
testImage.unlockFocus()

if let n1 = ImagePipeline.normalize(testImage, maxEdge: 1568), let n2 = ImagePipeline.normalize(testImage, maxEdge: 1568) {
    check("image.normalize.ok", true)
    check("image.deterministic", n1.sha256 == n2.sha256)
    check("image.resized", n1.pixelSize.width == 1568 || n1.pixelSize.height == 1568, "\(n1.pixelSize)")
    if let small = ImagePipeline.normalize(testImage, maxEdge: 200) {
        check("image.thumbnail", small.pixelSize.width <= 200 && small.jpeg.count < n1.jpeg.count)
    } else {
        check("image.thumbnail", false, "normalize 200 失败")
    }
} else {
    check("image.normalize.ok", false, "normalize 失败")
    check("image.deterministic", false)
    check("image.resized", false)
    check("image.thumbnail", false)
}

// MARK: - L2a 修复回归（错误映射/句切/DONE-flush/幂等注册语义）

check("fix.timeoutIsTimeout", { if case .timeout = LLMClient.mapURLError(URLError(.timedOut)) { return true }; return false }(), "timedOut 应映射 .timeout")
if case .cancelled = LLMClient.mapURLError(URLError(.cancelled)) { check("fix.cancelMapping", true) } else { check("fix.cancelMapping", false) }
if case .network = LLMClient.mapURLError(URLError(.cannotConnectToHost)) { check("fix.networkMapping", true) } else { check("fix.networkMapping", false) }
check("fix.errorDesc.timeout", AppError.timeout.errorDescription == "模型响应超时")

let noNewlineLong = String(repeating: "Distributed systems coordinate many machines and must tolerate partial failure. ", count: 70)
let nlBatches = PromptLibrary.splitBatches(noNewlineLong)
check("fix.splitLongParagraph", nlBatches.count >= 2, "无换行超长段应按句切分 count=\(nlBatches.count)")

var p6 = SSEParser()
_ = p6.feed("data: {\"choices\":[{\"delta\":{\"content\":\"tail\"}}]}")
let c6 = p6.feed("data: [DONE]")
check("fix.doneFlushesBuffer", c6?.content == "tail" && c6?.done == true, "\(String(describing: c6))")

// MARK: - MiniMax M3 think 内联剥离（C1 校准实测形态）

var tf = InlineThinkFilter()
var tContent = ""; var tReason = ""
// 跨 chunk 切碎标记：<thi|nk>正文中</thi|nk>结果
for piece in ["<thi", "nk>", "正文中", "</thi", "nk>结", "果"] {
    let r = tf.feed(piece)
    tContent += r.content
    tReason += r.reasoning
}
let tfFlush = tf.flush()
tContent += tfFlush.content; tReason += tfFlush.reasoning
check("think.crossChunk", tContent == "结果" && tReason == "正文中", "content=\(tContent) reason=\(tReason)")

var tf2 = InlineThinkFilter()
let r2 = tf2.feed("没有标记的普通输出")
check("think.passthrough", r2.content == "没有标记的普通输出" && r2.reasoning.isEmpty)

var tf3 = InlineThinkFilter()
let r3 = tf3.feed("<think>只思考不结尾")
let f3 = tf3.flush()
check("think.flushUnclosed", r3.reasoning == "只思考不结尾" && r3.content.isEmpty && f3.content.isEmpty && f3.reasoning.isEmpty)

var tf4 = InlineThinkFilter()
let r4a = tf4.feed("开头<think>思考")
let r4b = tf4.feed("</think>结尾")
check("think.normalFlow", r4a.content == "开头" && r4b.content == "结尾" && r4a.reasoning + r4b.reasoning == "思考")

// MARK: - 汇总

print("----")
if failures.count == 0 {
    print("SELFCHECK ALL PASS")
} else {
    print("SELFCHECK FAILED: \(failures.count)")
    exit(1)
}
