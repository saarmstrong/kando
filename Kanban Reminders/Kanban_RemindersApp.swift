import SwiftUI

@main
struct Kanban_RemindersApp: App {
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(settings)
                .preferredColorScheme(settings.colorMode.colorScheme)
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var boardViewModel = KanbanBoardViewModel(columns: KanbanColumn.defaultKanban)
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            KanbanBoardView(title: "Kanban", columns: settings.kanbanColumns, viewModel: boardViewModel)
                .tabItem { Label("Kanban", systemImage: "rectangle.3.group") }

            EisenhowerMatrixView(viewModel: boardViewModel)
                .tabItem { Label("Matrix", systemImage: "square.grid.2x2") }

            SettingsHelpView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .onAppear {
            boardViewModel.updateColumns(settings.kanbanColumns)
        }
        .onChange(of: settings.kanbanColumns) { _, newColumns in
            boardViewModel.updateColumns(newColumns)
            Task { await boardViewModel.load() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await boardViewModel.load() }
            }
        }
    }
}
