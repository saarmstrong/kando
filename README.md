# Kanban Reminders

A simple SwiftUI iOS 17+ and macOS 14+ app that turns native Apple Reminders into a lightweight Kanban board.

## GitHub Pages

Static pages for App Store/support links live in `docs/` and can be hosted with GitHub Pages:

- `docs/index.html` — landing page
- `docs/privacy.html` — privacy policy
- `docs/support.html` — support page

In GitHub, enable Pages from **Settings → Pages → Deploy from a branch**, then choose the `docs/` folder.

## What it does

- Requests full Reminders access on first launch.
- Creates or reuses native Reminders lists with a Kando/Kanban prefix:
  - `Kando - Kanban - Backlog`
  - `Kando - Kanban - Doing`
  - `Kando - Kanban - Done`
- Shows reminders from those lists as cards in horizontal Kanban columns.
- Includes an Eisenhower Matrix tab as another visual view of the same Kanban tasks.
- Lets you create and edit title, notes, due date, priority, completion, and column/quadrant.
- Moves cards with a long-press context menu or drag/drop.
- Supports System, Light, and Dark appearance modes.
- Lets you rename, reorder, hide/show, color, add, and remove Kanban columns in Settings, and reorder columns directly on the board by dragging the column title handle.
- Refreshes on pull-to-refresh.
- Supports configurable WIP limits with visual warning colors as columns approach or reach capacity.

## Setup

1. Open `Kanban Reminders.xcodeproj` in Xcode 15+.
2. Select the `Kanban Reminders` target.
3. Set your development team and replace the example bundle identifier with your own if you want to run on a physical device or distribute/archive the app.
4. Build and run on iOS 17 or newer, or choose **My Mac** as the run destination for the native macOS 14+ app.

The project includes the required Reminders privacy usage strings in `Kanban Reminders/Info.plist`. The same SwiftUI target supports iPhone, iPad, and native macOS with shared EventKit/iCloud Reminders data.

## Tests

The project includes an XCTest unit test target, `Kanban RemindersTests`, and an Xcode test plan, `Kanban Reminders.xctestplan`, attached to the shared `Kanban Reminders` scheme.

Current unit tests cover task sorting and filtering behavior for priority and due dates. The UI test target, `Kanban RemindersUITests`, launches the app in a safe UI-test mode with in-memory sample reminders so it can exercise the board, Matrix, Settings, and task creation without touching your real Apple Reminders data.

Run all unit and UI tests in Xcode with Product → Test. The shared `Kanban Reminders` scheme uses `Kanban Reminders.xctestplan`, which includes both `Kanban RemindersTests` and `Kanban RemindersUITests`.

Command-line examples:

```bash
# iOS Simulator: unit + UI tests
xcodebuild -project "Kanban Reminders.xcodeproj" -scheme "Kanban Reminders" -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# macOS: unit + UI tests. Some desktop UI flows may skip if the local runner cannot expose the seeded UI.
xcodebuild -project "Kanban Reminders.xcodeproj" -scheme "Kanban Reminders" -sdk macosx -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO

# Unit tests only
xcodebuild -project "Kanban Reminders.xcodeproj" -scheme "Kanban Reminders" -sdk macosx test -skip-testing:"Kanban RemindersUITests" CODE_SIGNING_ALLOWED=NO
```

## License

This project is released under the MIT License. You are welcome to fork it, modify it, build on it, and redistribute it. Please keep the copyright notice and license text with copies or substantial portions of the project so attribution stays intact.

See [`LICENSE`](LICENSE) for the full license text.

## Sync and limitations

This app does **not** implement its own cloud sync or database. Tasks are saved as native Apple Reminders via EventKit. Sync happens through the user's Apple Reminders/iCloud configuration. If iCloud Reminders is disabled, tasks remain in the configured local or account-backed Reminders store.

The lightweight `ReminderTask` model is only a UI projection. Apple Reminders remains the source of truth.

Column display names and Matrix quadrant names are app settings saved locally. The backing Apple Reminders list names use the `Kando - Kanban - ...` prefix and are kept stable after creation so existing tasks do not disconnect when you rename a column. Existing older lists such as `Kanban - Backlog` are renamed automatically when loaded.

Matrix quadrant assignments are saved locally in app settings as an alternate view of the same native Reminders tasks. The Kanban list/status remains the source of truth for where the reminder is stored in Apple Reminders, so tasks are not moved into separate Matrix Reminders lists.
