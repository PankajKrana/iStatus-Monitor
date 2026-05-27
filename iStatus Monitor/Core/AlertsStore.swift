import Foundation
import Observation

@MainActor
@Observable
final class AlertsStore {
    private let engine: AlertEngine

    var rules: [AlertRule] = []
    var history: [AlertHistoryEntry] = []
    var badgeCountLastHour: Int = 0

    init(engine: AlertEngine) {
        self.engine = engine
    }

    func refresh() {
        Task {
            rules = await engine.getRules()
            history = await engine.getHistory()
            badgeCountLastHour = await engine.recentAlertCount(last: 3600)
        }
    }

    func saveRule(_ rule: AlertRule) {
        Task {
            await engine.upsertRule(rule)
            refresh()
        }
    }

    func deleteRule(id: UUID) {
        Task {
            await engine.deleteRule(id: id)
            refresh()
        }
    }

    func testRule(id: UUID) {
        Task {
            await engine.fireTestAlert(ruleID: id)
        }
    }
}
