// BetterClip/UI/Snippets/FolderTreeView.swift
import SwiftUI

struct SnippetManagerView: View {
    @State private var folders: [SnippetFolder] = []
    @State private var snippets: [Snippet] = []
    @State private var selectedFolderId: Int64? = nil
    @State private var showingEditor = false
    @State private var editingSnippet: Snippet? = nil
    @State private var editingFolderId: Int64? = nil
    @State private var editingFolderName: String = ""

    var body: some View {
        HSplitView {
            folderSidebar
                .frame(minWidth: 160, maxWidth: 220)
            snippetList
        }
        .frame(minWidth: 560, minHeight: 400)
        .toolbar {
            ToolbarItem {
                Button { showingEditor = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            SnippetEditorView(folderId: selectedFolderId) { refreshSnippets() }
        }
        .onAppear {
            cancelEditing()
            refresh()
        }
        .onDisappear {
            cancelEditing()
        }
    }

    private var folderSidebar: some View {
        List(selection: $selectedFolderId) {
            Label("All Snippets", systemImage: "tray.full")
                .tag(Optional<Int64>.none)
            ForEach(folders) { folder in
                if editingFolderId == folder.id {
                    HStack {
                        Image(systemName: "folder")
                        TextField("Folder name", text: $editingFolderName, onCommit: {
                            saveRenamedFolder()
                        })
                        .textFieldStyle(.roundedBorder)
                        Button("Save") { saveRenamedFolder() }
                            .buttonStyle(.plain)
                        Button("Cancel") { editingFolderId = nil }
                            .buttonStyle(.plain)
                    }
                    .tag(Optional(folder.id!))
                } else {
                    Label(folder.name, systemImage: "folder")
                        .tag(Optional(folder.id!))
                        .onTapGesture(count: 2) {
                            editingFolderId = folder.id
                            editingFolderName = folder.name
                        }
                        .contextMenu {
                            Button("Rename") {
                                editingFolderId = folder.id
                                editingFolderName = folder.name
                            }
                            Button("Delete Folder", role: .destructive) {
                                try? SnippetStore.shared.deleteFolder(id: folder.id!)
                                refresh()
                            }
                        }
                }
            }
            Button {
                let name = "New Folder"
                _ = try? SnippetStore.shared.createFolder(name: name)
                refresh()
            } label: {
                Label("Add Folder", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.plain)
        }
        .onChange(of: selectedFolderId) { _ in refreshSnippets() }
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
                    Button("Edit") { editingSnippet = snippet; showingEditor = true }
                    Button("Delete", role: .destructive) {
                        guard let id = snippet.id else { return }
                        try? SnippetStore.shared.delete(id: id)
                        refreshSnippets()
                    }
                }
            }
        }
        .sheet(item: $editingSnippet) { snippet in
            SnippetEditorView(existingSnippet: snippet) { refreshSnippets() }
        }
    }

    private func refresh() {
        folders = (try? SnippetStore.shared.folders()) ?? []
        refreshSnippets()
    }

    private func cancelEditing() {
        editingFolderId = nil
        editingSnippet = nil
        showingEditor = false
        editingFolderName = ""
    }

    private func refreshSnippets() {
        snippets = (try? SnippetStore.shared.snippets(folderId: selectedFolderId)) ?? []
    }
}
