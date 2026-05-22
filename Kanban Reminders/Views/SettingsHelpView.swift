import SwiftUI

struct SettingsHelpView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var newKanbanColumn = ""
    @State private var newMatrixQuadrant = ""
    @State private var reminderListNames: [String] = []
    @State private var reminderListError: String?

    private let reminderService = ReminderStoreService()

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
                        .accessibilityIdentifier("HideCompletedToggle")
                    Text("Completed tasks are always hidden from the Matrix view. This setting also hides them from the Kanban board, including Done.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Kanban Columns") {
                    ForEach($settings.kanbanColumns) { $column in
                        KanbanColumnSettingsRow(
                            column: $column,
                            reminderListNames: reminderListNames,
                            moveUp: { settings.moveKanbanColumnUp(id: column.id) },
                            moveDown: { settings.moveKanbanColumnDown(id: column.id) },
                            delete: { settings.removeKanbanColumn(id: column.id) },
                            renameReminderList: renameReminderList
                        )
                    }
                    .onMove(perform: settings.moveKanbanColumn)
                    .onDelete(perform: settings.removeKanbanColumn)

                    VStack(alignment: .leading, spacing: 8) {
                        TextField("New column", text: $newKanbanColumn)
                            .accessibilityIdentifier("NewColumnTextField")
                            .onSubmit(addKanbanColumn)
                        Button(action: addKanbanColumn) {
                            Label("Add Column", systemImage: "plus")
                        }
                        .accessibilityIdentifier("AddColumnButton")
                        .buttonStyle(.borderedProminent)
                        .disabled(newKanbanColumn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    Button {
                        Task { await loadReminderLists() }
                    } label: {
                        Label("Refresh Reminders Lists", systemImage: "arrow.clockwise")
                    }

                    if let reminderListError {
                        Text(reminderListError)
                            .font(.caption)
                            .foregroundStyle(.red)
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
                    #if os(iOS)
                    Label("Pull down on a board to refresh.", systemImage: "arrow.clockwise")
                    #endif
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
            .task { await loadReminderLists() }
        }
    }

    private func loadReminderLists() async {
        do {
            reminderListError = nil
            reminderListNames = try await reminderService.reminderListNames()
        } catch {
            reminderListError = error.localizedDescription
        }
    }

    private func renameReminderList(from oldTitle: String, to newTitle: String) async throws {
        try await reminderService.renameReminderList(from: oldTitle, to: newTitle)
        await loadReminderLists()
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
    let reminderListNames: [String]
    @State private var hasLimit: Bool
    @State private var limit: Int
    @State private var backingListDraft: String
    @State private var listActionError: String?
    @State private var isUpdatingList = false
    @State private var showReassociateConfirmation = false
    @State private var showRenameConfirmation = false
    @State private var showDeleteConfirmation = false
    let moveUp: () -> Void
    let moveDown: () -> Void
    let delete: () -> Void
    let renameReminderList: (String, String) async throws -> Void

    init(
        column: Binding<KanbanColumn>,
        reminderListNames: [String],
        moveUp: @escaping () -> Void,
        moveDown: @escaping () -> Void,
        delete: @escaping () -> Void,
        renameReminderList: @escaping (String, String) async throws -> Void
    ) {
        _column = column
        self.reminderListNames = reminderListNames
        _hasLimit = State(initialValue: column.wrappedValue.wipLimit != nil)
        _limit = State(initialValue: column.wrappedValue.wipLimit ?? 3)
        _backingListDraft = State(initialValue: column.wrappedValue.backingReminderListName)
        self.moveUp = moveUp
        self.moveDown = moveDown
        self.delete = delete
        self.renameReminderList = renameReminderList
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
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
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

            DisclosureGroup("Reminders List") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current: \(column.backingReminderListName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !kandoReminderListNames.isEmpty {
                        Picker("Reassociate with", selection: $backingListDraft) {
                            ForEach(kandoReminderListNames, id: \.self) { listName in
                                Text(listName).tag(listName)
                            }
                        }
                    }

                    TextField("Reminders list name", text: $backingListDraft)
                        .onSubmit { requestBackingListReassociation() }

                    if !isKandoListName(backingListDraft) {
                        Label("This is not a Kando-managed list. The app may read, move, or update reminders in that Apple Reminders list.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    HStack {
                        Button("Use This List Name") {
                            requestBackingListReassociation()
                        }
                        Button(isUpdatingList ? "Renaming…" : "Rename Native List") {
                            showRenameConfirmation = true
                        }
                        .disabled(isUpdatingList || backingListDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .buttonStyle(.borderless)

                    Text("Use This List Name reassociates the column with an existing or new Reminders list. Rename Native List renames the current Apple Reminders list too.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let listActionError {
                        Text(listActionError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 4)
            }

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
        .onChange(of: column.backingReminderListName) { _, newValue in
            backingListDraft = newValue
        }
        .confirmationDialog("Delete Column?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Column", role: .destructive, action: delete)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the column from Kando settings. It does not delete the Apple Reminders list or its reminders.")
        }
        .confirmationDialog("Reassociate Column?", isPresented: $showReassociateConfirmation, titleVisibility: .visible) {
            Button("Reassociate Column", role: isKandoListName(backingListDraft) ? nil : .destructive) {
                applyBackingListName()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This column will point at \"\(backingListDraft)\". Tasks shown in this column will come from that Apple Reminders list.")
        }
        .confirmationDialog("Rename Native Reminders List?", isPresented: $showRenameConfirmation, titleVisibility: .visible) {
            Button("Rename Apple Reminders List", role: .destructive) {
                Task { await renameNativeList() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This renames the actual Apple Reminders list from \"\(column.backingReminderListName)\" to \"\(backingListDraft)\". This change can sync through iCloud.")
        }
    }

    private var kandoReminderListNames: [String] {
        let names = reminderListNames.filter(isKandoListName)
        if isKandoListName(column.backingReminderListName), !names.contains(column.backingReminderListName) {
            return ([column.backingReminderListName] + names).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        return names
    }

    private func isKandoListName(_ name: String) -> Bool {
        name.localizedCaseInsensitiveContains("Kando - Kanban -") || name.localizedCaseInsensitiveContains("Kando - Matrix -")
    }

    private func requestBackingListReassociation() {
        let trimmed = backingListDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        backingListDraft = trimmed
        showReassociateConfirmation = true
    }

    private func applyBackingListName() {
        let trimmed = backingListDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        column.backingReminderListName = trimmed
        listActionError = nil
    }

    private func renameNativeList() async {
        let oldTitle = column.backingReminderListName
        let newTitle = backingListDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTitle.isEmpty else { return }
        isUpdatingList = true
        defer { isUpdatingList = false }
        do {
            try await renameReminderList(oldTitle, newTitle)
            column.backingReminderListName = newTitle
            listActionError = nil
        } catch {
            listActionError = error.localizedDescription
        }
    }
}
