import SwiftUI

struct PermissionDeniedView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Reminders Access Needed", systemImage: "checklist")
        } description: {
            Text("Kanban Reminders stores tasks as native Apple Reminders. Please allow Reminders access in Settings.")
        } actions: {
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: settingsURL)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}
