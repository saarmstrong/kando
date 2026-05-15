import EventKit
import Foundation

enum ReminderStoreError: LocalizedError {
    case accessDenied
    case listCreationFailed
    case reminderNotFound
    case unsupportedCalendarSource

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Kanban Reminders does not have access to Reminders."
        case .listCreationFailed:
            return "Could not create the Kanban Reminders lists."
        case .reminderNotFound:
            return "The reminder could not be found. It may have been deleted in Reminders."
        case .unsupportedCalendarSource:
            return "No writable Reminders account was found. Please enable Reminders in Settings."
        }
    }
}

struct ReminderDraft: Equatable {
    var title: String
    var notes: String?
    var dueDate: Date?
    var priority: Int
    var isCompleted: Bool
    var column: KanbanColumn.Kind
}

final class ReminderStoreService {
    private let eventStore = EKEventStore()

    func requestAccessIfNeeded() async throws -> Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            return true
        case .notDetermined:
            return try await withCheckedThrowingContinuation { continuation in
                eventStore.requestFullAccessToReminders { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        case .denied, .restricted, .writeOnly:
            return false
        @unknown default:
            return false
        }
    }

    func loadBoard() async throws -> [ReminderTask] {
        guard try await requestAccessIfNeeded() else { throw ReminderStoreError.accessDenied }
        let lists = try ensureKanbanLists()

        var loaded: [ReminderTask] = []
        for column in KanbanColumn.allCases {
            guard let calendar = lists[column.kind] else { continue }
            let reminders = try await fetchReminders(in: calendar)
            loaded.append(contentsOf: reminders.map { makeTask(from: $0, column: column.kind) })
        }

        return loaded.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    @discardableResult
    func createReminder(_ draft: ReminderDraft) async throws -> ReminderTask {
        guard try await requestAccessIfNeeded() else { throw ReminderStoreError.accessDenied }
        let lists = try ensureKanbanLists()
        guard let calendar = lists[draft.column] else { throw ReminderStoreError.listCreationFailed }

        let reminder = EKReminder(eventStore: eventStore)
        apply(draft: draft, to: reminder)
        reminder.calendar = calendar
        try eventStore.save(reminder, commit: true)
        return makeTask(from: reminder, column: draft.column)
    }

    @discardableResult
    func updateReminder(identifier: String, with draft: ReminderDraft) async throws -> ReminderTask {
        guard try await requestAccessIfNeeded() else { throw ReminderStoreError.accessDenied }
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw ReminderStoreError.reminderNotFound
        }

        let lists = try ensureKanbanLists()
        guard let calendar = lists[draft.column] else { throw ReminderStoreError.listCreationFailed }

        apply(draft: draft, to: reminder)
        reminder.calendar = calendar
        try eventStore.save(reminder, commit: true)
        return makeTask(from: reminder, column: draft.column)
    }

    func moveReminder(identifier: String, to column: KanbanColumn.Kind) async throws {
        guard try await requestAccessIfNeeded() else { throw ReminderStoreError.accessDenied }
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw ReminderStoreError.reminderNotFound
        }
        let lists = try ensureKanbanLists()
        guard let calendar = lists[column] else { throw ReminderStoreError.listCreationFailed }
        reminder.calendar = calendar
        reminder.isCompleted = column == .done
        try eventStore.save(reminder, commit: true)
    }

    func setCompletion(identifier: String, isCompleted: Bool) async throws {
        guard try await requestAccessIfNeeded() else { throw ReminderStoreError.accessDenied }
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw ReminderStoreError.reminderNotFound
        }
        reminder.isCompleted = isCompleted
        try eventStore.save(reminder, commit: true)
    }

    private func ensureKanbanLists() throws -> [KanbanColumn.Kind: EKCalendar] {
        let existing = eventStore.calendars(for: .reminder)
        var lists: [KanbanColumn.Kind: EKCalendar] = [:]

        for column in KanbanColumn.allCases {
            if let calendar = existing.first(where: { $0.title == column.backingReminderListName }) {
                lists[column.kind] = calendar
                continue
            }

            guard let source = writableReminderSource() else { throw ReminderStoreError.unsupportedCalendarSource }
            let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
            calendar.title = column.backingReminderListName
            calendar.source = source
            try eventStore.saveCalendar(calendar, commit: true)
            lists[column.kind] = calendar
        }

        return lists
    }

    private func writableReminderSource() -> EKSource? {
        if let defaultSource = eventStore.defaultCalendarForNewReminders()?.source {
            return defaultSource
        }
        return eventStore.sources.first { source in
            source.sourceType == .calDAV || source.sourceType == .local || source.sourceType == .exchange
        }
    }

    private func fetchReminders(in calendar: EKCalendar) async throws -> [EKReminder] {
        let predicate = eventStore.predicateForReminders(in: [calendar])
        return try await withCheckedThrowingContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private func apply(draft: ReminderDraft, to reminder: EKReminder) {
        reminder.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Task" : draft.title
        reminder.notes = draft.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        reminder.priority = draft.priority
        reminder.isCompleted = draft.isCompleted

        if let dueDate = draft.dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        } else {
            reminder.dueDateComponents = nil
        }
    }

    private func makeTask(from reminder: EKReminder, column: KanbanColumn.Kind) -> ReminderTask {
        ReminderTask(
            reminderIdentifier: reminder.calendarItemIdentifier,
            title: reminder.title ?? "Untitled Task",
            notes: reminder.notes,
            dueDate: reminder.dueDateComponents?.date,
            priority: reminder.priority,
            isCompleted: reminder.isCompleted,
            column: column
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
