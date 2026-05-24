import SwiftUI
import AppKit

// MARK: — Custom NSTextView that forwards keystrokes to shell stdin
final class ShellTextView: NSTextView {
    var onInput: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func becomeFirstResponder() -> Bool {
        return true
    }

    override func keyDown(with event: NSEvent) {
        // Handle special keys
        switch event.keyCode {
        case 36: // Return
            onInput?("\n")
        case 51: // Backspace
            onInput?("\u{7f}")
        case 48: // Tab
            onInput?("\t")
        case 126: // Up arrow
            onInput?("\u{1b}[A")
        case 125: // Down arrow
            onInput?("\u{1b}[B")
        case 124: // Right arrow
            onInput?("\u{1b}[C")
        case 123: // Left arrow
            onInput?("\u{1b}[D")
        default:
            // Handle Ctrl+C, Ctrl+D, Ctrl+Z etc.
            if event.modifierFlags.contains(.control), let chars = event.charactersIgnoringModifiers {
                for char in chars {
                    let asciiVal = char.asciiValue ?? 0
                    if asciiVal >= 97 && asciiVal <= 122 { // a-z
                        let ctrlChar = Character(UnicodeScalar(asciiVal - 96))
                        onInput?(String(ctrlChar))
                    }
                }
            } else if let chars = event.characters, !chars.isEmpty {
                onInput?(chars)
            }
        }
    }

    // Prevent the normal editing behavior — all input goes to shell
    override func insertText(_ string: Any, replacementRange: NSRange) {
        if let str = string as? String {
            onInput?(str)
        }
    }

    override func doCommand(by selector: Selector) {
        // Swallow default commands
    }
}

// MARK: — NSViewRepresentable wrapper
struct TerminalNSViewRepresentable: NSViewRepresentable {
    @ObservedObject var viewModel: TerminalViewModel

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)

        let textView = ShellTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)
        textView.textContainerInset = NSSize(width: 10, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor(red: 0.85, green: 0.87, blue: 0.90, alpha: 1.0)
        textView.insertionPointColor = NSColor(red: 0.4, green: 0.85, blue: 0.55, alpha: 1.0)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        textView.onInput = { [weak viewModel] chars in
            viewModel?.sendRawInput(chars)
        }

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        // Make the text view first responder once the window is available
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let window = textView.window {
                window.makeFirstResponder(textView)
            }
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        let newOutput = viewModel.output

        if textView.string != newOutput {
            // Preserve selection if user is selecting text
            let wasAtBottom = context.coordinator.isAtBottom(scrollView: scrollView)

            textView.string = newOutput

            if wasAtBottom {
                textView.scrollToEndOfDocument(nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var textView: ShellTextView?
        var scrollView: NSScrollView?

        func isAtBottom(scrollView: NSScrollView) -> Bool {
            guard let documentView = scrollView.documentView else { return true }
            let visibleRect = scrollView.contentView.bounds
            let contentHeight = documentView.frame.height
            return visibleRect.maxY >= contentHeight - 20
        }
    }
}

// MARK: — SwiftUI Terminal View
struct TerminalView: View {
    @ObservedObject var terminalManager: TerminalManagerViewModel

    var body: some View {
        HStack(spacing: 0) {
            // MAIN TERMINAL AREA
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    Label("TERMINAL", systemImage: "terminal.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)

                    Spacer()

                    if let activeTerminal = terminalManager.activeTerminal,
                       let folder = activeTerminal.workingDirectory {
                        Text(folder.lastPathComponent)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.trailing, 8)
                    }

                    Button {
                        terminalManager.activeTerminal?.clearOutput()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .help("Clear terminal")
                    .padding(.trailing, 12)
                }
                .background(Color(red: 0.10, green: 0.10, blue: 0.12))

                // Inline terminal
                if let activeTerminal = terminalManager.activeTerminal {
                    TerminalNSViewRepresentable(viewModel: activeTerminal)
                        .id(activeTerminal.id) // Force recreation if terminal switches
                } else {
                    Spacer()
                    Text("No Active Terminals")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                }
            }
            
            // SIDEBAR
            VStack(spacing: 0) {
                // Sidebar Header
                HStack {
                    Text("INSTANCES")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                    Button {
                        terminalManager.createTerminal()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("New Terminal")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(red: 0.08, green: 0.08, blue: 0.10))
                
                Divider().background(Color.white.opacity(0.1))
                
                // Terminal List
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(terminalManager.terminals) { terminal in
                            HStack {
                                Label(terminal.name, systemImage: "chevron.right.square")
                                    .font(.system(size: 11))
                                    .foregroundColor(terminalManager.activeTerminalId == terminal.id ? .white : .white.opacity(0.6))
                                
                                Spacer()
                                
                                // Hover trash can (always visible for now)
                                Button {
                                    terminalManager.removeTerminal(id: terminal.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(terminalManager.activeTerminalId == terminal.id ? Color.white.opacity(0.1) : Color.clear)
                            .cornerRadius(4)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                terminalManager.selectTerminal(id: terminal.id)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                }
            }
            .frame(width: 150)
            .background(Color(red: 0.10, green: 0.10, blue: 0.12))
            
            Divider()
                .background(Color.white.opacity(0.1))
        }
    }
}
