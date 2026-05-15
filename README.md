# Kanban Reminders

A simple SwiftUI iOS 17+ app that turns native Apple Reminders into a lightweight Kanban board.

## What it does

- Requests full Reminders access on first launch.
- Creates or reuses three native Reminders lists:
  - `Kanban - Backlog`
  - `Kanban - Doing`
  - `Kanban - Done`
- Shows reminders from those lists as cards in horizontal Kanban columns.
- Lets you create and edit title, notes, due date, priority, completion, and column.
- Moves cards with a long-press context menu or drag/drop.
- Refreshes on pull-to-refresh and when the app becomes active.

## Setup

1. Open `Kanban Reminders.xcodeproj` in Xcode 15+.
2. Select the `Kanban Reminders` target.
3. Set your development team and bundle identifier if you want to run on a physical device.
4. Build and run on iOS 17 or newer.

The project includes the required Reminders privacy usage strings in `Kanban Reminders/Info.plist`.

## Sync and limitations

This app does **not** implement its own cloud sync or database. Tasks are saved as native Apple Reminders via EventKit. Sync happens through the user's Apple Reminders/iCloud configuration. If iCloud Reminders is disabled, tasks remain in the configured local or account-backed Reminders store.

The lightweight `ReminderTask` model is only a UI projection. Apple Reminders remains the source of truth.
