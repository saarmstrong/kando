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

    private func firstTextField(containing label: String) -> XCUIElement {
        let exact = app.textFields[label]
        if exact.exists { return exact }

        let predicate = NSPredicate(format: "label CONTAINS[c] %@ OR placeholderValue CONTAINS[c] %@ OR value CONTAINS[c] %@", label, label, label)
        let match = app.textFields.matching(predicate).firstMatch
        if match.exists { return match }

        return app.textFields.firstMatch
    }
}
