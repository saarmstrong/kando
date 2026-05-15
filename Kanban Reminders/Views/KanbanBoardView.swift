import SwiftUI

struct KanbanBoardView: View {
    @ObservedObject var viewModel: KanbanBoardViewModel
    @State private var editor: EditorState?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.hasPermission {
                    board
                } else {
                    PermissionDeniedView()
                }
            }
            .navigationTitle("Kanban Reminders")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editor = .new(.backlog)
                    } label: {
                        Label("Add Task", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsHelpView()
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                }
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
                        tasks: viewModel.tasks(in: column.kind),
                        allColumns: viewModel.columns,
                        onAdd: { editor = .new(column.kind) },
                        onEdit: { editor = .edit($0) },
                        onMove: { task, target in Task { await viewModel.move(task, to: target) } },
                        onComplete: { task, completed in Task { await viewModel.setCompletion(task, isCompleted: completed) } },
                        onDropIdentifier: { identifier in Task { await viewModel.move(identifier: identifier, to: column.kind) } }
                    )
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
}

enum EditorState: Identifiable {
    case new(KanbanColumn.Kind)
    case edit(ReminderTask)

    var id: String {
        switch self {
        case .new(let column): return "new-\(column.rawValue)"
        case .edit(let task): return task.id
        }
    }
}
