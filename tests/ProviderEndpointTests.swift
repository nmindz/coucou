import Foundation

// Base URLs typed in Settings → Chat (App/ProviderEndpoint.swift). The API key goes wherever
// they point, so the https rule matters as much as the paths. Mirrors the anthropic_endpoint
// tests in windows/src-tauri/src/net.rs.

@main
enum ProviderEndpointTests {

    static var failures = 0

    static func check(_ label: String, _ got: Bool) {
        if got { print("  ✓ \(label)") }
        else   { print("  ✗ \(label)"); failures += 1 }
    }

    static func messages(_ raw: String) -> String? {
        try? ProviderEndpoint.anthropicMessages(raw).get().absoluteString
    }

    static func base(_ raw: String) -> String? {
        try? ProviderEndpoint.openAICompatibleBase(raw).get()
    }

    static func main() {
        print("anthropicMessages — a host or /v1 gets /v1/messages, a full endpoint is kept")
        check("host",               messages("https://gw.example.com") == "https://gw.example.com/v1/messages")
        check("host with /",        messages("https://gw.example.com/") == "https://gw.example.com/v1/messages")
        check("…/v1",               messages("https://gw.example.com/v1") == "https://gw.example.com/v1/messages")
        check("…/v1/messages",      messages("https://gw.example.com/v1/messages/") == "https://gw.example.com/v1/messages")
        check("path prefix",        messages("https://gw.example.com/anthropic") == "https://gw.example.com/anthropic/v1/messages")
        check("port kept",          messages("https://gw.example.com:8443") == "https://gw.example.com:8443/v1/messages")
        check("spaces trimmed",     messages("  https://gw.example.com  ") == "https://gw.example.com/v1/messages")
        check("query dropped",      messages("https://gw.example.com/v1?x=1#f") == "https://gw.example.com/v1/messages")

        print("anthropicModels — next to the Messages endpoint")
        let models = ProviderEndpoint.anthropicModels(messages: URL(string: "https://gw.example.com/p/v1/messages")!)
        check("…/v1/models?limit=100", models.absoluteString == "https://gw.example.com/p/v1/models?limit=100")
        let official = ProviderEndpoint.anthropicModels(messages: URL(string: "https://api.anthropic.com/v1/messages")!)
        check("Anthropic's own", official.absoluteString == "https://api.anthropic.com/v1/models?limit=100")

        print("openAICompatibleBase — the base, without a trailing slash or a pasted endpoint")
        check("kept as typed",         base("https://openrouter.ai/api/v1") == "https://openrouter.ai/api/v1")
        check("trailing slash",        base("https://openrouter.ai/api/v1/") == "https://openrouter.ai/api/v1")
        check("/chat/completions cut", base("https://gw.example.com/v1/chat/completions") == "https://gw.example.com/v1")
        check("/models cut",           base("https://gw.example.com/v1/models") == "https://gw.example.com/v1")
        check("loopback http",         base("http://127.0.0.1:4000/v1") == "http://127.0.0.1:4000/v1")
        check("localhost http",        base("http://localhost:4000") == "http://localhost:4000")
        check("::1 http",              base("http://[::1]:4000/v1") == "http://[::1]:4000/v1")

        print("refused — the key would leak or go nowhere")
        let refused: [(String, ProviderEndpoint.Failure)] = [
            ("http://gw.example.com/v1", .insecure),
            ("http://127.0.0.1.evil.com/v1", .insecure),
            ("https://user:pass@gw.example.com/v1", .credentials),
            ("https://user@gw.example.com/v1", .credentials),
            ("ftp://gw.example.com", .invalid),
            ("gw.example.com/v1", .invalid),
            ("", .invalid),
            ("https://", .invalid),
        ]
        for (raw, failure) in refused {
            if case .failure(let got) = ProviderEndpoint.openAICompatibleBase(raw) {
                check("'\(raw)' → \(failure)", got == failure)
            } else {
                check("'\(raw)' → \(failure)", false)
            }
            if case .failure(let got) = ProviderEndpoint.anthropicMessages(raw) {
                check("'\(raw)' → \(failure) (Anthropic)", got == failure)
            } else {
                check("'\(raw)' → \(failure) (Anthropic)", false)
            }
        }

        if failures > 0 {
            print("\(failures) failure(s)")
            exit(1)
        }
        print("All provider endpoint tests passed.")
    }
}
