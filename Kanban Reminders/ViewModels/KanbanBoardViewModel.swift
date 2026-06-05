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
    private var isUITesting: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["KANDO_UI_TESTING"] == "1" ||
        ProcessInfo.processInfo.arguments.contains("-KANDO_UI_TESTING")
        #else
        false
        #endif
    }

    init(columns: [KanbanColumn] = KanbanColumn.defaultKanban, service: ReminderStoreService = ReminderStoreService()) {
        self.columns = columns
        self.service = service
    }

    func updateColumns(_ columns: [KanbanColumn]) {
        self.columns = columns
        tasks.removeAll { task in !columns.contains(where: { $0.id == task.columnId }) }
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if isUITesting {
            hasPermission = true
            if tasks.isEmpty { tasks = sampleUITestTasks() }
            return
        }

        do {
            hasPermission = try await service.requestAccessIfNeeded()
            guard hasPermission else { return }
            // Replace the UI projection only after EventKit returns successfully. If
            // refresh fails, the current board stays visible instead of being cleared.
            let latestTasks = try await service.loadBoard(columns: columns)
            tasks = latestTasks
        } catch {
            logError("Load failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func refreshFromReminders() async {
        await load()
    }

    func tasks(in columnId: String) -> [ReminderTask] {
        tasks.filter { $0.columnId == columnId }
    }

    func saveTask(identifier: String?, draft: ReminderDraft) async {
        if isUITesting {
            let normalizedDraft = normalizedDraftForCompletion(draft)
            if let identifier, let index = tasks.firstIndex(where: { $0.reminderIdentifier == identifier }) {
                tasks[index].title = normalizedDraft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Task" : normalizedDraft.title
                tasks[index].notes = normalizedDraft.notes
                tasks[index].commentsMarkdown = normalizedDraft.commentsMarkdown
                tasks[index].matrixQuadrantId = normalizedDraft.matrixQuadrantId
                tasks[index].dueDate = normalizedDraft.dueDate
                tasks[index].tags = ReminderTagParser.normalize(normalizedDraft.tags + ReminderTagParser.tags(in: normalizedDraft.title) + ReminderTagParser.tags(in: normalizedDraft.notes) + ReminderTagParser.tags(in: normalizedDraft.commentsMarkdown))
                tasks[index].priority = normalizedDraft.priority
                tasks[index].isCompleted = normalizedDraft.isCompleted
                tasks[index].columnId = normalizedDraft.columnId
            } else {
                tasks.append(ReminderTask(
                    reminderIdentifier: UUID().uuidString,
                    title: normalizedDraft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Task" : normalizedDraft.title,
                    notes: normalizedDraft.notes,
                    commentsMarkdown: normalizedDraft.commentsMarkdown,
                    matrixQuadrantId: normalizedDraft.matrixQuadrantId,
                    dueDate: normalizedDraft.dueDate,
                    tags: ReminderTagParser.normalize(normalizedDraft.tags + ReminderTagParser.tags(in: normalizedDraft.title) + ReminderTagParser.tags(in: normalizedDraft.notes) + ReminderTagParser.tags(in: normalizedDraft.commentsMarkdown)),
                    priority: normalizedDraft.priority,
                    isCompleted: normalizedDraft.isCompleted,
                    columnId: normalizedDraft.columnId
                ))
            }
            return
        }

        do {
            let normalizedDraft = normalizedDraftForCompletion(draft)
            if let identifier {
                _ = try await service.updateReminder(identifier: identifier, with: normalizedDraft, columns: columns)
            } else {
                _ = try await service.createReminder(normalizedDraft, columns: columns)
            }
            await load()
        } catch {
            logError("Save task failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func move(_ task: ReminderTask, to columnId: String) async {
        guard task.columnId != columnId else { return }
        if isUITesting {
            guard let index = tasks.firstIndex(where: { $0.reminderIdentifier == task.reminderIdentifier }) else { return }
            tasks[index].columnId = columnId
            if isDoneColumnId(columnId) { tasks[index].isCompleted = true }
            return
        }
        let previousTasks = tasks
        applyLocalMove(identifier: task.reminderIdentifier, to: columnId)
        do {
            try await service.moveReminder(identifier: task.reminderIdentifier, to: columnId, columns: columns)
        } catch {
            tasks = previousTasks
            logError("Move task failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func move(identifier: String, to columnId: String) async {
        guard let task = tasks.first(where: { $0.reminderIdentifier == identifier }) else { return }
        await move(task, to: columnId)
    }

    func setMatrixQuadrant(_ task: ReminderTask, quadrantId: String) async {
        if isUITesting {
            if let index = tasks.firstIndex(where: { $0.reminderIdentifier == task.reminderIdentifier }) {
                tasks[index].matrixQuadrantId = quadrantId
            }
            return
        }
        do {
            try await service.setMatrixQuadrant(identifier: task.reminderIdentifier, quadrantId: quadrantId)
            if let index = tasks.firstIndex(where: { $0.reminderIdentifier == task.reminderIdentifier }) {
                tasks[index].matrixQuadrantId = quadrantId
            }
        } catch {
            logError("Set matrix quadrant failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func setCompletion(_ task: ReminderTask, isCompleted: Bool) async {
        if isUITesting {
            guard let index = tasks.firstIndex(where: { $0.reminderIdentifier == task.reminderIdentifier }) else { return }
            tasks[index].isCompleted = isCompleted
            if isCompleted, let doneColumn {
                tasks[index].columnId = doneColumn.id
            } else if !isCompleted, isDoneColumnId(tasks[index].columnId), let firstNonDoneColumn {
                tasks[index].columnId = firstNonDoneColumn.id
            }
            return
        }
        let previousTasks = tasks
        do {
            if isCompleted, let doneColumn = doneColumn {
                // Completing a reminder should also move it to the Done Kanban list so
                // Apple Reminders and the board stay in sync.
                applyLocalMove(identifier: task.reminderIdentifier, to: doneColumn.id)
                try await service.moveReminder(identifier: task.reminderIdentifier, to: doneColumn.id, columns: columns)
            } else {
                applyLocalCompletion(identifier: task.reminderIdentifier, isCompleted: false)
                try await service.setCompletion(identifier: task.reminderIdentifier, isCompleted: false)

                // If a task is uncompleted while it is in Done, place it back into the
                // first non-Done column instead of leaving it visually completed.
                if isDoneColumnId(task.columnId), let fallbackColumn = firstNonDoneColumn {
                    applyLocalMove(identifier: task.reminderIdentifier, to: fallbackColumn.id)
                    try await service.moveReminder(identifier: task.reminderIdentifier, to: fallbackColumn.id, columns: columns)
                }
            }
        } catch {
            tasks = previousTasks
            logError("Set completion failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    private func applyLocalMove(identifier: String, to columnId: String) {
        guard let index = tasks.firstIndex(where: { $0.reminderIdentifier == identifier }) else { return }
        tasks[index].columnId = columnId
        if isDoneColumnId(columnId) {
            tasks[index].isCompleted = true
        }
    }

    private func applyLocalCompletion(identifier: String, isCompleted: Bool) {
        guard let index = tasks.firstIndex(where: { $0.reminderIdentifier == identifier }) else { return }
        tasks[index].isCompleted = isCompleted
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

    private func logError(_ message: String) {
        AppLogStore.shared.error(message)
    }

    private func sampleUITestTasks() -> [ReminderTask] {
        let backlog = columns.first(where: { $0.id == "backlog" })?.id ?? columns.first?.id ?? "backlog"
        let doing = columns.first(where: { $0.id == "doing" })?.id ?? backlog
        return [
            ReminderTask(
                reminderIdentifier: "ui-seed-backlog",
                title: "UITest Backlog Task",
                notes: "Seed task for UI tests",
                commentsMarkdown: "**Seed** markdown comment",
                matrixQuadrantId: nil,
                dueDate: nil,
                tags: ["seed", "mobile"],
                priority: 5,
                isCompleted: false,
                columnId: backlog
            ),
            ReminderTask(
                reminderIdentifier: "ui-seed-doing",
                title: "UITest Doing Task",
                notes: nil,
                commentsMarkdown: nil,
                matrixQuadrantId: nil,
                dueDate: nil,
                tags: ["seed", "doing"],
                priority: 1,
                isCompleted: false,
                columnId: doing
            )
        ]
    }
}
