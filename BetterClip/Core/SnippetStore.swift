// BetterClip/Core/SnippetStore.swift
import Foundation

final class SnippetStore {
    static let shared = SnippetStore()
    /// Posted after any snippet or folder write. userInfo[folderIdKey] carries the
    /// folder a snippet was saved into, when there is one.
    static let didChangeNotification = Notification.Name("SnippetStoreDidChange")
    static let folderIdKey = "folderId"

    private let db: Database

    init(db: Database = .shared) {
        self.db = db
    }

    func createFolder(name: String, parentId: Int64? = nil) throws -> SnippetFolder {
        var folder = SnippetFolder(id: nil, name: name, parentId: parentId, sortOrder: 0)
        try db.insertFolder(&folder)
        notifyChange()
        return folder
    }

    func folders() throws -> [SnippetFolder] {
        try db.fetchFolders()
    }

    func updateFolder(_ folder: SnippetFolder) throws {
        try db.updateFolder(folder)
        notifyChange()
    }

    func deleteFolder(id: Int64) throws {
        try db.deleteFolder(id: id)
        notifyChange()
    }

    func createSnippet(name: String, content: String, folderId: Int64? = nil) throws -> Snippet {
        var snippet = Snippet(id: nil, folderId: try existingFolderId(folderId), name: name,
                              content: content, shortcut: nil,
                              createdAt: Date(), sortOrder: 0)
        try db.insertSnippet(&snippet)
        notifyChange(folderId: snippet.folderId)
        return snippet
    }

    func snippets(folderId: Int64? = nil) throws -> [Snippet] {
        try db.fetchSnippets(folderId: folderId)
    }

    func search(query: String) throws -> [Snippet] {
        try db.searchSnippets(query: query)
    }

    func update(_ snippet: Snippet) throws {
        var snippet = snippet
        snippet.folderId = try existingFolderId(snippet.folderId)
        try db.updateSnippet(snippet)
        notifyChange(folderId: snippet.folderId)
    }

    func delete(id: Int64) throws {
        try db.deleteSnippet(id: id)
        notifyChange()
    }

    func saveAsSnippet(clip: Clip, name: String, folderId: Int64? = nil) throws -> Snippet {
        let content = clip.textContent ?? ""
        return try createSnippet(name: name, content: content, folderId: folderId)
    }

    // A stale folder id (folder deleted while a view still held it) would violate the
    // foreign key and fail the save, so fall back to "No Folder" instead.
    private func existingFolderId(_ folderId: Int64?) throws -> Int64? {
        guard let folderId else { return nil }
        return try db.fetchFolders().contains { $0.id == folderId } ? folderId : nil
    }

    private func notifyChange(folderId: Int64? = nil) {
        let userInfo = folderId.map { [Self.folderIdKey: $0] }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self, userInfo: userInfo)
    }
}