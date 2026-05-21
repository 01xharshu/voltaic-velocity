import SwiftUI
import CodeEditorView

struct ContentView: View {
    @ObservedObject var projectViewModel: ProjectViewModel
    @ObservedObject var editorViewModel: EditorViewModel
    @ObservedObject var terminalViewModel: TerminalViewModel
    @ObservedObject var gitViewModel: GitViewModel
    @ObservedObject var agentViewModel: AgentViewModel
    @ObservedObject var liveServerViewModel: LiveServerViewModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appTheme") private var appTheme: String = AppTheme.system.rawValue

    private var preferredScheme: ColorScheme? {
        switch AppTheme(rawValue: appTheme) ?? .system {
        case .system: return nil
        case .dark, .metallic: return .dark
        case .light: return .light
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                SidebarView(
                    projectViewModel: projectViewModel,
                    editorViewModel: editorViewModel
                )
                .navigationTitle("Explorer")
            } content: {
                VSplitView {
                    VStack(spacing: 0) {
                        EditorTabBarView(
                            editorViewModel: editorViewModel,
                            projectViewModel: projectViewModel
                        )
                        Divider()
                        EditorView(
                            editorViewModel: editorViewModel,
                            projectViewModel: projectViewModel
                        )
                    }
                    .frame(minHeight: 420)

                    Divider()

                    TerminalView(terminalViewModel: terminalViewModel)
                        .frame(minHeight: 180)
                }
            } detail: {
                AgentPanelView(
                    agentViewModel: agentViewModel,
                    projectViewModel: projectViewModel,
                    editorViewModel: editorViewModel,
                    terminalViewModel: terminalViewModel
                )
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button(action: projectViewModel.openProjectFolder) {
                        Label("Open Project", systemImage: "folder.badge.plus")
                    }
                    Button(action: projectViewModel.refreshWorkspace) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                ToolbarItemGroup(placement: .automatic) {
                    Button(action: editorViewModel.saveActiveFile) {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    Button(action: agentViewModel.startNewChat) {
                        Label("New Chat", systemImage: "bubble.left.and.bubble.right")
                    }
                }
            }
            .sheet(isPresented: $agentViewModel.isShowingCommandPalette) {
                CommandPaletteView(agentViewModel: agentViewModel,
                                   projectViewModel: projectViewModel,
                                   editorViewModel: editorViewModel,
                                   terminalViewModel: terminalViewModel,
                                   gitViewModel: gitViewModel)
            }
            .sheet(isPresented: $gitViewModel.isShowingDiffPreview) {
                DiffPreviewView(title: gitViewModel.diffTitle, diffText: gitViewModel.diffText)
            }
            .environment(\.codeEditorTheme, colorScheme == .dark ? Theme.defaultDark : Theme.defaultLight)
            .onAppear {
                projectViewModel.restoreLastProject()
                terminalViewModel.restoreWorkingDirectory(from: projectViewModel.projectURL)
                agentViewModel.link(projectViewModel: projectViewModel,
                                    editorViewModel: editorViewModel,
                                    terminalViewModel: terminalViewModel)
                Task {
                    await gitViewModel.refreshRepositoryStatus(projectURL: projectViewModel.projectURL)
                }
            }
            .onChange(of: projectViewModel.projectURL) { _, projectURL in
                Task {
                    await gitViewModel.refreshRepositoryStatus(projectURL: projectURL)
                    terminalViewModel.restoreWorkingDirectory(from: projectURL)
                }
            }
            
            // VS Code Style Status Bar
            statusBar
        }
        .preferredColorScheme(preferredScheme)
    }
    
    private var statusBar: some View {
        HStack {
            Button(action: {
                liveServerViewModel.toggleServer(
                    in: projectViewModel.projectURL,
                    activeFileURL: editorViewModel.activeFile?.url
                )
            }) {
                HStack(spacing: 4) {
                    Image(systemName: liveServerViewModel.isRunning ? "antenna.radiowaves.left.and.right" : "play.circle")
                    Text(liveServerViewModel.isRunning ? "Port: \(liveServerViewModel.port)" : "Go Live")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
        .frame(height: 24)
        .background(Color.blue)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(
            projectViewModel: ProjectViewModel(),
            editorViewModel: EditorViewModel(),
            terminalViewModel: TerminalViewModel(),
            gitViewModel: GitViewModel(),
            agentViewModel: AgentViewModel(),
            liveServerViewModel: LiveServerViewModel()
        )
    }
}
