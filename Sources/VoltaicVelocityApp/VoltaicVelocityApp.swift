import SwiftUI

@main
struct VoltaicVelocityApp: App {
    @StateObject private var projectViewModel = ProjectViewModel()
    @StateObject private var editorViewModel = EditorViewModel()
    @StateObject private var gitViewModel = GitViewModel()
    @StateObject private var agentViewModel = AgentViewModel()
    @StateObject private var liveServerViewModel = LiveServerViewModel()
    @StateObject private var terminalManager = TerminalManagerViewModel()

    init() {
        // Ensure app remains responsive during long-running tool operations
        AppDefaults.registerDefaults()
        
        // Start the background python agent server
        BackendService.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                projectViewModel: projectViewModel,
                editorViewModel: editorViewModel,
                terminalManager: terminalManager,
                gitViewModel: gitViewModel,
                agentViewModel: agentViewModel,
                liveServerViewModel: liveServerViewModel
            )
            .frame(minWidth: 1300, minHeight: 800)
            .environmentObject(projectViewModel)
            .environmentObject(editorViewModel)
            .environmentObject(terminalManager)
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

            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    editorViewModel.saveActiveFile()
                }
                .keyboardShortcut("s", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
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
