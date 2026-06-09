// BetterClip/Core/SnippetStore.swift
import Foundation

final class SnippetStore {
    static let shared = SnippetStore()
    private let db = Database.shared

    func createFolder(name: String, parentId: Int64? = nil) throws -> SnippetFolder {
        var folder = SnippetFolder(id: nil, name: name, parentId: parentId, sortOrder: 0)
        try db.insertFolder(&folder)
        return folder
    }

    func folders() throws -> [SnippetFolder] {
        try db.fetchFolders()
    }

    func updateFolder(_ folder: SnippetFolder) throws {
        try db.updateFolder(folder)
    }

    func deleteFolder(id: Int64) throws {
        try db.deleteFolder(id: id)
    }

    func createSnippet(name: String, content: String, folderId: Int64? = nil) throws -> Snippet {
        var snippet = Snippet(id: nil, folderId: folderId, name: name,
                              content: content, shortcut: nil,
                              createdAt: Date(), sortOrder: 0)
        try db.insertSnippet(&snippet)
        return snippet
    }

    func snippets(folderId: Int64? = nil) throws -> [Snippet] {
        try db.fetchSnippets(folderId: folderId)
    }

    func search(query: String) throws -> [Snippet] {
        try db.searchSnippets(query: query)
    }

    func update(_ snippet: Snippet) throws {
        try db.updateSnippet(snippet)
    }

    func delete(id: Int64) throws {
        try db.deleteSnippet(id: id)
    }

    func saveAsSnippet(clip: Clip, name: String, folderId: Int64? = nil) throws -> Snippet {
        let content = clip.textContent ?? ""
        return try createSnippet(name: name, content: content, folderId: folderId)
    }
}
