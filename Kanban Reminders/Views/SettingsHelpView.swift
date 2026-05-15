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
                        KanbanColumnSettingsRow(
                            column: $column,
                            moveUp: { settings.moveKanbanColumnUp(id: column.id) },
                            moveDown: { settings.moveKanbanColumnDown(id: column.id) },
                            delete: { settings.removeKanbanColumn(id: column.id) }
                        )
                    }
                    .onMove(perform: settings.moveKanbanColumn)
                    .onDelete(perform: settings.removeKanbanColumn)

                    VStack(alignment: .leading, spacing: 8) {
                        TextField("New column", text: $newKanbanColumn)
                            .onSubmit(addKanbanColumn)
                        Button(action: addKanbanColumn) {
                            Label("Add Column", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newKanbanColumn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section("Eisenhower Matrix Quadrants") {
                    ForEach($settings.matrixQuadrants) { $quadrant in
                        HStack {
                            TextField("Quadrant name", text: $quadrant.title)
                            Button(role: .destructive) {
                                settings.removeMatrixQuadrant(id: quadrant.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .disabled(settings.matrixQuadrants.count <= 1)
                        }
                    }
                    .onDelete(perform: settings.removeMatrixQuadrant)

                    VStack(alignment: .leading, spacing: 8) {
                        TextField("New quadrant", text: $newMatrixQuadrant)
                            .onSubmit(addMatrixQuadrant)
                        Button(action: addMatrixQuadrant) {
                            Label("Add Quadrant", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
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
            #if os(macOS)
            .formStyle(.grouped)
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .frame(maxWidth: 860, maxHeight: .infinity)
            #endif
            .navigationTitle("Settings")
            #if os(iOS)
            .toolbar { EditButton() }
            #endif
        }
    }

    private func addKanbanColumn() {
        let title = newKanbanColumn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        settings.addKanbanColumn(title: title)
        newKanbanColumn = ""
    }

    private func addMatrixQuadrant() {
        let title = newMatrixQuadrant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        settings.addMatrixQuadrant(title: title)
        newMatrixQuadrant = ""
    }
}

private struct KanbanColumnSettingsRow: View {
    @Binding var column: KanbanColumn
    @State private var hasLimit: Bool
    @State private var limit: Int
    let moveUp: () -> Void
    let moveDown: () -> Void
    let delete: () -> Void

    init(column: Binding<KanbanColumn>, moveUp: @escaping () -> Void, moveDown: @escaping () -> Void, delete: @escaping () -> Void) {
        _column = column
        _hasLimit = State(initialValue: column.wrappedValue.wipLimit != nil)
        _limit = State(initialValue: column.wrappedValue.wipLimit ?? 3)
        self.moveUp = moveUp
        self.moveDown = moveDown
        self.delete = delete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Column name", text: $column.title)

            HStack {
                Button { moveUp() } label: {
                    Label("Move Up", systemImage: "chevron.up")
                }
                Button { moveDown() } label: {
                    Label("Move Down", systemImage: "chevron.down")
                }
                Spacer()
                Button(role: .destructive, action: delete) {
                    Label("Delete", systemImage: "trash")
                }
            }
            .buttonStyle(.borderless)
            .labelStyle(.titleAndIcon)

            Toggle("Show column on board", isOn: Binding(
                get: { !column.isHidden },
                set: { column.isHidden = !$0 }
            ))

            ColorPicker("Column color", selection: Binding(
                get: { column.colorHex.map(Color.init(hex:)) ?? .blue },
                set: { column.colorHex = $0.hexString }
            ), supportsOpacity: false)

            Button("Clear color") {
                column.colorHex = nil
            }
            .disabled(column.colorHex == nil)

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
