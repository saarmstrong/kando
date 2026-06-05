import SwiftUI

struct TaskCardView: View {
    let task: ReminderTask
    let allColumns: [KanbanColumn]
    var wipAccentColor: Color? = nil
    let onEdit: () -> Void
    let onMove: (String) -> Void
    let onComplete: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Button {
                    onComplete(!task.isCompleted)
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(task.isCompleted ? .green : .secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(task.isCompleted ? "Mark incomplete" : "Mark complete")
                .accessibilityHint("Toggles this reminder's native completed state")

                Text(task.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .strikethrough(task.isCompleted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(task.title)

                priorityBadge
            }

            if let notes = task.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if task.hasMarkdownComments {
                Label("Markdown comments", systemImage: "text.bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !task.normalizedTags.isEmpty {
                TagChips(tags: task.normalizedTags)
            }

            if let dueDate = task.dueDate {
                Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(wipAccentColor ?? .clear, lineWidth: wipAccentColor == nil ? 0 : 2)
        )
        .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onEdit)
        // Keep child Text views exposed as staticTexts for UI tests and VoiceOver.
        // Synthesizing the whole card as one Button-like accessibility element can
        // hide task titles from XCUIElementQuery.staticTexts.
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Edit", onEdit)
        .contextMenu {
            Button("Edit", systemImage: "pencil", action: onEdit)
            Menu("Move to…") {
                ForEach(allColumns) { column in
                    Button(column.title) { onMove(column.id) }
                        .disabled(column.id == task.columnId)
                }
            }
        }
    }

    @ViewBuilder
    private var priorityBadge: some View {
        if task.priority > 0 {
            Text(priorityLabel)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(priorityColor.opacity(0.16), in: Capsule())
                .foregroundStyle(priorityColor)
        }
    }

    private var priorityLabel: String {
        switch task.priority {
        case 1...4: return "Low"
        case 5...8: return "Med"
        case 9: return "High"
        default: return "P\(task.priority)"
        }
    }

    private var priorityColor: Color {
        switch task.priority {
        case 1...4: return .blue
        case 5...8: return .orange
        case 9: return .red
        default: return .secondary
        }
    }
}

struct TagChips: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(tags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("TagChip-\(tag)")
            }
        }
        .lineLimit(1)
    }
}
