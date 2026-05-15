import SwiftUI

struct TaskEditorSheet: View {
    let state: EditorState
    let columns: [KanbanColumn]
    let onSave: (String?, ReminderDraft) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var notes: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var priority: Int
    @State private var isCompleted: Bool
    @State private var columnId: String
    @State private var isSaving = false

    init(state: EditorState, columns: [KanbanColumn], onSave: @escaping (String?, ReminderDraft) async -> Void) {
        self.state = state
        self.columns = columns
        self.onSave = onSave

        switch state {
        case .new(let columnId):
            _title = State(initialValue: "")
            _notes = State(initialValue: "")
            _hasDueDate = State(initialValue: false)
            _dueDate = State(initialValue: Date())
            _priority = State(initialValue: 0)
            _isCompleted = State(initialValue: false)
            _columnId = State(initialValue: columnId)
        case .edit(let task):
            _title = State(initialValue: task.title)
            _notes = State(initialValue: task.notes ?? "")
            _hasDueDate = State(initialValue: task.dueDate != nil)
            _dueDate = State(initialValue: task.dueDate ?? Date())
            _priority = State(initialValue: task.priority)
            _isCompleted = State(initialValue: task.isCompleted)
            _columnId = State(initialValue: task.columnId)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $title)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Details") {
                    Picker("Column", selection: $columnId) {
                        ForEach(columns) { column in
                            Text(column.title).tag(column.id)
                        }
                    }

                    Toggle("Completed", isOn: $isCompleted)

                    Toggle("Due Date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    }

                    Picker("Priority", selection: $priority) {
                        Text("None").tag(0)
                        Text("Low").tag(1)
                        Text("Medium").tag(5)
                        Text("High").tag(9)
                    }
                }
            }
            .navigationTitle(identifier == nil ? "New Task" : "Edit Task")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var identifier: String? {
        if case .edit(let task) = state { return task.reminderIdentifier }
        return nil
    }

    private func save() async {
        isSaving = true
        let draft = ReminderDraft(
            title: title,
            notes: notes,
            dueDate: hasDueDate ? dueDate : nil,
            priority: priority,
            isCompleted: isCompleted,
            columnId: columnId
        )
        await onSave(identifier, draft)
        isSaving = false
        dismiss()
    }
}
