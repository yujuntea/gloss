import AppKit
import Foundation

enum CardPhase: Equatable {
    case capturing // 正在获取选中文本（⌥D 通道）
    case loading
    case streaming
    case done
    case failed(String)
    case noKey
    case notice(String)
}

@MainActor
final class CardState: ObservableObject, Identifiable {
    let id = UUID()
    var kind: QueryKind
    var inputText: String?
    var context: String?
    var origin: InputOrigin
    var selectionBounds: CGRect?
    let kindParams: KindParams?
    var originalImage: NSImage? // 截图原图，仅内存不落盘
    var thumbnail: NSImage?
    @Published var phase: CardPhase = .loading
    @Published var content: String = ""
    @Published var reasoningActive = false
    @Published var usedCache = false

    init(kind: QueryKind, inputText: String?, context: String?, origin: InputOrigin,
         selectionBounds: CGRect?, kindParams: KindParams?, originalImage: NSImage?, thumbnail: NSImage?) {
        self.kind = kind
        self.inputText = inputText
        self.context = context
        self.origin = origin
        self.selectionBounds = selectionBounds
        self.kindParams = kindParams
        self.originalImage = originalImage
        self.thumbnail = thumbnail
    }

    var displayWord: String { inputText ?? "截图" }

    /// 底部动作（朗读/复制）的查询对象：文本卡=输入原文；点词卡=模型识别词（## 标题）
    var displayQuery: String {
        if kind == .screenshotWordAt,
           let r = content.range(of: "^##\\s+[^\\n]+", options: .regularExpression) {
            let m = String(content[r].dropFirst(3)).trimmingCharacters(in: .whitespaces)
            if !m.isEmpty { return m }
        }
        return inputText ?? ""
    }
}

/// 会话状态机：查询入口 → 取词/截图 → 路由 → LLM 流式 → 缓存/历史。
/// 面板内导航栈：子查询（难词词条/图上点词）入栈，深 ≤2，切卡不重触发捕获层。
@MainActor
final class SessionCoordinator: ObservableObject {
    static let shared = SessionCoordinator()

    @Published private(set) var stack: [CardState] = []
    @Published var pinned = false
    @Published var revision = 0 // 流式内容变更计数，驱动面板高度重算

    private var currentTask: Task<Void, Never>?
    private var pendingCapture: Task<Void, Never>?

    var currentCard: CardState? { stack.last }

    // MARK: - 查询入口

    func beginTextQuery(text: String, context: String?, selectionBounds: CGRect?, origin: InputOrigin) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        cancelCurrent()
        if QueryRouter.isChineseDominant(t) {
            let card = CardState(kind: .word, inputText: t, context: context, origin: origin,
                                 selectionBounds: selectionBounds, kindParams: nil, originalImage: nil, thumbnail: nil)
            card.phase = .notice("中文划词查询即将支持，敬请期待")
            show(card: card, bounds: selectionBounds)
            return
        }
        if QueryRouter.wordCount(t) >= 400 {
            hidePanel()
            WindowManager.shared.showReader(text: t)
            return
        }
        let kind = QueryRouter.classify(t)
        let card = CardState(kind: kind, inputText: t, context: context, origin: origin,
                             selectionBounds: selectionBounds, kindParams: nil, originalImage: nil, thumbnail: nil)
        show(card: card, bounds: selectionBounds)
        runText(card: card)
    }

    /// ⌥D：先弹骨架（capturing），AX(150ms) 失败自动落 ⌘C(300ms)
    func beginHotkeyQuery() {
        cancelCurrent()
        let card = CardState(kind: .word, inputText: nil, context: nil, origin: .hotkeyAX,
                             selectionBounds: nil, kindParams: nil, originalImage: nil, thumbnail: nil)
        card.phase = .capturing
        show(card: card, bounds: nil)
        pendingCapture = Task { [weak self] in
            let primaryHeight = NSScreen.screens.first?.frame.height // 主线程预取（K3-P2-10）
            let axResult = await withTimeout(seconds: 0.25) { AXTextFetcher.fetchWithBudget(0.15, primaryHeight: primaryHeight) }
            guard let self, !Task.isCancelled else { return }
            var result: CaptureResult? = axResult
            if result == nil {
                result = await withTimeout(seconds: 0.45) { ClipboardFallback.fetchWithBudget(0.3) }
            }
            guard !Task.isCancelled else { return }
            guard let r = result else {
                card.phase = .failed("未能获取选中文本。可改用截图查询：⌥S 框选目标区域。")
                self.revision += 1
                return
            }
            card.inputText = r.text
            card.context = r.context
            card.selectionBounds = r.selectionBounds
            card.origin = r.origin
            if QueryRouter.isChineseDominant(r.text) {
                card.phase = .notice("中文划词查询即将支持，敬请期待")
                self.revision += 1
                return
            }
            if QueryRouter.wordCount(r.text) >= 400 {
                self.hidePanel()
                WindowManager.shared.showReader(text: r.text)
                return
            }
            card.kind = QueryRouter.classify(r.text)
            if card.selectionBounds != nil { PanelController.shared.show(near: card.selectionBounds) }
            self.runText(card: card)
        }
    }

    /// ⌥S：交互框选 → 截图管线；取消静默返回；通道关闭时忽略。
    /// 采集成功后弹面板；无需接管守卫——所有新入口先 cancelCurrent（含 pendingCapture），
    /// 且采集完成到 show 之间无 await（K3-P0-1：守卫读残留旧栈反而丢弃截图）。
    func beginScreenshotFlow() {
        guard SettingsStore.shared.screenshotEnabled else { return }
        cancelCurrent()
        let card = CardState(kind: .screenshotExplain, inputText: nil, context: nil, origin: .screenshot,
                             selectionBounds: nil, kindParams: nil, originalImage: nil, thumbnail: nil)
        card.phase = .capturing
        pendingCapture = Task { [weak self] in
            let image = await ScreenshotManager.captureInteractive()
            guard let self, !Task.isCancelled else { return }
            guard let image else { return }
            self.startScreenshotExplain(card: card, image: image, useCache: true)
            self.show(card: card, bounds: nil)
        }
    }

    // MARK: - 面板栈

    func pushWordQuery(word: String, context: String?) {
        guard stack.count < 2 else { return }
        cancelCurrent()
        let card = CardState(kind: .word, inputText: word, context: context,
                             origin: currentCard?.origin ?? .service, selectionBounds: nil,
                             kindParams: nil, originalImage: nil, thumbnail: nil)
        stack.append(card)
        revision += 1
        runText(card: card)
    }

    func pushWordAtQuery(image: NSImage, point: CGPoint) {
        guard stack.count < 2, stack.first?.kind == .screenshotExplain else { return }
        cancelCurrent()
        let quantized = CGPoint(x: (point.x * 100).rounded() / 100, y: (point.y * 100).rounded() / 100)
        let card = CardState(kind: .screenshotWordAt, inputText: nil, context: nil, origin: .screenshot,
                             selectionBounds: nil, kindParams: KindParams(point: quantized, pageIndex: nil),
                             originalImage: image, thumbnail: nil)
        card.phase = .loading
        stack.append(card)
        revision += 1
        guard let proc = ImagePipeline.normalize(image, maxEdge: 1568) else {
            card.phase = .failed("图像处理失败")
            return
        }
        let model = SettingsStore.shared.activeConfig?.model ?? ""
        let key = CacheStore.makeKey(normalizedInput: proc.sha256, kind: .screenshotWordAt, params: card.kindParams, model: model)
        let prompt = PromptLibrary.userPrompt(kind: .screenshotWordAt, text: "", context: nil, point: quantized)
        run(card: card, cacheKey: key, imageJPEG: proc.jpeg, prompt: prompt)
    }

    func popCard() {
        guard stack.count > 1 else { return }
        cancelCurrent()
        stack.removeLast()
        revision += 1
    }

    /// 类型手动切换（同输入重新查询）
    func requery(as kind: QueryKind) {
        guard kind != .screenshotExplain, kind != .screenshotWordAt, kind != .article, kind != .pdfPage else { return }
        guard let root = stack.first, let text = root.inputText, !text.isEmpty else { return }
        cancelCurrent()
        let card = CardState(kind: kind, inputText: text, context: root.context, origin: root.origin,
                             selectionBounds: root.selectionBounds, kindParams: nil, originalImage: nil, thumbnail: nil)
        stack = [card]
        revision += 1
        runText(card: card)
    }

    func retryCurrent() {
        guard let card = stack.last else { return }
        // 无原图的截图卡（历史回放）不可重查——先挡再清（K3-P1-4）
        switch card.kind {
        case .screenshotExplain, .screenshotWordAt:
            guard card.originalImage != nil else {
                card.phase = .notice("原图已释放，请重新截图（⌥S）")
                revision += 1
                return
            }
        default:
            break
        }
        cancelCurrent()
        card.content = ""
        card.reasoningActive = false
        card.usedCache = false
        switch card.kind {
        case .screenshotExplain:
            if let image = card.originalImage {
                startScreenshotExplain(card: card, image: image, useCache: false)
            }
        case .screenshotWordAt:
            guard let image = card.originalImage, let p = card.kindParams?.point else { return }
            guard let proc = ImagePipeline.normalize(image, maxEdge: 1568) else { card.phase = .failed("图像处理失败"); return }
            let model = SettingsStore.shared.activeConfig?.model ?? ""
            let key = CacheStore.makeKey(normalizedInput: proc.sha256, kind: .screenshotWordAt, params: card.kindParams, model: model)
            let prompt = PromptLibrary.userPrompt(kind: .screenshotWordAt, text: "", context: nil, point: p)
            run(card: card, cacheKey: key, imageJPEG: proc.jpeg, prompt: prompt, useCache: false)
        default:
            runText(card: card, useCache: false)
        }
    }

    // MARK: - 生命周期

    func cancelCurrent() {
        currentTask?.cancel()
        currentTask = nil
        pendingCapture?.cancel()
        pendingCapture = nil
        // 被取消的流式/加载卡给出终态（K3-P1-3：push 子查询等路径旧卡不再冻结在 streaming）
        for case let old in stack where old.phase == .streaming || old.phase == .loading {
            old.phase = .notice("已取消")
        }
        TTSEngine.shared.stop()
    }

    func closeAndCancel() {
        cancelCurrent()
        hidePanel()
    }

    func hidePanel() {
        PanelController.shared.hide()
    }

    /// 面板关闭（ESC/外点）→ 停止未完成的查询与 TTS
    func panelDidHide() {
        cancelCurrent()
    }

    // MARK: - 验收/演示入口

    func demoTextQuery(text: String, context: String? = nil) {
        beginTextQuery(text: text, context: context, selectionBounds: nil, origin: .service)
    }

    func demoImageQuery(text: String) {
        let image = DemoSupport.textImage(text)
        beginScreenshotWithImage(image)
    }

    /// 图上点词验收通道：合成图 + 指定归一化坐标
    func demoWordAtQuery(text: String, point: CGPoint) {
        let image = DemoSupport.textImage(text)
        beginScreenshotWithImage(image)
        pushWordAtQuery(image: image, point: point)
    }

    func beginScreenshotWithImage(_ image: NSImage) {
        cancelCurrent()
        let card = CardState(kind: .screenshotExplain, inputText: nil, context: nil, origin: .screenshot,
                             selectionBounds: nil, kindParams: nil, originalImage: nil, thumbnail: nil)
        show(card: card, bounds: nil)
        startScreenshotExplain(card: card, image: image, useCache: true)
    }

    // MARK: - 内部

    private func show(card: CardState, bounds: CGRect?) {
        stack = [card]
        revision += 1
        PanelController.shared.show(near: bounds)
    }

    private func startScreenshotExplain(card: CardState, image: NSImage, useCache: Bool) {
        guard let proc = ImagePipeline.normalize(image, maxEdge: 1568) else {
            card.phase = .failed("图像处理失败")
            revision += 1
            return
        }
        card.originalImage = image
        if card.thumbnail == nil { card.thumbnail = ImagePipeline.thumbnailImage(image) }
        let model = SettingsStore.shared.activeConfig?.model ?? ""
        let key = CacheStore.makeKey(normalizedInput: proc.sha256, kind: .screenshotExplain, params: nil, model: model)
        let prompt = PromptLibrary.userPrompt(kind: .screenshotExplain, text: "", context: nil)
        run(card: card, cacheKey: key, imageJPEG: proc.jpeg, prompt: prompt, useCache: useCache)
    }

    private func runText(card: CardState, useCache: Bool = true) {
        let model = SettingsStore.shared.activeConfig?.model ?? ""
        let key = CacheStore.makeKey(normalizedInput: QueryRouter.cacheNormalized(card.inputText ?? ""),
                                     kind: card.kind, params: nil, model: model)
        let prompt = PromptLibrary.userPrompt(kind: card.kind, text: card.inputText ?? "", context: card.context)
        run(card: card, cacheKey: key, imageJPEG: nil, prompt: prompt, useCache: useCache)
    }

    private func run(card: CardState, cacheKey: String, imageJPEG: Data?, prompt: String, useCache: Bool = true) {
        guard let config = SettingsStore.shared.activeConfig else {
            GlossLog.error("run abort: no active config")
            card.phase = .failed("未找到模型配置，请到设置添加")
            revision += 1
            return
        }
        guard let apiKey = SettingsStore.shared.apiKey(for: config) else {
            GlossLog.error("run abort: no api key for config \(config.id.uuidString)")
            card.phase = .noKey
            revision += 1
            return
        }
        if useCache, let cached = CacheStore.shared.get(cacheKey), !cached.isEmpty {
            card.content = cached
            card.usedCache = true
            card.phase = .done
            revision += 1
            GlossLog.info("cache hit \(cacheKey.prefix(12))")
            return
        }
        card.usedCache = false
        card.phase = .loading
        currentTask?.cancel()
        GlossLog.info("query begin kind=\(card.kind.rawValue) key=\(cacheKey.prefix(12))")
        currentTask = Task { [weak self] in
            do {
                let messages = [PromptLibrary.systemMessage(), ChatMessage(role: .user, text: prompt, imageJPEG: imageJPEG)]
                let stream = LLMClient.stream(messages: messages, config: config, apiKey: apiKey)
                for try await event in stream {
                    switch event {
                    case .reasoningDelta:
                        card.reasoningActive = true
                    case .contentDelta(let s):
                        card.reasoningActive = false
                        card.content += s
                        if card.phase != .streaming { card.phase = .streaming }
                        self?.revision += 1
                    case .done:
                        break
                    }
                }
                guard !Task.isCancelled else { return }
                if card.content.isEmpty {
                    card.phase = .failed("模型未返回内容")
                } else {
                    card.phase = .done
                    CacheStore.shared.put(cacheKey, card.content)
                    self?.saveHistory(card: card, model: config.model)
                }
                self?.revision += 1
                GlossLog.info("query done kind=\(card.kind.rawValue) chars=\(card.content.count)")
            } catch let e as AppError {
                if case .cancelled = e { return }
                card.phase = .failed(e.errorDescription ?? "查询失败")
                self?.revision += 1
                GlossLog.error("query failed kind=\(card.kind.rawValue) \(e.errorDescription ?? "?")")
            } catch is CancellationError {
                return
            } catch {
                card.phase = .failed("查询失败：\(error.localizedDescription)")
                self?.revision += 1
            }
        }
    }

    private func saveHistory(card: CardState, model: String) {
        guard SettingsStore.shared.historyEnabled else { return }
        let thumbJPEG: Data? = card.originalImage.flatMap { ImagePipeline.normalize($0, maxEdge: 200)?.jpeg }
        DataStore.addQuery(inputText: card.inputText, kind: card.kind, params: card.kindParams,
                           origin: card.origin, thumbnail: thumbJPEG, response: card.content, model: model)
    }

    /// 历史回放（词/句/段/图；读条目走 ReaderWindow）
    func replay(recordKind: String, inputText: String?, response: String, thumbnail: NSImage? = nil) {
        cancelCurrent()
        guard let kind = QueryKind(rawValue: recordKind) else { return }
        let card = CardState(kind: kind, inputText: inputText, context: nil, origin: .service,
                             selectionBounds: nil, kindParams: nil, originalImage: nil, thumbnail: thumbnail)
        card.content = response
        card.usedCache = true
        card.phase = .done
        stack = [card]
        revision += 1
        PanelController.shared.show(near: nil)
    }
}
