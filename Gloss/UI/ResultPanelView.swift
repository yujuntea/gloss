import SwiftUI

/// 浮窗根视图：顶栏（类型切换/固定/设置/关闭）+ 卡片区 + 底部操作条
struct ResultPanelView: View {
    @ObservedObject private var coordinator = SessionCoordinator.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: coordinator.revision) { _ in
            PanelController.shared.resizeToContent()
        }
        .onChange(of: coordinator.pinned) { _ in
            PanelController.shared.resizeToContent()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if isTextKind {
                Picker("", selection: kindSelection) {
                    Text("词").tag(0)
                    Text("句").tag(1)
                    Text("段").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
            } else if isScreenshotKind {
                Text("读图").font(.callout.bold())
            }
            Spacer()
            Button {
                coordinator.pinned.toggle()
            } label: {
                Image(systemName: coordinator.pinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.plain)
            .help("固定浮窗")
            Button {
                WindowManager.shared.showSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("设置")
            Button {
                coordinator.closeAndCancel()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("关闭 (ESC)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var content: some View {
        if let card = coordinator.currentCard {
            CardRouterView(card: card)
        } else {
            Text("无查询").font(.callout).foregroundStyle(.secondary).padding(20)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let card = coordinator.currentCard {
                Text(originLabel(card.origin)).font(.caption2).foregroundStyle(.secondary)
                if card.usedCache {
                    Text("缓存")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
                Spacer()
                actions(for: card)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - 派生

    private var isTextKind: Bool {
        switch coordinator.currentCard?.kind {
        case .word, .sentence, .paragraph: return true
        default: return false
        }
    }

    private var isScreenshotKind: Bool {
        switch coordinator.currentCard?.kind {
        case .screenshotExplain, .screenshotWordAt: return true
        default: return false
        }
    }

    private var kindSelection: Binding<Int> {
        Binding(
            get: {
                switch coordinator.currentCard?.kind {
                case .sentence: return 1
                case .paragraph: return 2
                default: return 0
                }
            },
            set: { v in
                let k: QueryKind = v == 1 ? .sentence : (v == 2 ? .paragraph : .word)
                coordinator.requery(as: k)
            }
        )
    }

    private func originLabel(_ origin: InputOrigin) -> String {
        switch origin {
        case .service: return "服务"
        case .hotkeyAX: return "⌥D"
        case .hotkeyClipboard: return "⌥D·⌘C"
        case .screenshot: return "⌥S"
        case .pdfSelection, .pdfPage: return "PDF"
        }
    }

    @ViewBuilder
    private func actions(for card: CardState) -> some View {
        switch card.kind {
        case .word, .screenshotWordAt:
            iconButton("speaker.wave.2", "朗读美音") { TTSEngine.shared.speak(card.displayQuery, accent: .us) }
            iconButton("speaker.wave.2.fill", "朗读英音") { TTSEngine.shared.speak(card.displayQuery, accent: .uk) }
            iconButton("doc.on.doc", "复制") { copy(card.displayQuery) }
        case .sentence, .paragraph:
            iconButton("speaker.wave.2", "朗读原文") { TTSEngine.shared.speak(card.inputText ?? "", accent: .us) }
            iconButton("doc.on.doc", "复制") { copy(card.inputText ?? "") }
            if card.kind == .paragraph {
                iconButton("book", "展开精读") { WindowManager.shared.showReader(text: card.inputText ?? "") }
            }
        case .screenshotExplain:
            iconButton("speaker.wave.2", "朗读识别文本") { TTSEngine.shared.speak(speakText(card), accent: .us) }
            iconButton("doc.on.doc", "复制识别文本") { copy(speakText(card)) }
            iconButton("book", "展开精读") { WindowManager.shared.showReader(text: speakText(card)) }
            iconButton("arrow.clockwise", "重新截图") { coordinator.beginScreenshotFlow() }
        default:
            EmptyView()
        }
        if card.usedCache {
            let replayWithoutImage = (card.kind == .screenshotExplain || card.kind == .screenshotWordAt) && card.originalImage == nil
            if !replayWithoutImage { // 回放截图卡无原图不可重查（K3-P1-4）
                iconButton("arrow.triangle.2.circlepath", "重新查询（跳过缓存）") { coordinator.retryCurrent() }
            }
        }
    }

    private func speakText(_ card: CardState) -> String {
        SectionExtractor.section(named: "识别内容", in: card.content) ?? String(card.content.prefix(200))
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    private func iconButton(_ system: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: system) }
            .buttonStyle(.plain)
            .help(help)
    }
}
