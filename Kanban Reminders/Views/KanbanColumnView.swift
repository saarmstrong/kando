import SwiftUI

struct KanbanColumnView: View {
    let column: KanbanColumn
    let tasks: [ReminderTask]
    let allColumns: [KanbanColumn]
    var shortcutHint: String? = nil
    var isCollapsed = false
    var expandedWidth: CGFloat = 310
    let onToggleCollapse: () -> Void
    let onAdd: () -> Void
    let onEdit: (ReminderTask) -> Void
    let onMove: (ReminderTask, String) -> Void
    let onComplete: (ReminderTask, Bool) -> Void
    let onDropIdentifier: (String) -> Void

    @State private var isDropTargeted = false

    var body: some View {
        Group {
            if isCollapsed {
                collapsedColumn
            } else {
                expandedColumn
            }
        }
        .animation(.snappy(duration: 0.2), value: isCollapsed)
    }

    private var expandedColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(column.title)
                    .font(.headline)
                    .accessibilityIdentifier("KanbanColumnTitle-\(column.id)")
                Spacer()
                countBadge
                Button(action: onToggleCollapse) {
                    Image(systemName: "sidebar.leading")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Collapse column")
                .accessibilityLabel("Collapse \(column.title)")
            }

            Button(action: onAdd) {
                HStack {
                    Label("Add", systemImage: "plus")
                    Spacer()
                    if let shortcutHint {
                        Text(shortcutHint)
                            .font(.caption.monospaced().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.thinMaterial, in: Capsule())
                    }
                }
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
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .draggable(task.reminderIdentifier) {
                        TaskCardView(
                            task: task,
                            allColumns: allColumns,
                            wipAccentColor: wipStatus == .normal ? columnColor : wipStatus.accentColor,
                            onEdit: {},
                            onMove: { _ in },
                            onComplete: { _ in }
                        )
                        .frame(width: 280)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: expandedWidth, alignment: .top)
        .frame(minHeight: 500, alignment: .top)
        .columnContainer(background: columnBackground, isDropTargeted: isDropTargeted)
        .dropDestination(for: String.self, action: handleDrop, isTargeted: { isDropTargeted = $0 })
    }

    private var collapsedColumn: some View {
        Button(action: onToggleCollapse) {
            VStack(spacing: 12) {
                Image(systemName: "sidebar.trailing")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text(column.title)
                    .font(.headline)
                    .accessibilityIdentifier("KanbanColumnTitle-\(column.id)")
                    .lineLimit(1)
                    .rotationEffect(.degrees(-90))
                    .fixedSize()
                    .frame(width: 28, height: 170)

                countBadge
                    .rotationEffect(.degrees(-90))

                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
            .frame(width: 54, alignment: .top)
            .frame(minHeight: 500, alignment: .top)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .columnContainer(background: columnBackground, isDropTargeted: isDropTargeted)
        .dropDestination(for: String.self, action: handleDrop, isTargeted: { isDropTargeted = $0 })
        .help("Expand \(column.title)")
        .accessibilityLabel("Expand \(column.title), \(countText) tasks")
    }

    private var countBadge: some View {
        Text(countText)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(wipStatus.accentColor.opacity(wipStatus == .normal ? 0 : 0.18), in: Capsule())
            .foregroundStyle(wipStatus == .normal ? .secondary : wipStatus.accentColor)
    }

    private func handleDrop(_ identifiers: [String], _ location: CGPoint) -> Bool {
        guard !identifiers.isEmpty else { return false }
        identifiers.forEach(onDropIdentifier)
        return true
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

private extension View {
    func columnContainer(background: Color, isDropTargeted: Bool) -> some View {
        self
            .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isDropTargeted ? Color.accentColor : .clear, lineWidth: 3)
            )
            .contentShape(Rectangle())
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
