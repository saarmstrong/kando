import Foundation

struct KanbanColumn: Identifiable, Hashable, CaseIterable {
    enum Kind: String, CaseIterable, Identifiable {
        case backlog
        case doing
        case done

        var id: String { rawValue }
    }

    let kind: Kind
    let title: String
    let backingReminderListName: String

    var id: Kind { kind }

    static let backlog = KanbanColumn(kind: .backlog, title: "Backlog", backingReminderListName: "Kanban - Backlog")
    static let doing = KanbanColumn(kind: .doing, title: "Doing", backingReminderListName: "Kanban - Doing")
    static let done = KanbanColumn(kind: .done, title: "Done", backingReminderListName: "Kanban - Done")

    static let allCases: [KanbanColumn] = [.backlog, .doing, .done]
}
