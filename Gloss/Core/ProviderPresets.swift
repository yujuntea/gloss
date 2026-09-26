import Foundation

struct PresetRegion: Identifiable, Equatable {
    let id: String
    let name: String
    let baseURL: String
}

struct ProviderPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let baseURL: String
    let chatPath: String
    let defaultModel: String
    let regions: [PresetRegion]?

    /// 端点/模型 ID 已按 §13-C1 真实 Key 实测校准（2026-09-26）：api.minimaxi.com/v1/chat/completions + MiniMax-M3
    /// 国内/国际同域；区域下拉已按用户反馈移除，BaseURL 由用户直接编辑
    static let all: [ProviderPreset] = [
        ProviderPreset(id: "minimax", name: "MiniMax", baseURL: "https://api.minimaxi.com", chatPath: "/v1/chat/completions", defaultModel: "MiniMax-M3", regions: nil),
        ProviderPreset(id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1", chatPath: "/chat/completions", defaultModel: "gpt-4o-mini", regions: nil),
        ProviderPreset(id: "deepseek", name: "DeepSeek", baseURL: "https://api.deepseek.com/v1", chatPath: "/chat/completions", defaultModel: "deepseek-chat", regions: nil),
        ProviderPreset(id: "zhipu", name: "智谱 GLM", baseURL: "https://open.bigmodel.cn/api/paas/v4", chatPath: "/chat/completions", defaultModel: "glm-4-flash", regions: nil),
        ProviderPreset(id: "kimi", name: "Kimi", baseURL: "https://api.moonshot.cn/v1", chatPath: "/chat/completions", defaultModel: "moonshot-v1-8k", regions: nil),
        ProviderPreset(id: "custom", name: "自定义（任意 OpenAI 兼容端点）", baseURL: "http://127.0.0.1:8787", chatPath: "/v1/chat/completions", defaultModel: "custom-model", regions: nil),
    ]

    static func byID(_ id: String) -> ProviderPreset? {
        all.first { $0.id == id }
    }

    static func config(from preset: ProviderPreset, region: PresetRegion? = nil) -> LLMConfig {
        LLMConfig(presetID: preset.id,
                  displayName: preset.name,
                  baseURL: region?.baseURL ?? preset.baseURL,
                  chatPath: preset.chatPath,
                  model: preset.defaultModel,
                  regionID: region?.id)
    }
}
