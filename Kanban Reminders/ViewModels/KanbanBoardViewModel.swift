import Foundation
import SwiftUI

@MainActor
final class KanbanBoardViewModel: ObservableObject {
    @Published private(set) var tasks: [ReminderTask] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasPermission = true
    @Published var columns: [KanbanColumn]

    private let service: ReminderStoreService

    init(columns: [KanbanColumn] = KanbanColumn.defaultKanban, service: ReminderStoreService = ReminderStoreService()) {
        self.columns = columns
        self.service = service
    }

    func updateColumns(_ columns: [KanbanColumn]) {
        self.columns = columns
        tasks.removeAll { task in !columns.contains(where: { $0.id == task.columnId }) }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            hasPermission = try await service.requestAccessIfNeeded()
            guard hasPermission else { return }
            tasks = try await service.loadBoard(columns: columns)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func tasks(in columnId: String) -> [ReminderTask] {
        tasks.filter { $0.columnId == columnId }
    }

    func saveTask(identifier: String?, draft: ReminderDraft) async {
        do {
            let normalizedDraft = normalizedDraftForCompletion(draft)
            if let identifier {
                _ = try await service.updateReminder(identifier: identifier, with: normalizedDraft, columns: columns)
            } else {
                _ = try await service.createReminder(normalizedDraft, columns: columns)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func move(_ task: ReminderTask, to columnId: String) async {
        guard task.columnId != columnId else { return }
        do {
            try await service.moveReminder(identifier: task.reminderIdentifier, to: columnId, columns: columns)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func move(identifier: String, to columnId: String) async {
        guard let task = tasks.first(where: { $0.reminderIdentifier == identifier }) else { return }
        await move(task, to: columnId)
    }

    func setCompletion(_ task: ReminderTask, isCompleted: Bool) async {
        do {
            if isCompleted, let doneColumn = doneColumn {
                // Completing a reminder should also move it to the Done Kanban list so
                // Apple Reminders and the board stay in sync.
                try await service.moveReminder(identifier: task.reminderIdentifier, to: doneColumn.id, columns: columns)
            } else {
                try await service.setCompletion(identifier: task.reminderIdentifier, isCompleted: isCompleted)

                // If a task is uncompleted while it is in Done, place it back into the
                // first non-Done column instead of leaving it visually completed.
                if !isCompleted, isDoneColumnId(task.columnId), let fallbackColumn = firstNonDoneColumn {
                    try await service.moveReminder(identifier: task.reminderIdentifier, to: fallbackColumn.id, columns: columns)
                }
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var doneColumn: KanbanColumn? {
        columns.first { isDoneColumn($0) }
    }

    private var firstNonDoneColumn: KanbanColumn? {
        columns.first { !isDoneColumn($0) }
    }

    private func normalizedDraftForCompletion(_ draft: ReminderDraft) -> ReminderDraft {
        var normalized = draft
        if draft.isCompleted, let doneColumn {
            normalized.columnId = doneColumn.id
        } else if !draft.isCompleted, isDoneColumnId(draft.columnId), let firstNonDoneColumn {
            normalized.columnId = firstNonDoneColumn.id
        }
        return normalized
    }

    private func isDoneColumnId(_ columnId: String) -> Bool {
        columns.first(where: { $0.id == columnId }).map(isDoneColumn) ?? false
    }

    private func isDoneColumn(_ column: KanbanColumn) -> Bool {
        column.id.localizedCaseInsensitiveContains("done") || column.title.localizedCaseInsensitiveContains("done")
    }

    func clearError() {
        errorMessage = nil
    }
}
