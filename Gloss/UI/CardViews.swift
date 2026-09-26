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
                    NoticeView(text: s)
                case .failed(let msg):
                    FailedView(message: msg, showScreenshotOption: card.inputText == nil)
                case .loading:
                    SkeletonView(reasoning: card.reasoningActive)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let img = card.originalImage ?? card.thumbnail {
                ImageTapView(image: img)
            }
            MarkdownView(markdown: card.content)
        }
    }
}

/// 缩略图 + 图上点词（SpatialTapGesture，坐标按实际显示区域归一化）
struct ImageTapView: View {
    let image: NSImage

    var body: some View {
        GeometryReader { geo in
            let iw = max(image.size.width, 1)
            let ih = max(image.size.height, 1)
            let s = min(geo.size.width / iw, geo.size.height / ih)
            let dw = iw * s, dh = ih * s
            let ox = (geo.size.width - dw) / 2, oy = (geo.size.height - dh) / 2
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { v in
                    let nx = (v.location.x - ox) / max(dw, 1)
                    let ny = (v.location.y - oy) / max(dh, 1)
                    guard nx >= 0, nx <= 1, ny >= 0, ny <= 1 else { return }
                    SessionCoordinator.shared.pushWordAtQuery(image: image, point: CGPoint(x: nx, y: ny))
                })
        }
        .frame(height: 160)
        .help("点击图中英文单词可查询")
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
                    HStack(spacing: 6) {
                        Button {
                            SessionCoordinator.shared.pushWordQuery(word: word, context: context)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.2)).frame(width: 140, height: 16)
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12)).frame(height: 10)
            }
            if reasoning {
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.6)
                    Text("思考中…").font(.caption).foregroundStyle(.secondary)
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
