import XCTest

final class ReminderTaskSortingFilteringTests: XCTestCase {
    private func task(
        id: String,
        title: String,
        dueDate: Date? = nil,
        priority: Int = 0,
        isCompleted: Bool = false
    ) -> ReminderTask {
        ReminderTask(
            reminderIdentifier: id,
            title: title,
            notes: nil,
            dueDate: dueDate,
            priority: priority,
            isCompleted: isCompleted,
            columnId: "backlog"
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
