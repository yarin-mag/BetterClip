// BetterClip/Core/Database.swift
import Foundation
import GRDB

final class Database {
    static let shared: Database = {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BetterClip")
        try! FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return Database(path: appSupport.appendingPathComponent("betterclip.sqlite").path)
    }()

    private let queue: DatabaseQueue

    // Production init
    init(path: String) {
        queue = try! DatabaseQueue(path: path)
        try! applyMigrations()
    }

    // In-memory init for tests
    init() {
        queue = try! DatabaseQueue()
        try! applyMigrations()
    }

    private func applyMigrations() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "clips") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("type", .text).notNull()
                t.column("textContent", .text)
                t.column("blobHash", .text)
                t.column("appSource", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("lastUsedAt", .datetime).notNull()
            }
            try db.create(virtualTable: "clips_fts", using: FTS5()) { t in
                t.synchronize(withTable: "clips")
                t.column("textContent")
            }
            try db.create(table: "snippet_folders") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("parentId", .integer).references("snippet_folders")
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "snippets") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("folderId", .integer).references("snippet_folders")
                t.column("name", .text).notNull()
                t.column("content", .text).notNull()
                t.column("shortcut", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }
        }
        try migrator.migrate(queue)
    }

    // MARK: - Clips

    func insertClip(_ clip: inout Clip) throws {
        try queue.write { db in try clip.insert(db) }
    }

    func fetchRecentClips(limit: Int = 50) throws -> [Clip] {
        try queue.read { db in
            try Clip.order(Column("createdAt").desc).limit(limit).fetchAll(db)
        }
    }

    func searchClips(query: String) throws -> [Clip] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return try fetchRecentClips() }

        let lower = q.lowercased()

        // Type-filter shortcuts
        let typeFilter: String?
        switch lower {
        case "img", "image", "images":           typeFilter = "image"
        case "text", "texts", "txt":             typeFilter = "text"
        case "url", "urls", "link", "links":     typeFilter = "url"
        case "file", "files":                    typeFilter = "file"
        default:                                 typeFilter = nil
        }

        if let type = typeFilter {
            return try queue.read { db in
                try Clip.filter(Column("type") == type)
                    .order(Column("createdAt").desc)
                    .fetchAll(db)
            }
        }

        // Build FTS5 prefix query: each token wrapped in quotes + * for partial matching
        let ftsQuery = q.components(separatedBy: .whitespaces)
            .compactMap { token -> String? in
                let safe = token.filter { $0.isLetter || $0.isNumber }
                return safe.isEmpty ? nil : "\"\(safe)\"*"
            }
            .joined(separator: " ")

        return try queue.read { db in
            if !ftsQuery.isEmpty,
               let results = try? Clip.fetchAll(db, sql: """
                   SELECT clips.* FROM clips
                   WHERE clips.id IN (
                       SELECT rowid FROM clips_fts WHERE clips_fts MATCH ?
                   )
                   ORDER BY clips.createdAt DESC
                   """, arguments: [ftsQuery]),
               !results.isEmpty {
                return results
            }
            // Fallback: LOWER LIKE for case-insensitive Unicode matching
            let pattern = "%\(lower)%"
            return try Clip.fetchAll(db, sql: """
                SELECT * FROM clips
                WHERE LOWER(IFNULL(textContent, '')) LIKE ?
                ORDER BY createdAt DESC
                """, arguments: [pattern])
        }
    }

    func updateClipLastUsed(id: Int64) throws {
        try queue.write { db in
            try db.execute(sql: "UPDATE clips SET lastUsedAt = ? WHERE id = ?",
                           arguments: [Date(), id])
        }
    }

    func deleteClip(id: Int64) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM clips WHERE id = ?", arguments: [id])
        }
    }

    func trimClips(keepingLatest limit: Int) throws {
        try queue.write { db in
            try db.execute(sql: """
                DELETE FROM clips WHERE id NOT IN (
                    SELECT id FROM clips ORDER BY createdAt DESC LIMIT ?
                )
            """, arguments: [limit])
        }
    }

    func mostRecentClip() throws -> Clip? {
        try queue.read { db in
            try Clip.order(Column("createdAt").desc).limit(1).fetchOne(db)
        }
    }

    // MARK: - Snippets

    func insertSnippet(_ snippet: inout Snippet) throws {
        try queue.write { db in try snippet.insert(db) }
    }

    func fetchSnippets(folderId: Int64? = nil) throws -> [Snippet] {
        try queue.read { db in
            var request = Snippet.order(Column("sortOrder"))
            if let folderId { request = request.filter(Column("folderId") == folderId) }
            return try request.fetchAll(db)
        }
    }

    func searchSnippets(query: String) throws -> [Snippet] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return try fetchSnippets() }
        let pattern = "%\(q.lowercased())%"
        return try queue.read { db in
            try Snippet.fetchAll(db, sql: """
                SELECT * FROM snippets
                WHERE LOWER(name) LIKE ? OR LOWER(content) LIKE ?
                ORDER BY sortOrder
                """, arguments: [pattern, pattern])
        }
    }

    func updateSnippet(_ snippet: Snippet) throws {
        try queue.write { db in try snippet.update(db) }
    }

    func deleteSnippet(id: Int64) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM snippets WHERE id = ?", arguments: [id])
        }
    }

    func insertFolder(_ folder: inout SnippetFolder) throws {
        try queue.write { db in try folder.insert(db) }
    }

    func fetchFolders() throws -> [SnippetFolder] {
        try queue.read { db in
            try SnippetFolder.order(Column("sortOrder")).fetchAll(db)
        }
    }

    func updateFolder(_ folder: SnippetFolder) throws {
        try queue.write { db in try folder.update(db) }
    }

    func deleteFolder(id: Int64) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM snippets WHERE folderId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM snippet_folders WHERE id = ?", arguments: [id])
        }
    }

    // MARK: - Clean History

    func deleteAllClips() throws -> (clipsDeleted: Int, blobsCleaned: Int) {
        try queue.write { db in
            // Get all blob hashes from clips before deletion
            let clipBlobHashes = try db.fetch(sql: """
                SELECT DISTINCT blobHash FROM clips WHERE blobHash IS NOT NULL
            """).compactMap { $0["blobHash"] as? String }.filter { !$0.isEmpty }

            // Delete all clips
            let clipsDeleted = try db.execute(sql: "DELETE FROM clips")

            // Clean up blobs from disk (snippets store content as text, not as blobs)
            let blobStore = BlobStore.shared
            for hash in clipBlobHashes {
                blobStore.delete(hash: hash)
            }

            return (clipsDeleted: clipsDeleted, blobsCleaned: clipBlobHashes.count)
        }
    }
}
