import Foundation

// claude-lb's /api/analytics/quota turned into the notch gauge (App/ClaudeLBQuota.swift).
// The body mirrors docs/usage-analytics-api.md in claude-lb.

@main
enum ClaudeLBQuotaTests {

    static var failures = 0

    static func check(_ label: String, _ got: Bool) {
        if got { print("  ✓ \(label)") }
        else   { print("  ✗ \(label)"); failures += 1 }
    }

    static func window(_ pct: Double, _ reset: String, passed: Bool = false) -> String {
        #"{"status":"allowed","utilizationPercent":\#(pct),"remainingPercent":0,"resetAt":"\#(reset)","resetPassed":\#(passed)}"#
    }

    static let body = """
    {"meta":{"window":null},"data":{"accounts":[
      {"account":{"id":"a","label":"work@example.com","planTier":"max-5x"},
       "fiveHour":\(window(20, "2099-01-01T05:00:00.000Z")),"sevenDay":\(window(60, "2099-01-03T00:00:00Z"))},
      {"account":{"id":"b","label":"home@example.com","planTier":"pro"},
       "fiveHour":\(window(80, "2099-01-01T04:00:00.000Z")),"sevenDay":\(window(115, "2099-01-05T00:00:00Z"))},
      {"account":{"id":"c","email":"new@example.com","planTier":"pro"},"fiveHour":null,"sevenDay":null},
      {"account":{"id":"d","label":"rolled","planTier":"pro"},
       "fiveHour":\(window(90, "2000-01-01T00:00:00Z", passed: true)),"sevenDay":null}
    ],"pool":{}}}
    """

    static func main() {
        guard let accounts = ClaudeLB.parseQuota(Data(body.utf8)) else {
            print("  ✗ body did not parse"); exit(1)
        }

        print("parseQuota")
        check("four accounts, claude-lb order", accounts.map(\.id) == ["a", "b", "c", "d"])
        check("label falls back to email", accounts[2].label == "new@example.com")
        check("never probed stays nil, not 0 %", accounts[2].fiveHour == nil && accounts[2].sevenDay == nil)
        check("over 100 % clamps to 100", accounts[1].sevenDay?.usedPct == 100)
        check("rolled-over window reads 0", accounts[3].fiveHour?.usedPct == 0)
        check("fractional and plain ISO dates", accounts[0].fiveHour != nil && accounts[0].sevenDay != nil)
        check("garbage → nil", ClaudeLB.parseQuota(Data("{}".utf8)) == nil)

        print("average (default)")
        let avg = ClaudeLB.planUsage(accounts, selected: ["a", "b"], mode: .average)
        check("5h mean of selected", avg?.fiveHour?.usedPct == 50)
        check("7d mean of selected", avg?.sevenDay?.usedPct == 80)
        check("reset = earliest", avg?.fiveHour?.resetsAt == accounts[1].fiveHour?.resetsAt)
        let all = ClaudeLB.planUsage(accounts, selected: [], mode: .average)
        check("empty selection = every account; unprobed ignored", all?.fiveHour?.usedPct == (20 + 80 + 0) / 3)

        print("most used")
        let top = ClaudeLB.planUsage(accounts, selected: ["a", "b"], mode: .mostUsed)
        check("5h = busiest account", top?.fiveHour?.usedPct == 80)
        check("its own reset", top?.fiveHour?.resetsAt == accounts[1].fiveHour?.resetsAt)

        print("single")
        let one = ClaudeLB.planUsage(accounts, selected: ["b", "a"], mode: .single)
        check("first selected in claude-lb order", one?.fiveHour?.usedPct == 20)
        check("counted keeps one", ClaudeLB.counted(accounts, selected: [], mode: .single).count == 1)

        print("nothing to show")
        check("only unprobed accounts → nil", ClaudeLB.planUsage(accounts, selected: ["c"], mode: .average) == nil)

        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("All claude-lb quota tests passed.")
    }
}
