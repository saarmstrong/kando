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
                Text("\(tasks.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
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
        column.title.localizedCaseInsensitiveContains("done") ? Color.green.opacity(0.12) : Color.appSecondaryGroupedBackground
    }
}
