// BetterClip/UI/Panel/ClipRowView.swift
import SwiftUI

struct ClipRowView: View, Equatable {
    let clip: Clip
    let isSelected: Bool
    let index: Int
    let onDelete: () -> Void
    @State private var isHovered = false

    static func == (lhs: ClipRowView, rhs: ClipRowView) -> Bool {
        lhs.isSelected == rhs.isSelected && lhs.clip.id == rhs.clip.id && lhs.index == rhs.index
    }

    var body: some View {
        HStack(spacing: 8) {
            rowNumber
            typeIcon
            content
            Spacer()
            if clip.type == .image, let hash = clip.blobHash {
                ImageThumbnailView(hash: hash)
            }
            Button(action: onDelete) {
                Image(systemName: "minus.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .help("Remove from history")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accentColor.opacity(0.18) : isHovered ? Color.primary.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private var rowNumber: some View {
        Text("\(index)")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.quaternary)
            .frame(width: 20, alignment: .trailing)
    }

    private var typeIcon: some View {
        Text(clip.type.iconLabel)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: 28)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(clip.displayText)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
            if let source = clip.appSource {
                Text(source)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct ImageThumbnailView: View {
    let hash: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 28)
                    .cornerRadius(3)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 28)
            }
        }
        .task(id: hash) {
            image = await Task.detached(priority: .utility) {
                guard let data = BlobStore.shared.read(hash: hash),
                      data.count < 50 * 1024 * 1024 else { return nil }
                return NSImage(data: data)
            }.value
        }
    }
}

private extension ClipType {
    var iconLabel: String {
        switch self {
        case .text:  return "txt"
        case .image: return "img"
        case .rtf:   return "rtf"
        case .url:   return "url"
        case .file:  return "file"
        }
    }
}

private extension Clip {
    var displayText: String {
        switch type {
        case .image: return "Image — \(createdAt.formatted(.dateTime.month().day().hour().minute()))"
        default:
            guard let text = textContent else { return "—" }
            let maxLen = 200
            return text.count > maxLen ? String(text.prefix(maxLen)) + "…" : text
        }
    }
}
