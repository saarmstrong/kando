import SwiftUI

struct SettingsHelpView: View {
    var body: some View {
        List {
            Section("How sync works") {
                Text("This app does not run its own cloud service. Tasks are saved as native Apple Reminders in three lists: Kanban - Backlog, Kanban - Doing, and Kanban - Done.")
                Text("Sync depends on your Apple Reminders and iCloud settings. If iCloud Reminders is disabled, tasks remain local to the configured Reminders account.")
            }

            Section("Tips") {
                Label("Pull down on the board to refresh.", systemImage: "arrow.clockwise")
                Label("Long-press a card to move it between columns.", systemImage: "hand.tap")
                Label("Drag cards between columns on supported devices.", systemImage: "rectangle.and.hand.point.up.left")
            }
        }
        .navigationTitle("Help")
    }
}
