import Foundation

/// An error a method returns. Application errors use -32000 with `{kind, detail}` in `data`.
struct RPCFailure: Error, Equatable {
    let code: Int
    let message: String
    var kind: String? = nil
    var detail: String? = nil

    static let parse = RPCFailure(code: -32700, message: "Parse error")
    static let invalidRequest = RPCFailure(code: -32600, message: "Invalid Request")
    static func methodNotFound(_ method: String) -> RPCFailure { .init(code: -32601, message: "Method not found: \(method)") }
    static func invalidParams(_ detail: String) -> RPCFailure { .init(code: -32602, message: "Invalid params", detail: detail) }
    static func app(_ kind: String, _ detail: String) -> RPCFailure { .init(code: -32000, message: detail, kind: kind, detail: detail) }
    static func timeout(revision: UInt64) -> RPCFailure {
        .init(code: -32001, message: "Timed out at revision \(revision)", kind: "timeout", detail: "\(revision)")
    }

    var object: [String: Any] {
        var error: [String: Any] = ["code": code, "message": message]
        if let kind { error["data"] = ["kind": kind, "detail": detail ?? ""] }
        else if let detail { error["data"] = ["detail": detail] }
        return error
    }
}

/// JSON-RPC 2.0, one JSON document per line, batches allowed; requests without `id` are
/// notifications and get no answer.
@MainActor
enum RPCProtocol {
    typealias Handler = @MainActor (_ method: String, _ params: [String: Any]) async throws -> Any

    /// The answer line for one request line, or nil when nothing is owed (notifications only).
    static func respond(to line: Data, handler: Handler) async -> Data? {
        guard let parsed = try? JSONSerialization.jsonObject(with: line) else {
            return encode(reply(id: NSNull(), error: .parse))
        }
        if let batch = parsed as? [Any] {
            guard !batch.isEmpty else { return encode(reply(id: NSNull(), error: .invalidRequest)) }
            var answers: [[String: Any]] = []
            for request in batch {
                if let answer = await one(request, handler) { answers.append(answer) }
            }
            return answers.isEmpty ? nil : encode(answers)
        }
        return await one(parsed, handler).flatMap(encode)
    }

    private static func one(_ raw: Any, _ handler: Handler) async -> [String: Any]? {
        guard let request = raw as? [String: Any], request["jsonrpc"] as? String == "2.0",
              let method = request["method"] as? String else {
            return reply(id: (raw as? [String: Any])?["id"] ?? NSNull(), error: .invalidRequest)
        }
        let id = request["id"]
        let params: [String: Any]
        switch request["params"] {
        case nil, is NSNull: params = [:]
        case let object as [String: Any]: params = object
        default: return id.map { reply(id: $0, error: .invalidParams("params must be an object")) }
        }
        do {
            let result = try await handler(method, params)
            return id.map { ["jsonrpc": "2.0", "id": $0, "result": result] }
        } catch let failure as RPCFailure {
            return id.map { reply(id: $0, error: failure) }
        } catch {
            return id.map { reply(id: $0, error: .init(code: -32603, message: error.localizedDescription)) }
        }
    }

    private static func reply(id: Any, error: RPCFailure) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": error.object]
    }

    private static func encode(_ object: Any) -> Data? {
        try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    // MARK: Params

    static func string(_ params: [String: Any], _ key: String) throws -> String {
        guard let value = params[key] as? String, !value.isEmpty else { throw RPCFailure.invalidParams("\(key) must be a string") }
        return value
    }

    static func bool(_ params: [String: Any], _ key: String) throws -> Bool {
        guard let value = params[key] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else {
            throw RPCFailure.invalidParams("\(key) must be true or false")
        }
        return value.boolValue
    }

    static func uint(_ params: [String: Any], _ key: String) throws -> UInt64? {
        guard let raw = params[key] else { return nil }
        guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.int64Value >= 0 else {
            throw RPCFailure.invalidParams("\(key) must be a whole number ≥ 0")
        }
        return value.uint64Value
    }
}
