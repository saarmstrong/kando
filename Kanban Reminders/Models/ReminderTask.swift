import Foundation

struct ReminderTask: Identifiable, Hashable {
    let reminderIdentifier: String
    var title: String
    var notes: String?
    var dueDate: Date?
    var priority: Int
    var isCompleted: Bool
    var columnId: String

    var id: String { reminderIdentifier }
}
