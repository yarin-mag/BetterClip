// BetterClip/UI/Panel/PreviewPane.swift
import SwiftUI

struct PreviewPane: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Group {
            if viewModel.selectedTab == .history {
                clipPreview
            } else {
                snippetPreview
            }
        }
        .frame(minWidth: 300)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }

    @ViewBuilder
    private var clipPreview: some View {
        let idx = viewModel.selectedIndex
        if idx < viewModel.clips.count {
            let clip = viewModel.clips[idx]
            switch clip.type {
            case .image:
                AsyncPreviewImage(hash: clip.blobHash ?? "")
            default:
                DebouncedTextView(text: clip.textContent ?? "")
            }
        } else {
            placeholder("Select an item")
        }
    }

    @ViewBuilder
    private var snippetPreview: some View {
        let idx = viewModel.selectedIndex
        if idx < viewModel.snippets.count {
            let snippet = viewModel.snippets[idx]
            VStack(alignment: .leading, spacing: 8) {
                Text(snippet.name).font(.headline)
                Divider()
                DebouncedTextView(text: snippet.content)
            }
        } else {
            placeholder("Select a snippet")
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text).foregroundStyle(.tertiary).font(.system(size: 13))
    }
}

// Header updates immediately; body text debounces 80ms to avoid layout thrash during fast navigation.
private struct DebouncedTextView: View {
    let text: String
    @State private var displayedText: String = ""

    var body: some View {
        ScrollView {
            let preview = displayedText.count > 5_000
                ? String(displayedText.prefix(5_000)) + "\n…"
                : displayedText
            Text(preview)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: text) {
            try? await Task.sleep(nanoseconds: 80_000_000)
            displayedText = text
        }
        .onAppear { displayedText = text }
    }
}

private struct AsyncPreviewImage: View {
    let hash: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(6)
            } else {
                Text("No image data").foregroundStyle(.tertiary).font(.system(size: 13))
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
