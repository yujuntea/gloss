import Carbon.HIToolbox
import Foundation

/// Carbon 全局热键（⌥D=划词 / ⌥S=截图 / ESC=面板关闭，消费式）。
final class HotkeyManager {
    static let shared = HotkeyManager()
    private final class Box { let owner: HotkeyManager; init(_ o: HotkeyManager) { owner = o } }

    private var installed = false
    private var hotkeys: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]

    @discardableResult
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> Bool {
        if hotkeys[id] != nil { unregister(id: id) } // 幂等：重复注册先卸旧（面板重复 show 场景）
        if !installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let box = Unmanaged.passRetained(Box(self)).toOpaque()
            let cb: EventHandlerUPP = { _, event, userData in
                guard let event, let userData else { return noErr }
                var hkID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
                Unmanaged<Box>.fromOpaque(userData).takeUnretainedValue().owner.dispatch(id: hkID.id)
                return noErr
            }
            let st = InstallEventHandler(GetApplicationEventTarget(), cb, 1, &spec, box, nil)
            guard st == noErr else {
                GlossLog.error("InstallEventHandler failed \(st)")
                return false
            }
            installed = true
        }
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x474C5353), id: id) // 'GLSS'
        let st = RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        guard st == noErr, let ref else {
            GlossLog.error("RegisterEventHotKey id=\(id) failed \(st)")
            return false
        }
        hotkeys[id] = ref
        handlers[id] = handler
        return true
    }

    func unregister(id: UInt32) {
        if let ref = hotkeys.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers.removeValue(forKey: id)
    }

    /// ⌥D / ⌥S
    func unregisterUserHotkeys() {
        unregister(id: 1)
        unregister(id: 2)
    }

    /// ESC 面板热键：随面板显隐装拆（面板可见期间消费 ESC，与目标 App 的 ESC 行为互斥——product-design §4.1 有意取舍）。
    @discardableResult
    func registerEscape(_ handler: @escaping () -> Void) -> Bool {
        register(id: 99, keyCode: 0x35, modifiers: 0, handler: handler)
    }

    func unregisterEscape() {
        unregister(id: 99)
    }

    func unregisterAll() {
        for id in Array(hotkeys.keys) { unregister(id: id) }
    }

    private func dispatch(id: UInt32) {
        handlers[id]?()
    }
}
