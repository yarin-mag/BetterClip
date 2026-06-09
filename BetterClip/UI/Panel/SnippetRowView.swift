// BetterClip/UI/Panel/SnippetRowView.swift
import SwiftUI

struct SnippetRowView: View, Equatable {
    let snippet: Snippet
    let isSelected: Bool
    let index: Int
    var depth: Int = 0
    @State private var isHovered = false

    static func == (lhs: SnippetRowView, rhs: SnippetRowView) -> Bool {
        lhs.isSelected == rhs.isSelected && lhs.snippet.id == rhs.snippet.id &&
        lhs.index == rhs.index && lhs.depth == rhs.depth
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.quaternary)
                .frame(width: 20, alignment: .trailing)
            Image(systemName: "pin.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(snippet.content)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            if let shortcut = snippet.shortcut {
                Text(shortcut)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(3)
            }
        }
        .padding(.leading, 12 + CGFloat(depth) * 18)
        .padding(.trailing, 12)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accentColor.opacity(0.18) : isHovered ? Color.primary.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
