import CoreGraphics
import Foundation

enum QueryKind: String, CaseIterable {
    case word, sentence, paragraph, article
    case screenshotExplain, screenshotWordAt
    case pdfPage // M2
}

/// 带参 kind 的参数（纯字符串枚举不带关联值——tech-design §4.1）
struct KindParams: Codable, Equatable {
    var point: CGPoint? // 归一化坐标，量化到 1% 网格
    var pageIndex: Int? // M2 pdfPage
}

enum InputOrigin: String {
    case service, hotkeyAX, hotkeyClipboard, screenshot, pdfSelection, pdfPage
}

/// 文本路由（与 product-design §4.4 / tech-design §4.1 同源，勿单方修改）：
/// ≤3 词且无句中标点/句末标点 → word；含句末标点且 <60 词 → sentence；
/// 其余 <400 词 → paragraph；≥400 → article。
enum QueryRouter {
    static func classify(_ raw: String) -> QueryKind {
        let t = trimmed(raw)
        guard !t.isEmpty else { return .paragraph }
        let words = wordCount(t)
        let sentenceEnd = t.contains { ".!?。！？…".contains($0) }
        let midPunct = t.contains { ",;:，；：、".contains($0) }
        if words <= 3 && !midPunct && !sentenceEnd { return .word }
        if sentenceEnd && words < 60 { return .sentence }
        return words < 400 ? .paragraph : .article
    }

    static func trimmed(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 缓存键归一化：trim + 连续空白折叠为单空格（不改大小写——§10 键稳定性测试基准）
    static func cacheNormalized(_ raw: String) -> String {
        raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func wordCount(_ t: String) -> Int {
        t.split(whereSeparator: { $0.isWhitespace }).count
    }

    static func isChineseDominant(_ t: String) -> Bool {
        let scalars = Array(t.unicodeScalars)
        guard !scalars.isEmpty else { return false }
        let cjk = scalars.filter { (0x4E00...0x9FFF).contains($0.value) || (0x3000...0x303F).contains($0.value) }.count
        return Double(cjk) / Double(scalars.count) > 0.5
    }
}
