import Foundation
import SwiftUI

@MainActor
final class KanbanBoardViewModel: ObservableObject {
    @Published private(set) var tasks: [ReminderTask] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasPermission = true

    let columns = KanbanColumn.allCases
    private let service: ReminderStoreService

    init(service: ReminderStoreService = ReminderStoreService()) {
        self.service = service
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            hasPermission = try await service.requestAccessIfNeeded()
            guard hasPermission else { return }
            tasks = try await service.loadBoard()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func tasks(in column: KanbanColumn.Kind) -> [ReminderTask] {
        tasks.filter { $0.column == column }
    }

    func saveTask(identifier: String?, draft: ReminderDraft) async {
        do {
            if let identifier {
                _ = try await service.updateReminder(identifier: identifier, with: draft)
            } else {
                _ = try await service.createReminder(draft)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func move(_ task: ReminderTask, to column: KanbanColumn.Kind) async {
        guard task.column != column else { return }
        do {
            try await service.moveReminder(identifier: task.reminderIdentifier, to: column)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func move(identifier: String, to column: KanbanColumn.Kind) async {
        guard let task = tasks.first(where: { $0.reminderIdentifier == identifier }) else { return }
        await move(task, to: column)
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
