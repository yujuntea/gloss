import AppKit
import SwiftUI

@MainActor
final class ReaderViewModel: ObservableObject {
    enum BatchPhase: Equatable { case pending, running, done, failed }

    struct WordRow: Identifiable {
        let id = UUID()
        let word: String
        let phonetic: String
        let meaning: String
        let example: String
    }

    struct TermRow: Identifiable {
        let id = UUID()
        let term: String
        let field: String
        let explanation: String
    }

    let inputText: String
    @Published var batches: [String] = []
    @Published var batchPhases: [BatchPhase] = []
    @Published var batchTranslations: [String] = []
    @Published var wordRows: [WordRow] = []
    @Published var termRows: [TermRow] = []
    @Published var aggregatePhase: BatchPhase = .pending
    @Published var logicMarkdown = ""
    @Published var isRunning = false
    @Published var progressLine = ""
    private var task: Task<Void, Never>?

    init(text: String) {
        inputText = text
    }

    func start() {
        guard !isRunning else { return }
        cancel()
        // 已分批（取消后继续）则沿用现有批次（done 批经缓存秒回）；否则新分批（K3-P2-3）
        if batches.isEmpty {
            batches = PromptLibrary.splitBatches(inputText)
            batchPhases = batches.map { _ in .pending }
            batchTranslations = batches.map { _ in "" }
            wordRows = []
            termRows = []
            logicMarkdown = ""
            aggregatePhase = .pending
        }
        isRunning = true
        task = Task { [weak self] in await self?.runAll() }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
        // 取消时把 running 批置回 pending，避免转圈动画永驻（L2a P2-2）
        for i in batchPhases.indices where batchPhases[i] == .running { batchPhases[i] = .pending }
        if aggregatePhase == .running { aggregatePhase = .pending }
    }

    func retryBatch(_ idx: Int) {
        guard batches.indices.contains(idx), batchPhases[idx] == .failed else { return }
        task?.cancel() // 覆盖前脱锚旧任务（K3-P2-2）
        task = Task { [weak self] in
            guard let self else { return }
            isRunning = true
            await runBatchBody(idx)
            isRunning = false
        }
    }

    func retryAggregate() {
        guard aggregatePhase == .failed else { return }
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            isRunning = true
            await runAggregate()
            isRunning = false
        }
    }

    private func runAll() async {
        for i in batches.indices {
            await runBatchBody(i)
            if Task.isCancelled { isRunning = false; return }
        }
        await runAggregate()
        isRunning = false
    }

    private func runBatchBody(_ i: Int) async {
        guard batches.indices.contains(i) else { return }
        batchPhases[i] = .running
        progressLine = "批次 \(i + 1)/\(batches.count)"
        let prompt = PromptLibrary.articleBatchPrompt(text: batches[i], index: i + 1, total: batches.count)
        do {
            let out = try await queryOnce(prompt: prompt)
            batchTranslations[i] = out
            batchPhases[i] = .done
            ingestBatch(out)
        } catch {
            if Task.isCancelled { return }
            batchPhases[i] = .failed
            GlossLog.error("reader batch \(i + 1) failed")
        }
    }

    private func ingestBatch(_ markdown: String) {
        if let w = SectionExtractor.section(named: "难词表", in: markdown) {
            for row in SectionExtractor.tableRows(w).dropFirst() where row.count >= 3 {
                let ex = row.count > 3 ? row[3] : ""
                if !wordRows.contains(where: { $0.word.lowercased() == row[0].lowercased() }) {
                    wordRows.append(WordRow(word: row[0], phonetic: row[1], meaning: row[2], example: ex))
                }
            }
        }
        if let t = SectionExtractor.section(named: "本批术语", in: markdown) {
            for row in SectionExtractor.tableRows(t).dropFirst() where row.count >= 3 {
                if row[0] == "无" { continue }
                if !termRows.contains(where: { $0.term == row[0] }) {
                    termRows.append(TermRow(term: row[0], field: row[1], explanation: row[2]))
                }
            }
        }
    }

    private func runAggregate() async {
        aggregatePhase = .running
        progressLine = "汇总分析"
        var materials = ""
        for (i, b) in batches.enumerated() {
            let missing = batchPhases.indices.contains(i) && batchPhases[i] != .done
            if missing {
                materials += "【第\(i + 1)批】（该批查询失败，材料缺失）\n\n"
            } else {
                materials += "【第\(i + 1)批】\n\(batchTranslations.indices.contains(i) ? batchTranslations[i] : "")\n\n"
            }
        }
        let prompt = PromptLibrary.aggregatePrompt(batchMaterials: materials)
        do {
            let out = try await queryOnce(prompt: prompt)
            ingestAggregate(out)
            aggregatePhase = .done
            DataStore.addQuery(inputText: inputText, kind: .article, params: nil, origin: .service,
                               thumbnail: nil, response: out, model: SettingsStore.shared.activeConfig?.model ?? "")
            GlossLog.info("reader aggregate done")
        } catch {
            if Task.isCancelled { return }
            aggregatePhase = .failed
            GlossLog.error("reader aggregate failed")
        }
    }

    private func ingestAggregate(_ markdown: String) {
        logicMarkdown = SectionExtractor.section(named: "逻辑解读", in: markdown) ?? markdown
        if let w = SectionExtractor.section(named: "生词表", in: markdown) {
            for row in SectionExtractor.tableRows(w).dropFirst() where row.count >= 3 {
                let ex = row.count > 3 ? row[3] : ""
                if !wordRows.contains(where: { $0.word.lowercased() == row[0].lowercased() }) {
                    wordRows.append(WordRow(word: row[0], phonetic: row[1], meaning: row[2], example: ex))
                }
            }
        }
        if let t = SectionExtractor.section(named: "术语表", in: markdown) {
            for row in SectionExtractor.tableRows(t).dropFirst() where row.count >= 3 {
                if row[0] == "无" { continue }
                if !termRows.contains(where: { $0.term == row[0] }) {
                    termRows.append(TermRow(term: row[0], field: row[1], explanation: row[2]))
                }
            }
        }
    }

    private func queryOnce(prompt: String) async throws -> String {
        guard let config = SettingsStore.shared.activeConfig else { throw AppError.noAPIKey }
        guard let apiKey = SettingsStore.shared.apiKey(for: config) else { throw AppError.noAPIKey }
        let cacheKey = CacheStore.makeKey(normalizedInput: QueryRouter.cacheNormalized(prompt), kind: .article, params: nil, model: config.model)
        if let cached = CacheStore.shared.get(cacheKey) { return cached }
        let messages = [PromptLibrary.systemMessage(), ChatMessage(role: .user, text: prompt)]
        var out = ""
        for try await ev in LLMClient.stream(messages: messages, config: config, apiKey: apiKey) {
            if case .contentDelta(let s) = ev { out += s }
        }
        guard !out.isEmpty else { throw AppError.parse("空响应") }
        CacheStore.shared.put(cacheKey, out)
        return out
    }
}

struct ReaderView: View {
    // 所有权在 WindowManager（替换精读内容时由其取消旧 VM——L2a P1-6）
    @ObservedObject private var vm: ReaderViewModel
    @State private var tab = 0

    // VM 必须由外部注入：任务启动归 WindowManager，视图自己不再造 VM（免得造出一个永不启动的空窗口）
    init(vm: ReaderViewModel) {
        _vm = ObservedObject(wrappedValue: vm)
    }

    var body: some View {
        HSplitView {
            ScrollView {
                Text(vm.inputText)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 380, maxWidth: 560)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Picker("", selection: $tab) {
                        Text("翻译").tag(0)
                        Text("生词").tag(1)
                        Text("术语").tag(2)
                        Text("解读").tag(3)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 320)
                    Spacer()
                    if vm.isRunning {
                        ProgressView().scaleEffect(0.7)
                        Text(vm.progressLine).font(.caption).foregroundStyle(.secondary)
                    }
                    Button {
                        if vm.isRunning { vm.cancel() } else { vm.start() }
                    } label: {
                        Image(systemName: vm.isRunning ? "stop.circle" : "play.circle")
                    }
                    .buttonStyle(.plain)
                    .help(vm.isRunning ? "取消（可继续）" : "继续")
                }
                .padding(10)
                Divider()
                tabContent
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(minWidth: 500)
        }
        .frame(minWidth: 980, minHeight: 620)
        // 只负责「换内容」路径：旧视图消失即取消它自己那个 VM（cancel 幂等，与 showReader 的显式取消重复调用无害）。
        // 关窗不会触发 onDisappear（实测），关窗取消在 WindowManager.windowWillClose。
        .onDisappear { vm.cancel() }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case 0: translationTab
        case 1: wordsTab
        case 2: termsTab
        default: logicTab
        }
    }

    private var translationTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(vm.batches.enumerated()), id: \.offset) { i, _ in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("第 \(i + 1)/\(vm.batches.count) 批").font(.caption.bold()).foregroundStyle(.secondary)
                            switch vm.batchPhases.indices.contains(i) ? vm.batchPhases[i] : .pending {
                            case .running: ProgressView().scaleEffect(0.5)
                            case .failed:
                                Button("重试本批") { vm.retryBatch(i) }.buttonStyle(.link).font(.caption)
                            default: EmptyView()
                            }
                        }
                        if vm.batchTranslations.indices.contains(i), !vm.batchTranslations[i].isEmpty {
                            MarkdownView(markdown: vm.batchTranslations[i])
                        } else {
                            Text("…").foregroundStyle(.tertiary)
                        }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var wordsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if vm.wordRows.isEmpty {
                    Text("暂无生词").font(.callout).foregroundStyle(.secondary)
                }
                ForEach(vm.wordRows) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(row.word).font(.callout.bold())
                            Text(row.phonetic).font(.caption).foregroundStyle(.secondary)
                            Button {
                                TTSEngine.shared.speak(row.word, accent: .us)
                            } label: {
                                Image(systemName: "speaker.wave.2").font(.caption)
                            }
                            .buttonStyle(.plain)
                            .help("朗读")
                        }
                        Text(row.meaning).font(.system(size: 13))
                        if !row.example.isEmpty {
                            Text(row.example).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var termsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if vm.termRows.isEmpty {
                    Text("本文未检出专业术语").font(.callout).foregroundStyle(.secondary)
                }
                ForEach(vm.termRows) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(row.term).font(.callout.bold())
                            Text(row.field).font(.caption).foregroundStyle(.tint)
                        }
                        Text(row.explanation).font(.system(size: 13))
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var logicTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                switch vm.aggregatePhase {
                case .pending:
                    Text("（等待各批次完成后汇总）").font(.callout).foregroundStyle(.secondary)
                case .running:
                    HStack { ProgressView().scaleEffect(0.6); Text("正在汇总…").font(.callout) }
                case .failed:
                    VStack(alignment: .leading, spacing: 6) {
                        Text("汇总失败").font(.callout).foregroundStyle(.orange)
                        Button("重试汇总") { vm.retryAggregate() }.buttonStyle(.bordered)
                    }
                case .done:
                    MarkdownView(markdown: vm.logicMarkdown)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
