import XCTest

final class ReminderTaskSortingFilteringTests: XCTestCase {
    private func task(
        id: String,
        title: String,
        dueDate: Date? = nil,
        priority: Int = 0,
        tags: [String] = [],
        isCompleted: Bool = false,
        columnId: String = "backlog"
    ) -> ReminderTask {
        ReminderTask(
            reminderIdentifier: id,
            title: title,
            notes: nil,
            commentsMarkdown: nil,
            matrixQuadrantId: nil,
            dueDate: dueDate,
            tags: tags,
            priority: priority,
            isCompleted: isCompleted,
            columnId: columnId
        )
    }

    func testFiltersHighPriorityTasks() {
        let tasks = [
            task(id: "1", title: "Low", priority: 1),
            task(id: "2", title: "High", priority: 9),
            task(id: "3", title: "None", priority: 0)
        ]

        XCTAssertEqual(tasks.filtered(.highPriority).map(\.title), ["High"])
    }

    func testFiltersTasksDueToday() {
        let calendar = Calendar.current
        let today = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        let tasks = [
            task(id: "1", title: "Today", dueDate: today),
            task(id: "2", title: "Tomorrow", dueDate: tomorrow),
            task(id: "3", title: "No Date")
        ]

        XCTAssertEqual(tasks.filtered(.dueToday).map(\.title), ["Today"])
    }

    func testFiltersOverdueIncompleteTasksOnly() {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!

        let tasks = [
            task(id: "1", title: "Overdue", dueDate: yesterday),
            task(id: "2", title: "Completed Overdue", dueDate: yesterday, isCompleted: true),
            task(id: "3", title: "No Date")
        ]

        XCTAssertEqual(tasks.filtered(.overdue).map(\.title), ["Overdue"])
    }

    func testSortsPriorityHighToLow() {
        let tasks = [
            task(id: "1", title: "Low", priority: 1),
            task(id: "2", title: "High", priority: 9),
            task(id: "3", title: "Medium", priority: 5)
        ]

        XCTAssertEqual(tasks.sorted(by: .priorityHighToLow).map(\.title), ["High", "Medium", "Low"])
    }

    func testSortsDueSoonestWithNilDatesLast() {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: Date())!

        let tasks = [
            task(id: "1", title: "No Date"),
            task(id: "2", title: "Next Week", dueDate: nextWeek),
            task(id: "3", title: "Tomorrow", dueDate: tomorrow)
        ]

        XCTAssertEqual(tasks.sorted(by: .dueSoonest).map(\.title), ["Tomorrow", "Next Week", "No Date"])
    }

    func testCompletedTasksAreSortedAfterIncompleteTasks() {
        let tasks = [
            task(id: "1", title: "A Completed", isCompleted: true),
            task(id: "2", title: "B Active"),
            task(id: "3", title: "C Completed", isCompleted: true),
            task(id: "4", title: "A Active")
        ]

        let sorted = tasks.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        XCTAssertEqual(sorted.map(\.title), ["A Active", "B Active", "A Completed", "C Completed"])
    }

    func testCompletedTasksCanBeProjectedIntoDoneColumn() {
        let tasks = [
            task(id: "1", title: "Completed in Doing", isCompleted: true, columnId: "doing"),
            task(id: "2", title: "Active in Doing", isCompleted: false, columnId: "doing")
        ]
        let doneColumnId = "done"
        let normalized = tasks.map { task -> ReminderTask in
            var copy = task
            if copy.isCompleted {
                copy.columnId = doneColumnId
            }
            return copy
        }

        XCTAssertEqual(normalized.first { $0.title == "Completed in Doing" }?.columnId, doneColumnId)
        XCTAssertEqual(normalized.first { $0.title == "Active in Doing" }?.columnId, "doing")
    }

    func testExtractsHashtagTagsFromReminderContent() {
        var tagged = task(id: "1", title: "Call client #Work", tags: ["Urgent"])
        tagged.notes = "Follow up for #client-success"
        tagged.commentsMarkdown = "Discuss #work plan"

        XCTAssertEqual(tagged.normalizedTags, ["client-success", "urgent", "work"])
    }

    func testNormalizesTagsWithOrWithoutHashmark() {
        XCTAssertEqual(ReminderTagParser.normalize(["#Work", "home", " work "]), ["home", "work"])
    }

    func testFiltersTasksByTag() {
        let tasks = [
            task(id: "1", title: "Design", tags: ["work"]),
            task(id: "2", title: "Groceries", tags: ["home"]),
            task(id: "3", title: "No Tag")
        ]

        XCTAssertEqual(tasks.filtered(byTag: "#WORK").map(\.title), ["Design"])
        XCTAssertEqual(tasks.availableTags, ["home", "work"])
    }

    func testFiltersTasksByMultipleSelectedTags() {
        let tasks = [
            task(id: "1", title: "Work Mobile", tags: ["work", "mobile"]),
            task(id: "2", title: "Work Desktop", tags: ["work", "desktop"]),
            task(id: "3", title: "Mobile Personal", tags: ["mobile", "home"])
        ]

        XCTAssertEqual(tasks.filtered(byTags: ["work", "mobile"]).map(\.title), ["Work Mobile"])
    }

    func testCombinedFilterTagAndSort() {
        let tasks = [
            task(id: "1", title: "B", priority: 1, tags: ["work"]),
            task(id: "2", title: "A", priority: 9, tags: ["home"]),
            task(id: "3", title: "C", priority: 5, tags: ["work"]),
            task(id: "4", title: "None", priority: 0, tags: ["work"])
        ]

        XCTAssertEqual(
            tasks.filteredAndSorted(filter: .hasPriority, tag: "work", sort: .title).map(\.title),
            ["B", "C"]
        )
    }

    func testCombinedFilterAndSort() {
        let tasks = [
            task(id: "1", title: "B", priority: 1),
            task(id: "2", title: "A", priority: 9),
            task(id: "3", title: "C", priority: 5),
            task(id: "4", title: "None", priority: 0)
        ]

        XCTAssertEqual(
            tasks.filteredAndSorted(filter: .hasPriority, sort: .title).map(\.title),
            ["A", "B", "C"]
        )
    }
}
