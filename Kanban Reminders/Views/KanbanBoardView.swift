import SwiftUI
#if os(macOS)
import AppKit
#endif

struct KanbanBoardView: View {
    let title: String
    let columns: [KanbanColumn]

    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var viewModel: KanbanBoardViewModel
    @State private var editor: EditorState?
    @State private var sortOption: TaskSortOption = .title
    @State private var filterOption: TaskFilterOption = .all
    #if os(macOS)
    @State private var isCommandKeyPressed = false
    @State private var commandKeyMonitor: Any?
    #endif

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
                ToolbarItemGroup(placement: .automatic) {
                    sortFilterMenu
                    #if os(macOS)
                    Button {
                        Task { await viewModel.refreshFromReminders() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(viewModel.isLoading)
                    #endif
                    Button {
                        openNewTask()
                    } label: {
                        Label(addTaskLabel, systemImage: "plus")
                    }
                    .accessibilityIdentifier("AddTaskButton")
                    #if os(macOS)
                    .keyboardShortcut("n", modifiers: .command)
                    #endif
                    .disabled(visibleColumns.isEmpty)
                }
            }
            .background(columnHotkeys)
            .onAppear {
                viewModel.updateColumns(columns)
                installCommandKeyMonitorIfNeeded()
            }
            .onDisappear { removeCommandKeyMonitor() }
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

    private func tasks(in columnId: String) -> [ReminderTask] {
        viewModel.tasks(in: columnId)
            .filter { !settings.hideCompletedTasks || !$0.isCompleted }
            .filteredAndSorted(filter: filterOption, sort: sortOption)
    }

    private var board: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(Array(visibleColumns.enumerated()), id: \.element.id) { index, column in
                    KanbanColumnView(
                        column: column,
                        tasks: tasks(in: column.id),
                        allColumns: viewModel.columns,
                        shortcutHint: shortcutHint(forColumnAt: index),
                        onAdd: { editor = .newTask(in: column.id) },
                        onEdit: { editor = .edit($0) },
                        onMove: { task, target in Task { await viewModel.move(task, to: target) } },
                        onComplete: { task, completed in Task { await viewModel.setCompletion(task, isCompleted: completed) } },
                        onDropIdentifier: { identifier in
                            Task { await viewModel.move(identifier: identifier, to: column.id) }
                        }
                    )
                }
            }
            .padding()
        }
        .scrollIndicators(.visible)
        .background(Color.appGroupedBackground)
    }

    private var visibleColumns: [KanbanColumn] {
        viewModel.columns.filter { !$0.isHidden }
    }

    private var addTaskLabel: String {
        #if os(macOS)
        isCommandKeyPressed ? "Add Task ⌘N" : "Add Task"
        #else
        "Add Task"
        #endif
    }

    private func shortcutHint(forColumnAt index: Int) -> String? {
        #if os(macOS)
        guard isCommandKeyPressed, index < 9 else { return nil }
        return "⌘\(index + 1)"
        #else
        return nil
        #endif
    }

    @ViewBuilder
    private var columnHotkeys: some View {
        #if os(macOS)
        ForEach(Array(visibleColumns.prefix(9).enumerated()), id: \.element.id) { index, column in
            Button("Add to \(column.title)") {
                editor = .newTask(in: column.id)
            }
            .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            .hidden()
            .accessibilityHidden(true)
        }
        #else
        EmptyView()
        #endif
    }

    private func openNewTask() {
        if let first = visibleColumns.first {
            editor = .newTask(in: first.id)
        }
    }

    private func installCommandKeyMonitorIfNeeded() {
        #if os(macOS)
        guard commandKeyMonitor == nil else { return }
        isCommandKeyPressed = NSEvent.modifierFlags.contains(.command)
        commandKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { event in
            isCommandKeyPressed = event.modifierFlags.contains(.command)
            return event
        }
        #endif
    }

    private func removeCommandKeyMonitor() {
        #if os(macOS)
        if let commandKeyMonitor {
            NSEvent.removeMonitor(commandKeyMonitor)
            self.commandKeyMonitor = nil
        }
        isCommandKeyPressed = false
        #endif
    }
}

enum EditorState: Identifiable {
    case new(columnId: String, nonce: UUID)
    case edit(ReminderTask)

    static func newTask(in columnId: String) -> EditorState {
        .new(columnId: columnId, nonce: UUID())
    }

    var id: String {
        switch self {
        case .new(let columnId, let nonce): return "new-\(columnId)-\(nonce.uuidString)"
        case .edit(let task): return task.id
        }
    }
}
