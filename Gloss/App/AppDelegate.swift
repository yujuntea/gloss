import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        SettingsStore.shared.loadIfNeeded()
        DataStore.warmUp()
        CacheStore.shared.persistPut = { key, response, date in DataStore.cachePut(key: key, response: response, date: date) }
        CacheStore.shared.persistLoader = { DataStore.cacheLoadAll() }
        CacheStore.shared.persistTouch = { key, date in DataStore.cacheTouch(key: key, date: date) }
        CacheStore.shared.loadPersisted()
        DataStore.cachePruneToLoaded()
        setupStatusItem()
        setupServices()
        installHotkeys()
        NotificationCenter.default.addObserver(self, selector: #selector(channelsChanged),
                                               name: .glossChannelsChanged, object: nil)
        PermissionCenter.logStatus()
        // keychain 探针：启动早期验证 SecItemCopyMatching 是否可用（验收诊断）
        if let cfg = SettingsStore.shared.activeConfig {
            let t0 = Date()
            let k = KeychainStore.get(account: cfg.id.uuidString)
            GlossLog.info("keychain probe \(k != nil ? "hit" : "miss") in \(Int(Date().timeIntervalSince(t0) * 1000))ms")
        }
        handleLaunchArgs()
        if !SettingsStore.shared.onboardingCompleted && !hasDemoArgs {
            WindowManager.shared.showOnboarding()
        }
        GlossLog.info("launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregisterAll()
    }

    private var hasDemoArgs: Bool {
        CommandLine.arguments.contains { $0.hasPrefix("-demo") || $0 == "-seed-key" || $0 == "-seed-history" }
    }

    // MARK: 菜单栏

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: "Gloss")
        item.button?.toolTip = "Gloss — 划词即释"
        let menu = NSMenu()
        let mSettings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        mSettings.target = self
        menu.addItem(mSettings)
        let mHistory = NSMenuItem(title: "历史记录…", action: #selector(openHistory), keyEquivalent: "")
        mHistory.target = self
        menu.addItem(mHistory)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: PermissionCenter.summaryLine(), action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 Gloss", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    private func setupServices() {
        NSApp.servicesProvider = ServicesBridge()
        NSUpdateDynamicServices()
    }

    func installHotkeys() {
        HotkeyManager.shared.unregisterUserHotkeys()
        let enabledD = SettingsStore.shared.hotkeyEnabled
        let enabledS = SettingsStore.shared.screenshotEnabled
        let okD = enabledD && HotkeyManager.shared.register(id: 1, keyCode: 0x02, modifiers: UInt32(optionKey)) { [weak self] in self?.hotkeyD() }
        let okS = enabledS && HotkeyManager.shared.register(id: 2, keyCode: 0x01, modifiers: UInt32(optionKey)) { [weak self] in self?.hotkeyS() }
        // 冲突=通道开启但注册失败；用户主动关闭不算冲突（K3-P1-5）
        SettingsStore.shared.hotkeyConflict = (enabledD && !okD) || (enabledS && !okS)
        GlossLog.info("hotkeys registered d=\(okD) s=\(okS)")
    }

    private func hotkeyD() {
        DispatchQueue.main.async { MainActor.assumeIsolated { SessionCoordinator.shared.beginHotkeyQuery() } }
    }

    private func hotkeyS() {
        DispatchQueue.main.async { MainActor.assumeIsolated { SessionCoordinator.shared.beginScreenshotFlow() } }
    }

    @objc private func channelsChanged() {
        installHotkeys()
    }

    @objc private func openSettings() { WindowManager.shared.showSettings() }
    @objc private func openHistory() { WindowManager.shared.showHistory() }

    // MARK: 启动参数（验收/调试用）

    private func handleLaunchArgs() {
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
            return args[i + 1]
        }
        if let key = value("-seed-key"), let cfg = SettingsStore.shared.activeConfig {
            KeychainStore.set(key, account: cfg.id.uuidString)
            let readback = KeychainStore.get(account: cfg.id.uuidString)
            GlossLog.info("seeded key for config \(cfg.id.uuidString) readback=\(readback != nil ? "ok" : "NIL")")
        }
        if args.contains("-pin") { SessionCoordinator.shared.pinned = true }
        if let pos = value("-panel-at"), pos.split(separator: ",").count == 2 {
            let ys = pos.split(separator: ",")
            if let x = Double(ys[0]), let y = Double(ys[1]) {
                PanelController.shared.positionOverride = CGPoint(x: x, y: y)
            }
        }
        if args.contains("-seed-history") { DataStore.seedDemoHistory() }
        if args.contains("-onboarding") { WindowManager.shared.showOnboarding(); return }
        if args.contains("-settings") { WindowManager.shared.showSettings(); return }
        if args.contains("-history") { WindowManager.shared.showHistory(); return }
        if args.contains("-speak-test") {
            TTSEngine.shared.speak("Hello, this is Gloss text to speech test.", accent: .us)
            return
        }
        if let t = value("-demo-query") {
            SessionCoordinator.shared.demoTextQuery(text: t, context: "In distributed systems design, operations are often expected to be repeatable.")
            return
        }
        if let t = value("-demo-sentence") { SessionCoordinator.shared.demoTextQuery(text: t); return }
        if let t = value("-demo-paragraph") { SessionCoordinator.shared.demoTextQuery(text: t); return }
        if args.contains("-demo-image") {
            let t = value("-demo-image") ?? "Idempotent operations ensure the same result."
            SessionCoordinator.shared.demoImageQuery(text: t)
            return
        }
        if args.contains("-demo-image-twice") {
            // 同会话连续两次截图（栈残留旧卡后新截图——P0-1 修复验证）
            SessionCoordinator.shared.demoImageQuery(text: "First screenshot text for pipeline.")
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                SessionCoordinator.shared.demoImageQuery(text: "Second screenshot replaces the first one.")
            }
            return
        }
        if args.contains("-demo-wordat") {
            let t = value("-demo-wordat") ?? "Idempotent operations ensure the same result."
            SessionCoordinator.shared.demoWordAtQuery(text: t, point: CGPoint(x: 0.12, y: 0.45))
            return
        }
        if args.contains("-demo-reader") {
            WindowManager.shared.showReader(text: value("-demo-reader") ?? DemoSupport.readerText)
            return
        }
    }
}

enum DemoSupport {
    static func textImage(_ text: String) -> NSImage {
        let size = NSSize(width: 900, height: 300)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 30),
            .foregroundColor: NSColor.black,
        ]
        NSAttributedString(string: text, attributes: attrs).draw(at: NSPoint(x: 40, y: 130))
        img.unlockFocus()
        return img
    }

    static let readerText = """
    Distributed systems are groups of networked computers that coordinate their actions to appear as a single coherent system. Unlike a single machine, a distributed system must contend with partial failure: some nodes may crash, some network links may drop messages, and clocks on different machines may drift apart. These realities force engineers to design protocols that remain correct even when individual components misbehave.

    The first fundamental property to understand is idempotency. An operation is idempotent if performing it once has the same effect as performing it many times. Consider a payment service that receives a retry after a timeout: if the charge operation is idempotent, the customer is billed exactly once, because the second attempt recognizes that the first already succeeded. Idempotency turns unreliable networks into something we can reason about, which is why every retry mechanism should be paired with an idempotency key.

    The second property is consistency. When data is replicated across nodes, the system must decide how quickly updates become visible everywhere. Strong consistency guarantees that every read sees the latest write, but it imposes a coordination cost that grows with scale. Eventual consistency relaxes this requirement: replicas converge over time, and during the convergence window different readers may observe different values. Choosing between these models is a business decision as much as a technical one, because it determines what kinds of anomalies users are willing to tolerate.

    The third property is partition tolerance. A network partition splits the cluster into groups that cannot communicate. The CAP theorem states that when a partition happens, a system must sacrifice either consistency or availability. Real deployments rarely choose permanently; they tune behavior per request, using quorum reads and writes to balance the two. For example, a checkout service may demand strong consistency for inventory, while a recommendation feed happily runs on stale data.

    Putting the three properties together explains why modern infrastructure looks the way it does. Message queues make side effects idempotent by design. Consensus algorithms such as Raft and Paxos replicate a log with strong consistency while tolerating node failures. Monitoring systems embrace eventual consistency because a slightly delayed dashboard is far cheaper than a global lock. When you read a distributed systems paper, identify which of these properties it strengthens, what it trades away, and whether the trade matches the failure modes your product can actually afford.
    """
}
