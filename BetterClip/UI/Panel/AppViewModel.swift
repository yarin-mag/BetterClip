// BetterClip/UI/Panel/AppViewModel.swift
import Foundation
import Combine
import AppKit

enum PanelTab { case history, snippets }

enum SnippetPanelItem: Identifiable {
    case folder(SnippetFolder, isExpanded: Bool)
    case snippet(Snippet, depth: Int)

    var id: String {
        switch self {
        case .folder(let folder, _): return "folder-\(folder.id ?? -1)"
        case .snippet(let snippet, _): return "snippet-\(snippet.id ?? -1)"
        }
    }
}

final class AppViewModel: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var clips: [Clip] = []
    @Published var snippets: [Snippet] = []
    @Published var folders: [SnippetFolder] = []
    @Published var expandedFolderIds: Set<Int64> = []
    @Published var selectedTab: PanelTab = .history
    @Published var selectedIndex: Int = 0
    @Published var clipToSaveAsSnippet: Clip? = nil

    let shouldClosePanel = PassthroughSubject<Void, Never>()
    var previousApp: NSRunningApplication?
    private var cancellables = Set<AnyCancellable>()
    private var lastRefreshedQuery: String?

    var snippetPanelItems: [SnippetPanelItem] {
        if !searchQuery.isEmpty {
            return snippets.map { .snippet($0, depth: 0) }
        }
        var items: [SnippetPanelItem] = []
        let knownFolderIds = Set(folders.compactMap { $0.id })
        for folder in folders {
            guard let fid = folder.id else { continue }
            let expanded = expandedFolderIds.contains(fid)
            items.append(.folder(folder, isExpanded: expanded))
            if expanded {
                for snippet in snippets.filter({ $0.folderId == fid }) {
                    items.append(.snippet(snippet, depth: 1))
                }
            }
        }
        for snippet in snippets.filter({ folderId in
            guard let fid = folderId.folderId else { return true }
            return !knownFolderIds.contains(fid)
        }) {
            items.append(.snippet(snippet, depth: 0))
        }
        return items
    }

    init() {
        refresh(query: "")

        $searchQuery
            .debounce(for: .milliseconds(80), scheduler: DispatchQueue.main)
            .sink { [weak self] query in self?.refresh(query: query) }
            .store(in: &cancellables)

        ClipboardMonitor.shared.newClipPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh(query: self?.searchQuery ?? "") }
            .store(in: &cancellables)

        // Keep the panel in sync with edits made in the Snippet Manager window, and
        // reveal the folder a snippet was just saved into.
        NotificationCenter.default.publisher(for: SnippetStore.didChangeNotification)
            .sink { [weak self] note in
                guard let self else { return }
                if let folderId = note.userInfo?[SnippetStore.folderIdKey] as? Int64 {
                    self.expandedFolderIds.insert(folderId)
                }
                self.refresh(query: self.searchQuery)
            }
            .store(in: &cancellables)
    }

    func refresh(query: String) {
        clips    = (try? Database.shared.searchClips(query: query, limit: Preferences.shared.historyLimit)) ?? []
        snippets = (try? SnippetStore.shared.search(query: query)) ?? []
        folders  = (try? SnippetStore.shared.folders()) ?? []
        lastRefreshedQuery = query
        selectedIndex = 0
    }

    func pasteClip(_ clip: Clip) {
        PasteboardWriter.write(clip: clip)
        if let id = clip.id { try? Database.shared.updateClipLastUsed(id: id) }
        refresh(query: searchQuery)
        finishClickPaste()
    }

    func pasteSnippet(_ snippet: Snippet) {
        PasteboardWriter.write(snippet: snippet)
        finishClickPaste()
    }

    // Auto-paste off means "copy only", but still hand focus back to the previous app
    // so the user's ⌘V lands there instead of in the panel.
    private func finishClickPaste() {
        if Preferences.shared.autoPasteAndClose {
            triggerPasteAndClose()
        } else {
            shouldClosePanel.send()
            previousApp?.activate(options: .activateIgnoringOtherApps)
        }
    }

    func deleteClip(_ clip: Clip) {
        guard let id = clip.id else { return }
        try? Database.shared.deleteClip(id: id)
        if let hash = clip.blobHash { BlobStore.shared.delete(hash: hash) }
        refresh(query: searchQuery)
    }

    func moveSelectionUp() {
        selectedIndex = max(0, selectedIndex - 1)
    }

    func moveSelectionDown() {
        let count = selectedTab == .history ? clips.count : snippetPanelItems.count
        guard count > 0 else { return }
        selectedIndex = min(count - 1, selectedIndex + 1)
    }

    func switchTabLeft() {
        guard selectedTab == .snippets else { return }
        selectedTab = .history
        selectedIndex = 0
    }

    func switchTabRight() {
        guard selectedTab == .history else { return }
        selectedTab = .snippets
        selectedIndex = 0
    }

    func toggleFolderExpansion(_ folder: SnippetFolder) {
        guard let fid = folder.id else { return }
        if expandedFolderIds.contains(fid) {
            expandedFolderIds.remove(fid)
        } else {
            expandedFolderIds.insert(fid)
        }
    }

    func pasteSelected() {
        // Enter pressed before the search debounce fired: paste from the current results.
        if lastRefreshedQuery != searchQuery { refresh(query: searchQuery) }
        switch selectedTab {
        case .history:
            guard selectedIndex >= 0, selectedIndex < clips.count else { return }
            let clip = clips[selectedIndex]
            PasteboardWriter.write(clip: clip)
            if let id = clip.id { try? Database.shared.updateClipLastUsed(id: id) }
            refresh(query: searchQuery)
            triggerPasteAndClose()
        case .snippets:
            let items = snippetPanelItems
            guard selectedIndex < items.count else { return }
            switch items[selectedIndex] {
            case .folder(let folder, _):
                toggleFolderExpansion(folder)
            case .snippet(let snippet, _):
                PasteboardWriter.write(snippet: snippet)
                triggerPasteAndClose()
            }
        }
    }

    @discardableResult
    func clearHistory() -> (clipsDeleted: Int, blobsCleaned: Int)? {
        let result = try? Database.shared.deleteAllClips()
        NSPasteboard.general.clearContents()
        ClipboardMonitor.shared.syncChangeCount()
        refresh(query: searchQuery)
        return result
    }

    func showSaveAsSnippet(clip: Clip) {
        clipToSaveAsSnippet = clip
    }

    private func triggerPasteAndClose() {
        guard PasteboardWriter.hasAccessibilityPermission() else {
            PasteboardWriter.requestAccessibilityPermission()
            return
        }
        shouldClosePanel.send()
        previousApp?.activate(options: .activateIgnoringOtherApps)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            PasteboardWriter.simulatePaste()
        }
    }
}