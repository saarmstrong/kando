import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct KanbanColumn: Identifiable, Hashable, Codable {
    var id: String
    var title: String
    var backingReminderListName: String

    static let defaultKanban: [KanbanColumn] = [
        KanbanColumn(id: "backlog", title: "Backlog", backingReminderListName: "Kanban - Backlog"),
        KanbanColumn(id: "doing", title: "Doing", backingReminderListName: "Kanban - Doing"),
        KanbanColumn(id: "done", title: "Done", backingReminderListName: "Kanban - Done")
    ]

    static let defaultMatrix: [KanbanColumn] = [
        KanbanColumn(id: "urgent-important", title: "Do First", backingReminderListName: "Matrix - Do First"),
        KanbanColumn(id: "not-urgent-important", title: "Schedule", backingReminderListName: "Matrix - Schedule"),
        KanbanColumn(id: "urgent-not-important", title: "Delegate", backingReminderListName: "Matrix - Delegate"),
        KanbanColumn(id: "not-urgent-not-important", title: "Eliminate", backingReminderListName: "Matrix - Eliminate")
    ]
}

enum AppColorMode: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var colorMode: AppColorMode = .system { didSet { save() } }
    @Published var kanbanColumns: [KanbanColumn] = KanbanColumn.defaultKanban { didSet { save() } }
    @Published var matrixQuadrants: [KanbanColumn] = KanbanColumn.defaultMatrix { didSet { save() } }
    @Published var matrixAssignments: [String: String] = [:] { didSet { save() } }
    @Published var hideCompletedTasks: Bool = false { didSet { save() } }

    private let defaults = UserDefaults.standard
    private let colorModeKey = "colorMode"
    private let kanbanColumnsKey = "kanbanColumns"
    private let matrixQuadrantsKey = "matrixQuadrants"
    private let matrixAssignmentsKey = "matrixAssignments"
    private let hideCompletedTasksKey = "hideCompletedTasks"

    init() {
        load()
    }

    func addKanbanColumn(title: String) {
        kanbanColumns.append(makeColumn(title: title, prefix: "Kanban"))
    }

    func addMatrixQuadrant(title: String) {
        matrixQuadrants.append(makeColumn(title: title, prefix: "Matrix"))
    }

    func removeKanbanColumn(at offsets: IndexSet) {
        guard kanbanColumns.count > offsets.count else { return }
        kanbanColumns.remove(atOffsets: offsets)
    }

    func removeMatrixQuadrant(at offsets: IndexSet) {
        guard matrixQuadrants.count > offsets.count else { return }
        let removedIds = offsets.map { matrixQuadrants[$0].id }
        matrixQuadrants.remove(atOffsets: offsets)
        matrixAssignments = matrixAssignments.filter { !removedIds.contains($0.value) }
    }

    func quadrantId(for task: ReminderTask) -> String {
        if let assigned = matrixAssignments[task.reminderIdentifier], matrixQuadrants.contains(where: { $0.id == assigned }) {
            return assigned
        }
        return suggestedQuadrantId(for: task)
    }

    func assign(_ task: ReminderTask, to quadrantId: String) {
        matrixAssignments[task.reminderIdentifier] = quadrantId
    }

    private func suggestedQuadrantId(for task: ReminderTask) -> String {
        guard !matrixQuadrants.isEmpty else { return "" }
        let isImportant = task.priority >= 5
        let isUrgent = task.dueDate.map { $0 <= Calendar.current.date(byAdding: .day, value: 2, to: Date())! } ?? false

        if isUrgent && isImportant { return matrixQuadrants[safe: 0]?.id ?? matrixQuadrants[0].id }
        if !isUrgent && isImportant { return matrixQuadrants[safe: 1]?.id ?? matrixQuadrants[0].id }
        if isUrgent && !isImportant { return matrixQuadrants[safe: 2]?.id ?? matrixQuadrants[0].id }
        return matrixQuadrants[safe: 3]?.id ?? matrixQuadrants[0].id
    }

    private func makeColumn(title: String, prefix: String) -> KanbanColumn {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Column" : title
        return KanbanColumn(
            id: UUID().uuidString,
            title: cleanTitle,
            backingReminderListName: "\(prefix) - \(cleanTitle) - \(UUID().uuidString.prefix(4))"
        )
    }

    private func load() {
        if let raw = defaults.string(forKey: colorModeKey), let mode = AppColorMode(rawValue: raw) {
            colorMode = mode
        }
        if let data = defaults.data(forKey: kanbanColumnsKey), let decoded = try? JSONDecoder().decode([KanbanColumn].self, from: data), !decoded.isEmpty {
            kanbanColumns = decoded
        }
        if let data = defaults.data(forKey: matrixQuadrantsKey), let decoded = try? JSONDecoder().decode([KanbanColumn].self, from: data), !decoded.isEmpty {
            matrixQuadrants = decoded
        }
        if let decoded = defaults.dictionary(forKey: matrixAssignmentsKey) as? [String: String] {
            matrixAssignments = decoded
        }
        hideCompletedTasks = defaults.bool(forKey: hideCompletedTasksKey)
    }

    private func save() {
        defaults.set(colorMode.rawValue, forKey: colorModeKey)
        if let data = try? JSONEncoder().encode(kanbanColumns) {
            defaults.set(data, forKey: kanbanColumnsKey)
        }
        if let data = try? JSONEncoder().encode(matrixQuadrants) {
            defaults.set(data, forKey: matrixQuadrantsKey)
        }
        defaults.set(matrixAssignments, forKey: matrixAssignmentsKey)
        defaults.set(hideCompletedTasks, forKey: hideCompletedTasksKey)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Color {
    static var appGroupedBackground: Color {
        #if os(iOS)
        Color(.systemGroupedBackground)
        #elseif os(macOS)
        Color(NSColor.windowBackgroundColor)
        #else
        Color(.background)
        #endif
    }

    static var appSecondaryGroupedBackground: Color {
        #if os(iOS)
        Color(.secondarySystemGroupedBackground)
        #elseif os(macOS)
        Color(NSColor.controlBackgroundColor)
        #else
        Color(.secondary)
        #endif
    }

    static var appCardBackground: Color {
        #if os(iOS)
        Color(.systemBackground)
        #elseif os(macOS)
        Color(NSColor.textBackgroundColor)
        #else
        Color(.background)
        #endif
    }
}
