import SwiftUI

struct SettingsHelpView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var newKanbanColumn = ""
    @State private var newMatrixQuadrant = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $settings.colorMode) {
                        ForEach(AppColorMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }

                Section("Task Display") {
                    Toggle("Hide completed tasks", isOn: $settings.hideCompletedTasks)
                    Text("Completed tasks are always hidden from the Matrix view. This setting also hides them from the Kanban board, including Done.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Kanban Columns") {
                    ForEach($settings.kanbanColumns) { $column in
                        KanbanColumnSettingsRow(column: $column)
                    }
                    .onDelete(perform: settings.removeKanbanColumn)

                    HStack {
                        TextField("New column", text: $newKanbanColumn)
                        Button("Add") {
                            settings.addKanbanColumn(title: newKanbanColumn)
                            newKanbanColumn = ""
                        }
                        .disabled(newKanbanColumn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section("Eisenhower Matrix Quadrants") {
                    ForEach($settings.matrixQuadrants) { $quadrant in
                        TextField("Quadrant name", text: $quadrant.title)
                    }
                    .onDelete(perform: settings.removeMatrixQuadrant)

                    HStack {
                        TextField("New quadrant", text: $newMatrixQuadrant)
                        Button("Add") {
                            settings.addMatrixQuadrant(title: newMatrixQuadrant)
                            newMatrixQuadrant = ""
                        }
                        .disabled(newMatrixQuadrant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section("How sync works") {
                    Text("This app does not run its own cloud service. Tasks are saved as native Apple Reminders in app-created lists.")
                    Text("Renaming a column or quadrant changes its display name in this app. The backing Apple Reminders list name is kept stable so existing tasks stay connected.")
                    Text("Sync depends on your Apple Reminders and iCloud settings.")
                }

                Section("Tips") {
                    Label("Pull down on a board to refresh.", systemImage: "arrow.clockwise")
                    Label("Long-press a card to move it between columns or quadrants.", systemImage: "hand.tap")
                    Label("Drag cards between columns on supported devices.", systemImage: "rectangle.and.hand.point.up.left")
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .toolbar { EditButton() }
            #endif
        }
    }
}

private struct KanbanColumnSettingsRow: View {
    @Binding var column: KanbanColumn
    @State private var hasLimit: Bool
    @State private var limit: Int

    init(column: Binding<KanbanColumn>) {
        _column = column
        _hasLimit = State(initialValue: column.wrappedValue.wipLimit != nil)
        _limit = State(initialValue: column.wrappedValue.wipLimit ?? 3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Column name", text: $column.title)

            Toggle("WIP limit", isOn: $hasLimit)
                .onChange(of: hasLimit) { _, enabled in
                    column.wipLimit = enabled ? limit : nil
                }

            if hasLimit {
                Stepper("Max active tasks: \(limit)", value: $limit, in: 1...99)
                    .onChange(of: limit) { _, newValue in
                        column.wipLimit = newValue
                    }
                Text("Column turns orange near the limit and red at or over the limit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
