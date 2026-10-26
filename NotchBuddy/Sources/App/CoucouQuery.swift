import Foundation

/// What agents can ask the running Coucou through its MCP server (`coucou-mcp`, docs/MCP.md):
/// the Notetaker's recordings, their summaries, to-dos and transcripts. Read-only, JSON in and out.
enum CoucouQuery {
    struct Failure: Error, Equatable {
        let message: String
    }

    /// Answers one tool call from the notes, newest first. The result is JSON-serialisable.
    static func answer(tool: String, args: [String: Any], notes: [Note]) -> Result<Any, Failure> {
        let notes = notes.sorted { $0.start > $1.start }
        switch tool {
        case "list_recordings": return listRecordings(args, notes)
        case "get_summary":     return recording(args, notes).map(summary)
        case "get_transcript":  return recording(args, notes).map(transcript)
        case "get_todos":       return todos(args, notes)
        default:                return .failure(Failure(message: "Unknown tool \(tool)."))
        }
    }

    // MARK: Tools

    private static func listRecordings(_ args: [String: Any], _ notes: [Note]) -> Result<Any, Failure> {
        var found = notes
        if let raw = args["since"] as? String, !raw.isEmpty {
            guard let since = parseDate(raw) else {
                return .failure(Failure(message: "since must be a date like 2026-10-27 or an ISO 8601 time."))
            }
            found = found.filter { $0.start >= since }
        }
        if let query = (args["query"] as? String)?.trimmingCharacters(in: .whitespaces), !query.isEmpty {
            found = found.filter { matches($0, query) }
        }
        let limit = min(100, max(1, (args["limit"] as? NSNumber)?.intValue ?? 20))
        return .success(found.prefix(limit).map { note -> [String: Any] in
            var row = header(note)
            row["summary_preview"] = note.summary.map { String($0.prefix(200)) } ?? NSNull()
            row["todos_open"] = note.todos.filter { !$0.done }.count
            row["todos_done"] = note.todos.filter(\.done).count
            row["lines"] = note.lines.count
            return row
        })
    }

    private static func summary(_ note: Note) -> Any {
        var out = header(note)
        out["summary"] = note.summary ?? NSNull()
        out["key_points"] = note.keyPoints
        out["todos"] = note.todos.map(todo)
        if let error = note.error { out["error"] = error }
        return out
    }

    private static func transcript(_ note: Note) -> Any {
        var out = header(note)
        out["lines"] = note.lines.map { line -> [String: Any] in
            var row: [String: Any] = [
                "at": clock(line.start),
                "start": rounded(line.start),
                "end": rounded(line.end),
                "speaker": note.speaker(line.speaker)?.name ?? line.speaker,
                "text": line.text,
            ]
            // The words as first transcribed, when a correction changed them.
            if let raw = line.raw, raw != line.text { row["heard"] = raw }
            return row
        }
        return out
    }

    private static func todos(_ args: [String: Any], _ notes: [Note]) -> Result<Any, Failure> {
        let includeDone = args["include_done"] as? Bool ?? false
        let scope: [Note]
        if args["id"] != nil {
            switch recording(args, notes) {
            case .success(let note): scope = [note]
            case .failure(let failure): return .failure(failure)
            }
        } else {
            scope = notes
        }
        return .success(scope.flatMap { note in
            note.todos.filter { includeDone || !$0.done }.map { item -> [String: Any] in
                var row = todo(item)
                row["recording_id"] = note.id.uuidString
                row["recording_title"] = note.title
                row["recording_start"] = iso(note.start)
                return row
            }
        })
    }

    // MARK: Pieces

    /// A recording by its full id, or by a unique prefix of at least 6 characters.
    private static func recording(_ args: [String: Any], _ notes: [Note]) -> Result<Note, Failure> {
        guard let raw = (args["id"] as? String)?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return .failure(Failure(message: "id is required: take it from list_recordings."))
        }
        let id = raw.uppercased()
        if let exact = notes.first(where: { $0.id.uuidString == id }) { return .success(exact) }
        guard id.count >= 6 else { return .failure(Failure(message: "No recording \(raw).")) }
        let matching = notes.filter { $0.id.uuidString.hasPrefix(id) }
        switch matching.count {
        case 1:  return .success(matching[0])
        case 0:  return .failure(Failure(message: "No recording \(raw)."))
        default: return .failure(Failure(message: "\(raw) matches \(matching.count) recordings: give more of the id."))
        }
    }

    private static func header(_ note: Note) -> [String: Any] {
        [
            "id": note.id.uuidString,
            "title": note.title,
            "start": iso(note.start),
            "end": note.end.map(iso) ?? NSNull(),
            "duration_minutes": Int((note.duration / 60).rounded()),
            "app": note.app ?? NSNull(),
            "status": note.status.rawValue,
            "speakers": note.speakers.map(\.name),
        ]
    }

    private static func todo(_ item: NoteTodo) -> [String: Any] {
        ["text": item.text, "owner": item.owner ?? NSNull(), "due": item.due ?? NSNull(), "done": item.done]
    }

    private static func matches(_ note: Note, _ query: String) -> Bool {
        let fields = [note.title, note.summary ?? ""] + note.keyPoints + note.todos.map(\.text) + note.lines.map(\.text)
        return fields.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private static func clock(_ seconds: Double) -> String {
        let s = Int(seconds)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%02d:%02d", s / 60, s % 60)
    }

    private static func rounded(_ value: Double) -> Double { (value * 10).rounded() / 10 }

    private static func iso(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    private static func parseDate(_ raw: String) -> Date? {
        if let date = try? Date(raw, strategy: .iso8601) { return date }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: raw)
    }
}
