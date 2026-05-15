# Kanban Reminders

A simple SwiftUI iOS 17+ and macOS 14+ app that turns native Apple Reminders into a lightweight Kanban board.

## What it does

- Requests full Reminders access on first launch.
- Creates or reuses three native Reminders lists:
  - `Kanban - Backlog`
  - `Kanban - Doing`
  - `Kanban - Done`
- Shows reminders from those lists as cards in horizontal Kanban columns.
- Includes an Eisenhower Matrix tab as another visual view of the same Kanban tasks.
- Lets you create and edit title, notes, due date, priority, completion, and column/quadrant.
- Moves cards with a long-press context menu or drag/drop.
- Supports System, Light, and Dark appearance modes.
- Lets you rename, add, and remove Kanban columns and Matrix quadrants in Settings.
- Refreshes on pull-to-refresh.

## Setup

1. Open `Kanban Reminders.xcodeproj` in Xcode 15+.
2. Select the `Kanban Reminders` target.
3. Set your development team and bundle identifier if you want to run on a physical device or distribute the Mac app.
4. Build and run on iOS 17 or newer, or choose **My Mac** as the run destination for the native macOS 14+ app.

The project includes the required Reminders privacy usage strings in `Kanban Reminders/Info.plist`. The same SwiftUI target supports iPhone, iPad, and native macOS with shared EventKit/iCloud Reminders data.

## Sync and limitations

This app does **not** implement its own cloud sync or database. Tasks are saved as native Apple Reminders via EventKit. Sync happens through the user's Apple Reminders/iCloud configuration. If iCloud Reminders is disabled, tasks remain in the configured local or account-backed Reminders store.

The lightweight `ReminderTask` model is only a UI projection. Apple Reminders remains the source of truth.

Column display names and Matrix quadrant names are app settings saved locally. The backing Apple Reminders list names are kept stable after creation so existing tasks do not disconnect when you rename a column.

Matrix quadrant assignments are saved locally in app settings as an alternate view of the same native Reminders tasks. The Kanban list/status remains the source of truth for where the reminder is stored in Apple Reminders.
