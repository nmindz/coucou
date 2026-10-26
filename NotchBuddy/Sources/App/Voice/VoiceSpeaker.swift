#if !APPSTORE
import AVFoundation
import AppKit

// MARK: - VoiceSpeaker
//
// Gives Coucou a voice, sentence by sentence:
//   • macOS voices (AVSpeechSynthesizer), best installed voice for the language;
//   • ElevenLabs (Settings → Voice, the user's own API key), female or male.
//     Each queued sentence starts downloading right away, so the next one is usually
//     ready when the previous one ends. Any ElevenLabs failure falls back to the Mac
//     voice for that sentence: Coucou never goes silent.
// onDidFinish fires ~150 ms after the queue drains. All methods: @MainActor.
@MainActor
final class VoiceSpeaker: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate, @unchecked Sendable {
    static let shared = VoiceSpeaker()

    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private(set) var isSpeaking = false
    private var currentUtterance: AVSpeechUtterance? = nil
    private var waitingForAudio = false

    private struct Item {
        let text: String
        let locale: Locale?
        let audio: Task<Data?, Never>?   // ElevenLabs download, started at enqueue time
    }
    private var queue: [Item] = []
    /// Bumped by stop()/speak(): late callbacks from an older utterance are ignored.
    private var generation = 0

    /// Called ~150 ms after the last queued sentence finishes.
    var onDidFinish: (() -> Void)?

    override init() {
        super.init()
        synth.delegate = self
    }

    // MARK: - Public API

    /// Clears the queue, stops current speech, and speaks text now.
    func speak(_ text: String, locale: Locale?) {
        guard VoiceSettings.speakEnabled else { return }
        stopPlayback()
        enqueue(text, locale: locale)
    }

    /// Adds a sentence to the queue. Starts playing if nothing is playing.
    func enqueue(_ text: String, locale: Locale?) {
        guard VoiceSettings.speakEnabled else { return }
        let audio: Task<Data?, Never>? = ElevenLabsTTS.isActive
            ? Task { await ElevenLabsTTS.shared.audio(for: text) }
            : nil
        queue.append(Item(text: text, locale: locale, audio: audio))
        if !isSpeaking { playNext() }
    }

    func stop() { stopPlayback() }

    /// What the mic gate uses: what is actually playing or about to play, never a flag
    /// alone, so a missed callback cannot leave Coucou deaf.
    var isBusy: Bool {
        synth.isSpeaking || (player?.isPlaying ?? false) || waitingForAudio || !queue.isEmpty
    }

    // MARK: - Playback

    private func stopPlayback() {
        generation += 1
        for item in queue { item.audio?.cancel() }
        queue.removeAll()
        currentUtterance = nil
        waitingForAudio = false
        isSpeaking = false
        player?.stop()
        player = nil
        synth.stopSpeaking(at: .immediate)
    }

    private func playNext() {
        guard !queue.isEmpty else { finished(); return }
        let item = queue.removeFirst()
        isSpeaking = true
        guard let audio = item.audio else { speakSystem(item.text, locale: item.locale); return }
        let gen = generation
        waitingForAudio = true
        Task { @MainActor in
            let data = await audio.value
            guard gen == self.generation else { return }
            self.waitingForAudio = false
            if let data, let p = try? AVAudioPlayer(data: data) {
                p.delegate = self
                self.player = p
                if p.play() { return }
                self.player = nil
            }
            self.speakSystem(item.text, locale: item.locale)   // fallback: Mac voice
        }
    }

    private func speakSystem(_ text: String, locale: Locale?) {
        let utt = AVSpeechUtterance(string: text)
        let gender = VoiceSettings.elevenGender
        utt.rate = min(AVSpeechUtteranceMaximumSpeechRate,
                       AVSpeechUtteranceDefaultSpeechRate * Float(VoiceSettings.speechRate))
        if let system = Self.chosenSystemVoice(for: locale) {
            utt.voice = system   // as set in System Settings, pitch included
        } else {
            // Pitch per voice type (Settings → Voice): the male voice a bit higher sounds younger.
            utt.pitchMultiplier = Float(VoiceSettings.pitch(for: gender))
            utt.voice = Self.bestVoice(for: locale, gender: gender)
        }
        currentUtterance = utt
        synth.speak(utt)
    }

    private func itemDone() {
        currentUtterance = nil
        player = nil
        playNext()
    }

    private func finished() {
        isSpeaking = false
        let gen = generation
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)  // 150 ms gap
            guard gen == self.generation, !self.isSpeaking else { return }
            self.onDidFinish?()
        }
    }

    /// Best installed Mac voice for the language and the chosen gender (Settings → Voice):
    /// quality first (.premium > .enhanced > default — Ava Premium beats a compact US voice),
    /// then same region. Novelty voices and the user's Personal Voice are never used.
    /// Falls back to any gender when none of the chosen one is installed.
    /// Premium and Siri voices often report no gender: their name tells it instead.
    static func bestVoice(for locale: Locale?, gender: String) -> AVSpeechSynthesisVoice? {
        guard let loc = locale else { return nil }
        // Listing the system voices (150+) for every sentence cost milliseconds between
        // sentences: one lookup per language and voice type, redone when voices change.
        let key = "\(loc.identifier)|\(gender)"
        if let hit = voiceCache[key] { return hit }
        observeVoiceChanges()
        let v = findBestVoice(for: loc, gender: gender)
        voiceCache[key] = .some(v)
        return v
    }

    private static var voiceCache: [String: AVSpeechSynthesisVoice?] = [:]
    private static var observingVoices = false

    private static func observeVoiceChanges() {
        guard !observingVoices else { return }
        observingVoices = true
        NotificationCenter.default.addObserver(
            forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { VoiceSpeaker.voiceCache.removeAll() }
        }
    }

    private static func findBestVoice(for loc: Locale, gender: String) -> AVSpeechSynthesisVoice? {
        let lang = loc.language.languageCode?.identifier ?? ""
        guard !lang.isEmpty else { return nil }
        let exact = loc.region.map { "\(lang)-\($0.identifier)" }

        let voices = AVSpeechSynthesisVoice.speechVoices().filter { v in
            (v.language == lang || v.language.hasPrefix(lang + "-"))
                && !v.voiceTraits.contains(.isNoveltyVoice)
                && !v.voiceTraits.contains(.isPersonalVoice)
        }
        guard !voices.isEmpty else { return AVSpeechSynthesisVoice(language: exact ?? lang) }
        let wanted: AVSpeechSynthesisVoiceGender = gender == "male" ? .male : .female
        let ofGender = voices.filter { Self.gender(of: $0) == wanted }
        let pool = ofGender.isEmpty ? voices : ofGender

        func rank(_ v: AVSpeechSynthesisVoice) -> (Int, Int) {
            (v.quality.rawValue, v.language == exact ? 1 : 0)
        }
        return pool.max { rank($0) < rank($1) }
    }

    /// The voice's gender, from the system when it says, else from its identifier
    /// ("siri_female_…") or its first name (Ava, Zoe… / Jamie, Evan…).
    static func gender(of v: AVSpeechSynthesisVoice) -> AVSpeechSynthesisVoiceGender {
        if v.gender != .unspecified { return v.gender }
        switch VoiceGenderNames.gender(name: v.name, identifier: v.identifier) {
        case "female": return .female
        case "male":   return .male
        default:       return .unspecified
        }
    }

    /// The voice chosen in System Settings → Accessibility → Read & Speak (Spoken Content before
    /// macOS 26) for the answer's language, when "Use the system voice" is on. Read fresh each
    /// time, so a change there applies to the next answer.
    static func chosenSystemVoice(for locale: Locale?) -> AVSpeechSynthesisVoice? {
        guard VoiceSettings.useSystemVoice, let lang = locale?.language.languageCode?.identifier else { return nil }
        let speaks = { (v: AVSpeechSynthesisVoice) in v.language == lang || v.language.hasPrefix(lang + "-") }
        if let id = systemVoiceSelections()[lang], let v = AVSpeechSynthesisVoice(identifier: id), speaks(v) {
            return v
        }
        // No choice saved for this language: the global system voice, when it speaks it.
        if let v = AVSpeechSynthesisVoice(identifier: NSSpeechSynthesizer.defaultVoice.rawValue), speaks(v) {
            return v
        }
        return nil
    }

    /// Language code → voice id, as System Settings saves them (one per language, kept even when
    /// "Detect languages" is off). Stored as [language, selection, language, selection, …].
    private static func systemVoiceSelections() -> [String: String] {
        let domain = "com.apple.Accessibility" as CFString
        CFPreferencesAppSynchronize(domain)
        guard let list = CFPreferencesCopyAppValue("SpokenContentDefaultVoiceSelectionsByLanguage" as CFString,
                                                   domain) as? [Any] else { return [:] }
        var result: [String: String] = [:]
        for i in stride(from: 0, to: list.count - 1, by: 2) {
            guard let lang = list[i] as? String,
                  let id = (list[i + 1] as? [String: Any])?["voiceId"] as? String else { continue }
            let code = Locale(identifier: lang).language.languageCode?.identifier ?? lang
            if result[code] == nil { result[code] = id }
        }
        return result
    }

    /// "Ava (Premium)" — shown in Settings so it is clear which voice Coucou uses.
    static func macVoiceName(for locale: Locale, gender: String) -> String {
        guard let v = chosenSystemVoice(for: locale) ?? bestVoice(for: locale, gender: gender) else { return "—" }
        switch v.quality {
        case .premium:  return "\(v.name) (Premium)"
        case .enhanced: return "\(v.name) (Enhanced)"
        default:        return v.name
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                        didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard let curr = self.currentUtterance, ObjectIdentifier(curr) == id else { return }
            self.itemDone()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                        didCancel utterance: AVSpeechUtterance) {
        // stopPlayback() already reset everything; nothing to do for older utterances.
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(p)
        Task { @MainActor in
            guard let curr = self.player, ObjectIdentifier(curr) == id else { return }
            self.itemDone()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ p: AVAudioPlayer, error: Error?) {
        let id = ObjectIdentifier(p)
        Task { @MainActor in
            guard let curr = self.player, ObjectIdentifier(curr) == id else { return }
            self.itemDone()
        }
    }
}
#endif
