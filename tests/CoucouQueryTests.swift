import Foundation

// What agents read through Coucou's MCP server (App/CoucouQuery.swift).

@main
enum CoucouQueryTests {

    static var failures = 0

    static func check(_ label: String, _ got: Bool) {
        if got { print("  ✓ \(label)") }
        else   { print("  ✗ \(label)"); failures += 1 }
    }

    static func ok(_ tool: String, _ args: [String: Any] = [:], _ notes: [Note]) -> Any? {
        try? CoucouQuery.answer(tool: tool, args: args, notes: notes).get()
    }

    static func error(_ tool: String, _ args: [String: Any], _ notes: [Note]) -> String? {
        if case .failure(let f) = CoucouQuery.answer(tool: tool, args: args, notes: notes) { return f.message }
        return nil
    }

    static func main() {
        let me = NoteSpeaker(id: "me", name: "Evandro", color: 0, isMe: true)
        let p2 = NoteSpeaker(id: "p2", name: "Person 2", color: 1)
        var older = Note(id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!, title: "Cloud cracks",
                         start: Date(timeIntervalSince1970: 1_800_000_000))
        older.end = older.start.addingTimeInterval(480)
        older.status = .ready
        older.speakers = [me, p2]
        older.lines = [NoteLine(speaker: "p2", start: 5, end: 9, text: "We patched the bucket policy.")]
        older.todos = [NoteTodo(text: "Rotate keys", owner: "Evandro", done: true)]
        var newer = Note(id: UUID(uuidString: "AAAAAAAB-0000-0000-0000-000000000002")!, title: "Interview prep",
                         start: Date(timeIntervalSince1970: 1_800_090_000))
        newer.end = newer.start.addingTimeInterval(2_760)
        newer.status = .ready
        newer.speakers = [me, p2]
        newer.summary = "Finalising the resume."
        newer.keyPoints = ["Verify education"]
        newer.lines = [
            NoteLine(speaker: "me", start: 62, end: 66, text: "Let's review the resume.", raw: "Let's review the resumé."),
            NoteLine(speaker: "p2", start: 3_725, end: 3_730, text: "Sure.", raw: "Sure."),
        ]
        newer.todos = [NoteTodo(text: "Adjust resume sections", owner: "Person 2", due: "Friday")]
        let notes = [older, newer]

        print("list_recordings")
        let all = ok("list_recordings", [:], notes) as? [[String: Any]] ?? []
        check("newest first", all.map { $0["title"] as? String } == ["Interview prep", "Cloud cracks"])
        check("speakers by name", all.first?["speakers"] as? [String] == ["Evandro", "Person 2"])
        check("to-do counts", all.last?["todos_open"] as? Int == 0 && all.last?["todos_done"] as? Int == 1)
        check("duration in minutes", all.first?["duration_minutes"] as? Int == 46)
        let found = ok("list_recordings", ["query": "BUCKET"], notes) as? [[String: Any]] ?? []
        check("query searches transcripts, any case", found.map { $0["title"] as? String } == ["Cloud cracks"])
        let since = ok("list_recordings", ["since": "2027-01-16"], notes) as? [[String: Any]] ?? []
        check("since a day", since.map { $0["title"] as? String } == ["Interview prep"])
        check("bad since → message", error("list_recordings", ["since": "yesterday"], notes) != nil)
        check("limit", (ok("list_recordings", ["limit": 1], notes) as? [[String: Any]])?.count == 1)

        print("get_summary")
        let summary = ok("get_summary", ["id": "aaaaaaab"], notes) as? [String: Any]
        check("unique id prefix, any case", summary?["title"] as? String == "Interview prep")
        check("summary and key points", summary?["summary"] as? String == "Finalising the resume."
              && summary?["key_points"] as? [String] == ["Verify education"])
        check("to-dos with owner and due", (summary?["todos"] as? [[String: Any]])?.first?["due"] as? String == "Friday")
        check("ambiguous prefix → message", error("get_summary", ["id": "AAAAAAA"], notes)?.contains("2 recordings") == true)
        check("short prefix refused", error("get_summary", ["id": "AAAA"], notes) != nil)
        check("missing id → message", error("get_summary", [:], notes)?.contains("list_recordings") == true)

        print("get_transcript")
        let transcript = ok("get_transcript", ["id": newer.id.uuidString], notes) as? [String: Any]
        let lines = transcript?["lines"] as? [[String: Any]] ?? []
        check("speaker names, not ids", lines.map { $0["speaker"] as? String } == ["Evandro", "Person 2"])
        check("clock mm:ss and h:mm:ss", lines.map { $0["at"] as? String } == ["01:02", "1:02:05"])
        check("heard kept where a correction changed it", lines.first?["heard"] as? String == "Let's review the resumé.")
        check("no heard when unchanged", lines.last?["heard"] == nil)

        print("get_todos")
        let open = ok("get_todos", [:], notes) as? [[String: Any]] ?? []
        check("open ones across recordings", open.map { $0["text"] as? String } == ["Adjust resume sections"])
        check("with their recording", open.first?["recording_title"] as? String == "Interview prep")
        let everything = ok("get_todos", ["include_done": true], notes) as? [[String: Any]] ?? []
        check("include_done", everything.count == 2)
        let one = ok("get_todos", ["id": older.id.uuidString, "include_done": true], notes) as? [[String: Any]] ?? []
        check("one recording", one.map { $0["text"] as? String } == ["Rotate keys"])

        print("results are JSON")
        for tool in ["list_recordings", "get_todos"] {
            check("\(tool) serialises", JSONSerialization.isValidJSONObject(ok(tool, ["include_done": true], notes) ?? 0))
        }
        check("get_transcript serialises", JSONSerialization.isValidJSONObject(transcript ?? 0))
        check("unknown tool → message", error("delete_everything", [:], notes) != nil)

        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("All Coucou query tests passed.")
    }
}
