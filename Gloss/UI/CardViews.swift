import SwiftUI

/// 四类卡片 + 状态视图的路由容器
struct CardRouterView: View {
    @ObservedObject var card: CardState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if stackDepth > 1 {
                    Button { SessionCoordinator.shared.popCard() } label: {
                        Label(backLabel, systemImage: "chevron.left")
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
                switch card.phase {
                case .capturing:
                    CapturingView()
                case .noKey:
                    NoKeyView()
                case .notice(let s):
                    // 取消提示不吞掉已生成的内容：用户点词条切到子卡后返回时，
                    // 若根卡正流式则内容已有一部分，直接盖成"已取消"等于白等一场
                    if card.content.isEmpty {
                        NoticeView(text: s)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            NoticeView(text: s)
                            kindBody
                        }
                    }
                case .failed(let msg):
                    FailedView(message: msg, showScreenshotOption: card.inputText == nil)
                case .loading:
                    SkeletonView(reasoning: card.reasoningActive,
                                 reasoningText: card.reasoningText,
                                 reasoningSince: card.reasoningStartedAt)
                case .streaming, .done:
                    kindBody
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var stackDepth: Int { SessionCoordinator.shared.stack.count }

    private var backLabel: String {
        guard let root = SessionCoordinator.shared.stack.first else { return "返回" }
        switch root.kind {
        case .sentence: return "返回句子"
        case .paragraph: return "返回段落"
        case .screenshotExplain: return "返回整图"
        default: return "返回"
        }
    }

    @ViewBuilder
    private var kindBody: some View {
        switch card.kind {
        case .word, .screenshotWordAt:
            WordCardBody(card: card)
        case .sentence:
            SentenceCardBody(card: card)
        case .paragraph:
            ParagraphCardBody(card: card)
        case .screenshotExplain:
            ScreenshotCardBody(card: card)
        default:
            MarkdownView(markdown: card.content)
        }
    }
}

// MARK: - 单词卡

enum CardMarkdown {
    /// 去掉首个 1–3 级 "＃" 标题行（卡头已单独展示词名，避免重复；M3 实测可能降级为 # 输出）
    static func stripFirstHeading(_ md: String) -> String {
        guard let r = md.range(of: "^#{1,3}\\s+[^\\n]*\\n?", options: .regularExpression) else { return md }
        return String(md[r.upperBound...])
    }
}

struct WordCardBody: View {
    @ObservedObject var card: CardState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.displayQuery.isEmpty ? "截图取词" : card.displayQuery)
                    .font(.title3.bold())
                    .textSelection(.enabled)
                Spacer()
                if card.phase == .streaming { BlinkingCursor() }
            }
            MarkdownView(markdown: CardMarkdown.stripFirstHeading(card.content))
        }
    }
}

// MARK: - 句子卡

struct SentenceCardBody: View {
    @ObservedObject var card: CardState

    private var chips: [[String]] {
        guard let sec = SectionExtractor.section(named: "句中难词", in: card.content) else { return [] }
        return Array(SectionExtractor.tableRows(sec).dropFirst())
    }

    private var bodyMarkdown: String {
        SectionExtractor.removingSection(named: "句中难词", in: card.content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let original = card.inputText {
                Text(original)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            MarkdownView(markdown: bodyMarkdown)
            WordChipsRow(rows: chips, context: card.inputText)
        }
    }
}

// MARK: - 段落卡

struct ParagraphCardBody: View {
    @ObservedObject var card: CardState

    private var chips: [[String]] {
        guard let sec = SectionExtractor.section(named: "难词表", in: card.content) else { return [] }
        return Array(SectionExtractor.tableRows(sec).dropFirst())
    }

    private var bodyMarkdown: String {
        SectionExtractor.removingSection(named: "难词表", in: card.content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let original = card.inputText {
                Text(original)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            MarkdownView(markdown: bodyMarkdown)
            WordChipsRow(rows: chips, context: card.inputText)
        }
    }
}

// MARK: - 截图卡

struct ScreenshotCardBody: View {
    @ObservedObject var card: CardState

    private var chips: [[String]] {
        guard let sec = SectionExtractor.section(named: "难词表", in: card.content) else { return [] }
        return Array(SectionExtractor.tableRows(sec).dropFirst())
    }

    // 难词表已由 chips 渲染，从正文移除避免同一张表格被渲染两遍
    private var bodyMarkdown: String {
        SectionExtractor.removingSection(named: "难词表", in: card.content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let img = card.originalImage ?? card.thumbnail {
                ImageTapView(image: img)
            }
            // chips 放在正文**之前**：面板高度上限为屏高 0.65，密集截图的正文（识别+翻译+要点）
            // 往往超出上限，若 chips 在末尾就会被推到滚动区外——而这正是最需要点词的场景（实机验收实证）。
            // 缩略图 + chips 构成首屏「看图 → 点词」的完整入口，长正文退到下方滚动。
            WordChipsRow(rows: chips, context: card.inputText)
            MarkdownView(markdown: bodyMarkdown)
        }
    }
}

/// 缩略图 + 图上点词（SpatialTapGesture，坐标按实际显示区域归一化）。
/// 分流（§4.5）：原图自然宽度 ≤ 卡片内宽时缩略图里的正文本就看得清，直接就地点词（保留 S6 现状）；
/// 宽于卡片内宽则正文在 160pt 高度里不可读，改为打开图片放大窗在整图上点词。
struct ImageTapView: View {
    let image: NSImage

    var body: some View {
        GeometryReader { geo in
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { v in
                    tap(viewSize: geo.size, at: v.location)
                })
                // 文案与分流用同一个实测卡宽判定，否则面板拉宽后 help 会与实际行为相反
                .help(ImageGeometry.needsZoomWindow(imageWidth: image.size.width, cardWidth: geo.size.width)
                      ? "点击放大查看（在大图上点单词）" : "点击图中英文单词可查询")
        }
        .frame(height: 160)
    }

    private func tap(viewSize: CGSize, at location: CGPoint) {
        if ImageGeometry.needsZoomWindow(imageWidth: image.size.width, cardWidth: viewSize.width) {
            WindowManager.shared.showImage(image: image) { point, screenRect in
                SessionCoordinator.shared.pushWordAtQuery(image: image, point: point, clickRect: screenRect)
            }
            return
        }
        guard let p = ImageGeometry.normalizedPoint(viewSize: viewSize, imagePixelSize: image.size, click: location) else { return }
        SessionCoordinator.shared.pushWordAtQuery(image: image, point: p)
    }
}

// MARK: - 难词 chips（全文统一交互：点击主体=切单词卡，尾随 🔊=朗读）

struct WordChipsRow: View {
    let rows: [[String]]
    let context: String?

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("难词").font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    let word = row.first ?? ""
                    let phon = row.count > 1 ? row[1] : ""
                    let mean = row.count > 2 ? row[2] : ""
                    // 原文例句是这一行词最贴切的语境（§6.2）；模型偶尔输出空串，空串不得覆盖上层传下来的 context
                    let rowContext = row.count > 3 && !row[3].isEmpty ? row[3] : context
                    HStack(spacing: 6) {
                        Button {
                            SessionCoordinator.shared.pushWordQuery(word: word, context: rowContext)
                        } label: {
                            HStack(spacing: 6) {
                                Text(word).font(.callout.bold())
                                if !phon.isEmpty { Text(phon).font(.caption).foregroundStyle(.secondary) }
                                if !mean.isEmpty { Text(mean).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(word.isEmpty)
                        .help("查这个词")
                        Button {
                            TTSEngine.shared.speak(word, accent: .us)
                        } label: {
                            Image(systemName: "speaker.wave.2").font(.caption)
                        }
                        .buttonStyle(.plain)
                        .disabled(word.isEmpty)
                        .help("朗读")
                    }
                }
            }
        }
    }
}

// MARK: - 状态视图

struct CapturingView: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.7)
            Text("正在获取选中文本…").font(.callout).foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
    }
}

struct SkeletonView: View {
    let reasoning: Bool
    var reasoningText: String = ""
    var reasoningSince: Date? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.2)).frame(width: 140, height: 16)
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12)).frame(height: 10)
            }
            // 始终给一行文字：模型还没发出 reasoning delta 时也要有反馈，
            // 否则骨架屏是"静默"的，用户无从判断是在跑还是卡了
            if reasoning {
                ReasoningPreview(text: reasoningText, since: reasoningSince ?? Date())
            } else {
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.6)
                    Text("正在查询…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// 思考流实时预览：秒表 + 固定高的尾部滚动区。
/// 固定高是刻意的：思考 delta 很密，高度随文本增长会驱动面板逐帧 resize（抖动）；
/// 正文到达后整块随骨架屏消失，思考文本不入缓存不入历史（回放卡天然无此区）。
private struct ReasoningPreview: View {
    let text: String
    let since: Date
    private static let tailID = "reasoning-tail"

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.6)
                    Text("思考中 · \(max(0, Int(ctx.date.timeIntervalSince(since))))s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Text(text.isEmpty ? "等待模型输出思考…" : text)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(Self.tailID)
                }
                .frame(height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                .onChange(of: text) { _, _ in
                    withAnimation(.linear(duration: 0.12)) { proxy.scrollTo(Self.tailID, anchor: .bottom) }
                }
            }
        }
    }
}

struct FailedView: View {
    let message: String
    let showScreenshotOption: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
            HStack(spacing: 10) {
                Button("重试") { SessionCoordinator.shared.retryCurrent() }.buttonStyle(.bordered)
                if showScreenshotOption {
                    Button("改用截图查询 ⌥S") { SessionCoordinator.shared.beginScreenshotFlow() }.buttonStyle(.bordered)
                }
            }
        }
    }
}

struct NoKeyView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("未配置 API Key", systemImage: "key")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("去设置") { WindowManager.shared.showSettings() }.buttonStyle(.bordered)
        }
    }
}

struct NoticeView: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "info.circle")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
    }
}

struct BlinkingCursor: View {
    @State private var on = true

    var body: some View {
        Text("▍")
            .font(.callout.bold())
            .foregroundStyle(.tint)
            .opacity(on ? 1 : 0.15)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { on = false }
            }
    }
}
