import SwiftUI

@main
struct VoltaicVelocityApp: App {
    @StateObject private var projectViewModel = ProjectViewModel()
    @StateObject private var editorViewModel = EditorViewModel()
    @StateObject private var terminalViewModel = TerminalViewModel()
    @StateObject private var gitViewModel = GitViewModel()
    @StateObject private var agentViewModel = AgentViewModel()

    init() {
        // Ensure app remains responsive during long-running tool operations
        AppDefaults.registerDefaults()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                projectViewModel: projectViewModel,
                editorViewModel: editorViewModel,
                terminalViewModel: terminalViewModel,
                gitViewModel: gitViewModel,
                agentViewModel: agentViewModel
            )
            .frame(minWidth: 1300, minHeight: 800)
            .environmentObject(projectViewModel)
            .environmentObject(editorViewModel)
            .environmentObject(terminalViewModel)
            .environmentObject(agentViewModel)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Project…") {
                    projectViewModel.openProjectFolder()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Command Palette…") {
                    projectViewModel.isShowingCommandPalette.toggle()
                }
                .keyboardShortcut("k", modifiers: [.command])
            }
        }
    }
}

private enum AppDefaults {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            "VoltaicVelocityLastProjectPath": ""
        ])
    }
}
