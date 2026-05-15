import SwiftUI

@main
struct Kanban_RemindersApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = KanbanBoardViewModel()

    var body: some Scene {
        WindowGroup {
            KanbanBoardView(viewModel: viewModel)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await viewModel.load() }
            }
        }
    }
}
