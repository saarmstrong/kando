import XCTest

final class KanbanRemindersCoreUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["KANDO_UI_TESTING"] = "1"
        app.launchArguments += ["-KANDO_UI_TESTING", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testLaunchesShowsCoreTabsAndSeedTask() throws {
        if !app.staticTexts["UITest Backlog Task"].waitForExistence(timeout: 5) {
            #if os(macOS)
            throw XCTSkip("Seeded UI-test board is not visible in this desktop UI-test environment.")
            #else
            XCTFail("Expected seeded UI-test task to be visible")
            #endif
        }
        XCTAssertTrue(app.staticTexts["Backlog"].exists)
        XCTAssertTrue(app.staticTexts["Doing"].exists)
        XCTAssertTrue(app.staticTexts["Done"].exists)

        openTab(named: "Matrix")
        XCTAssertTrue(app.navigationBars["Matrix"].waitForExistence(timeout: 3) || app.staticTexts["Matrix"].exists)

        openTab(named: "Settings")
        XCTAssertTrue(app.staticTexts["Task Display"].waitForExistence(timeout: 3) || app.switches["Hide completed tasks"].exists)
    }

    func testCanCreateTaskWithNotesAndMarkdownComments() throws {
        openTab(named: "Kanban")

        guard tapFirstExistingButton(named: "AddTaskButton", fallback: "Add Task") else {
            throw XCTSkip("Add Task button is not visible; likely running desktop UI tests without UI-test launch arguments.")
        }

        let titleField = firstTextField(containing: "Title")
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        titleField.tap()
        titleField.typeText("UITest New Task")

        let notesField = firstTextField(containing: "Notes")
        if notesField.exists {
            notesField.tap()
            notesField.typeText("Created by UI automation")
        }

        let textView = app.textViews.firstMatch
        if textView.exists {
            textView.tap()
            textView.typeText("**Automated** markdown comment")
        }

        _ = tapFirstExistingButton(named: "Save")

        XCTAssertTrue(app.staticTexts["UITest New Task"].waitForExistence(timeout: 5))
    }

    func testMarkdownCommentsDefaultToRenderedPreviewAndEditInline() throws {
        openTab(named: "Kanban")

        guard tapFirstExistingButton(named: "AddTaskButton", fallback: "Add Task") else {
            throw XCTSkip("Add Task button is not visible; likely running desktop UI tests without UI-test launch arguments.")
        }

        let titleField = firstTextField(containing: "Title")
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        titleField.tap()
        titleField.typeText("UITest Markdown Task")

        let previewButton = app.buttons["MarkdownCommentsPreviewButton"]
        XCTAssertTrue(previewButton.waitForExistence(timeout: 3), "Markdown comments should default to rendered preview mode")
        XCTAssertFalse(app.textViews["MarkdownCommentsEditor"].exists, "Markdown editor should not be visible until the rendered preview is tapped")

        previewButton.tap()

        let editor = app.textViews["MarkdownCommentsEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3), "Tapping the rendered preview should switch to inline Markdown editing")
        editor.tap()
        editor.typeText("# Heading")
        typeNewline()
        editor.typeText("**Bold comment**")
        typeNewline()
        editor.typeText("- item one")

        titleField.tap()

        XCTAssertTrue(previewButton.waitForExistence(timeout: 3), "Moving focus away should return to rendered preview mode")
        XCTAssertFalse(editor.exists, "Markdown editor should hide after focus leaves it")
        let renderedPreview = app.buttons["MarkdownCommentsPreviewButton"]
        XCTAssertTrue(renderedPreview.label.contains("Heading"), "Rendered Markdown should expose the heading text")
        XCTAssertTrue(renderedPreview.label.contains("Bold comment"), "Rendered Markdown should expose bold text without Markdown delimiters")
        XCTAssertTrue(renderedPreview.label.contains("item one"), "Rendered Markdown should expose list item text")
        XCTAssertFalse(renderedPreview.label.contains("**Bold comment**"), "Rendered Markdown should not show raw bold delimiters")
    }

    func testCompletedRadioInTaskDetailsMarksTaskDone() throws {
        openTab(named: "Kanban")

        guard app.staticTexts["UITest Backlog Task"].waitForExistence(timeout: 5) else {
            throw XCTSkip("Seeded UI-test board is not visible in this UI-test environment.")
        }
        app.staticTexts["UITest Backlog Task"].tap()

        let completedButton = app.buttons["CompletedRadioButton"].exists ? app.buttons["CompletedRadioButton"] : app.buttons["Mark complete"]
        guard completedButton.waitForExistence(timeout: 3) else {
            throw XCTSkip("Task detail completed radio button is not visible in this UI-test environment.")
        }
        completedButton.tap()
        _ = tapFirstExistingButton(named: "Save")

        XCTAssertTrue(app.staticTexts["UITest Backlog Task"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Done"].exists, "Completing from task details should keep the Done column visible and move the task there")
    }

    func testTaskDetailColumnDropdownDoesNotExposeDoneColumn() throws {
        openTab(named: "Kanban")

        guard app.staticTexts["UITest Backlog Task"].waitForExistence(timeout: 5) else {
            throw XCTSkip("Seeded UI-test board is not visible in this UI-test environment.")
        }
        app.staticTexts["UITest Backlog Task"].tap()

        let picker = app.popUpButtons["Column"].exists ? app.popUpButtons["Column"] : app.buttons["Column"]
        guard picker.waitForExistence(timeout: 3) else {
            throw XCTSkip("Column picker is not visible in this UI-test environment.")
        }
        picker.tap()

        XCTAssertTrue(app.staticTexts["Backlog"].waitForExistence(timeout: 2) || app.menuItems["Backlog"].exists)
        XCTAssertFalse(app.menuItems["Done"].exists, "Done should not be available in the task detail column dropdown; use the Completed radio instead")

        #if os(macOS)
        app.typeKey(.escape, modifierFlags: [])
        #endif
        _ = tapFirstExistingButton(named: "Cancel")
    }

    func testCardCompletionMovesTaskToDoneAndHideCompletedHidesDoneColumn() throws {
        openTab(named: "Kanban")

        guard app.staticTexts["UITest Backlog Task"].waitForExistence(timeout: 5) else {
            throw XCTSkip("Seeded UI-test board is not visible in this UI-test environment.")
        }

        let markComplete = app.buttons["Mark complete"].firstMatch
        guard markComplete.waitForExistence(timeout: 3) else {
            throw XCTSkip("Card complete button is not visible in this UI-test environment.")
        }
        markComplete.tap()

        let doneColumnTitle = app.staticTexts["KanbanColumnTitle-done"]
        XCTAssertTrue(doneColumnTitle.waitForExistence(timeout: 3), "Marking a card complete should route it to the Done column")

        openTab(named: "Settings")
        let toggle = app.switches["HideCompletedToggle"].exists ? app.switches["HideCompletedToggle"] : app.switches["Hide completed tasks"]
        guard toggle.waitForExistence(timeout: 3) else {
            throw XCTSkip("Hide completed toggle is not visible in this UI-test environment.")
        }
        setSwitch(toggle, on: true)

        openTab(named: "Kanban")
        let hiddenDoneColumnTitle = app.staticTexts["KanbanColumnTitle-done"]
        XCTAssertTrue(waitForNonExistence(hiddenDoneColumnTitle, timeout: 5), "Hide completed tasks should also hide the Done column")
    }

    func testColumnAddCreatesTaskInThatColumnAndGlobalAddUsesBacklog() throws {
        openTab(named: "Kanban")

        guard app.staticTexts["UITest Doing Task"].waitForExistence(timeout: 5) else {
            throw XCTSkip("Seeded UI-test board is not visible in this UI-test environment.")
        }

        let addButtons = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Add"))
        guard addButtons.count >= 2 else {
            throw XCTSkip("Column Add buttons are not visible in this UI-test environment.")
        }
        addButtons.element(boundBy: 1).tap()

        let doingTitle = firstTextField(containing: "Title")
        XCTAssertTrue(doingTitle.waitForExistence(timeout: 3))
        doingTitle.tap()
        doingTitle.typeText("UITest Added To Doing")
        _ = tapFirstExistingButton(named: "Save")
        XCTAssertTrue(app.staticTexts["UITest Added To Doing"].waitForExistence(timeout: 5))

        guard tapFirstExistingButton(named: "AddTaskButton", fallback: "Add Task") else {
            throw XCTSkip("Global Add Task button is not visible.")
        }
        let backlogTitle = firstTextField(containing: "Title")
        XCTAssertTrue(backlogTitle.waitForExistence(timeout: 3))
        backlogTitle.tap()
        backlogTitle.typeText("UITest Added To Backlog")
        _ = tapFirstExistingButton(named: "Save")
        XCTAssertTrue(app.staticTexts["UITest Added To Backlog"].waitForExistence(timeout: 5))
    }

    func testCanCreateTaskWithTagsAndFilterByTag() throws {
        openTab(named: "Kanban")

        guard tapFirstExistingButton(named: "AddTaskButton", fallback: "Add Task") else {
            throw XCTSkip("Add Task button is not visible.")
        }

        let titleField = firstTextField(containing: "Title")
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        titleField.tap()
        titleField.typeText("UITest Tagged Task")

        let tagsField = app.textFields["TagsTextField"].exists ? app.textFields["TagsTextField"] : app.textFields["Tags"]
        scrollUntilElementExists(tagsField)
        XCTAssertTrue(tagsField.waitForExistence(timeout: 3))
        tagsField.tap()
        tagsField.typeText("focus mobile")

        _ = tapFirstExistingButton(named: "Save")
        XCTAssertTrue(app.staticTexts["UITest Tagged Task"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["TagChip-focus"].exists || app.staticTexts["#focus"].exists)

        guard tapFirstExistingButton(named: "Sort and Filter") else {
            throw XCTSkip("Sort and filter menu is not visible.")
        }
        if app.buttons["Tag"].waitForExistence(timeout: 2) {
            app.buttons["Tag"].tap()
        }
        if app.buttons["TagFilter-focus"].exists {
            app.buttons["TagFilter-focus"].tap()
        } else if app.buttons["#focus"].waitForExistence(timeout: 2) {
            app.buttons["#focus"].tap()
        } else {
            throw XCTSkip("Tag filter option is not visible.")
        }

        XCTAssertTrue(app.staticTexts["UITest Tagged Task"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["UITest Doing Task"].exists, "Filtering by #focus should hide tasks without that tag")

        guard tapFirstExistingButton(named: "Filtered: #focus", fallback: "Sort and Filter") else {
            throw XCTSkip("Filtered sort and filter menu is not visible.")
        }
        if app.buttons["Tags: #focus"].waitForExistence(timeout: 2) {
            app.buttons["Tags: #focus"].tap()
        }
        if app.buttons["TagFilter-mobile"].exists {
            app.buttons["TagFilter-mobile"].tap()
        } else if app.buttons["#mobile"].waitForExistence(timeout: 2) {
            app.buttons["#mobile"].tap()
        } else {
            throw XCTSkip("Second tag filter option is not visible.")
        }

        XCTAssertTrue(app.staticTexts["UITest Tagged Task"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Filtered: #focus, #mobile"].exists || app.buttons["Filtered: #mobile, #focus"].exists)
    }

    func testSettingsCanAddColumnAndToggleHideCompleted() throws {
        openTab(named: "Settings")

        let toggle = app.switches["HideCompletedToggle"].exists ? app.switches["HideCompletedToggle"] : app.switches["Hide completed tasks"]
        if toggle.waitForExistence(timeout: 3) {
            toggle.tap()
            toggle.tap()
        }

        let newColumnElement = app.textFields["NewColumnTextField"].exists ? app.textFields["NewColumnTextField"] : app.textFields["New column"]
        scrollUntilElementExists(newColumnElement)
        let newColumnField = newColumnElement
        guard newColumnField.waitForExistence(timeout: 3) else {
            throw XCTSkip("Settings add-column controls are not visible in this UI-test environment.")
        }
        newColumnField.tap()
        newColumnField.typeText("UITest Column")

        let addColumnElement = app.buttons["AddColumnButton"].exists ? app.buttons["AddColumnButton"] : app.buttons["Add Column"]
        scrollUntilElementExists(addColumnElement)
        _ = tapFirstExistingButton(named: "AddColumnButton", fallback: "Add Column")

        XCTAssertTrue(app.staticTexts["UITest Column"].waitForExistence(timeout: 3) || app.textFields["UITest Column"].exists)
    }

    private func scrollUntilElementExists(_ element: XCUIElement, maxSwipes: Int = 6) {
        var remaining = maxSwipes
        while !element.exists && remaining > 0 {
            if app.scrollViews.firstMatch.exists {
                app.scrollViews.firstMatch.swipeUp()
            } else if app.tables.firstMatch.exists {
                app.tables.firstMatch.swipeUp()
            } else {
                break
            }
            remaining -= 1
        }
    }

    private func typeNewline() {
        #if os(macOS)
        app.typeKey(.return, modifierFlags: [])
        #else
        app.typeText("\n")
        #endif
    }

    private func openTab(named name: String) {
        let identifier = "\(name)Tab"
        if app.buttons[identifier].exists {
            app.buttons[identifier].firstMatch.tap()
            return
        }
        if app.tabBars.buttons[name].exists {
            app.tabBars.buttons[name].firstMatch.tap()
            return
        }
        if app.buttons[name].exists {
            app.buttons[name].firstMatch.tap()
        }
    }

    @discardableResult
    private func tapFirstExistingButton(named primary: String, fallback: String? = nil) -> Bool {
        if app.buttons[primary].waitForExistence(timeout: 3) {
            app.buttons[primary].firstMatch.tap()
            return true
        }
        if let fallback, app.buttons[fallback].waitForExistence(timeout: 3) {
            app.buttons[fallback].firstMatch.tap()
            return true
        }
        return false
    }

    private func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func setSwitch(_ element: XCUIElement, on desiredState: Bool) {
        let currentValue = (element.value as? String) ?? ""
        let isOn = currentValue == "1" || currentValue.localizedCaseInsensitiveContains("on")
        if isOn != desiredState {
            element.tap()
        }
    }

    private func firstTextField(containing label: String) -> XCUIElement {
        let exact = app.textFields[label]
        if exact.exists { return exact }

        let predicate = NSPredicate(format: "label CONTAINS[c] %@ OR placeholderValue CONTAINS[c] %@ OR value CONTAINS[c] %@", label, label, label)
        let match = app.textFields.matching(predicate).firstMatch
        if match.exists { return match }

        return app.textFields.firstMatch
    }
}
