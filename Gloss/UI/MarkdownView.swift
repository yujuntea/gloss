import SwiftUI

/// 模板子集 Markdown 渲染（标题/粗体行/列表/表格/分隔线/段落；行内样式走 AttributedString）。
/// 设计原文选用 swift-markdown-ui；为消除 SPM 网络依赖且只渲染固定模板子集，M1 内置该渲染器（偏差已在评审声明）。
struct MarkdownView: View {
    let markdown: String

    enum Block {
        case heading(String, Int)
        case boldLine(String)
        case paragraph(String)
        case listItem(String)
        case table([[String]])
        case divider
    }

    static func parseBlocks(_ md: String) -> [Block] {
        var blocks: [Block] = []
        var tableBuf: [[String]] = []
        func flushTable() {
            if !tableBuf.isEmpty {
                blocks.append(.table(tableBuf))
                tableBuf = []
            }
        }
        for rawLine in md.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flushTable(); continue }
            if line.hasPrefix("|"), line.hasSuffix("|"), line.count > 1 {
                let cells = line.dropFirst().dropLast().components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if cells.allSatisfy({ $0.isEmpty || $0.allSatisfy { $0 == "-" || $0 == ":" } }) { continue }
                tableBuf.append(cells)
                continue
            }
            flushTable()
            if line == "---" { blocks.append(.divider); continue }
            if line.hasPrefix("# ") { blocks.append(.heading(String(line.dropFirst(2)), 1)); continue }
            if line.hasPrefix("### ") { blocks.append(.heading(String(line.dropFirst(4)), 3)); continue }
            if line.hasPrefix("## ") { blocks.append(.heading(String(line.dropFirst(3)), 2)); continue }
            if line.hasPrefix("- ") { blocks.append(.listItem(String(line.dropFirst(2)))); continue }
            if let r = line.range(of: "^\\d+[.、]\\s*", options: .regularExpression) {
                blocks.append(.listItem(String(line[r.upperBound...])))
                continue
            }
            if let inner = boldLine(line) { blocks.append(.boldLine(inner)); continue }
            blocks.append(.paragraph(line))
        }
        flushTable()
        return blocks
    }

    static func boldLine(_ line: String) -> String? {
        guard line.hasPrefix("**"), line.hasSuffix("**"), line.count > 4 else { return nil }
        let inner = String(line.dropFirst(2).dropLast(2))
        return inner.contains("**") ? nil : inner.trimmingCharacters(in: CharacterSet(charactersIn: "：: "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(Self.parseBlocks(markdown).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ b: Block) -> some View {
        switch b {
        case .heading(let s, let level):
            InlineText(s)
                .font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                .padding(.top, 2)
        case .boldLine(let s):
            InlineText(s).font(.callout.bold())
        case .paragraph(let s):
            InlineText(s).font(.system(size: 13))
        case .listItem(let s):
            HStack(alignment: .top, spacing: 6) {
                Text("·").font(.system(size: 13, weight: .bold))
                InlineText(s).font(.system(size: 13))
            }
            .padding(.leading, 4)
        case .table(let rows):
            TemplateTable(rows: rows)
        case .divider:
            Divider()
        }
    }
}

struct InlineText: View {
    private let parsed: AttributedString

    init(_ s: String) {
        parsed = (try? AttributedString(markdown: s, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }

    var body: some View {
        // 模型输出不可信：禁用链接点击（tech §4.5）
        Text(parsed)
            .environment(\.openURL, OpenURLAction { _ in .discarded })
    }
}

struct TemplateTable: View {
    let rows: [[String]]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        InlineText(cell)
                            .font(.system(size: 12, weight: i == 0 ? .semibold : .regular))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
