import Foundation

/// Base URLs typed in Settings → Chat, turned into the endpoints Coucou calls. The API key goes
/// wherever they point, so they must be https (plain http only to this Mac) and carry no user
/// name or password. Mirrors `anthropic_endpoint` in windows/src-tauri/src/net.rs.
enum ProviderEndpoint {
    enum Failure: Error, Equatable {
        case invalid
        case insecure
        case credentials
    }

    /// The Messages endpoint of an Anthropic-compatible API: a host or `…/v1` gets
    /// `/v1/messages` added, a full `…/v1/messages` is kept.
    static func anthropicMessages(_ raw: String) -> Result<URL, Failure> {
        validated(raw).flatMap { url in
            let path = trimmedPath(url)
            let messages = if path.hasSuffix("/v1/messages") { path }
                else if path.hasSuffix("/v1") { path + "/messages" }
                else { path + "/v1/messages" }
            return replacingPath(url, with: messages)
        }
    }

    /// The model list next to a Messages endpoint.
    static func anthropicModels(messages: URL) -> URL {
        var path = trimmedPath(messages)
        if path.hasSuffix("/messages") { path.removeLast("/messages".count) }
        guard var parts = URLComponents(url: messages, resolvingAgainstBaseURL: false) else { return messages }
        parts.path = path + "/models"
        parts.queryItems = [URLQueryItem(name: "limit", value: "100")]
        return parts.url ?? messages
    }

    /// An OpenAI-compatible base (`https://host/v1`), without a trailing slash. A pasted
    /// `/chat/completions` or `/models` endpoint is cut back to its base.
    static func openAICompatibleBase(_ raw: String) -> Result<String, Failure> {
        validated(raw).flatMap { url in
            var path = trimmedPath(url)
            for tail in ["/chat/completions", "/models"] where path.hasSuffix(tail) {
                path.removeLast(tail.count)
            }
            return replacingPath(url, with: path).map { $0.absoluteString }
        }
    }

    private static func validated(_ raw: String) -> Result<URL, Failure> {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: text), let scheme = parts.scheme?.lowercased(),
              let host = parts.host, !host.isEmpty, let url = parts.url else { return .failure(.invalid) }
        if parts.user != nil || parts.password != nil { return .failure(.credentials) }
        switch scheme {
        case "https": break
        case "http" where isLoopback(host): break
        case "http": return .failure(.insecure)
        default: return .failure(.invalid)
        }
        return .success(url)
    }

    private static func isLoopback(_ host: String) -> Bool {
        let h = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if h == "localhost" || h == "::1" { return true }
        let octets = h.split(separator: ".", omittingEmptySubsequences: false).map { UInt8($0) }
        return octets.count == 4 && !octets.contains(nil) && octets[0] == 127
    }

    private static func trimmedPath(_ url: URL) -> String {
        var path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path ?? ""
        while path.hasSuffix("/") { path.removeLast() }
        return path
    }

    private static func replacingPath(_ url: URL, with path: String) -> Result<URL, Failure> {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return .failure(.invalid) }
        parts.path = path
        parts.query = nil
        parts.fragment = nil
        return parts.url.map(Result.success) ?? .failure(.invalid)
    }
}
