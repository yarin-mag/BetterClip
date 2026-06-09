// BetterClip/Models/Snippet.swift
import Foundation
import GRDB

struct Snippet: Identifiable, Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var folderId: Int64?
    var name: String
    var content: String
    var shortcut: String?
    var createdAt: Date
    var sortOrder: Int

    static let databaseTableName = "snippets"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
