import CoreGraphics
import Foundation

/// Prompt 模板（与 tech-design §4.3 对应，PROMPT_VERSION 参与缓存键）。
enum PromptLibrary {
    static let version = "m1"

    static func systemMessage() -> ChatMessage {
        ChatMessage(role: .system, text: "你是 Gloss——macOS 上的英文阅读理解助手。始终用简体中文回答，严格按用户消息给定的 Markdown 结构输出，不添加额外内容。")
    }

    static func userPrompt(kind: QueryKind, text: String, context: String?, point: CGPoint? = nil) -> String {
        switch kind {
        case .word:
            return """
            解释下面的英文单词或短语，Markdown，严格按此结构：
            ## {原词}
            /{美式音标}/ /{英式音标}/
            **语境义**：{结合"语境"的准确中文含义；无语境则写"（通用）"并给最常用义}
            **词性与释义**
            1. {词性}. {释义}
            **高频搭配**
            - {搭配} — {中文}
            **例句**
            1. {英文例句}（{中文翻译}）
            **辨析**：{易混词/词源/使用注意，≤3 句；无则省略本节}
            ---
            查询：\(text)
            语境：\(context ?? "无")
            """
        case .sentence:
            return """
            解析下面的英文长难句，Markdown，严格按此结构：
            **翻译**
            {忠实流畅的中文翻译；有歧义处附（直译：…）}
            **结构拆解**
            - 主干：{…}
            - {修饰/从句}：{…}——{为什么这么理解}
            **难点**：{习语/倒装/指代/省略等 1–3 条}
            **句中难词**
            | 词/短语 | 音标 | 文中义 |
            |---|---|---|
            {2–3 行，按难度排序}
            ---
            句子：\(text)
            语境：\(context ?? "无")
            """
        case .paragraph:
            return """
            翻译下面的英文段落，Markdown，严格按此结构：
            **译文**
            {逐句对应翻译，保持段落结构；专业术语首次出现处保留英文括注}
            **难词表**
            | 词/短语 | 音标 | 文中义 | 原文例句 |
            |---|---|---|---|
            {3–6 行，按对理解的重要性排序；原文例句取自输入原文，不新造}
            ---
            段落：\(text)
            """
        case .screenshotExplain:
            return """
            解读这张 Mac 截图中的内容（可能是文本、图表、界面或混合）。中文回答，Markdown，严格按此结构：
            **识别内容**
            {忠实转写图中全部可读英文文本，保留原有结构；无文本则描述画面}
            **翻译与解释**
            {中文翻译；若含图表/界面，先说明它展示什么，再解释关键信息}
            **要点**
            - {2–4 条：生词、术语、值得注意的信息}
            """
        case .screenshotWordAt:
            let x = Int(((point?.x ?? 0) * 100).rounded())
            let y = Int(((point?.y ?? 0) * 100).rounded())
            return """
            用户在截图中点击了坐标（\(x)%，\(y)%）附近，想查那里的英文单词/短语。
            定位最接近点击处的英文词，按"词"模板结构输出（## 词 → 美英音标 → 语境义取它在本图语境中的含义 → 词性与释义 → 高频搭配 → 例句 → 辨析）。
            若点击处附近没有英文单词：明确说明，并列出图中主要英文词供选择。
            """
        case .article, .pdfPage:
            return text
        }
    }

    /// 长文按 ~600 词分批（段落聚合；无换行超长段落按句子二次切分）
    static func splitBatches(_ text: String, targetWords: Int = 600) -> [String] {
        let paragraphs = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var units: [String] = [] // 切分单元：优先段落，超长段落内部再按句切
        for p in paragraphs {
            if QueryRouter.wordCount(p) > targetWords {
                units.append(contentsOf: splitLongParagraph(p, targetWords: targetWords))
            } else {
                units.append(p)
            }
        }
        var batches: [String] = []
        var current: [String] = []
        var count = 0
        for u in units {
            current.append(u)
            count += QueryRouter.wordCount(u)
            if count >= targetWords {
                batches.append(current.joined(separator: "\n\n"))
                current = []
                count = 0
            }
        }
        if !current.isEmpty { batches.append(current.joined(separator: "\n\n")) }
        return batches.isEmpty ? [text] : batches
    }

    /// 按句号边界把超长段落切成 ≤targetWords 的块
    private static func splitLongParagraph(_ p: String, targetWords: Int) -> [String] {
        let sentences = p.components(separatedBy: ". ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var out: [String] = []
        var cur: [String] = []
        var count = 0
        for s in sentences {
            let piece = s.hasSuffix(".") ? s : s + "."
            cur.append(piece)
            count += QueryRouter.wordCount(piece)
            if count >= targetWords {
                out.append(cur.joined(separator: " "))
                cur = []
                count = 0
            }
        }
        if !cur.isEmpty { out.append(cur.joined(separator: " ")) }
        return out
    }

    static func articleBatchPrompt(text: String, index: Int, total: Int) -> String {
        """
        翻译并分析下面的英文段落（长文分批的第 \(index)/\(total) 批），Markdown，严格按此结构：
        **译文**
        {逐句对应翻译，保持段落结构；专业术语首次出现处保留英文括注}
        **难词表**
        | 词/短语 | 音标 | 文中义 | 原文例句 |
        |---|---|---|---|
        {3–6 行，按对理解的重要性排序；原文例句取自输入原文，不新造}
        **本批要点**
        - {2–3 条}
        **本批术语**（若有）
        | 术语 | 领域 | 解释 |
        |---|---|---|
        {无则写"无"}
        ---
        段落：\(text)
        """
    }

    /// 聚合请求入参 = 逐批要点 + 难词表 + 术语表（入参覆盖不了的输出只能靠编造——禁只喂要点）
    static func aggregatePrompt(batchMaterials: String) -> String {
        """
        汇总一篇英文长文各批次的分析结果，Markdown，严格按此结构：
        **生词表**
        | 词/短语 | 音标 | 文中义 | 原文例句 |
        |---|---|---|---|
        {从下方各批难词表去重合并，按重要性排序取 10–20 个；原文例句沿用批内条目，不新造}
        **术语表**
        | 术语 | 领域 | 解释 |
        |---|---|---|
        {各批术语去重合并；无则写"无"}
        **逻辑解读**
        {文章主线 / 论证结构（观点→证据→结论）/ 关键转折 / 结论 / 背景补充}
        ---
        \(batchMaterials)
        """
    }
}
