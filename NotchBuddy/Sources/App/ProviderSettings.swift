import Foundation

/// Each cloud provider's base URL and model name from Settings → Chat, for Anthropic- or
/// OpenAI-compatible backends. Not secret: kept in UserDefaults, readable from any thread.
/// AppState writes them so the chat views refresh.
enum ProviderSettings {
    static let baseURLsKey = "providerBaseURLs"
    static let modelsKey = "customChatModels"
    /// Anthropic's small model, for Flow clean-up, notes and spoken answers.
    static let anthropicFastModel = "claude-haiku-4-5"

    static func baseURL(_ provider: ChatProvider) -> String {
        stored(baseURLsKey)[provider.rawValue] ?? ""
    }

    static func customModel(_ provider: ChatProvider) -> String {
        stored(modelsKey)[provider.rawValue] ?? ""
    }

    static func customModels() -> [ChatProvider: String] {
        var result: [ChatProvider: String] = [:]
        for (raw, model) in stored(modelsKey) {
            if let provider = ChatProvider(rawValue: raw), !model.isEmpty { result[provider] = model }
        }
        return result
    }

    static func store(_ value: String, for provider: ChatProvider, in key: String) {
        var all = stored(key)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        all[provider.rawValue] = trimmed.isEmpty ? nil : trimmed
        UserDefaults.standard.set(all, forKey: key)
    }

    static func hasCustomBaseURL(_ provider: ChatProvider) -> Bool {
        !baseURL(provider).isEmpty
    }

    /// The Messages endpoint every Claude call uses.
    static var anthropicMessagesURL: URL {
        if case .success(let url) = ProviderEndpoint.anthropicMessages(baseURL(.anthropic)) { return url }
        return URL(string: ChatProvider.anthropic.defaultBaseURL + "/v1/messages")!
    }

    /// The OpenAI-compatible base a cloud provider's chat and model list use.
    static func openAICompatibleBase(_ provider: ChatProvider) -> String {
        if case .success(let base) = ProviderEndpoint.openAICompatibleBase(baseURL(provider)) { return base }
        return provider.defaultBaseURL
    }

    /// A fixed Anthropic model, unless Settings names the model to use: a compatible backend
    /// may serve none of Anthropic's model IDs.
    static func anthropicModel(orElse fixed: String) -> String {
        let custom = customModel(.anthropic)
        return custom.isEmpty ? fixed : custom
    }

    private static func stored(_ key: String) -> [String: String] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }
}
