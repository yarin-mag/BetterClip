// BetterClip/UI/Snippets/FolderTreeView.swift
import SwiftUI

private enum SnippetEditorMode: Identifiable {
    case add(folderId: Int64?)
    case edit(Snippet)

    var id: String {
        switch self {
        case .add(let folderId): return "add-\(String(describing: folderId))"
        case .edit(let snippet): return "edit-\(snippet.id ?? -1)"
        }
    }
}

// List(selection:) only matches rows whose tag type equals the selection's wrapped
// type, so "All Snippets" can't be a nil Int64? tag; use an explicit case instead.
private enum SidebarItem: Hashable {
    case all
    case folder(Int64)
}

struct SnippetManagerView: View {
    @State private var folders: [SnippetFolder] = []
    @State private var snippets: [Snippet] = []
    @State private var sidebarSelection: SidebarItem? = .all
    @State private var editorMode: SnippetEditorMode? = nil
    @State private var editingFolderId: Int64? = nil
    @State private var editingFolderName: String = ""
    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        HSplitView {
            folderSidebar
                .frame(minWidth: 160, maxWidth: 220)
            snippetList
        }
        .frame(minWidth: 560, minHeight: 400)
        .toolbar {
            ToolbarItem {
                Button { editorMode = .add(folderId: selectedFolderId) } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editorMode) { mode in
            switch mode {
            case .add(let folderId):
                SnippetEditorView(folderId: folderId) { refreshSnippets() }
            case .edit(let snippet):
                SnippetEditorView(existingSnippet: snippet) { refreshSnippets() }
            }
        }
        .onAppear {
            cancelEditing()
            refresh()
        }
        .onDisappear {
            cancelEditing()
        }
        .onReceive(NotificationCenter.default.publisher(for: SnippetStore.didChangeNotification)) { _ in
            refresh()
        }
    }

    private var folderSidebar: some View {
        List(selection: $sidebarSelection) {
            Label("All Snippets", systemImage: "tray.full")
                .tag(SidebarItem.all)
            ForEach(folders) { folder in
                if editingFolderId == folder.id {
                    HStack {
                        Image(systemName: "folder")
                        TextField("Folder name", text: $editingFolderName, onCommit: {
                            saveRenamedFolder()
                        })
                        .textFieldStyle(.roundedBorder)
                        .focused($renameFieldFocused)
                        Button("Save") { saveRenamedFolder() }
                            .buttonStyle(.plain)
                        Button("Cancel") { editingFolderId = nil }
                            .buttonStyle(.plain)
                    }
                    .tag(SidebarItem.folder(folder.id!))
                } else {
                    // No tap gestures here: on macOS they swallow the click that
                    // selects the row.
                    Label(folder.name, systemImage: "folder")
                        .tag(SidebarItem.folder(folder.id!))
                        .contextMenu {
                            Button("Rename") { startRenaming(folder) }
                            Button("Delete Folder", role: .destructive) {
                                deleteFolder(folder)
                            }
                        }
                }
            }
            Button {
                guard let folder = try? SnippetStore.shared.createFolder(name: "New Folder") else { return }
                refresh()
                sidebarSelection = .folder(folder.id!)
                startRenaming(folder)
            } label: {
                Label("Add Folder", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.plain)
        }
        .onChange(of: sidebarSelection) { _ in
            Preferences.shared.lastSnippetFolderId = selectedFolderId
            refreshSnippets()
        }
    }

    private var selectedFolderId: Int64? {
        if case .folder(let id) = sidebarSelection { return id }
        return nil
    }

    private func startRenaming(_ folder: SnippetFolder) {
        editingFolderId = folder.id
        editingFolderName = folder.name
        DispatchQueue.main.async { renameFieldFocused = true }
    }

    private func deleteFolder(_ folder: SnippetFolder) {
        guard let id = folder.id else { return }
        try? SnippetStore.shared.deleteFolder(id: id)
        if selectedFolderId == id { sidebarSelection = .all }
        if editingFolderId == id { editingFolderId = nil }
        refresh()
    }

    private func saveRenamedFolder() {
        guard let folderId = editingFolderId else { return }
        guard var folder = folders.first(where: { $0.id == folderId }) else {
            editingFolderId = nil
            return
        }
        folder.name = editingFolderName
        do {
            try SnippetStore.shared.updateFolder(folder)
            editingFolderId = nil
            refresh()
        } catch {
            print("Failed to rename folder: \(error)")
            editingFolderId = nil
        }
    }

    private var snippetList: some View {
        List {
            ForEach(snippets) { snippet in
                VStack(alignment: .leading, spacing: 3) {
                    Text(snippet.name).font(.system(size: 13, weight: .medium))
                    Text(snippet.content)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .contextMenu {
                    Button("Edit") { editorMode = .edit(snippet) }
                    Button("Delete", role: .destructive) {
                        guard let id = snippet.id else { return }
                        try? SnippetStore.shared.delete(id: id)
                        refreshSnippets()
                    }
                }
            }
        }
    }

    private func refresh() {
        folders = (try? SnippetStore.shared.folders()) ?? []
        refreshSnippets()
    }

    private func cancelEditing() {
        editingFolderId = nil
        editorMode = nil
        editingFolderName = ""
    }

    private func refreshSnippets() {
        snippets = (try? SnippetStore.shared.snippets(folderId: selectedFolderId)) ?? []
    }
}