import SwiftUI

struct SafetyDiffPreviewView: View {
    let pendingAction: PendingFileAction
    var onApply: () -> Void
    var onModify: () -> Void
    var onCancel: () -> Void

    @State private var diffLines: [DiffLine] = []

    struct DiffLine: Identifiable {
        let id = UUID()
        let type: LineType
        let text: String
    }

    enum LineType {
        case added, removed, unchanged
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Safety Diff Preview: \(pendingAction.summary)")
                    .font(.title2)
                    .bold()
                Spacer()
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(diffLines) { line in
                        Text(line.text)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                line.type == .added ? Color.green.opacity(0.2) :
                                line.type == .removed ? Color.red.opacity(0.2) :
                                Color.clear
                            )
                    }
                }
                .padding(.vertical)
            }
            .background(Color(NSColor.textBackgroundColor))
            
            Divider()
            
            HStack {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
                
                Button("Modify") {
                    onModify()
                }
                
                Button("Apply") {
                    onApply()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            computeDiff()
        }
    }

    private func computeDiff() {
        let oldLines = (pendingAction.existingText ?? "").components(separatedBy: .newlines)
        let newLines = pendingAction.newText.components(separatedBy: .newlines)
        let diff = newLines.difference(from: oldLines)
        
        var result: [DiffLine] = []
        for change in diff {
            switch change {
            case let .remove(_, element, _):
                result.append(DiffLine(type: .removed, text: "- " + element))
            case let .insert(_, element, _):
                result.append(DiffLine(type: .added, text: "+ " + element))
            }
        }
        
        if result.isEmpty {
            self.diffLines = [.init(type: .unchanged, text: "No changes detected.")]
        } else {
            self.diffLines = result
        }
    }
}
