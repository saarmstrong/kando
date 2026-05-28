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
    @State private var collapsedColumnIds: Set<String> = []
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
                collapsedColumnIds.formIntersection(newColumns.map(\.id))
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
                // Force SwiftUI to build a fresh editor every time. Without this,
                // @State from a previously edited task can be reused when opening
                // the Add sheet from a column.
                .id(state.id)
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
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .top, spacing: boardColumnSpacing) {
                    ForEach(Array(visibleColumns.enumerated()), id: \.element.id) { index, column in
                        KanbanColumnView(
                            column: column,
                            tasks: tasks(in: column.id),
                            allColumns: viewModel.columns,
                            shortcutHint: shortcutHint(forColumnAt: index),
                            isCollapsed: collapsedColumnIds.contains(column.id),
                            expandedWidth: expandedColumnWidth(in: geometry.size.width),
                            onToggleCollapse: { toggleColumnCollapse(column.id) },
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
                .padding(boardPadding)
                .frame(minWidth: geometry.size.width, alignment: .center)
            }
            .scrollIndicators(.visible)
            .background(Color.appGroupedBackground)
        }
    }

    private var visibleColumns: [KanbanColumn] {
        viewModel.columns.filter { column in
            !column.isHidden && (!settings.hideCompletedTasks || !isDoneColumn(column))
        }
    }

    private func isDoneColumn(_ column: KanbanColumn) -> Bool {
        column.id.localizedCaseInsensitiveContains("done") ||
        column.title.localizedCaseInsensitiveContains("done") ||
        column.backingReminderListName.localizedCaseInsensitiveContains("done")
    }

    private let boardColumnSpacing: CGFloat = 16
    private let boardPadding: CGFloat = 16
    private let collapsedColumnWidth: CGFloat = 54

    private func expandedColumnWidth(in windowWidth: CGFloat) -> CGFloat {
        #if os(macOS)
        let columns = visibleColumns
        let expandedCount = max(1, columns.filter { !collapsedColumnIds.contains($0.id) }.count)
        let collapsedCount = columns.count - expandedCount
        let targetContentWidth = max(0, windowWidth * 0.9 - boardPadding * 2)
        let totalSpacing = boardColumnSpacing * CGFloat(max(0, columns.count - 1))
        let totalCollapsedWidth = collapsedColumnWidth * CGFloat(collapsedCount)
        let availableForExpanded = targetContentWidth - totalSpacing - totalCollapsedWidth
        return max(220, availableForExpanded / CGFloat(expandedCount))
        #else
        return 310
        #endif
    }

    private func toggleColumnCollapse(_ columnId: String) {
        if collapsedColumnIds.contains(columnId) {
            collapsedColumnIds.remove(columnId)
        } else {
            collapsedColumnIds.insert(columnId)
        }
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
        if let backlog = backlogColumn ?? visibleColumns.first {
            editor = .newTask(in: backlog.id)
        }
    }

    private var backlogColumn: KanbanColumn? {
        visibleColumns.first { column in
            column.id.localizedCaseInsensitiveContains("backlog") ||
            column.title.localizedCaseInsensitiveContains("backlog") ||
            column.backingReminderListName.localizedCaseInsensitiveContains("backlog")
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
