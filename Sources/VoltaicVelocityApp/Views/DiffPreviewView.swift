import SwiftUI

struct DiffPreviewView: View {
    let title: String
    let diffText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.title2)
                    .bold()
                Spacer()
            }
            .padding()

            Divider()

            ScrollView {
                Text(diffText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .frame(minWidth: 620, minHeight: 480)
    }
}
