import SwiftUI

struct KanbanBoardView: View {
    let title: String
    let columns: [KanbanColumn]

    @ObservedObject var viewModel: KanbanBoardViewModel
    @State private var editor: EditorState?

    init(title: String = "Kanban", columns: [KanbanColumn] = KanbanColumn.defaultKanban, viewModel: KanbanBoardViewModel) {
        self.title = title
        self.columns = columns
        self.viewModel = viewModel
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.hasPermission {
                    board
                } else {
                    PermissionDeniedView()
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let first = viewModel.columns.first { editor = .new(first.id) }
                    } label: {
                        Label("Add Task", systemImage: "plus")
                    }
                    .disabled(viewModel.columns.isEmpty)
                }
            }
            .onAppear { viewModel.updateColumns(columns) }
            .onChange(of: columns) { _, newColumns in
                viewModel.updateColumns(newColumns)
                Task { await viewModel.load() }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .overlay {
                if viewModel.isLoading && viewModel.tasks.isEmpty {
                    ProgressView("Loading Reminders…")
                }
            }
            .sheet(item: $editor) { state in
                TaskEditorSheet(state: state, columns: viewModel.columns) { identifier, draft in
                    await viewModel.saveTask(identifier: identifier, draft: draft)
                }
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearError() } }
            )) {
                Button("OK", role: .cancel) { viewModel.clearError() }
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
            }
        }
    }

    private var board: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(viewModel.columns) { column in
                    KanbanColumnView(
                        column: column,
                        tasks: viewModel.tasks(in: column.id),
                        allColumns: viewModel.columns,
                        onAdd: { editor = .new(column.id) },
                        onEdit: { editor = .edit($0) },
                        onMove: { task, target in Task { await viewModel.move(task, to: target) } },
                        onComplete: { task, completed in Task { await viewModel.setCompletion(task, isCompleted: completed) } },
                        onDropIdentifier: { identifier in Task { await viewModel.move(identifier: identifier, to: column.id) } }
                    )
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
}

enum EditorState: Identifiable {
    case new(String)
    case edit(ReminderTask)

    var id: String {
        switch self {
        case .new(let columnId): return "new-\(columnId)"
        case .edit(let task): return task.id
        }
    }
}
