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

    var body: some View {
        TabView {
            appearanceSettings
                .tabItem { Label("Appearance", systemImage: "paintpalette") }

            ollamaSettings
                .tabItem { Label("AI / Ollama", systemImage: "cpu") }

            editorSettings
                .tabItem { Label("Editor", systemImage: "doc.text") }

            terminalSettings
                .tabItem { Label("Terminal", systemImage: "terminal") }

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

    // MARK: — AI / Ollama
    private var ollamaSettings: some View {
        Form {
            Section("Connection") {
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
            }

            Section("Info") {
                Text("Models are fetched dynamically from your local Ollama instance on startup. To install a model, run:")
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
                        Text("Voltaic Velocity")
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
