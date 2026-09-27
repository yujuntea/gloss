import AVFoundation
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @State private var selectedID: UUID?
    @State private var draft: LLMConfig?
    @State private var keyInput = ""
    @State private var showKey = false
    @State private var testResult: String?
    @State private var testing = false
    @State private var voices: [AVSpeechSynthesisVoice] = []
    @State private var launchAtLoginOn = false
    @State private var autoCheckUpdates = false
    @State private var lastCheckText = "尚未检查"

    var body: some View {
        TabView {
            modelTab.tabItem { Label("模型", systemImage: "cpu") }
            triggerTab.tabItem { Label("触发", systemImage: "keyboard") }
            ttsTab.tabItem { Label("朗读", systemImage: "speaker.wave.2") }
            advancedTab.tabItem { Label("高级", systemImage: "gearshape.2") }
        }
        .padding(8)
        .frame(width: 680, height: 520)
        .onAppear {
            voices = AVSpeechSynthesisVoice.speechVoices()
            selectedID = settings.activeConfigID ?? settings.configs.first?.id
            syncDraft()
            launchAtLoginOn = SMAppService.mainApp.status == .enabled
        }
    }

    private func syncDraft() {
        if let id = selectedID, let c = settings.configs.first(where: { $0.id == id }) {
            draft = c
        } else {
            draft = settings.activeConfig
            selectedID = draft?.id
        }
        keyInput = ""
        testResult = nil
    }

    // MARK: - 模型

    private var modelTab: some View {
        HStack(spacing: 14) {
            VStack(spacing: 8) {
                Text("配置").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                ForEach(settings.configs) { c in
                    Button {
                        selectedID = c.id
                        settings.activeConfigID = c.id
                        syncDraft()
                    } label: {
                        HStack {
                            Image(systemName: settings.activeConfigID == c.id ? "checkmark.circle.fill" : "circle")
                            Text(c.displayName).lineLimit(1)
                            Spacer()
                            Text(c.model).font(.caption2).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .background(selectedID == c.id ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                }
                HStack {
                    Button("新增") {
                        let c = ProviderPreset.config(from: .byID("custom")!)
                        settings.upsert(c)
                        selectedID = c.id
                        settings.activeConfigID = c.id
                        syncDraft()
                    }
                    Button("删除") {
                        if let d = draft { settings.remove(d); syncDraft() }
                    }
                    .disabled(settings.configs.count <= 1)
                    Spacer()
                }
                Spacer()
            }
            .frame(width: 200)

            Divider()

            configEditor
        }
        .padding(10)
    }

    @ViewBuilder
    private var configEditor: some View {
        if let d = draft, let binding = draftBinding(d) {
            Form {
                Picker("厂商预设", selection: presetBinding(binding)) {
                    ForEach(ProviderPreset.all) { p in
                        Text(p.name).tag(p.id)
                    }
                }
                TextField("显示名称", text: binding.displayName)
                TextField("BaseURL", text: binding.baseURL)
                TextField("Chat 路径", text: binding.chatPath)
                TextField("模型名", text: binding.model)
                HStack {
                    Text("温度").frame(width: 60, alignment: .leading)
                    Slider(value: binding.temperature, in: 0...1, step: 0.1)
                    Text(String(format: "%.1f", binding.wrappedValue.temperature)).monospacedDigit()
                }
                HStack {
                    Group {
                        if showKey {
                            TextField("API Key", text: $keyInput)
                        } else {
                            SecureField("API Key", text: $keyInput)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    Button(showKey ? "隐藏" : "显示") { showKey.toggle() }
                    Button("保存 Key") {
                        if let d = binding.wrappedValue as LLMConfig? {
                            settings.upsert(d)
                            KeychainStore.set(keyInput, account: d.id.uuidString)
                            testResult = "Key 已保存"
                        }
                    }
                    .disabled(keyInput.isEmpty)
                }
                // Key 安全不回显：显示已存状态避免"到底存没存"的歧义
                if let saved = settings.apiKey(for: binding.wrappedValue) {
                    Text(keyInput.isEmpty
                         ? "✓ 已保存在本机钥匙串（\(KeychainStore.masked(saved))）· 点「测试连接」可验证"
                         : "输入了新 Key，点「保存 Key」覆盖")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button(testing ? "测试中…" : "测试连接") { testConnection(binding.wrappedValue) }.disabled(testing)
                    if let msg = testResult { Text(msg).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
            }
        } else {
            Text("无配置").foregroundStyle(.secondary)
        }
    }

    private func draftBinding(_ c: LLMConfig) -> Binding<LLMConfig>? {
        guard settings.configs.contains(where: { $0.id == c.id }) else { return nil }
        return Binding<LLMConfig>(
            get: {
                settings.configs.first { $0.id == c.id } ?? c
            },
            set: { new in
                settings.upsert(new)
                draft = new
            }
        )
    }

    private func presetBinding(_ b: Binding<LLMConfig>) -> Binding<String> {
        Binding(get: { b.wrappedValue.presetID },
                set: { pid in
                    guard let preset = ProviderPreset.byID(pid) else { return }
                    var c = b.wrappedValue
                    c.presetID = pid
                    c.displayName = preset.name
                    c.baseURL = preset.baseURL
                    c.chatPath = preset.chatPath
                    c.model = preset.defaultModel
                    c.regionID = nil
                    b.wrappedValue = c
                })
    }

    private func testConnection(_ config: LLMConfig) {
        settings.upsert(config)
        testing = true
        testResult = nil
        Task {
            // 优先用输入框草稿（用户贴新 Key 直接测试——L2a P2-12）；为空回退已存 Key
            let key = keyInput.isEmpty ? settings.apiKey(for: config) : keyInput
            let result: Result<Double, AppError>
            if let key {
                result = await LLMClient.testConnection(config: config, apiKey: key)
            } else {
                result = .failure(.noAPIKey)
            }
            await MainActor.run {
                testing = false
                switch result {
                case .success(let ms): testResult = String(format: "连接成功 · %.0fms", ms)
                case .failure(let e): testResult = e.errorDescription
                }
            }
        }
    }

    // MARK: - 触发

    private var triggerTab: some View {
        Form {
            Toggle("右键服务菜单（选中文本 → 服务 → Gloss 查词，无需权限）", isOn: $settings.channelServiceEnabled)
            Toggle("划词快捷键 ⌥D（需辅助功能权限）", isOn: $settings.hotkeyEnabled)
            Toggle("截图快捷键 ⌥S（需屏幕录制权限）", isOn: $settings.screenshotEnabled)
            if settings.hotkeyConflict {
                Text("快捷键注册失败（可能已被占用），请在系统设置中释放或反馈调整默认键。")
                    .font(.callout).foregroundStyle(.red)
            }
            Text("权限状态：\(PermissionCenter.summaryLine())").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("打开辅助功能设置") { PermissionCenter.openAccessibilitySettings() }
                Button("打开屏幕录制设置") { PermissionCenter.openScreenRecordingSettings() }
            }
            Text("快捷键自定义控件将在后续版本提供，当前固定 ⌥D / ⌥S。").font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
    }

    // MARK: - 朗读

    private var ttsTab: some View {
        Form {
            Picker("美音音色", selection: usVoiceBinding) {
                Text("系统默认").tag(String?.none)
                ForEach(usVoices, id: \.identifier) { v in
                    Text("\(v.name) (\(qualityLabel(v.quality)))").tag(String?.some(v.identifier))
                }
            }
            Picker("英音音色", selection: ukVoiceBinding) {
                Text("系统默认").tag(String?.none)
                ForEach(ukVoices, id: \.identifier) { v in
                    Text("\(v.name) (\(qualityLabel(v.quality)))").tag(String?.some(v.identifier))
                }
            }
            HStack {
                Button("试听美音") { TTSEngine.shared.speak("Hello, this is the American voice of Gloss.", accent: .us) }
                Button("试听英音") { TTSEngine.shared.speak("Hello, this is the British voice of Gloss.", accent: .uk) }
            }
            HStack {
                Text("语速").frame(width: 60, alignment: .leading)
                Slider(value: $settings.ttsRate, in: 0.5...1.5, step: 0.1)
                Text(String(format: "%.1f×", settings.ttsRate)).monospacedDigit()
            }
            Text("优质音色（Premium/Enhanced）需在 系统设置→辅助功能→朗读内容→系统声音 中下载。").font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
    }

    private var usVoices: [AVSpeechSynthesisVoice] { voices.filter { $0.language.hasPrefix("en-US") } }
    private var ukVoices: [AVSpeechSynthesisVoice] { voices.filter { $0.language.hasPrefix("en-GB") } }

    private var usVoiceBinding: Binding<String?> {
        Binding(get: { settings.ttsVoiceUS }, set: { settings.ttsVoiceUS = $0 })
    }

    private var ukVoiceBinding: Binding<String?> {
        Binding(get: { settings.ttsVoiceUK }, set: { settings.ttsVoiceUK = $0 })
    }

    private func qualityLabel(_ q: AVSpeechSynthesisVoiceQuality) -> String {
        switch q {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return "Default"
        }
    }

    // MARK: - 高级

    private var advancedTab: some View {
        Form {
            HStack {
                Text("响应缓存：\(CacheStore.shared.count) 条 / \(ByteCountFormatter.string(fromByteCount: Int64(CacheStore.shared.approxBytes), countStyle: .memory))")
                Spacer()
                Button("清除缓存") {
                    DataStore.cacheClearAll()
                }
            }
            Toggle("记录查询历史", isOn: $settings.historyEnabled)
            Toggle("开机自启（登录时启动）", isOn: $launchAtLoginOn)
            Button("重跑首启向导") { WindowManager.shared.showOnboarding() }
            Divider()
            updateSection
            Divider()
            Text("隐私说明：查询内容仅发送给你配置的模型服务商；API Key 仅保存在本机钥匙串；无遥测、无崩溃上报。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .onChange(of: launchAtLoginOn) { on in
            do {
                if on {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                GlossLog.error("SMAppService toggle failed: \(error)")
            }
        }
    }

    // MARK: 版本与更新

    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("版本")
                Spacer()
                Text(UpdaterCenter.versionText)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Toggle("自动检查更新（每天一次）", isOn: $autoCheckUpdates)
            HStack {
                Text("上次检查：\(lastCheckText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("检查更新…") { UpdaterCenter.checkForUpdates() }
                    .disabled(!UpdaterCenter.updater.canCheckForUpdates)
            }
        }
        .padding(.vertical, 2)
        .onAppear { refreshUpdateState() }
        // Sparkle 检查完成后会更新 lastUpdateCheckDate/canCheckForUpdates，但这些是 ObjC 属性
        // SwiftUI 不自动观察；页面可见期间低频同步一次，避免「上次检查」停在旧值
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            refreshUpdateState()
        }
        .onChange(of: autoCheckUpdates) { on in
            UpdaterCenter.updater.automaticallyChecksForUpdates = on
        }
    }

    /// Sparkle 状态在权限询问框/检查完成后会变化，SwiftUI 不自动观察 ObjC 属性，
    /// 需在页面出现时主动同步，否则会显示打开窗口那一刻的陈旧值
    private func refreshUpdateState() {
        autoCheckUpdates = UpdaterCenter.updater.automaticallyChecksForUpdates
        lastCheckText = UpdaterCenter.lastCheckText
    }
}
