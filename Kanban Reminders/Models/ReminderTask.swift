import Foundation

struct ReminderTask: Identifiable, Hashable {
    let reminderIdentifier: String
    var title: String
    var notes: String?
    var commentsMarkdown: String?
    var matrixQuadrantId: String?
    var dueDate: Date?
    var priority: Int
    var isCompleted: Bool
    var columnId: String

    var id: String { reminderIdentifier }

    var hasMarkdownComments: Bool {
        commentsMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var trimmedMarkdownComments: String? {
        commentsMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

enum ReminderContentCodec {
    static let commentsHeader = "---\nKando Comments (Markdown):"
    static let metadataHeader = "---\nKando Metadata:"
    private static let matrixKey = "matrixQuadrantId"

    static func splitNotesAndComments(_ rawNotes: String?) -> (notes: String?, commentsMarkdown: String?, matrixQuadrantId: String?) {
        guard var rawNotes, !rawNotes.isEmpty else { return (nil, nil, nil) }

        let matrixQuadrantId: String?
        if let metadataRange = rawNotes.range(of: sectionSeparator + metadataHeader + "\n") ?? rawNotes.range(of: metadataHeader + "\n") {
            let metadata = String(rawNotes[metadataRange.upperBound...])
            matrixQuadrantId = metadata
                .split(separator: "\n")
                .first { $0.hasPrefix("\(matrixKey):") }
                .map { String($0.dropFirst("\(matrixKey):".count)).trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.nilIfEmpty }
            rawNotes = String(rawNotes[..<metadataRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            matrixQuadrantId = nil
        }

        guard let range = rawNotes.range(of: sectionSeparator + commentsHeader + "\n") ?? rawNotes.range(of: commentsHeader + "\n") else {
            return (rawNotes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty, nil, matrixQuadrantId)
        }

        let plainNotes = String(rawNotes[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let comments = String(rawNotes[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        return (plainNotes, comments, matrixQuadrantId)
    }

    static func combinedNotes(notes: String?, commentsMarkdown: String?, matrixQuadrantId: String?) -> String? {
        let cleanNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let cleanComments = commentsMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let cleanMatrix = matrixQuadrantId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        var sections: [String] = []
        if let cleanNotes { sections.append(cleanNotes) }
        if let cleanComments { sections.append("\(commentsHeader)\n\(cleanComments)") }
        if let cleanMatrix { sections.append("\(metadataHeader)\n\(matrixKey): \(cleanMatrix)") }
        return sections.isEmpty ? nil : sections.joined(separator: sectionSeparator)
    }

    private static var sectionSeparator: String { "\n\n" }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

enum TaskSortOption: String, CaseIterable, Identifiable {
    case title
    case priorityHighToLow
    case priorityLowToHigh
    case dueSoonest
    case dueLatest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .title: return "Title"
        case .priorityHighToLow: return "Priority: High to Low"
        case .priorityLowToHigh: return "Priority: Low to High"
        case .dueSoonest: return "Due Date: Soonest"
        case .dueLatest: return "Due Date: Latest"
        }
    }
}

enum TaskFilterOption: String, CaseIterable, Identifiable {
    case all
    case highPriority
    case hasPriority
    case dueToday
    case dueThisWeek
    case overdue
    case noDueDate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Tasks"
        case .highPriority: return "High Priority"
        case .hasPriority: return "Any Priority"
        case .dueToday: return "Due Today"
        case .dueThisWeek: return "Due This Week"
        case .overdue: return "Overdue"
        case .noDueDate: return "No Due Date"
        }
    }
}

extension Array where Element == ReminderTask {
    func filtered(_ filter: TaskFilterOption) -> [ReminderTask] {
        let calendar = Calendar.current
        let now = Date()
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: now) ?? now

        return self.filter { task in
            switch filter {
            case .all:
                return true
            case .highPriority:
                return task.priority == 9
            case .hasPriority:
                return task.priority > 0
            case .dueToday:
                return task.dueDate.map { calendar.isDateInToday($0) } ?? false
            case .dueThisWeek:
                return task.dueDate.map { $0 >= calendar.startOfDay(for: now) && $0 <= endOfWeek } ?? false
            case .overdue:
                return task.dueDate.map { $0 < calendar.startOfDay(for: now) && !task.isCompleted } ?? false
            case .noDueDate:
                return task.dueDate == nil
            }
        }
    }

    func sorted(by option: TaskSortOption) -> [ReminderTask] {
        sorted { lhs, rhs in
            switch option {
            case .title:
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .priorityHighToLow:
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .priorityLowToHigh:
                if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .dueSoonest:
                switch (lhs.dueDate, rhs.dueDate) {
                case let (l?, r?): return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            case .dueLatest:
                switch (lhs.dueDate, rhs.dueDate) {
                case let (l?, r?): return l > r
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            }
        }
    }

    func filteredAndSorted(filter: TaskFilterOption, sort: TaskSortOption) -> [ReminderTask] {
        filtered(filter).sorted(by: sort)
    }
}
