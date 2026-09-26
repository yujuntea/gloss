import AVFoundation

/// 系统离线 TTS（AVSpeechSynthesizer；倍率→rate 映射并钳制到系统合法域）。
@MainActor
final class TTSEngine: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = TTSEngine()
    @Published private(set) var speaking = false
    private let synth = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synth.delegate = self
    }

    enum Accent: String {
        case us = "en-US"
        case uk = "en-GB"
    }

    func speak(_ text: String, accent: Accent) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: trimmed)
        u.voice = voice(for: accent)
        let base = AVSpeechUtteranceDefaultSpeechRate
        let mult = Float(SettingsStore.shared.ttsRate)
        u.rate = min(max(base * mult, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        synth.speak(u)
        GlossLog.info("tts speak accent=\(accent.rawValue) chars=\(trimmed.count)")
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        speaking = false
    }

    private func voice(for accent: Accent) -> AVSpeechSynthesisVoice? {
        let prefID = accent == .us ? SettingsStore.shared.ttsVoiceUS : SettingsStore.shared.ttsVoiceUK
        if let id = prefID, let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        let lang = accent.rawValue
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(lang) }
        return candidates.max(by: { rank($0) < rank($1) }) ?? AVSpeechSynthesisVoice(language: lang)
    }

    private func rank(_ v: AVSpeechSynthesisVoice) -> Int {
        switch v.quality {
        case .premium: return 3
        case .enhanced: return 2
        default: return 1
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = true }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.speaking = false
            GlossLog.info("tts didFinish")
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = false }
    }
}
