import os

enum GlossLog {
    private static let logger = Logger(subsystem: "com.wuyujun.gloss", category: "app")

    static func info(_ s: String) {
        logger.info("\(s, privacy: .public)")
        print("[Gloss] \(s)")
    }

    static func error(_ s: String) {
        logger.error("\(s, privacy: .public)")
        print("[Gloss][E] \(s)")
    }

    /// 诊断探针用:仅进 unified log debug 级，不落 stdout（热键路径高频，避免刷屏）
    static func debug(_ s: String) {
        logger.debug("\(s, privacy: .public)")
    }
}
