import Foundation

extension Notification.Name {
    static let glossChannelsChanged = Notification.Name("glossChannelsChanged")
}

/// 设置：非敏感项入 UserDefaults（LLMConfig JSON）；API Key 永不入 UserDefaults。
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    private let ud = UserDefaults.standard
    private let kConfigs = "llmConfigs"
    private let kActive = "activeConfigID"
    private let kOnboarded = "onboardingCompleted"
    private let kChService = "channelServiceEnabled"
    private let kChHotkey = "channelHotkeyEnabled"
    private let kChShot = "channelScreenshotEnabled"
    private let kVoiceUS = "ttsVoiceUS"
    private let kVoiceUK = "ttsVoiceUK"
    private let kRate = "ttsRate"
    private let kHistory = "historyEnabled"
    private let kHotkeyConflict = "hotkeyConflict"

    @Published var configs: [LLMConfig] = [] { didSet { persistConfigs() } }
    @Published var activeConfigID: UUID? { didSet { ud.set(activeConfigID?.uuidString, forKey: kActive) } }
    @Published var onboardingCompleted = false { didSet { ud.set(onboardingCompleted, forKey: kOnboarded) } }
    @Published var channelServiceEnabled = true { didSet { ud.set(channelServiceEnabled, forKey: kChService); notifyChannels() } }
    @Published var hotkeyEnabled = true { didSet { ud.set(hotkeyEnabled, forKey: kChHotkey); notifyChannels() } }
    @Published var screenshotEnabled = true { didSet { ud.set(screenshotEnabled, forKey: kChShot); notifyChannels() } }
    @Published var ttsVoiceUS: String? { didSet { ud.set(ttsVoiceUS, forKey: kVoiceUS) } }
    @Published var ttsVoiceUK: String? { didSet { ud.set(ttsVoiceUK, forKey: kVoiceUK) } }
    @Published var ttsRate: Double = 1.0 { didSet { ud.set(ttsRate, forKey: kRate) } }
    @Published var historyEnabled = true { didSet { ud.set(historyEnabled, forKey: kHistory) } }
    @Published var hotkeyConflict = false { didSet { ud.set(hotkeyConflict, forKey: kHotkeyConflict) } }

    private init() {}

    func loadIfNeeded() {
        if let s = ud.string(forKey: kConfigs), let data = s.data(using: .utf8),
           let cs = try? JSONDecoder().decode([LLMConfig].self, from: data) {
            configs = cs
        } else if let d = ud.data(forKey: kConfigs),
                  let cs = try? JSONDecoder().decode([LLMConfig].self, from: d) {
            configs = cs
        }
        if let s = ud.string(forKey: kActive) { activeConfigID = UUID(uuidString: s) }
        if configs.isEmpty {
            let def = ProviderPreset.config(from: .byID("minimax")!)
            configs = [def]
            activeConfigID = def.id
        }
        if ud.object(forKey: kOnboarded) != nil { onboardingCompleted = ud.bool(forKey: kOnboarded) }
        if ud.object(forKey: kChService) != nil { channelServiceEnabled = ud.bool(forKey: kChService) }
        if ud.object(forKey: kChHotkey) != nil { hotkeyEnabled = ud.bool(forKey: kChHotkey) }
        if ud.object(forKey: kChShot) != nil { screenshotEnabled = ud.bool(forKey: kChShot) }
        if ud.object(forKey: kVoiceUS) != nil { ttsVoiceUS = ud.string(forKey: kVoiceUS) }
        if ud.object(forKey: kVoiceUK) != nil { ttsVoiceUK = ud.string(forKey: kVoiceUK) }
        if ud.object(forKey: kRate) != nil { ttsRate = ud.double(forKey: kRate) }
        if ud.object(forKey: kHistory) != nil { historyEnabled = ud.bool(forKey: kHistory) }
        if ud.object(forKey: kHotkeyConflict) != nil { hotkeyConflict = ud.bool(forKey: kHotkeyConflict) }
    }

    private func persistConfigs() {
        if let data = try? JSONEncoder().encode(configs), let s = String(data: data, encoding: .utf8) {
            ud.set(s, forKey: kConfigs)
        }
    }

    private func notifyChannels() {
        NotificationCenter.default.post(name: .glossChannelsChanged, object: nil)
    }

    var activeConfig: LLMConfig? {
        configs.first { $0.id == activeConfigID } ?? configs.first
    }

    func apiKey(for config: LLMConfig) -> String? {
        KeychainStore.get(account: config.id.uuidString)
    }

    func upsert(_ config: LLMConfig) {
        if let i = configs.firstIndex(where: { $0.id == config.id }) {
            configs[i] = config
        } else {
            configs.append(config)
        }
    }

    func remove(_ config: LLMConfig) {
        configs.removeAll { $0.id == config.id }
        if activeConfigID == config.id { activeConfigID = configs.first?.id }
        KeychainStore.delete(account: config.id.uuidString)
    }

    func resetAll() {
        if ud.string(forKey: kConfigs) != nil { ud.removeObject(forKey: kConfigs) }
        for k in [kActive, kOnboarded, kChService, kChHotkey, kChShot, kVoiceUS, kVoiceUK, kRate, kHistory, kHotkeyConflict] {
            ud.removeObject(forKey: k)
        }
        configs = []
        activeConfigID = nil
        onboardingCompleted = false
    }
}
