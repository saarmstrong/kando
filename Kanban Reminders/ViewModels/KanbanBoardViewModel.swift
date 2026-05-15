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
            if let identifier {
                _ = try await service.updateReminder(identifier: identifier, with: draft, columns: columns)
            } else {
                _ = try await service.createReminder(draft, columns: columns)
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
            try await service.setCompletion(identifier: task.reminderIdentifier, isCompleted: isCompleted)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
