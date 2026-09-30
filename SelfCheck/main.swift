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
// 截图卡 chips 契约：难词表节名 + 4 列表头 + 竖线护栏（表格按朴素 | 切分，例句含竖线会错位）
let shotPrompt = PromptLibrary.userPrompt(kind: .screenshotExplain, text: "", context: nil)
check("prompt.screenshotHardWords",
      shotPrompt.contains("**难词表**") && shotPrompt.contains("| 词/短语 | 音标 | 图中义 | 图中原文例句 |")
      && shotPrompt.contains("\\|") && shotPrompt.contains("逐字一致") && shotPrompt.contains("整节省略"),
      shotPrompt)
check("prompt.screenshotWordAtCandidates",
      PromptLibrary.userPrompt(kind: .screenshotWordAt, text: "", context: nil, point: CGPoint(x: 0.3, y: 0.5))
        .contains("2–4 个候选"), "方案 C：多候选不得编造单个答案")

let longText = Array(repeating: String(repeating: "lorem ipsum dolor sit amet ", count: 8), count: 25).joined(separator: "\n\n")
let batches = PromptLibrary.splitBatches(longText)
check("prompt.batches.multi", batches.count >= 2, "count=\(batches.count)")
check("prompt.batch.prompt", PromptLibrary.articleBatchPrompt(text: "X", index: 1, total: 2).contains("本批术语"))
check("prompt.aggregate", PromptLibrary.aggregatePrompt(batchMaterials: "M").contains("去重合并"))
check("prompt.versionPerKind",
      PromptLibrary.version(for: .screenshotExplain) == "m2" && PromptLibrary.version(for: .screenshotWordAt) == "m2"
      && PromptLibrary.version(for: .word) == "m1" && PromptLibrary.version(for: .sentence) == "m1"
      && PromptLibrary.version(for: .paragraph) == "m1")
check("prompt.versionForWordUnchanged", PromptLibrary.version(for: .word) == "m1")

// MARK: - 截图卡难词表（§3.1）：读图输出与段落卡同构，chips 直接吃同一套 SectionExtractor 契约

let shotMarkdown = """
**识别内容**
Idempotent operations and leader election.
**翻译与解释**
幂等操作与领导者选举。
**要点**
- 分布式一致性
**难词表**
| 词/短语 | 音标 | 图中义 | 图中原文例句 |
|---|---|---|---|
| idempotent | /ˌaɪdemˈpɒɪtənt/ | 幂等的 | Idempotent operations |
| quorum | /ˈkwɔːrəm/ | 法定人数 | quorum reads |
"""
let shotSec = SectionExtractor.section(named: "难词表", in: shotMarkdown)
check("section.screenshotWords", shotSec?.contains("quorum") == true, "含难词表节的截图 markdown 应能取出该节")
let shotRows = Array(SectionExtractor.tableRows(shotSec ?? "").dropFirst())
check("section.screenshotTableRows", shotRows.count == 2 && shotRows[0].count == 4
      && shotRows[0][3] == "Idempotent operations" && !shotRows.contains { $0.contains("---") },
      "rows=\(shotRows)")
let shotRemoved = SectionExtractor.removingSection(named: "难词表", in: shotMarkdown)
check("section.screenshotRemoved",
      !shotRemoved.contains("quorum") && !shotRemoved.contains("**难词表**")
      && shotRemoved.contains("**识别内容**") && shotRemoved.contains("幂等操作与领导者选举"),
      "移除难词表后正文不得含该节且不丢其他节：\(shotRemoved)")
let noTableMarkdown = """
**识别内容**
Plain UI text.
**要点**
- 界面截图
"""
check("section.noWordTableIsNoop",
      SectionExtractor.section(named: "难词表", in: noTableMarkdown) == nil
      && SectionExtractor.removingSection(named: "难词表", in: noTableMarkdown) == noTableMarkdown,
      "无难词表时（模型漏发/老缓存）应原样返回")

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
// 语境入键（§6.1 D-b）：同词不同语境必须分键，否则命中的是别的语境的语境义
let ctxA = CacheStore.makeKey(normalizedInput: "operation", kind: .word, params: nil, model: "m", context: "ctx A")
let ctxB = CacheStore.makeKey(normalizedInput: "operation", kind: .word, params: nil, model: "m", context: "ctx B")
let ctxNone = CacheStore.makeKey(normalizedInput: "operation", kind: .word, params: nil, model: "m")
let ctxEmpty = CacheStore.makeKey(normalizedInput: "operation", kind: .word, params: nil, model: "m", context: "")
let ctxPadded = CacheStore.makeKey(normalizedInput: "operation", kind: .word, params: nil, model: "m", context: "  ctx  A  ")
// nil/空串 context 必须与 6.1 之前的键完全一致（无 "|ctx:" 段）——词类老缓存不得失效
let noCtxPayload = glossSHA256("operation|word|m|m1")
check("cachekey.wordContextDiffers", ctxA != ctxB && ctxNone == noCtxPayload && ctxEmpty == ctxNone, "ctxA=\(ctxA) ctxNone=\(ctxNone)")
check("cachekey.wordContextNormalized", ctxPadded == ctxA, "ctx 空白变体应归一后同键")
let sentCtxA = CacheStore.makeKey(normalizedInput: "A sentence.", kind: .sentence, params: nil, model: "m", context: "ctx A")
let sentCtxB = CacheStore.makeKey(normalizedInput: "A sentence.", kind: .sentence, params: nil, model: "m", context: "ctx B")
check("cachekey.contextIgnoredForNonWord", sentCtxA == sentCtxB, "§6.1 限 .word，句卡 context 不入键")
let shotKey = CacheStore.makeKey(normalizedInput: "imgsha", kind: .screenshotExplain, params: nil, model: "m")
let wordKeySameInput = CacheStore.makeKey(normalizedInput: "imgsha", kind: .word, params: nil, model: "m")
// 字节级锚定：与「仍用全局 m1 常量」的旧键逐字节比对，证明截图两类真的随版本失效、词类真的没失效
let shotKeyIfStillM1 = glossSHA256("imgsha|screenshotExplain|m|m1")
let wordAtKeyIfStillM1 = glossSHA256("imgsha|screenshotWordAt|m|m1")
let wordKeyIfStillM1 = glossSHA256("imgsha|word|m|m1")
let wordAtKey = CacheStore.makeKey(normalizedInput: "imgsha", kind: .screenshotWordAt,
                                   params: KindParams(point: CGPoint(x: 0.3, y: 0.5), pageIndex: nil), model: "m")
check("cachekey.screenshotVersionBumped",
      shotKey != wordKeySameInput && PromptLibrary.version(for: .screenshotExplain) == "m2"
      && PromptLibrary.version(for: .screenshotWordAt) == "m2", "截图两类键随版本变化，词类保持 m1")
check("cachekey.screenshotKeyDiffersFromM1",
      shotKey != shotKeyIfStillM1
      && wordAtKey == glossSHA256("imgsha|screenshotWordAt|m|m2|pt:30,50"),
      "整图/点词键确已从 m1 payload 迁到 m2（D-d：否则老缓存复活旧 prompt 的单猜行为）")
check("cachekey.wordKeyUnchangedByVersionSplit",
      wordKeySameInput == wordKeyIfStillM1,
      "词类键必须与旧版逐字节一致（分版本不得误伤词/句/段缓存）")
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

// MARK: - VisibleIdleMonitor（流外两级空闲计时，2026-09-29 加入 / 09-30 拆两级）

// ① 零事件流必须自行到期，且原因=.noEvent——2026-09-29 实机验收实证：
//    守卫若只在 `for try await` 循环体内判，流零事件时循环体一次都不执行，卡片永远 loading
let m1 = VisibleIdleMonitor(eventLimit: 0.3, thinkingLimit: 10)
let m1Start = Date()
let m1Timeout = await m1.waitForTimeout()
check("guard.monitor.zeroEventTimesOutWithReason", m1Timeout == .noEvent && Date().timeIntervalSince(m1Start) < 2,
      "无任何事件时应以 .noEvent 到期（实测 \(String(describing: m1Timeout))，耗时 \(String(format: "%.2f", Date().timeIntervalSince(m1Start)))s）")

// finish() 解除 + 切片化：finish 必须能**打断**长睡眠，否则快速失败（断网/401/重试尽）
// 要等计时器自然醒才上卡，界面假 loading 最长达 eventLimit（2026-09-29 复审实证的回归防护）
let m2 = VisibleIdleMonitor(eventLimit: 30, thinkingLimit: 30)
Task { try? await Task.sleep(nanoseconds: 50_000_000); m2.finish() }
let m2Start = Date()
let m2Timeout = await m2.waitForTimeout()
let m2Elapsed = Date().timeIntervalSince(m2Start)
check("guard.monitor.finishInterruptsLongSleep", m2Timeout == nil && m2Elapsed < 2.0,
      "limit=30s 下 finish() 应在切片粒度内（<2s）返回 nil，实测 \(String(format: "%.2f", m2Elapsed))s")

// markVisible（正文）重置两级计时：重置生效时第二次到期 = markVisible 时刻 + limit（0.15+0.4=0.55s），
// 被变异杀掉（正文不重置时钟）则 0.40s 提前到期——用**总耗时**下界 0.47s 区分两种情形。
// 调度容差：markVisible 睡眠超调需 >0.25s 才会误伤正确实现（K3 终审指出 0.12s/0.25s 参数下
// 超调 >0.13s 即反向 flake，本组参数把容差翻倍）
let m3 = VisibleIdleMonitor(eventLimit: 0.4, thinkingLimit: 0.4)
let m3Start = Date()
Task { try? await Task.sleep(nanoseconds: 150_000_000); m3.markVisible() }
let m3Timeout = await m3.waitForTimeout()
let m3Idle = m3.eventIdleSeconds()
let m3Elapsed = Date().timeIntervalSince(m3Start)
check("guard.monitor.markVisibleResets",
      m3Timeout == .noEvent && m3Idle < 0.4 + 0.15 && m3Elapsed > 0.47,
      "到期以 .noEvent、idle≈一个 limit，且总耗时 >0.47s（重置生效 0.15+0.4≈0.55s；被杀则 0.40s 提前到期），实测 \(String(describing: m3Timeout)) / idle \(String(format: "%.3f", m3Idle))s / 总 \(String(format: "%.3f", m3Elapsed))s")

// 关键新语义（2026-09-30）：思考 delta 重置①（无事件）但不重置②（纯思考）——
// 长思考不再被「20s 无正文」误杀；思考死循环仍会被 90s 兜底拦下
let m4 = VisibleIdleMonitor(eventLimit: 0.2, thinkingLimit: 0.6)
Task {
    for _ in 0..<3 {
        try? await Task.sleep(nanoseconds: 150_000_000)
        m4.markEvent()
    }
}
let m4Start = Date()
let m4Timeout = await m4.waitForTimeout()
let m4Elapsed = Date().timeIntervalSince(m4Start)
check("guard.monitor.reasoningPreventsNoEventButThinkingExpires",
      m4Timeout == .thinkingOnly && m4Elapsed >= 0.55,
      "持续思考流应把到期原因从 .noEvent 推迟为 .thinkingOnly（实测 \(String(describing: m4Timeout))，耗时 \(String(format: "%.2f", m4Elapsed))s）")

// 构造参数与生产口径一致
check("guard.monitor.limitsSane",
      VisibleIdleMonitor.eventLimit == 20 && VisibleIdleMonitor.thinkingLimit == 90
      && VisibleIdleMonitor.finishPollInterval > 0 && VisibleIdleMonitor.finishPollInterval <= 1.0,
      "①=20s / ②=90s / 切片 ≤1s（过细则忙等，过粗则 finish 感知迟）")

// 思考超时的错误文案独立于「模型响应超时」，用户能分辨两种失败
check("fix.errorDesc.thinkingTimeout", AppError.thinkingTimeout.errorDescription?.contains("思考") == true,
      "\(AppError.thinkingTimeout.errorDescription ?? "nil")")

// MARK: - ImageGeometry（fit 满窗的点击坐标换算，§4.4）

let thumbView = CGSize(width: 376, height: 160)
let thumbImg = CGSize(width: 1512, height: 982)
let thumbCenter = ImageGeometry.normalizedPoint(viewSize: thumbView, imagePixelSize: thumbImg, click: CGPoint(x: 188, y: 80))
let thumbLetterbox = ImageGeometry.normalizedPoint(viewSize: thumbView, imagePixelSize: thumbImg, click: CGPoint(x: 1, y: 1))
check("geo.normalizedPoint",
      thumbCenter.map { abs($0.x - 0.5) < 0.01 && abs($0.y - 0.5) < 0.01 } == true && thumbLetterbox == nil,
      "center=\(String(describing: thumbCenter)) letterbox=\(String(describing: thumbLetterbox))")
// 分流阈值（§4.5）：密集截图要弹窗、能卡内看清的图与历史缩略图不弹窗；面板可拉宽故按实测卡宽判
check("geo.needsZoomWindow.denseScreenshot",
      ImageGeometry.needsZoomWindow(imageWidth: 1512, cardWidth: 376),
      "1512 宽全屏截图在 376 卡宽下正文不可读，应开放大窗")
check("geo.needsZoomWindow.smallImage",
      !ImageGeometry.needsZoomWindow(imageWidth: 200, cardWidth: 376)
      && !ImageGeometry.needsZoomWindow(imageWidth: 300, cardWidth: 600),
      "≤卡宽的图（含历史 200px 缩略图）走就地点词；拉宽面板后 300 宽图不该再弹窗")
check("geo.needsZoomWindow.exactFit",
      !ImageGeometry.needsZoomWindow(imageWidth: 376, cardWidth: 376),
      "自然宽恰等于卡宽时可卡内就地点词，不应弹窗")

// MARK: - 汇总

print("----")
if failures.count == 0 {
    print("SELFCHECK ALL PASS")
} else {
    print("SELFCHECK FAILED: \(failures.count)")
    exit(1)
}
