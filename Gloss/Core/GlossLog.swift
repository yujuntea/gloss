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
}
