import EventKit
import Foundation

enum ReminderStoreError: LocalizedError {
    case accessDenied
    case listCreationFailed
    case reminderNotFound
    case unsupportedCalendarSource

    var errorDescription: String? {
        switch self {
        case .accessDenied: return "Kanban Reminders does not have access to Reminders."
        case .listCreationFailed: return "Could not create the Reminders lists."
        case .reminderNotFound: return "The reminder could not be found. It may have been deleted in Reminders."
        case .unsupportedCalendarSource: return "No writable Reminders account was found. Please enable Reminders in Settings."
        }
    }
}

struct ReminderDraft: Equatable {
    var title: String
    var notes: String?
    var dueDate: Date?
    var priority: Int
    var isCompleted: Bool
    var columnId: String
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
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: granted) }
                }
            }
        case .denied, .restricted, .writeOnly:
            return false
        @unknown default:
            return false
        }
    }

    func loadBoard(columns: [KanbanColumn]) async throws -> [ReminderTask] {
        guard try await requestAccessIfNeeded() else { throw ReminderStoreError.accessDenied }
        let lists = try ensureLists(columns: columns)

        var loaded: [ReminderTask] = []
        for column in columns {
            guard let calendar = lists[column.id] else { continue }
            let reminders = try await fetchReminders(in: calendar)
            loaded.append(contentsOf: reminders.map { makeTask(from: $0, column: column) })
        }

        return loaded.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    @discardableResult
    func createReminder(_ draft: ReminderDraft, columns: [KanbanColumn]) async throws -> ReminderTask {
        guard try await requestAccessIfNeeded() else { throw ReminderStoreError.accessDenied }
        let lists = try ensureLists(columns: columns)
        guard let column = columns.first(where: { $0.id == draft.columnId }), let calendar = lists[draft.columnId] else {
            throw ReminderStoreError.listCreationFailed
        }

        let reminder = EKReminder(eventStore: eventStore)
        apply(draft: draft, to: reminder)
        reminder.calendar = calendar
        try eventStore.save(reminder, commit: true)
        return makeTask(from: reminder, column: column)
    }

    @discardableResult
    func updateReminder(identifier: String, with draft: ReminderDraft, columns: [KanbanColumn]) async throws -> ReminderTask {
        guard try await requestAccessIfNeeded() else { throw ReminderStoreError.accessDenied }
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw ReminderStoreError.reminderNotFound
        }
        let lists = try ensureLists(columns: columns)
        guard let column = columns.first(where: { $0.id == draft.columnId }), let calendar = lists[draft.columnId] else {
            throw ReminderStoreError.listCreationFailed
        }

        apply(draft: draft, to: reminder)
        reminder.calendar = calendar
        try eventStore.save(reminder, commit: true)
        return makeTask(from: reminder, column: column)
    }

    func moveReminder(identifier: String, to columnId: String, columns: [KanbanColumn]) async throws {
        guard try await requestAccessIfNeeded() else { throw ReminderStoreError.accessDenied }
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw ReminderStoreError.reminderNotFound
        }
        let lists = try ensureLists(columns: columns)
        guard let column = columns.first(where: { $0.id == columnId }), let calendar = lists[columnId] else {
            throw ReminderStoreError.listCreationFailed
        }
        reminder.calendar = calendar
        if column.title.localizedCaseInsensitiveContains("done") {
            reminder.isCompleted = true
        }
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

    private func ensureLists(columns: [KanbanColumn]) throws -> [String: EKCalendar] {
        let existing = eventStore.calendars(for: .reminder)
        var lists: [String: EKCalendar] = [:]

        for column in columns {
            if let calendar = existing.first(where: { $0.title == column.backingReminderListName }) {
                lists[column.id] = calendar
                continue
            }

            if let legacyCalendar = existing.first(where: { legacyListNames(for: column).contains($0.title) }) {
                legacyCalendar.title = column.backingReminderListName
                try eventStore.saveCalendar(legacyCalendar, commit: true)
                lists[column.id] = legacyCalendar
                continue
            }

            guard let source = writableReminderSource() else { throw ReminderStoreError.unsupportedCalendarSource }
            let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
            calendar.title = column.backingReminderListName
            calendar.source = source
            try eventStore.saveCalendar(calendar, commit: true)
            lists[column.id] = calendar
        }

        return lists
    }

    private func legacyListNames(for column: KanbanColumn) -> [String] {
        var names: [String] = []
        let appPrefix = "\(KanbanColumn.appListPrefix) - "
        if column.backingReminderListName.hasPrefix(appPrefix) {
            names.append(String(column.backingReminderListName.dropFirst(appPrefix.count)))
        }
        names.append("Kanban - \(column.title)")
        names.append("Matrix - \(column.title)")
        return Array(Set(names))
    }

    private func writableReminderSource() -> EKSource? {
        if let defaultSource = eventStore.defaultCalendarForNewReminders()?.source { return defaultSource }
        return eventStore.sources.first { $0.sourceType == .calDAV || $0.sourceType == .local || $0.sourceType == .exchange }
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

    private func makeTask(from reminder: EKReminder, column: KanbanColumn) -> ReminderTask {
        ReminderTask(
            reminderIdentifier: reminder.calendarItemIdentifier,
            title: reminder.title ?? "Untitled Task",
            notes: reminder.notes,
            dueDate: reminder.dueDateComponents?.date,
            priority: reminder.priority,
            isCompleted: reminder.isCompleted,
            columnId: column.id
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
