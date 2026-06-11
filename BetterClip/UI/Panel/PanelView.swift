// BetterClip/UI/Panel/PanelView.swift
import AppKit
import SwiftUI

struct PanelView: View {
    @ObservedObject var viewModel: AppViewModel
    @FocusState private var searchFocused: Bool
    @State private var showClearHistoryConfirm = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                searchBar
                Divider()
                tabBar
                Divider()
                itemList
            }
            .frame(width: Preferences.shared.layoutMode == .full ? 320 : nil)

            if Preferences.shared.layoutMode == .full {
                Divider()
                PreviewPane(viewModel: viewModel)
            }
        }
        .onAppear { }
        .sheet(item: $viewModel.clipToSaveAsSnippet) { clip in
            SnippetEditorView(prefillContent: clip.textContent ?? "") {
                viewModel.refresh(query: viewModel.searchQuery)
            }
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search clipboard…", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
                .onSubmit { viewModel.pasteSelected() }
                .onKeyPress(.upArrow)    { viewModel.moveSelectionUp();      return .handled }
                .onKeyPress(.downArrow)  { viewModel.moveSelectionDown();    return .handled }
                .onKeyPress(.leftArrow)  { viewModel.switchTabLeft();        return .handled }
                .onKeyPress(.rightArrow) { viewModel.switchTabRight();       return .handled }
                .onKeyPress(.escape)     { viewModel.shouldClosePanel.send(); return .handled }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton("History", tab: .history)
            tabButton("Snippets", tab: .snippets)
            Spacer()
            tabActionButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .alert("Clear Clipboard History?", isPresented: $showClearHistoryConfirm) {
            Button("Clear", role: .destructive) { viewModel.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Permanently deletes all clipboard history. Snippets are not affected.")
        }
    }

    @ViewBuilder
    private var tabActionButton: some View {
        if viewModel.selectedTab == .history {
            Button {
                showClearHistoryConfirm = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .help("Clear clipboard history")
        } else {
            Button {
                NSApp.sendAction(#selector(AppDelegate.openSnippetManager), to: nil, from: nil)
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .help("Manage snippets")
        }
    }

    private func tabButton(_ title: String, tab: PanelTab) -> some View {
        Button(title) {
            viewModel.selectedTab = tab
            viewModel.selectedIndex = 0
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: viewModel.selectedTab == tab ? .semibold : .regular))
        .foregroundStyle(viewModel.selectedTab == tab ? .primary : .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var itemList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.selectedTab == .history {
                    historyList
                } else {
                    snippetList
                }
            }
            .onChange(of: viewModel.selectedIndex) { idx in
                proxy.scrollTo(idx, anchor: .center)
            }
            .onChange(of: viewModel.selectedTab) { _ in
                proxy.scrollTo(0, anchor: .top)
            }
        }
    }

    private var historyList: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.clips.enumerated()), id: \.element.id) { index, clip in
                ClipRowView(clip: clip, isSelected: index == viewModel.selectedIndex, index: index + 1)
                    .equatable()
                    .id(index)
                    .onTapGesture(count: 2) { viewModel.pasteClip(clip) }
                    .onTapGesture { viewModel.selectedIndex = index }
                    .contextMenu {
                        Button("Paste") { viewModel.pasteClip(clip) }
                        Button("Save as Snippet…") { viewModel.showSaveAsSnippet(clip: clip) }
                        Divider()
                        Button("Delete", role: .destructive) { viewModel.deleteClip(clip) }
                    }
            }
        }
    }

    private var snippetList: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.snippetPanelItems.enumerated()), id: \.offset) { index, item in
                snippetItemRow(item: item, index: index)
            }
        }
    }

    @ViewBuilder
    private func snippetItemRow(item: SnippetPanelItem, index: Int) -> some View {
        switch item {
        case .folder(let folder, let isExpanded):
            FolderRowView(folder: folder, isExpanded: isExpanded, isSelected: index == viewModel.selectedIndex)
                .id(index)
                .onTapGesture {
                    viewModel.selectedIndex = index
                    viewModel.toggleFolderExpansion(folder)
                }
        case .snippet(let snippet, let depth):
            SnippetRowView(snippet: snippet, isSelected: index == viewModel.selectedIndex, index: index + 1, depth: depth)
                .equatable()
                .id(index)
                .onTapGesture(count: 2) { viewModel.pasteSnippet(snippet) }
                .onTapGesture { viewModel.selectedIndex = index }
        }
    }
}

private struct FolderRowView: View {
    let folder: SnippetFolder
    let isExpanded: Bool
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isExpanded ? "folder.fill" : "folder")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
                .frame(width: 20)
            Text(folder.name)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accentColor.opacity(0.18) : isHovered ? Color.primary.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
