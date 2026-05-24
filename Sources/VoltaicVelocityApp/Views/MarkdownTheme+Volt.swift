import SwiftUI
import MarkdownUI

extension Theme {
    public static let voltTheme = Theme()
        .text {
            ForegroundColor(.primary)
            FontSize(14)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.85))
            ForegroundColor(Color(red: 0.85, green: 0.87, blue: 0.90))
            BackgroundColor(Color(red: 0.12, green: 0.12, blue: 0.14))
        }
        .strong {
            FontWeight(.semibold)
        }
        .link {
            ForegroundColor(.blue)
        }
        .heading1 { configuration in
            VStack(alignment: .leading, spacing: 0) {
                configuration.label
                    .font(.system(size: 24, weight: .bold))
                    .padding(.bottom, 8)
                Divider()
                    .padding(.bottom, 16)
            }
        }
        .heading2 { configuration in
            configuration.label
                .font(.system(size: 20, weight: .semibold))
                .padding(.top, 16)
                .padding(.bottom, 8)
        }
        .heading3 { configuration in
            configuration.label
                .font(.system(size: 16, weight: .semibold))
                .padding(.top, 12)
                .padding(.bottom, 6)
        }
        .codeBlock { configuration in
            VStack(alignment: .leading, spacing: 0) {
                if let language = configuration.language, !language.isEmpty {
                    Text(language)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
                
                configuration.label
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.12, green: 0.12, blue: 0.14))
            .cornerRadius(10)
            .padding(.vertical, 8)
            .markdownMargin(top: 0, bottom: 8)
        }
        .blockquote { configuration in
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.blue.opacity(0.5))
                    .frame(width: 4)
                configuration.label
                    .padding(.leading, 12)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
}
