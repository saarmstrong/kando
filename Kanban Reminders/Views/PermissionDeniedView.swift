import SwiftUI

struct PermissionDeniedView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Reminders Access Needed", systemImage: "checklist")
        } description: {
            Text("Kanban Reminders stores tasks as native Apple Reminders. Please allow Reminders access in System Settings/Settings.")
        } actions: {
            settingsLink
        }
        .padding()
    }

    @ViewBuilder
    private var settingsLink: some View {
        #if os(iOS)
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            Link("Open Settings", destination: settingsURL)
                .buttonStyle(.borderedProminent)
        }
        #elseif os(macOS)
        if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            Link("Open System Settings", destination: settingsURL)
                .buttonStyle(.borderedProminent)
        }
        #endif
    }
}
