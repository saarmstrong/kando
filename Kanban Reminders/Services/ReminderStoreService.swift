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
    var commentsMarkdown: String?
    var matrixQuadrantId: String?
    var dueDate: Date?
    var tags: [String] = []
    var priority: Int
    var isCompleted: Bool
    var columnId: String
}

final class ReminderStoreService {
    private let eventStore = EKEventStore()

    func requestAccessIfNeeded() async throws -> Bool {
        logVerbose("Checking Reminders authorization status")
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            logVerbose("Reminders authorization: full access")
            return true
        case .notDetermined:
            logInfo("Requesting Reminders access")
            return try await withCheckedThrowingContinuation { continuation in
                eventStore.requestFullAccessToReminders { granted, error in
                    if let error {
                        Self.logError("Reminders access request failed: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                    } else {
                        Self.logInfo("Reminders access request result: \(granted ? "granted" : "denied")")
                        continuation.resume(returning: granted)
                    }
                }
            }
        case .denied, .restricted, .writeOnly:
            logInfo("Reminders authorization unavailable")
            return false
        @unknown default:
            return false
        }
    }

    func loadBoard(columns: [KanbanColumn]) async throws -> [ReminderTask] {
        logVerbose("Loading board for \(columns.count) columns")
        guard try await requestAccessIfNeeded() else { throw ReminderStoreError.accessDenied }
        // Pull the latest Calendar/Reminders metadata before reading so changes made
        // in the native Reminders app are reflected without writing stale state back.
        eventStore.refreshSourcesIfNecessary()
        let lists = try ensureLists(columns: columns)

        let doneColumn = columns.first(where: isDoneColumn)
        let doneCalendar = doneColumn.flatMap { lists[$0.id] }

        var loaded: [ReminderTask] = []
        for column in columns {
            guard let calendar = lists[column.id] else { continue }
            let reminders = try await fetchReminders(in: calendar)
            for reminder in reminders {
                if reminder.isCompleted,
                   !isDoneColumn(column),
                   let doneColumn,
                   let doneCalendar {
                    // Native completion is canonical. If a reminder is completed
                    // from Apple Reminders or another device while it is still in
                    // Backlog/Doing, move it to the Done list on refresh so the
                    // board and Reminders stay consistent.
                    reminder.calendar = doneCalendar
                    try eventStore.save(reminder, commit: true)
                    logInfo("Moved completed reminder '\(reminder.title ?? "Untitled Task")' to \(doneColumn.title) during refresh")
                    loaded.append(makeTask(from: reminder, column: doneColumn))
                } else {
                    loaded.append(makeTask(from: reminder, column: column))
                }
            }
        }

        logVerbose("Loaded \(loaded.count) reminders from EventKit")
        return loaded.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    @discardableResult
    func createReminder(_ draft: ReminderDraft, columns: [KanbanColumn]) async throws -> ReminderTask {
        logVerbose("Creating reminder in column \(draft.columnId)")
        guard try await requestAccessIfNeeded() else { throw ReminderStoreError.accessDenied }
        let lists = try ensureLists(columns: columns)
        guard let column = columns.first(where: { $0.id == draft.columnId }), let calendar = lists[draft.columnId] else {
            throw ReminderStoreError.listCreationFailed
        }

        let reminder = EKReminder(eventStore: eventStore)
        apply(draft: draft, to: reminder)
        reminder.calendar = calendar
        try eventStore.save(reminder, commit: true)
        logInfo("Created reminder '\(reminder.title ?? "Untitled Task")' in \(column.title)")
        return makeTask(from: reminder, column: column)
    }

    @discardableResult
    func updateReminder(identifier: String, with draft: ReminderDraft, columns: [KanbanColumn]) async throws -> ReminderTask {
        logVerbose("Updating reminder \(identifier) in column \(draft.columnId)")
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
        logInfo("Updated reminder '\(reminder.title ?? "Untitled Task")'")
        return makeTask(from: reminder, column: column)
    }

    func moveReminder(identifier: String, to columnId: String, columns: [KanbanColumn]) async throws {
        logVerbose("Moving reminder \(identifier) to column \(columnId)")
        guard try await requestAccessIfNeeded() else { throw ReminderStoreError.accessDenied }
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw ReminderStoreError.reminderNotFound
        }
        eventStore.refreshSourcesIfNecessary()
        let lists = try ensureLists(columns: columns)
        guard let column = columns.first(where: { $0.id == columnId }), let calendar = lists[columnId] else {
            throw ReminderStoreError.listCreationFailed
        }
        reminder.calendar = calendar
        // Moving to the Done column should be a single EventKit save that both
        // changes the backing Reminders list and marks the native reminder
        // complete. Use id/title/backing-list checks so this still works if the
        // visible Done column has been renamed.
        if isDoneColumn(column) {
            reminder.isCompleted = true
        }
        try eventStore.save(reminder, commit: true)
        logInfo("Moved reminder '\(reminder.title ?? "Untitled Task")' to \(column.title)\(isDoneColumn(column) ? " and marked complete" : "")")
        eventStore.refreshSourcesIfNecessary()
    }

    func setCompletion(identifier: String, isCompleted: Bool) async throws {
        logVerbose("Setting completion for reminder \(identifier) to \(isCompleted)")
        guard try await requestAccessIfNeeded() else { throw ReminderStoreError.accessDenied }
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw ReminderStoreError.reminderNotFound
        }
        reminder.isCompleted = isCompleted
        try eventStore.save(reminder, commit: true)
        logInfo("Set reminder '\(reminder.title ?? "Untitled Task")' completion to \(isCompleted)")
    }

    func reminderListNames() async throws -> [String] {
        logVerbose("Loading Reminders list names")
        guard try await requestAccessIfNeeded() else { throw ReminderStoreError.accessDenied }
        eventStore.refreshSourcesIfNecessary()
        let names = eventStore.calendars(for: .reminder)
            .map(\.title)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        logVerbose("Loaded \(names.count) Reminders lists")
        return names
    }

    func setMatrixQuadrant(identifier: String, quadrantId: String?) async throws {
        guard try await requestAccessIfNeeded() else { throw ReminderStoreError.accessDenied }
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw ReminderStoreError.reminderNotFound
        }
        let content = ReminderContentCodec.splitNotesAndComments(reminder.notes)
        reminder.notes = ReminderContentCodec.combinedNotes(
            notes: content.notes,
            commentsMarkdown: content.commentsMarkdown,
            matrixQuadrantId: quadrantId
        )
        try eventStore.save(reminder, commit: true)
    }

    func renameReminderList(from oldTitle: String, to newTitle: String) async throws {
        guard try await requestAccessIfNeeded() else { throw ReminderStoreError.accessDenied }
        eventStore.refreshSourcesIfNecessary()
        let trimmedNewTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNewTitle.isEmpty else { throw ReminderStoreError.listCreationFailed }
        guard let calendar = eventStore.calendars(for: .reminder).first(where: { $0.title == oldTitle }) else {
            throw ReminderStoreError.listCreationFailed
        }
        calendar.title = trimmedNewTitle
        try eventStore.saveCalendar(calendar, commit: true)
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

    private func isDoneColumn(_ column: KanbanColumn) -> Bool {
        column.id.localizedCaseInsensitiveContains("done") ||
        column.title.localizedCaseInsensitiveContains("done") ||
        column.backingReminderListName.localizedCaseInsensitiveContains("done")
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
        let selectedTags = ReminderTagParser.normalize(draft.tags)
        let cleanTitle = (textByRemovingUnselectedHashtags(draft.title, keeping: selectedTags) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.title = cleanTitle.isEmpty ? "Untitled Task" : cleanTitle
        let existingContent = ReminderContentCodec.splitNotesAndComments(reminder.notes)
        reminder.notes = ReminderContentCodec.combinedNotes(
            notes: notesWithTags(draft.notes, tags: selectedTags),
            commentsMarkdown: textByRemovingUnselectedHashtags(draft.commentsMarkdown, keeping: selectedTags),
            matrixQuadrantId: draft.matrixQuadrantId ?? existingContent.matrixQuadrantId
        )
        reminder.priority = draft.priority
        reminder.isCompleted = draft.isCompleted

        if let dueDate = draft.dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        } else {
            reminder.dueDateComponents = nil
        }
    }

    private func notesWithTags(_ notes: String?, tags: [String]) -> String? {
        let normalizedTags = ReminderTagParser.normalize(tags)
        let cleanNotes = textByRemovingUnselectedHashtags(notes, keeping: normalizedTags)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalizedTags.isEmpty else { return cleanNotes.nilIfEmpty }
        let existingTags = ReminderTagParser.tags(in: cleanNotes)
        let missingTags = normalizedTags.filter { !existingTags.contains($0) }
        guard !missingTags.isEmpty else { return cleanNotes.nilIfEmpty }
        let tagLine = missingTags.map { "#\($0)" }.joined(separator: " ")
        return cleanNotes.isEmpty ? tagLine : "\(cleanNotes)\n\n\(tagLine)"
    }

    private func textByRemovingUnselectedHashtags(_ text: String?, keeping selectedTags: [String]) -> String? {
        guard let text, !text.isEmpty else { return nil }
        let selectedTags = Set(ReminderTagParser.normalize(selectedTags))
        let pattern = #"(?<![\p{L}\p{N}_])#([\p{L}\p{N}][\p{L}\p{N}_-]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).reversed()
        for match in matches {
            guard let tagRange = Range(match.range(at: 1), in: text),
                  let fullRange = Range(match.range(at: 0), in: result) else { continue }
            let tag = ReminderTagParser.normalize([String(text[tagRange])]).first ?? ""
            if !selectedTags.contains(tag) {
                result.removeSubrange(fullRange)
            }
        }
        return result
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private func logVerbose(_ message: String) {
        Self.logVerbose(message)
    }

    private func logInfo(_ message: String) {
        Self.logInfo(message)
    }

    private static func logVerbose(_ message: String) {
        Task { @MainActor in AppLogStore.shared.verbose(message) }
    }

    private static func logInfo(_ message: String) {
        Task { @MainActor in AppLogStore.shared.info(message) }
    }

    private static func logError(_ message: String) {
        Task { @MainActor in AppLogStore.shared.error(message) }
    }

    private func makeTask(from reminder: EKReminder, column: KanbanColumn) -> ReminderTask {
        let content = ReminderContentCodec.splitNotesAndComments(reminder.notes)
        return ReminderTask(
            reminderIdentifier: reminder.calendarItemIdentifier,
            title: reminder.title ?? "Untitled Task",
            notes: content.notes,
            commentsMarkdown: content.commentsMarkdown,
            matrixQuadrantId: content.matrixQuadrantId,
            dueDate: reminder.dueDateComponents?.date,
            tags: ReminderTagParser.normalize(ReminderTagParser.tags(in: reminder.title) + ReminderTagParser.tags(in: content.notes) + ReminderTagParser.tags(in: content.commentsMarkdown)),
            priority: reminder.priority,
            isCompleted: reminder.isCompleted,
            columnId: column.id
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
