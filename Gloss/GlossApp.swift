import AppKit

@main
enum GlossMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = MainActor.assumeIsolated { AppDelegate() }
        app.delegate = delegate
        // 必须在 run() 之前装：标准编辑快捷键依赖 mainMenu 的 key equivalent
        MainActor.assumeIsolated { MainMenu.install(settingsTarget: delegate) }
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
