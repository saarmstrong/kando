import SwiftUI

struct EisenhowerMatrixView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var viewModel: KanbanBoardViewModel
    @State private var detailTask: ReminderTask?
    @State private var sortOption: TaskSortOption = .priorityHighToLow
    @State private var filterOption: TaskFilterOption = .all

    private let grid = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.hasPermission {
                    matrix
                } else {
                    PermissionDeniedView()
                }
            }
            .navigationTitle("Matrix")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    sortFilterMenu
                    Button { Task { await viewModel.load() } } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .sheet(item: $detailTask) { task in
                MatrixTaskDetailView(
                    task: task,
                    quadrants: settings.matrixQuadrants,
                    currentQuadrantId: settings.quadrantId(for: task),
                    onMove: { targetId in settings.assign(task, to: targetId) },
                    onComplete: { completed in Task { await viewModel.setCompletion(task, isCompleted: completed) } }
                )
                .presentationDetents([.medium, .large])
            }
            .overlay {
                if viewModel.isLoading && viewModel.tasks.isEmpty {
                    ProgressView("Loading Reminders…")
                }
            }
        }
    }

    private var sortFilterMenu: some View {
        Menu {
            Picker("Filter", selection: $filterOption) {
                ForEach(TaskFilterOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }

            Picker("Sort", selection: $sortOption) {
                ForEach(TaskSortOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
        } label: {
            Label("Sort and Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    private var matrix: some View {
        ScrollView {
            LazyVGrid(columns: grid, spacing: 12) {
                ForEach(settings.matrixQuadrants) { quadrant in
                    MatrixQuadrantView(
                        quadrant: quadrant,
                        tasks: tasks(in: quadrant),
                        allQuadrants: settings.matrixQuadrants,
                        onLongPress: { detailTask = $0 },
                        onMove: { task, quadrantId in settings.assign(task, to: quadrantId) },
                        onDropIdentifier: { identifier in
                            if let task = viewModel.tasks.first(where: { $0.reminderIdentifier == identifier }) {
                                settings.assign(task, to: quadrant.id)
                            }
                        }
                    )
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func tasks(in quadrant: KanbanColumn) -> [ReminderTask] {
        viewModel.tasks
            .filter { settings.quadrantId(for: $0) == quadrant.id }
            .filteredAndSorted(filter: filterOption, sort: sortOption)
    }
}

struct MatrixQuadrantView: View {
    let quadrant: KanbanColumn
    let tasks: [ReminderTask]
    let allQuadrants: [KanbanColumn]
    let onLongPress: (ReminderTask) -> Void
    let onMove: (ReminderTask, String) -> Void
    let onDropIdentifier: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(quadrant.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text("\(tasks.count)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.thinMaterial, in: Capsule())
            }

            Divider()

            if tasks.isEmpty {
                ContentUnavailableView("No Tasks", systemImage: "tray")
                    .font(.caption)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(tasks) { task in
                        MatrixTaskSummaryCard(task: task)
                            .draggable(task.reminderIdentifier)
                            .onLongPressGesture { onLongPress(task) }
                            .contextMenu {
                                Button("Details", systemImage: "info.circle") { onLongPress(task) }
                                Menu("Move to…") {
                                    ForEach(allQuadrants) { target in
                                        Button(target.title) { onMove(task, target.id) }
                                            .disabled(target.id == quadrant.id)
                                    }
                                }
                            }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(minHeight: 250, alignment: .top)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .dropDestination(for: String.self) { identifiers, _ in
            identifiers.first.map(onDropIdentifier)
            return true
        }
    }
}

struct MatrixTaskSummaryCard: View {
    let task: ReminderTask

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
                    .font(.caption)
                Text(task.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .strikethrough(task.isCompleted)
            }

            HStack(spacing: 6) {
                if let dueDate = task.dueDate {
                    Label(dueDate.formatted(date: .numeric, time: .omitted), systemImage: "calendar")
                }
                if task.priority > 0 {
                    Label(priorityLabel, systemImage: "flag.fill")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var priorityLabel: String {
        switch task.priority {
        case 1...4: return "Low"
        case 5...8: return "Med"
        case 9: return "High"
        default: return "P\(task.priority)"
        }
    }
}

struct MatrixTaskDetailView: View {
    let task: ReminderTask
    let quadrants: [KanbanColumn]
    let currentQuadrantId: String
    let onMove: (String) -> Void
    let onComplete: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Task") {
                    Text(task.title).font(.headline)
                    if let notes = task.notes, !notes.isEmpty { Text(notes) }
                    if let dueDate = task.dueDate {
                        Label(dueDate.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    }
                    Label("Priority: \(task.priority == 0 ? "None" : String(task.priority))", systemImage: "flag")
                }

                Section("Actions") {
                    Button(task.isCompleted ? "Mark Incomplete" : "Mark Complete") {
                        onComplete(!task.isCompleted)
                        dismiss()
                    }

                    Menu("Move to Quadrant") {
                        ForEach(quadrants) { quadrant in
                            Button(quadrant.title) {
                                onMove(quadrant.id)
                                dismiss()
                            }
                            .disabled(quadrant.id == currentQuadrantId)
                        }
                    }
                }
            }
            .navigationTitle("Task Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
