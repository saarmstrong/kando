import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct KanbanColumn: Identifiable, Hashable, Codable {
    var id: String
    var title: String
    var backingReminderListName: String
    var wipLimit: Int? = nil
    var isHidden: Bool = false
    var colorHex: String? = nil

    init(id: String, title: String, backingReminderListName: String, wipLimit: Int? = nil, isHidden: Bool = false, colorHex: String? = nil) {
        self.id = id
        self.title = title
        self.backingReminderListName = backingReminderListName
        self.wipLimit = wipLimit
        self.isHidden = isHidden
        self.colorHex = colorHex
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, backingReminderListName, wipLimit, isHidden, colorHex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        backingReminderListName = try container.decode(String.self, forKey: .backingReminderListName)
        wipLimit = try container.decodeIfPresent(Int.self, forKey: .wipLimit)
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex)
    }

    static let appListPrefix = "Kando"
    static let kanbanListPrefix = "Kando - Kanban"
    static let matrixListPrefix = "Kando - Matrix"

    static let defaultKanban: [KanbanColumn] = [
        KanbanColumn(id: "backlog", title: "Backlog", backingReminderListName: "Kando - Kanban - Backlog"),
        KanbanColumn(id: "doing", title: "Doing", backingReminderListName: "Kando - Kanban - Doing"),
        KanbanColumn(id: "done", title: "Done", backingReminderListName: "Kando - Kanban - Done")
    ]

    static let defaultMatrix: [KanbanColumn] = [
        KanbanColumn(id: "urgent-important", title: "Do First", backingReminderListName: "Kando - Matrix - Do First"),
        KanbanColumn(id: "not-urgent-important", title: "Schedule", backingReminderListName: "Kando - Matrix - Schedule"),
        KanbanColumn(id: "urgent-not-important", title: "Delegate", backingReminderListName: "Kando - Matrix - Delegate"),
        KanbanColumn(id: "not-urgent-not-important", title: "Eliminate", backingReminderListName: "Kando - Matrix - Eliminate")
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
        #if DEBUG
        if ProcessInfo.processInfo.environment["KANDO_UI_TESTING"] == "1" || ProcessInfo.processInfo.arguments.contains("-KANDO_UI_TESTING") {
            colorMode = .system
            kanbanColumns = KanbanColumn.defaultKanban
            matrixQuadrants = KanbanColumn.defaultMatrix
            matrixAssignments = [:]
            hideCompletedTasks = false
        } else {
            load()
        }
        #else
        load()
        #endif
    }

    func addKanbanColumn(title: String) {
        kanbanColumns.append(makeColumn(title: title, prefix: KanbanColumn.kanbanListPrefix))
    }

    func addMatrixQuadrant(title: String) {
        matrixQuadrants.append(makeColumn(title: title, prefix: KanbanColumn.matrixListPrefix))
    }

    func removeKanbanColumn(at offsets: IndexSet) {
        guard kanbanColumns.count > offsets.count else { return }
        kanbanColumns.remove(atOffsets: offsets)
    }

    func removeKanbanColumn(id: String) {
        guard kanbanColumns.count > 1 else { return }
        kanbanColumns.removeAll { $0.id == id }
    }

    func moveKanbanColumn(from source: IndexSet, to destination: Int) {
        kanbanColumns.move(fromOffsets: source, toOffset: destination)
    }

    func moveKanbanColumn(id draggedId: String, before targetId: String) {
        guard draggedId != targetId,
              let source = kanbanColumns.firstIndex(where: { $0.id == draggedId }),
              let target = kanbanColumns.firstIndex(where: { $0.id == targetId }) else { return }
        let column = kanbanColumns.remove(at: source)
        let adjustedTarget = source < target ? target - 1 : target
        kanbanColumns.insert(column, at: adjustedTarget)
    }

    func moveKanbanColumnUp(id: String) {
        guard let index = kanbanColumns.firstIndex(where: { $0.id == id }), index > 0 else { return }
        kanbanColumns.swapAt(index, index - 1)
    }

    func moveKanbanColumnDown(id: String) {
        guard let index = kanbanColumns.firstIndex(where: { $0.id == id }), index < kanbanColumns.count - 1 else { return }
        kanbanColumns.swapAt(index, index + 1)
    }

    func removeMatrixQuadrant(at offsets: IndexSet) {
        guard matrixQuadrants.count > offsets.count else { return }
        let removedIds = offsets.map { matrixQuadrants[$0].id }
        matrixQuadrants.remove(atOffsets: offsets)
        matrixAssignments = matrixAssignments.filter { !removedIds.contains($0.value) }
    }

    func removeMatrixQuadrant(id: String) {
        guard matrixQuadrants.count > 1 else { return }
        matrixQuadrants.removeAll { $0.id == id }
        matrixAssignments = matrixAssignments.filter { $0.value != id }
    }

    func quadrantId(for task: ReminderTask) -> String {
        if let synced = task.matrixQuadrantId, matrixQuadrants.contains(where: { $0.id == synced }) {
            return synced
        }
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
            backingReminderListName: "\(prefix) - \(cleanTitle) - \(UUID().uuidString.prefix(4))",
            wipLimit: nil
        )
    }

    private func load() {
        if let raw = defaults.string(forKey: colorModeKey), let mode = AppColorMode(rawValue: raw) {
            colorMode = mode
        }
        if let data = defaults.data(forKey: kanbanColumnsKey), let decoded = try? JSONDecoder().decode([KanbanColumn].self, from: data), !decoded.isEmpty {
            kanbanColumns = decoded.map { migrateListPrefix(for: $0, viewPrefix: KanbanColumn.kanbanListPrefix) }
        } else {
            kanbanColumns = KanbanColumn.defaultKanban
        }
        if let data = defaults.data(forKey: matrixQuadrantsKey), let decoded = try? JSONDecoder().decode([KanbanColumn].self, from: data), !decoded.isEmpty {
            matrixQuadrants = decoded.map { migrateListPrefix(for: $0, viewPrefix: KanbanColumn.matrixListPrefix) }
        } else {
            matrixQuadrants = KanbanColumn.defaultMatrix
        }
        if let decoded = defaults.dictionary(forKey: matrixAssignmentsKey) as? [String: String] {
            matrixAssignments = decoded
        }
        hideCompletedTasks = defaults.bool(forKey: hideCompletedTasksKey)
    }

    private func migrateListPrefix(for column: KanbanColumn, viewPrefix: String) -> KanbanColumn {
        guard !column.backingReminderListName.hasPrefix("\(KanbanColumn.appListPrefix) - ") else { return column }
        var migrated = column
        if column.backingReminderListName.hasPrefix("Kanban - ") {
            migrated.backingReminderListName = column.backingReminderListName.replacingOccurrences(of: "Kanban", with: KanbanColumn.kanbanListPrefix, options: [], range: column.backingReminderListName.startIndex..<column.backingReminderListName.index(column.backingReminderListName.startIndex, offsetBy: "Kanban".count))
        } else if column.backingReminderListName.hasPrefix("Matrix - ") {
            migrated.backingReminderListName = column.backingReminderListName.replacingOccurrences(of: "Matrix", with: KanbanColumn.matrixListPrefix, options: [], range: column.backingReminderListName.startIndex..<column.backingReminderListName.index(column.backingReminderListName.startIndex, offsetBy: "Matrix".count))
        } else {
            migrated.backingReminderListName = "\(viewPrefix) - \(column.title)"
        }
        return migrated
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

    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b: Double
        switch cleaned.count {
        case 6:
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double(value & 0x0000FF) / 255
        default:
            r = 0.25; g = 0.45; b = 0.9
        }
        self.init(red: r, green: g, blue: b)
    }

    var hexString: String? {
        #if os(iOS)
        let native = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard native.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        #elseif os(macOS)
        guard let native = NSColor(self).usingColorSpace(.deviceRGB) else { return nil }
        let r = native.redComponent, g = native.greenComponent, b = native.blueComponent
        #else
        return nil
        #endif
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
