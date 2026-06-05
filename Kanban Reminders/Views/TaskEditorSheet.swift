import SwiftUI

struct TaskEditorSheet: View {
    let state: EditorState
    let columns: [KanbanColumn]
    let onSave: (String?, ReminderDraft) async -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: FocusedField?
    @State private var title: String
    @State private var notes: String
    @State private var commentsMarkdown: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var tagsText: String
    @State private var priority: Int
    @State private var isCompleted: Bool
    @State private var columnId: String
    @State private var isEditingMarkdown = false
    @State private var isSaving = false

    private enum FocusedField {
        case title
        case notes
        case markdown
    }

    init(state: EditorState, columns: [KanbanColumn], onSave: @escaping (String?, ReminderDraft) async -> Void) {
        self.state = state
        self.columns = columns
        self.onSave = onSave

        switch state {
        case .new(let columnId, _):
            _title = State(initialValue: "")
            _notes = State(initialValue: "")
            _commentsMarkdown = State(initialValue: "")
            _hasDueDate = State(initialValue: false)
            _dueDate = State(initialValue: Date())
            _tagsText = State(initialValue: "")
            _priority = State(initialValue: 0)
            _isCompleted = State(initialValue: false)
            _columnId = State(initialValue: columnId)
        case .edit(let task):
            _title = State(initialValue: task.title)
            _notes = State(initialValue: task.notes ?? "")
            _commentsMarkdown = State(initialValue: task.commentsMarkdown ?? "")
            _hasDueDate = State(initialValue: task.dueDate != nil)
            _dueDate = State(initialValue: task.dueDate ?? Date())
            _tagsText = State(initialValue: task.normalizedTags.joined(separator: " "))
            _priority = State(initialValue: task.priority)
            _isCompleted = State(initialValue: task.isCompleted)
            _columnId = State(initialValue: task.columnId)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .focused($focusedField, equals: .title)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .focused($focusedField, equals: .notes)
                        .lineLimit(3...6)
                }

                Section("Markdown Comments") {
                    markdownEditor

                    Text("Stored inside the reminder notes as a Kando Markdown comments section so it syncs with Apple Reminders.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Details") {
                    Picker("Column", selection: $columnId) {
                        ForEach(selectableColumns) { column in
                            Text(column.title).tag(column.id)
                        }
                    }

                    Button {
                        isCompleted.toggle()
                    } label: {
                        HStack {
                            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(isCompleted ? .green : .secondary)
                                .frame(width: 30, height: 30)
                            Text("Completed")
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("CompletedRadioButton")
                    .accessibilityLabel(isCompleted ? "Mark incomplete" : "Mark complete")

                    TextField("Tags", text: $tagsText)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("TagsTextField")
                    Text("Type tags separated by spaces or commas, e.g. work home. Kando saves them as native Reminders-style hashtags in the reminder notes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

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
            .formStyle(.grouped)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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
            .onAppear {
                // New sheets can be opened from a specific column's Add button.
                // Keep that requested column as the initial destination instead of
                // letting the Picker/Form fall back to the first column.
                if case .new(let requestedColumnId, _) = state,
                   selectableColumns.contains(where: { $0.id == requestedColumnId }) {
                    columnId = requestedColumnId
                } else if isDoneColumnId(columnId), let firstSelectable = selectableColumns.first {
                    columnId = firstSelectable.id
                }
            }
            .onChange(of: focusedField) { _, newValue in
                if newValue != .markdown {
                    isEditingMarkdown = false
                }
            }
        }
    }

    @ViewBuilder
    private var markdownEditor: some View {
        if isEditingMarkdown {
            TextEditor(text: $commentsMarkdown)
                .accessibilityIdentifier("MarkdownCommentsEditor")
                .font(.body.monospaced())
                .focused($focusedField, equals: .markdown)
                .frame(minHeight: 160)
                .padding(8)
                .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.secondary.opacity(0.25), lineWidth: 1)
                )
                .onAppear { focusedField = .markdown }
        } else {
            Button {
                isEditingMarkdown = true
            } label: {
                MarkdownPreview(markdown: commentsMarkdown)
                    .accessibilityIdentifier("MarkdownCommentsPreview")
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                    .padding(12)
                    .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.secondary.opacity(0.18), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("MarkdownCommentsPreviewButton")
            .accessibilityHint("Double tap to edit Markdown comments")
        }
    }

    private var identifier: String? {
        if case .edit(let task) = state { return task.reminderIdentifier }
        return nil
    }

    private var selectableColumns: [KanbanColumn] {
        columns.filter { !isDoneColumn($0) }
    }

    private func isDoneColumn(_ column: KanbanColumn) -> Bool {
        column.id.localizedCaseInsensitiveContains("done") ||
        column.title.localizedCaseInsensitiveContains("done") ||
        column.backingReminderListName.localizedCaseInsensitiveContains("done")
    }

    private func isDoneColumnId(_ columnId: String) -> Bool {
        columns.first(where: { $0.id == columnId }).map(isDoneColumn) ?? false
    }

    private var parsedTags: [String] {
        ReminderTagParser.normalize(tagsText.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init))
    }

    private func save() async {
        isSaving = true
        let draft = ReminderDraft(
            title: title,
            notes: notes,
            commentsMarkdown: commentsMarkdown,
            matrixQuadrantId: nil,
            dueDate: hasDueDate ? dueDate : nil,
            tags: parsedTags,
            priority: priority,
            isCompleted: isCompleted,
            columnId: columnId
        )
        await onSave(identifier, draft)
        isSaving = false
        dismiss()
    }
}

struct MarkdownPreview: View {
    let markdown: String

    var body: some View {
        if normalizedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("Click to add Markdown comments…")
                .foregroundStyle(.secondary)
                .italic()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(renderLines.enumerated()), id: \.offset) { _, line in
                    markdownLine(line)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
            .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func markdownLine(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            Spacer().frame(height: 4)
        } else if trimmed.hasPrefix("### ") {
            InlineMarkdownText(markdown: String(trimmed.dropFirst(4)))
                .font(.headline)
        } else if trimmed.hasPrefix("## ") {
            InlineMarkdownText(markdown: String(trimmed.dropFirst(3)))
                .font(.title3.weight(.semibold))
        } else if trimmed.hasPrefix("# ") {
            InlineMarkdownText(markdown: String(trimmed.dropFirst(2)))
                .font(.title2.weight(.bold))
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                InlineMarkdownText(markdown: String(trimmed.dropFirst(2)))
            }
        } else {
            InlineMarkdownText(markdown: line)
        }
    }

    private var renderLines: [String] {
        normalizedMarkdown.components(separatedBy: "\n")
    }

    private var accessibilityText: String {
        renderLines
            .map { line in
                line.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "### ", with: "")
                    .replacingOccurrences(of: "## ", with: "")
                    .replacingOccurrences(of: "# ", with: "")
                    .replacingOccurrences(of: "- ", with: "")
                    .replacingOccurrences(of: "* ", with: "")
                    .replacingOccurrences(of: "**", with: "")
                    .replacingOccurrences(of: "__", with: "")
                    .replacingOccurrences(of: "`", with: "")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private var normalizedMarkdown: String {
        var normalized = markdown
        normalized = normalized.replacingOccurrences(of: "\\*", with: "*")
        normalized = normalized.replacingOccurrences(of: "\\_", with: "_")
        normalized = normalized.replacingOccurrences(of: "\\`", with: "`")
        normalized = normalized.replacingOccurrences(of: "\\r\\n", with: "\n")
        normalized = normalized.replacingOccurrences(of: "\\n", with: "\n")
        return normalized
    }
}

private struct InlineMarkdownText: View {
    let markdown: String

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            Text(attributed)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(markdown)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
