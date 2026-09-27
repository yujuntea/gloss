import AppKit
import Foundation
import Sparkle

/// 更新能力单点入口：菜单栏菜单与设置窗口共用同一个 SPUStandardUpdaterController。
/// 控制器必须全局唯一——多实例会各自维护检查周期与驱动状态，菜单与设置页行为将不一致。
/// 首次访问发生在 AppDelegate 启动链内（搭菜单栏），满足 Sparkle「app 基本初始化后再启动 updater」的要求。
@MainActor
enum UpdaterCenter {
    static let controller = SPUStandardUpdaterController(startingUpdater: true,
                                                         updaterDelegate: nil,
                                                         userDriverDelegate: nil)

    static var updater: SPUUpdater { controller.updater }

    /// 用户可主动触发检查（菜单栏「检查更新…」与设置页共用）
    static func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// 等待 updater 异步启动就绪后再检查：
    /// checkForUpdates 在启动完成前是静默 no-op（SPUUpdater 校验 _startedUpdater 直接 return）。
    /// 供启动参数 `-check-updates`（验收钩子）使用，避免固定延迟在慢环境下过早触发。
    static func checkWhenReady(timeout: TimeInterval = 30, pollInterval: TimeInterval = 0.5) {
        Task { @MainActor in
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if updater.canCheckForUpdates {
                    checkForUpdates()
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            }
            GlossLog.error("updater not ready after \(Int(timeout))s, skip -check-updates")
        }
    }

    // MARK: - 版本信息

    /// 展示用版本号：vX.Y.Z（构建 N）
    static var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "v\(short)（构建 \(build)）"
    }

    static var lastCheckText: String {
        guard let date = updater.lastUpdateCheckDate else { return "尚未检查" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }
}
