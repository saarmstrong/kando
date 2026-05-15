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

                Section("Kanban Columns") {
                    ForEach($settings.kanbanColumns) { $column in
                        TextField("Column name", text: $column.title)
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
            .toolbar { EditButton() }
        }
    }
}
