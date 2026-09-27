import AppKit

/// 最小主菜单。Gloss 是 LSUIElement 应用（无 Dock 图标、无菜单栏），
/// 但 macOS 的标准编辑快捷键（⌘X/⌘C/⌘V/⌘Z/⌘A）是**主菜单的 key equivalent**，
/// 不是 NSTextField 自己处理的。没有 mainMenu 时这些快捷键全部失效——设置页/历史页/首启向导的
/// 输入框都只能靠右键粘贴。装上主菜单即修复，菜单栏不会外露（.accessory 策略不显示菜单栏，
/// 但 key equivalent 依然生效）。
///
/// 覆盖范围：所有会激活应用的常规窗口（设置/历史/首启/精读）。
/// **划词浮窗除外**——它是非激活面板（PanelController 用 orderFrontRegardless 显示，全程不
/// 激活 Gloss），键盘事件派发给当前活跃 app，key equivalent 无从生效；浮窗内选词复制请用
/// 卡片底部的「复制」按钮或右键菜单。
enum MainMenu {
    /// 菜单项 target 留空 → 走响应者链（第一响应者），这是 ⌘V 能落到输入框的关键；
    /// 设成 NSApp.delegate 会让编辑命令发不到文本框。
    /// - Parameter settingsTarget: 「设置…」项的 target，须为持有 `openSettings` 的 AppDelegate；
    ///   显式传入而非读 `NSApp.delegate`，免得调用顺序被后续重构打乱时该项静默失效。
    @MainActor
    static func install(settingsTarget: AnyObject) {
        let main = NSMenu()

        // 应用菜单
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Gloss")
        appMenu.addItem(withTitle: "关于 Gloss", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settings = NSMenuItem(title: "设置…", action: #selector(AppDelegate.openSettings), keyEquivalent: ",")
        settings.target = settingsTarget // openSettings 不在响应者链上，必须显式 target
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 Gloss", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Gloss", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        // 编辑菜单——本文件存在的唯一理由：⌘V/⌘C/⌘X/⌘A/⌘Z
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        // pasteAsPlainText: 是 NSTextView 的分类方法，不在 NSText 的 Swift 接口里，
        // #selector 取不到，只能按名查（Selector 字面量会触发 Swift 6 迁移 warning）
        let pastePlain = NSMenuItem(title: "粘贴并匹配样式", action: NSSelectorFromString("pasteAsPlainText:"), keyEquivalent: "v")
        pastePlain.keyEquivalentModifierMask = [.command, .option, .shift]
        editMenu.addItem(pastePlain)
        editMenu.addItem(withTitle: "删除", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        // 窗口菜单——补 ⌘W 关窗，⌘M 最小化；顺带让「窗口」菜单在多窗口（设置/历史/精读）间可用
        let winItem = NSMenuItem()
        let winMenu = NSMenu(title: "窗口")
        winMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        winMenu.addItem(.separator())
        winMenu.addItem(withTitle: "前置全部窗口", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        winMenu.addItem(.separator())
        winMenu.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        winItem.submenu = winMenu
        main.addItem(winItem)
        NSApp.windowsMenu = winMenu

        NSApp.mainMenu = main
    }
}
