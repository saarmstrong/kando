import SwiftUI

struct KanbanColumnView: View {
    let column: KanbanColumn
    let tasks: [ReminderTask]
    let allColumns: [KanbanColumn]
    let onAdd: () -> Void
    let onEdit: (ReminderTask) -> Void
    let onMove: (ReminderTask, String) -> Void
    let onComplete: (ReminderTask, Bool) -> Void
    let onDropIdentifier: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(column.title)
                    .font(.headline)
                Spacer()
                Text(countText)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(wipStatus.accentColor.opacity(wipStatus == .normal ? 0 : 0.18), in: Capsule())
                    .foregroundStyle(wipStatus == .normal ? .secondary : wipStatus.accentColor)
            }

            Button(action: onAdd) {
                Label("Add", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            LazyVStack(spacing: 10) {
                ForEach(tasks) { task in
                    TaskCardView(
                        task: task,
                        allColumns: allColumns,
                        wipAccentColor: wipStatus == .normal ? columnColor : wipStatus.accentColor,
                        onEdit: { onEdit(task) },
                        onMove: { onMove(task, $0) },
                        onComplete: { onComplete(task, $0) }
                    )
                    .draggable(task.reminderIdentifier)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 310, alignment: .top)
        .frame(minHeight: 500, alignment: .top)
        .background(columnBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .dropDestination(for: String.self) { identifiers, _ in
            identifiers.first.map(onDropIdentifier)
            return true
        }
    }

    private var columnBackground: Color {
        if wipStatus != .normal {
            return wipStatus.accentColor.opacity(0.12)
        }
        if let columnColor {
            return columnColor.opacity(0.14)
        }
        return column.title.localizedCaseInsensitiveContains("done") ? Color.green.opacity(0.12) : Color.appSecondaryGroupedBackground
    }

    private var activeTaskCount: Int {
        tasks.filter { !$0.isCompleted }.count
    }

    private var countText: String {
        if let limit = column.wipLimit {
            return "\(activeTaskCount)/\(limit)"
        }
        return "\(tasks.count)"
    }

    private var columnColor: Color? {
        column.colorHex.map(Color.init(hex:))
    }

    private var wipStatus: WIPStatus {
        guard let limit = column.wipLimit, limit > 0 else { return .normal }
        if activeTaskCount >= limit { return .atLimit }
        if activeTaskCount >= max(1, Int(ceil(Double(limit) * 0.8))) { return .nearLimit }
        return .normal
    }
}

private enum WIPStatus: Equatable {
    case normal
    case nearLimit
    case atLimit

    var accentColor: Color {
        switch self {
        case .normal: return .clear
        case .nearLimit: return .orange
        case .atLimit: return .red
        }
    }
}
