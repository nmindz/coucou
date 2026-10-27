import Foundation

// The screen store (App/ScreenStore.swift) and the debug JSON-RPC layer (App/RPCProtocol.swift).

@main
enum ScreenStoreRPCTests {
    @MainActor static var failures = 0

    @MainActor static func check(_ label: String, _ got: Bool) {
        if got { print("  ✓ \(label)") }
        else   { print("  ✗ \(label)"); failures += 1 }
    }

    struct Card: Codable, Equatable { let title: String; let pct: Int? }

    @MainActor static func main() async {
        print("ScreenStore")
        let store = ScreenStore()
        check("unpublished screen is at revision 0", store.revision(.plan) == 0)
        check("publish → revision 1", store.publish(.plan, "card", Card(title: "Plan", pct: 40)) && store.revision(.plan) == 1)
        check("identical value keeps the revision", !store.publish(.plan, "card", Card(title: "Plan", pct: 40)) && store.revision(.plan) == 1)
        store.publish(.plan, "card", Card(title: "Plan", pct: 41))
        check("changed value bumps it", store.revision(.plan) == 2)
        check("the view reads the typed value", store.part(.plan, "card", as: Card.self) == Card(title: "Plan", pct: 41))
        let view = store.entryJSON(.plan)["view"] as? [String: Any]
        let card = view?["card"] as? [String: Any]
        check("the RPC reads the same value as JSON", card?["title"] as? String == "Plan" && card?["pct"] as? Int == 41)
        check("nil fields are left out", ((store.publish(.plan, "card", Card(title: "Plan", pct: nil)), (store.entryJSON(.plan)["view"] as? [String: Any])?["card"] as? [String: Any]).1?["pct"] == nil))
        check("screens count apart", store.revision(.settings) == 0)

        check("UI state bumps the revision", store.mergeUI(.settings, ["status": "Saved"]) && store.revision(.settings) == 1)
        check("same UI state does not", !store.mergeUI(.settings, ["status": "Saved"]))
        store.mergeUI(.settings, ["pending": ["agent": "codex", "install": true]])
        check("nested UI state compares by value", !store.mergeUI(.settings, ["pending": ["agent": "codex", "install": true]]))
        store.mergeUI(.settings, ["pending": NSNull()])
        check("NSNull clears a key", store.ui(.settings, "pending") == nil && store.ui(.settings, "status") as? String == "Saved")

        print("schedule and wait")
        var builds = 0
        store.register(.plan) { builds += 1; store.publish(.plan, "card", Card(title: "Plan", pct: 50 + builds)) }
        store.schedule(.plan)
        store.schedule(.plan, .plan)
        let before = store.revision(.plan)
        check("wait resolves when the build lands", await store.wait(.plan, minRevision: before + 1, timeout: .seconds(2)))
        await Task.yield()
        check("three schedules in one turn → one build", builds == 1)
        check("wait times out when nothing changes", !(await store.wait(.plan, minRevision: 999, timeout: .milliseconds(50))))
        check("a reached revision returns at once", await store.wait(.plan, minRevision: 1, timeout: .milliseconds(1)))

        print("JSON-RPC")
        let handler: RPCProtocol.Handler = { method, params in
            switch method {
            case "echo": return params
            case "fail": throw RPCFailure.app("not_found", "No such agent.")
            case "bad": _ = try RPCProtocol.bool(params, "enabled"); return true
            default: throw RPCFailure.methodNotFound(method)
            }
        }
        func call(_ text: String) async -> Any? {
            guard let data = await RPCProtocol.respond(to: Data(text.utf8), handler: handler) else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        }
        func errorCode(_ reply: Any?) -> Int? { ((reply as? [String: Any])?["error"] as? [String: Any])?["code"] as? Int }

        let ok = await call(#"{"jsonrpc":"2.0","id":7,"method":"echo","params":{"a":1}}"#) as? [String: Any]
        check("result echoes id", ok?["id"] as? Int == 7 && (ok?["result"] as? [String: Any])?["a"] as? Int == 1)
        let parse = await call("{nope") as? [String: Any]
        check("garbage → -32700, id null", errorCode(parse) == -32700 && parse?["id"] is NSNull)
        check("no jsonrpc 2.0 → -32600", errorCode(await call(#"{"id":1,"method":"echo"}"#)) == -32600)
        check("unknown method → -32601", errorCode(await call(#"{"jsonrpc":"2.0","id":1,"method":"nope"}"#)) == -32601)
        check("params not an object → -32602", errorCode(await call(#"{"jsonrpc":"2.0","id":1,"method":"echo","params":[1]}"#)) == -32602)
        check("wrong param type → -32602", errorCode(await call(#"{"jsonrpc":"2.0","id":1,"method":"bad","params":{"enabled":1}}"#)) == -32602)
        let app = await call(#"{"jsonrpc":"2.0","id":1,"method":"fail"}"#) as? [String: Any]
        let data = (app?["error"] as? [String: Any])?["data"] as? [String: Any]
        check("app error → -32000 with its kind", errorCode(app) == -32000 && data?["kind"] as? String == "not_found")
        check("notification → no answer", await call(#"{"jsonrpc":"2.0","method":"echo"}"#) == nil)
        let batch = await call(#"[{"jsonrpc":"2.0","id":1,"method":"echo"},{"jsonrpc":"2.0","method":"echo"},{"jsonrpc":"2.0","id":2,"method":"nope"}]"#) as? [[String: Any]]
        check("batch answers each request, skips notifications", batch?.count == 2 && errorCode(batch?[1]) == -32601)
        check("empty batch → -32600", errorCode(await call("[]")) == -32600)

        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("All screen store and RPC tests passed.")
    }
}
