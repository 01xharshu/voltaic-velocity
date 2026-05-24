import SwiftUI

enum AppTheme: String, CaseIterable {
    case system = "System"
    case dark = "Dark"
    case light = "Light"
    case metallic = "Metallic"
}

struct SettingsView: View {
    @AppStorage("ollamaBaseURL") private var ollamaBaseURL = "http://localhost:11434"
    @AppStorage("defaultModel") private var defaultModel = "qwen2.5-coder"
    @AppStorage("terminalFontSize") private var terminalFontSize = 13.0
    @AppStorage("editorFontSize") private var editorFontSize = 14.0
    @AppStorage("autoSaveEnabled") private var autoSaveEnabled = true
    @AppStorage("showHiddenFiles") private var showHiddenFiles = false
    @AppStorage("appTheme") private var appTheme: String = AppTheme.system.rawValue
    @AppStorage("terminalShell") private var terminalShell = "/bin/zsh"
    @AppStorage("editorTabSize") private var editorTabSize = 4
    @AppStorage("editorShowLineNumbers") private var editorShowLineNumbers = true
    @AppStorage("editorWordWrap") private var editorWordWrap = false
    @AppStorage("agentFullAccess") private var agentFullAccess = false
    @AppStorage("autoOpenEditedFiles") private var autoOpenEditedFiles = true
    @AppStorage("enableShellIntegration") private var enableShellIntegration = true
    @AppStorage("agentAutoFixLints") private var agentAutoFixLints = false
    @AppStorage("explainAndFixInCurrentConversation") private var explainAndFixInCurrentConversation = true

    var body: some View {
        TabView {
            appearanceSettings
                .tabItem { Label("Appearance", systemImage: "paintpalette") }

            ollamaSettings
                .tabItem { Label("AI Engine", systemImage: "cpu") }

            editorSettings
                .tabItem { Label("Editor", systemImage: "doc.text") }

            terminalSettings
                .tabItem { Label("Terminal", systemImage: "terminal") }

            agentSettings
                .tabItem { Label("Agent", systemImage: "sparkles") }

            generalSettings
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 520, height: 400)
    }

    // MARK: — Appearance
    private var appearanceSettings: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $appTheme) {
                    ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                        Text(theme.rawValue).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)

                // Theme preview
                HStack(spacing: 12) {
                    ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                        themePreview(theme)
                    }
                }
                .padding(.top, 8)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func themePreview(_ theme: AppTheme) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 6)
                .fill(themeBackground(theme))
                .frame(width: 80, height: 50)
                .overlay(
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(themeForeground(theme).opacity(0.6))
                            .frame(width: 50, height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(themeForeground(theme).opacity(0.3))
                            .frame(width: 40, height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(themeForeground(theme).opacity(0.4))
                            .frame(width: 55, height: 4)
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(appTheme == theme.rawValue ? Color.accentColor : Color.clear, lineWidth: 2)
                )
                .onTapGesture {
                    appTheme = theme.rawValue
                }
            Text(theme.rawValue)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    private func themeBackground(_ theme: AppTheme) -> Color {
        switch theme {
        case .system: return Color(NSColor.windowBackgroundColor)
        case .dark: return Color(red: 0.10, green: 0.10, blue: 0.12)
        case .light: return Color(red: 0.97, green: 0.97, blue: 0.98)
        case .metallic: return Color(red: 0.18, green: 0.20, blue: 0.25)
        }
    }

    private func themeForeground(_ theme: AppTheme) -> Color {
        switch theme {
        case .system: return Color.primary
        case .dark: return Color.white
        case .light: return Color.black
        case .metallic: return Color(red: 0.7, green: 0.75, blue: 0.85)
        }
    }

    // MARK: — AI Engine
    @AppStorage("activeModels") private var activeModelsString = "qwen2.5-coder"
    @AppStorage("useMLXEngine") private var useMLXEngine = false
    @AppStorage("isMultiAgentEnabled") private var isMultiAgentEnabled = true
    @AppStorage("autonomyLevel") private var autonomyLevel = "Fully Autonomous"
    
    @State private var availableModels: [String] = []
    @State private var isFetchingModels = false
    
    private var activeModelsList: [String] {
        activeModelsString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    
    private func toggleModel(_ model: String) {
        var list = activeModelsList
        if list.contains(model) {
            list.removeAll { $0 == model }
        } else {
            list.append(model)
        }
        activeModelsString = list.joined(separator: ", ")
    }
    
    private func fetchModels() {
        guard !isFetchingModels else { return }
        isFetchingModels = true
        Task {
            do {
                let fetchedModels: [String]
                if useMLXEngine {
                    fetchedModels = try await MLXService().fetchModels()
                } else {
                    fetchedModels = try await OllamaService().fetchModels()
                }
                await MainActor.run { self.availableModels = fetchedModels }
            } catch {
                print("Failed to fetch models: \(error)")
            }
            await MainActor.run { self.isFetchingModels = false }
        }
    }
    
    private var ollamaSettings: some View {
        Form {
            Section("Inference Engine") {
                Toggle("Use Built-in MLX Engine", isOn: $useMLXEngine)
                if useMLXEngine {
                    Text("Using native Apple Silicon MLX inference (downloads Qwen2.5-Coder directly).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Using external Ollama instance (localhost:11434).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                Toggle("Enable Multi-Agent Team", isOn: $isMultiAgentEnabled)
                Picker("Autonomy Level", selection: $autonomyLevel) {
                    Text("Fully Autonomous").tag("Fully Autonomous")
                    Text("Manual Approval").tag("Manual Approval")
                }
                .pickerStyle(.segmented)
            }

            Section("Connection (Ollama Only)") {
                HStack {
                    Text("Base URL")
                    Spacer()
                    TextField("", text: $ollamaBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 260)
                }

                HStack {
                    Text("Default Model")
                    Spacer()
                    TextField("", text: $defaultModel)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 260)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Active Models")
                        Spacer()
                        if isFetchingModels {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button(action: fetchModels) {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    if availableModels.isEmpty && !isFetchingModels {
                        Text("No models found").foregroundColor(.secondary).font(.caption)
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(spacing: 2) {
                                ForEach(availableModels, id: \.self) { model in
                                    Toggle(isOn: Binding(
                                        get: { activeModelsList.contains(model) },
                                        set: { _ in toggleModel(model) }
                                    )) {
                                        Text(model)
                                            .font(.system(size: 13, design: .monospaced))
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(activeModelsList.contains(model) ? Color.accentColor.opacity(0.1) : Color.clear)
                                    .cornerRadius(6)
                                }
                            }
                        }
                        .frame(height: 120)
                        .padding(6)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    }
                }
            }
            .onAppear {
                fetchModels()
            }
            .onChange(of: useMLXEngine) {
                fetchModels()
            }

            Section("Info") {
                Text(useMLXEngine ? "Models are auto-downloaded on first launch for MLX Engine." : "Models are fetched dynamically from your local Ollama instance on startup. To install a model, run:")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("ollama pull <model-name>")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.primary)
                    .padding(6)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: — Editor
    private var editorSettings: some View {
        Form {
            Section("Font") {
                HStack {
                    Text("Font Size")
                    Spacer()
                    Stepper("\(Int(editorFontSize)) pt", value: $editorFontSize, in: 10...28, step: 1)
                }
            }

            Section("Behavior") {
                HStack {
                    Text("Tab Size")
                    Spacer()
                    Stepper("\(editorTabSize) spaces", value: $editorTabSize, in: 2...8, step: 2)
                }

                Toggle("Show Line Numbers", isOn: $editorShowLineNumbers)
                Toggle("Word Wrap", isOn: $editorWordWrap)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: — Terminal
    private var terminalSettings: some View {
        Form {
            Section("Font") {
                HStack {
                    Text("Font Size")
                    Spacer()
                    Stepper("\(Int(terminalFontSize)) pt", value: $terminalFontSize, in: 10...28, step: 1)
                }
            }

            Section("Shell") {
                HStack {
                    Text("Shell Path")
                    Spacer()
                    TextField("", text: $terminalShell)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 260)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: — Agent
    private var agentSettings: some View {
        Form {
            Section("Permissions & Access") {
                Toggle("Full access", isOn: $agentFullAccess)
                Text("Agents have full access to your machine and external resources.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("File & Terminal Behavior") {
                Toggle("Auto-Open Edited Files", isOn: $autoOpenEditedFiles)
                Text("Open files in the background if Agent creates or edits them")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Enable Shell Integration", isOn: $enableShellIntegration)
                Text("When enabled, Agent will use IDE's shell integration to detect and report terminal command execution.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Linting & Fixing") {
                Toggle("Agent Auto-Fix Lints", isOn: $agentAutoFixLints)
                Text("When enabled, Agent is given awareness of lint errors created by its edits and may fix them without explicit user prompting.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Explain and Fix in Current Conversation", isOn: $explainAndFixInCurrentConversation)
                Text("When enabled, 'Explain and Fix' actions will continue in the current conversation instead of starting a new one.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: — General
    private var generalSettings: some View {
        Form {
            Section("Files") {
                Toggle("Auto-save on tab switch", isOn: $autoSaveEnabled)
                Toggle("Show hidden files in explorer", isOn: $showHiddenFiles)
            }

            Section("About") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Volt Velocity")
                            .font(.system(size: 14, weight: .semibold))
                        Text("AI-Powered Native macOS IDE")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("Version 1.0.0")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
