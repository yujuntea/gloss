import AVFoundation
import SwiftUI

/// 首启 4 步向导：欢迎 → 配置模型 → 触发与权限 → 完成（示例试查）
struct OnboardingView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @State private var step = 0
    @State private var presetID = "minimax"
    @State private var keyInput = ""
    @State private var showKey = false
    @State private var testMsg: String?
    @State private var testing = false
    @State private var axOK = PermissionCenter.accessibility
    @State private var srOK = PermissionCenter.screenRecording

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: 34, height: 4)
                }
            }
            Group {
                switch step {
                case 0: welcomeStep
                case 1: modelStep
                case 2: triggerStep
                default: finishStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                if step > 0 { Button("上一步") { step -= 1 } }
                Spacer()
                if step == 1 { Button("跳过") { commitModelConfig(); step = 2 } }
                if step < 3 {
                    Button("下一步") {
                        if step == 1 { commitModelConfig() }
                        step += 1
                    }
                } else {
                    Button("完成") {
                        settings.onboardingCompleted = true
                        WindowManager.shared.closeOnboarding()
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 580, height: 470)
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gloss · 划词即释").font(.largeTitle.bold())
            Text("Mac 系统级英文阅读助手：选中即得带读音的词典级解释、语境翻译与文章精读，由你自己的大模型 API Key 驱动。")
                .font(.callout)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Label("选中文本右键 → 服务 → Gloss 查词", systemImage: "cursorarrow.and.square.on.square.dashed")
                Label("选中后按 ⌥D 快速查词（需辅助功能权限）", systemImage: "keyboard")
                Label("按 ⌥S 框选屏幕任意内容读图解释（需屏幕录制权限）", systemImage: "camera.viewfinder")
            }
            .font(.callout)
        }
    }

    private var modelStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("配置模型").font(.title2.bold())
            Picker("厂商预设", selection: $presetID) {
                ForEach(ProviderPreset.all) { p in Text(p.name).tag(p.id) }
            }
            .pickerStyle(.menu)
            HStack {
                Group {
                    if showKey { TextField("API Key", text: $keyInput) } else { SecureField("API Key", text: $keyInput) }
                }
                .textFieldStyle(.roundedBorder)
                Button(showKey ? "隐藏" : "显示") { showKey.toggle() }
            }
            HStack {
                Button(testing ? "测试中…" : "测试连接") { test() }.disabled(testing || keyInput.isEmpty)
                if let msg = testMsg { Text(msg).font(.caption).foregroundStyle(.secondary) }
            }
            // Key 安全不回显：已存状态可见（避免"到底存没存"歧义）
            if keyInput.isEmpty, let cfg = settings.activeConfig, let saved = settings.apiKey(for: cfg) {
                Text("✓ 已保存在本机钥匙串（\(KeychainStore.masked(saved))）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Key 仅保存在本机钥匙串；可跳过此步稍后在设置中配置。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var triggerStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("触发方式与权限").font(.title2.bold())
            triggerRow(title: "右键服务菜单", detail: "无需任何权限，始终可用", granted: true)
            triggerRow(title: "划词快捷键 ⌥D", detail: "需要辅助功能权限", granted: axOK,
                       open: { PermissionCenter.openAccessibilitySettings() },
                       recheck: { axOK = PermissionCenter.accessibility })
            triggerRow(title: "截图快捷键 ⌥S", detail: "需要屏幕录制权限", granted: srOK,
                       open: { PermissionCenter.openScreenRecordingSettings() },
                       recheck: { srOK = PermissionCenter.screenRecording })
            Text("权限为检测式引导：用到未授权的通道时才需要授权，不预索取。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func triggerRow(title: String, detail: String, granted: Bool,
                            open: (() -> Void)? = nil, recheck: (() -> Void)? = nil) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.bold())
                Text(granted ? "已就绪" : detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                if let open { Button("打开系统设置") { open() }.buttonStyle(.bordered) }
                if let recheck { Button("重新检测") { recheck() }.buttonStyle(.bordered) }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("一切就绪").font(.title2.bold())
            Text("试试查一个词：").font(.callout)
            HStack {
                Button("立即试查 serendipity") {
                    SessionCoordinator.shared.demoTextQuery(text: "serendipity",
                                                            context: "It was pure serendipity that we met at the conference.")
                    settings.onboardingCompleted = true
                    WindowManager.shared.closeOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasKey)
                if !hasKey {
                    Text("未配置 API Key，完成后可在设置中配置。").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("之后：在任意 App 选中英文 → 右键服务菜单或 ⌥D 即可查询。").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var hasKey: Bool {
        settings.activeConfig.flatMap { settings.apiKey(for: $0) } != nil
    }

    private func commitModelConfig() {
        guard let preset = ProviderPreset.byID(presetID) else { return }
        var cfg = settings.activeConfig ?? ProviderPreset.config(from: preset)
        cfg.presetID = preset.id
        cfg.displayName = preset.name
        cfg.baseURL = preset.baseURL
        cfg.chatPath = preset.chatPath
        cfg.model = preset.defaultModel
        cfg.regionID = nil
        settings.upsert(cfg)
        settings.activeConfigID = cfg.id
        if !keyInput.isEmpty {
            KeychainStore.set(keyInput, account: cfg.id.uuidString)
        }
    }

    private func test() {
        guard let preset = ProviderPreset.byID(presetID) else { return }
        let cfg = ProviderPreset.config(from: preset)
        testing = true
        testMsg = nil
        Task {
            let result = await LLMClient.testConnection(config: cfg, apiKey: keyInput)
            await MainActor.run {
                testing = false
                switch result {
                case .success(let ms): testMsg = String(format: "连接成功 · %.0fms", ms)
                case .failure(let e): testMsg = e.errorDescription
                }
            }
        }
    }
}
