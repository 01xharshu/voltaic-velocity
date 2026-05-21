import SwiftUI

struct TerminalView: View {
    @ObservedObject var terminalViewModel: TerminalViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Terminal")
                    .font(.headline)
                Spacer()
                if let folder = terminalViewModel.workingDirectory {
                    Text(folder.lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 10)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    Text(terminalViewModel.output)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .id("terminal-end")
                }
                .background(Color.black.opacity(0.95))
                .cornerRadius(6)
                .onChange(of: terminalViewModel.output) { _ in
                    proxy.scrollTo("terminal-end", anchor: .bottom)
                }
            }
            .frame(maxHeight: 210)

            HStack {
                TextField("Run command…", text: $terminalViewModel.inputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { terminalViewModel.runCurrentCommand() }
                Button(action: terminalViewModel.runCurrentCommand) {
                    Label("Send", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(terminalViewModel.isRunningCommand)
            }
            .padding()
        }
    }
}
