import Foundation

/// 取数契约（tech-design §4.3）：模型输出的可交互内容按固定粗体节名提取为类型化块，禁自由 Markdown 事后正则。
enum SectionExtractor {
    struct Section: Equatable {
        let name: String
        let body: String
    }

    /// 节名识别：以独立粗体段开头的行（**xxx** 或 **xxx**：… / **xxx**（若有））→ 节名
    static func isSectionHeader(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("**"), t.count > 4 else { return nil }
        let afterOpen = t.index(t.startIndex, offsetBy: 2)
        guard let close = t.range(of: "**", range: afterOpen..<t.endIndex) else { return nil }
        let inner = String(t[afterOpen..<close.lowerBound])
        guard !inner.isEmpty, !inner.contains("*") else { return nil }
        return inner.trimmingCharacters(in: CharacterSet(charactersIn: "：: "))
    }

    static func allSections(in markdown: String) -> [Section] {
        var out: [Section] = []
        var current: (name: String, lines: [String])? = nil
        func flush() {
            if let c = current {
                out.append(Section(name: c.name, body: c.lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            current = nil
        }
        for line in markdown.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                flush()
                continue
            }
            if let name = isSectionHeader(line) {
                flush()
                current = (name, [])
            } else if current != nil {
                current!.lines.append(line)
            }
        }
        flush()
        return out
    }

    static func section(named name: String, in markdown: String) -> String? {
        allSections(in: markdown).first { $0.name == name }?.body
    }

    /// 移除指定节（其余原样保留），用于卡片正文与交互 chips 去重
    static func removingSection(named name: String, in markdown: String) -> String {
        var lines: [String] = []
        var skipping = false
        for line in markdown.components(separatedBy: "\n") {
            if let n = isSectionHeader(line) {
                skipping = (n == name)
                if !skipping { lines.append(line) }
                continue
            }
            if !skipping { lines.append(line) }
        }
        return lines.joined(separator: "\n")
    }

    /// 简单 markdown 表格解析：|a|b|c| → [a,b,c]，跳过分隔行
    static func tableRows(_ body: String) -> [[String]] {
        var rows: [[String]] = []
        for rawLine in body.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("|"), line.hasSuffix("|"), line.count > 1 else { continue }
            let cells = line.dropFirst().dropLast().components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            if cells.allSatisfy({ $0.isEmpty || $0.allSatisfy { $0 == "-" || $0 == ":" } }) { continue }
            rows.append(cells)
        }
        return rows
    }

    static func listItems(_ body: String) -> [String] {
        body.components(separatedBy: "\n").compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("- ") { return String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
            if let r = t.range(of: "^\\d+[.、]\\s*", options: .regularExpression) {
                return String(t[r.upperBound...])
            }
            return nil
        }
    }
}
